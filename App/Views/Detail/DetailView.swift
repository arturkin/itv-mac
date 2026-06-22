import SwiftUI
import ITVKit

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.playlist == nil && !model.hasPlaylistURL {
                OnboardingView()
            } else if case .failed(let message) = model.libraryPhase {
                ErrorView(message: message) { Task { await model.loadLibrary() } }
            } else if let channel = model.selectedChannel {
                PlayerPane(channel: channel)
            } else if model.libraryPhase == .loading {
                ProgressView("Loading channels…")
            } else {
                ContentUnavailableView("Select a channel", systemImage: "tv")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerPane: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                NowPlayingHeader(channel: channel)
                Divider().overlay(Theme.separator)
                ZStack {
                    AVPlayerViewRepresentable(player: model.player.player)
                        .background(Theme.background)
                        .accessibilityIdentifier("player.view")
                    if model.player.videoUnavailable {
                        VideoUnavailableOverlay(player: model.player)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if channel.hasArchive {
                    TimeShiftBar(channel: channel)
                    Divider().overlay(Theme.separator)
                }

                ResizeHandle(height: bindingHeight(in: geo.size.height))
                ProgramTimelineView(channel: channel)
                    .frame(height: clampedHeight(geo.size.height))
            }
        }
        .background(Theme.background)
    }

    /// Clamp the persisted height so the player keeps a usable minimum on small
    /// windows, regardless of what was saved.
    private func clampedHeight(_ total: CGFloat) -> CGFloat {
        let maxByContainer = max(AppModel.minTimelineHeight, Double(total) - 260)
        let upper = min(AppModel.maxTimelineHeight, maxByContainer)
        return CGFloat(min(max(model.timelineHeight, AppModel.minTimelineHeight), upper))
    }

    private func bindingHeight(in total: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(clampedHeight(total)) },
            set: { newValue in
                let maxByContainer = max(AppModel.minTimelineHeight, Double(total) - 260)
                let upper = min(AppModel.maxTimelineHeight, maxByContainer)
                model.timelineHeight = min(max(newValue, AppModel.minTimelineHeight), upper)
            }
        )
    }
}

/// A thin draggable divider that resizes the bottom EPG/timeline panel.
/// Dragging up grows the panel; dragging down shrinks it.
private struct ResizeHandle: View {
    @Binding var height: Double
    @State private var startHeight: Double?

    var body: some View {
        ZStack {
            Theme.surface
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.textTertiary.opacity(0.6))
                .frame(width: 40, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = startHeight ?? height
                    if startHeight == nil { startHeight = height }
                    // Drag up (negative translation) → larger panel.
                    height = base - Double(value.translation.height)
                }
                .onEnded { _ in startHeight = nil }
        )
        .accessibilityIdentifier("timeline.resizeHandle")
        .help("Drag to resize the guide panel")
    }
}

/// Time-only seek transport: jump back/forward by 30 minutes (no EPG needed).
private struct TimeShiftBar: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    private var player: PlayerController { model.player }

    var body: some View {
        HStack(spacing: 12) {
            Button { player.stepBackward() } label: {
                Label("30 min", systemImage: "gobackward.30")
            }
            .help("Back 30 minutes")
            .accessibilityIdentifier("player.back30")

            Button { player.stepForward() } label: {
                Label("30 min", systemImage: "goforward.30")
            }
            .help("Forward 30 minutes")
            .disabled(player.isLive)
            .accessibilityIdentifier("player.fwd30")

            Spacer()

            TimeShiftPositionLabel()

            Spacer()

            if !player.isLive {
                Button { player.jumpToLive() } label: {
                    Label("Live", systemImage: "forward.end.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("player.goLiveBar")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 38)
        .background(Theme.surface)
    }
}

/// Live-updating "how far behind live / clock time" indicator.
private struct TimeShiftPositionLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let player = model.player
            if player.isLive {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.live)
            } else if let abs = player.currentAbsoluteDate {
                HStack(spacing: 8) {
                    Text("−\(behindText(player.secondsBehindLive))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(abs, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func behindText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "%dm", m)
    }
}

/// Shown over the video when audio plays but this Mac can't decode the video.
private struct VideoUnavailableOverlay: View {
    let player: PlayerController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv.badge.wifi")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Video can’t be decoded on this Mac")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Audio is playing. This channel uses a video codec macOS can’t decode — send it to your TV with AirPlay, which decodes it for you.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            AirPlayRoutePicker(player: player.player)
                .frame(width: 44, height: 30)
        }
        .padding(28)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("player.videoUnavailable")
    }
}

private struct NowPlayingHeader: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogo(url: channel.logoURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if model.player.isExternalPlaybackActive {
                Label("On TV", systemImage: "tv.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("player.onTV")
            }
            if let message = model.player.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(1)
            }
            if model.player.isLive {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold()).foregroundStyle(Theme.live)
                    .accessibilityIdentifier("player.liveBadge")
            } else {
                Button {
                    model.player.jumpToLive()
                } label: { Label("Go Live", systemImage: "forward.end.fill") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("player.goLive")
            }
            // AirPlay route picker — cast the current channel to the TV.
            AirPlayRoutePicker(player: model.player.player)
                .frame(width: 28, height: 24)
                .help("AirPlay to your TV")
            Button {
                model.toggleFavorite(channel.id)
            } label: {
                Image(systemName: model.isFavorite(channel.id) ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite(channel.id) ? Theme.star : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Toggle favorite")
            .accessibilityIdentifier("player.favorite")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(Theme.surface)
    }

    private var subtitle: String {
        if let programme = model.player.programme { return "Catch-up · \(programme.title)" }
        if !model.player.isLive { return "Time-shift" }
        if let now = model.snapshot?.index.nowNext(channelID: channel.id, at: Date()).now { return now.title }
        return "Live"
    }
}

struct OnboardingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Add your itv.live playlist", systemImage: "play.tv")
        } description: {
            Text("Open Settings (⌘,) and paste your itv.live playlist URL to load channels.")
        } actions: {
            SettingsLink { Text("Open Settings") }
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load channels", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
        }
    }
}
