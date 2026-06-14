import SwiftUI
import AVFoundation
import CoreImage
import CoreVideo
import QuartzCore
import AppKit
import ITVKit

/// Headless visual-verification mode.
///
/// Launch the built app binary with `--snapshot <dir>` to load the real playlist
/// + EPG and render the app's SwiftUI views to PNG via `ImageRenderer`, then quit.
/// This needs **no Screen Recording / Accessibility / UI-automation permission** —
/// it renders offscreen in-process, so it works in restricted sessions where
/// XCUITest and `screencapture` are blocked.
///
/// `ImageRenderer` on macOS can't capture AppKit-backed views: `List`,
/// `NavigationSplitView`, `AVPlayerView`, `ScrollView` content (comes out blank),
/// or `Button` controls (come out as a yellow "no-entry" glyph). Plain
/// `Text`/`Image`/`Label`/`HStack`/`VStack` render faithfully. So the snapshot
/// compositions below mirror the production layout with the real data-bearing
/// views (`ChannelRowView`) and lay out the rest with plain stacks, showing
/// interactive controls as static chrome. The live/catch-up video surface is
/// captured for real with `AVPlayerItemVideoOutput` (forces a decode → pixel
/// buffer) and composited into the player area.
enum SnapshotMode {
    static var requestedDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(filePath: args[i + 1])
    }

    @MainActor
    static func run(into preferred: URL) async {
        let dir = resolveOutputDir(preferred: preferred)
        print("SNAPSHOT_DIR=\(dir.path)")
        var log: [String] = ["dir=\(dir.path)"]

        log.append("probe=\(render(Text("probe").font(.largeTitle), size: CGSize(width: 240, height: 120), to: dir.appending(path: "_probe.png")))")

        // Real data: fetch the user's playlist + EPG over the network.
        let model = AppModel()
        await model.loadLibrary()
        let channels = model.playlist?.channels ?? []
        log.append("channels=\(channels.count)")
        log.append("epg=\(model.snapshot != nil ? "loaded(\(model.snapshot!.index.programmeCount) programmes)" : "nil")")

        guard let channel = channels.first(where: { $0.hasArchive }) ?? channels.first else {
            log.append("FATAL: no channels — check ITV_PLAYLIST_URL / network. Cannot render app views.")
            finish(log: log, dir: dir)
            return
        }
        model.selectedChannelID = channel.id
        log.append("selected=\(channel.name) archiveDays=\(channel.recDays)")

        // Seed favorites + Continue Watching (in memory only) so those sections render.
        let favIDs = Array(channels.prefix(3).map(\.id))
        model.seedForSnapshot(favorites: favIDs, recents: makeRecents(channels: channels, index: model.snapshot?.index))

        // Decode a real frame straight from the user's streams (forces video decode).
        var poster: NSImage?
        if let png = await capturePlayerFrame(url: ArchiveURLBuilder.liveURL(for: channel), timeout: 20) {
            try? png.write(to: dir.appending(path: "frame_live.png"))
            poster = NSImage(data: png)
            log.append("liveFrame=ok(\(png.count))")
        } else { log.append("liveFrame=nil") }

        if let prog = pastProgramme(channelID: channel.id, index: model.snapshot?.index),
           let url = ArchiveURLBuilder.catchUpURL(for: channel, programme: prog),
           let png = await capturePlayerFrame(url: url, timeout: 20) {
            try? png.write(to: dir.appending(path: "frame_archive.png"))
            if poster == nil { poster = NSImage(data: png) }
            log.append("archiveFrame=ok(\(png.count)) from \(prog.title)")
        } else { log.append("archiveFrame=nil") }

        // Full window (sidebar + player area + timeline), composed from real views + real data.
        log.append("window=\(render(SnapshotWindow(model: model, channel: channel, poster: poster).environment(model), size: CGSize(width: 1280, height: 800), to: dir.appending(path: "window.png")))")

        // Sidebar alone (groups, favorites, continue-watching, now/next subtitles).
        log.append("sidebar=\(render(SnapshotSidebar(model: model).environment(model), size: CGSize(width: 300, height: 760), to: dir.appending(path: "sidebar.png")))")

        // Headline UX: browse the archive timeline without playing — today and a past day.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        log.append("timeline_today=\(render(TimelineCard(model: model, channel: channel, day: Calendar.current.startOfDay(for: Date()), poster: poster).environment(model), size: CGSize(width: 860, height: 460), to: dir.appending(path: "timeline_today.png")))")
        log.append("timeline_prevday=\(render(TimelineCard(model: model, channel: channel, day: Calendar.current.startOfDay(for: yesterday), poster: nil).environment(model), size: CGSize(width: 860, height: 460), to: dir.appending(path: "timeline_prevday.png")))")

        // Search across channels + programme titles (Cyrillic-aware).
        if let query = searchQuery(channels: channels) {
            model.searchText = query
            log.append("searchQuery=\(query)")
            log.append("search=\(render(SnapshotSidebar(model: model).environment(model), size: CGSize(width: 300, height: 760), to: dir.appending(path: "search.png")))")
            model.searchText = ""
        }

        finish(log: log, dir: dir)
    }

    @MainActor
    private static func finish(log: [String], dir: URL) {
        let text = log.joined(separator: "\n") + "\n"
        try? text.write(to: dir.appending(path: "log.txt"), atomically: true, encoding: .utf8)
        print(text)
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Rendering

    @MainActor
    @discardableResult
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) -> String {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .tint(Theme.accent)
                .environment(\.colorScheme, .dark)
                .background(Theme.background)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage else { return "nil-nsImage" }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return "nil-png" }
        do { try png.write(to: url); return "ok(\(png.count))" }
        catch { return "write-error \(error)" }
    }

    // MARK: - Real video frame (no GUI / TCC needed)

    /// Plays an HLS URL just long enough to pull one decoded frame out of an
    /// `AVPlayerItemVideoOutput`, returning it as PNG `Data`. Attaching the output
    /// forces the pipeline to actually decode video even with no layer on screen.
    @MainActor
    private static func capturePlayerFrame(url: URL, timeout: Double) async -> Data? {
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()

        let deadline = Date().addingTimeInterval(timeout)
        defer { player.pause() }
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if item.status == .failed { return nil }
            guard item.status == .readyToPlay else { continue }
            let t = output.itemTime(forHostTime: CACurrentMediaTime())
            guard output.hasNewPixelBuffer(forItemTime: t),
                  let pb = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { continue }
            return pngFromPixelBuffer(pb)
        }
        return nil
    }

    private static func pngFromPixelBuffer(_ pb: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    // MARK: - Helpers

    private static func resolveOutputDir(preferred: URL) -> URL {
        let fm = FileManager.default
        let fallback = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appending(path: "itv.live/snapshots")
        for dir in [preferred, fallback] {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let probe = dir.appending(path: ".w")
                try Data([0]).write(to: probe)
                try? fm.removeItem(at: probe)
                return dir
            } catch { continue }
        }
        return fallback
    }

    private static func pastProgramme(channelID: String, index: EPGIndex?) -> Programme? {
        guard let index else { return nil }
        let now = Date()
        let range = now.addingTimeInterval(-6 * 3600)...now.addingTimeInterval(-600)
        return index.programmes(channelID: channelID, in: range).last(where: { $0.hasEnded(at: now) })
    }

    private static func makeRecents(channels: [Channel], index: EPGIndex?) -> [RecentItem] {
        let now = Date()
        return channels.prefix(4).map { ch in
            if let p = pastProgramme(channelID: ch.id, index: index) {
                return RecentItem(channelID: ch.id, programmeStart: p.start, title: p.title, lastPlayed: now)
            }
            return RecentItem(channelID: ch.id, programmeStart: nil, title: ch.name, lastPlayed: now)
        }
    }

    private static func searchQuery(channels: [Channel]) -> String? {
        guard let name = channels.first(where: { $0.name.count >= 3 })?.name else { return nil }
        return String(name.prefix(3))
    }
}

// MARK: - Snapshot compositions (renderable equivalents of the AppKit-backed shell)
//
// These mirror the production layout but avoid the views ImageRenderer can't
// capture (List, ScrollView, Button). They reuse the real `ChannelRowView` and
// the real models/EPG, so what they show is genuine data in the genuine layout.

private struct SnapshotWindow: View {
    let model: AppModel
    let channel: Channel
    let poster: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            SnapshotSidebar(model: model).frame(width: 300)
            Divider().overlay(Theme.separator)
            VStack(spacing: 0) {
                SnapshotHeader(model: model, channel: channel)
                Divider().overlay(Theme.separator)
                PlayerSurface(poster: poster).frame(maxWidth: .infinity, maxHeight: .infinity)
                SnapshotTimeline(model: model, channel: channel, day: Calendar.current.startOfDay(for: Date()), maxRows: 4)
                    .frame(height: 210)
                    .background(Theme.surface)
            }
        }
        .background(Theme.background)
    }
}

private struct TimelineCard: View {
    let model: AppModel
    let channel: Channel
    let day: Date
    let poster: NSImage?
    var body: some View {
        VStack(spacing: 0) {
            SnapshotHeader(model: model, channel: channel)
            Divider().overlay(Theme.separator)
            PlayerSurface(poster: poster).frame(height: 150)
            SnapshotTimeline(model: model, channel: channel, day: day, maxRows: 6)
                .background(Theme.surface)
        }
        .background(Theme.background)
    }
}

private struct PlayerSurface: View {
    let poster: NSImage?
    var body: some View {
        ZStack {
            Color.black
            if let poster {
                Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "play.tv").font(.system(size: 48)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

/// Mirrors `NowPlayingHeader` with static chrome (no Buttons).
private struct SnapshotHeader: View {
    let model: AppModel
    let channel: Channel
    var body: some View {
        HStack(spacing: 10) {
            ChannelLogo(url: channel.logoURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.bold()).foregroundStyle(Theme.live)
            Image(systemName: model.isFavorite(channel.id) ? "star.fill" : "star")
                .foregroundStyle(model.isFavorite(channel.id) ? Theme.star : Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(height: 48)
        .background(Theme.surface)
    }
    private var subtitle: String {
        if let now = model.snapshot?.index.nowNext(channelID: channel.id, at: Date()).now { return now.title }
        return "Live"
    }
}

/// Mirrors `ProgramTimelineView` (day bar + programme list) without ScrollView/Button.
private struct SnapshotTimeline: View {
    let model: AppModel
    let channel: Channel
    let day: Date
    var maxRows: Int = 6
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            dayBar
            Divider()
            VStack(spacing: 0) {
                ForEach(visibleProgrammes) { p in
                    SnapshotProgrammeRow(channel: channel, programme: p)
                    Divider()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var dayBar: some View {
        HStack {
            Image(systemName: "chevron.left").foregroundStyle(Theme.accent)
            Spacer()
            VStack(spacing: 0) {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                if channel.hasArchive {
                    Text("\(channel.recDays)-day archive").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            Text("Today").foregroundStyle(cal.isDateInToday(day) ? Theme.textTertiary : Theme.accent)
            Image(systemName: "chevron.right").foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var visibleProgrammes: [Programme] {
        guard let index = model.snapshot?.index else { return [] }
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let all = index.programmes(channelID: channel.id, in: day...end)
        if cal.isDateInToday(day), !all.isEmpty {
            let now = Date()
            if let i = all.firstIndex(where: { $0.contains(now) }) ?? all.firstIndex(where: { $0.start >= now }) {
                return Array(all[max(0, i - 1)...].prefix(maxRows))
            }
        }
        return Array(all.prefix(maxRows))
    }
}

/// Mirrors `ProgrammeCellView` without the Button wrapper.
private struct SnapshotProgrammeRow: View {
    let channel: Channel
    let programme: Programme
    var body: some View {
        let now = Date()
        let isAiring = programme.isAiring(at: now)
        let playable = ArchiveURLBuilder.mode(for: channel, programme: programme, now: now) != nil || isAiring
        HStack(alignment: .top, spacing: 10) {
            Text(programme.start, format: .dateTime.hour().minute())
                .font(.callout.monospacedDigit())
                .foregroundStyle(isAiring ? Theme.accent : Theme.textTertiary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(programme.title)
                        .fontWeight(isAiring ? .semibold : .regular)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if isAiring { Text("NOW").font(.caption2.bold()).foregroundStyle(Theme.live) }
                }
                if !programme.desc.isEmpty {
                    Text(programme.desc).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer()
            if playable {
                Image(systemName: isAiring ? "play.circle.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(Theme.accent.opacity(0.9))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .opacity(playable ? 1 : 0.4)
        .background(isAiring ? Theme.accent.opacity(0.14) : .clear)
    }
}

/// The sidebar content, laid out with plain stacks instead of `List`. Reuses the
/// production `ChannelRowView`.
private struct SnapshotSidebar: View {
    let model: AppModel

    var body: some View {
        let sections = model.sidebarSections   // computing this also populates searchProgrammeHits
        let hits = model.searchProgrammeHits

        VStack(alignment: .leading, spacing: 1) {
            searchField

            if model.searchText.isEmpty && !model.recents.isEmpty {
                header("Continue Watching")
                ForEach(model.recents.prefix(4)) { item in
                    Label {
                        Text(item.title).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    } icon: {
                        Image(systemName: item.programmeStart == nil ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath")
                            .foregroundStyle(item.programmeStart == nil ? Theme.live : Theme.accent)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                }
            }

            ForEach(Array(sections.prefix(3))) { section in
                header(section.title)
                ForEach(section.channels.prefix(8)) { channel in
                    ChannelRowView(channel: channel)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(channel.id == model.selectedChannelID ? Theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .leading) {
                            if channel.id == model.selectedChannelID {
                                Theme.accent.frame(width: 3).clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 6)
                }
            }

            if !hits.isEmpty {
                header("Programmes")
                ForEach(hits.prefix(8)) { hit in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.title).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Text(model.channel(for: hit.channelID)?.name ?? hit.channelID)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(Theme.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            Text(model.searchText.isEmpty ? "Search channels & programmes" : model.searchText)
                .foregroundStyle(model.searchText.isEmpty ? Theme.textTertiary : Theme.textPrimary)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func header(_ title: String) -> some View {
        Text(title).itvSectionHeader()
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }
}
