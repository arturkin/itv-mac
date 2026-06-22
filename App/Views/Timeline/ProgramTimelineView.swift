import SwiftUI
import ITVKit

/// The per-channel program history shown beneath the player. Browsing it —
/// scrolling programmes, stepping through days back to the archive limit — does
/// NOT change playback. Playback only starts when a programme is explicitly
/// clicked. This is the headline "scroll the archive without opening the full
/// view" interaction.
struct ProgramTimelineView: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    @State private var day: Date = Calendar.current.startOfDay(for: Date())

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.separator)
            dayBar
            Divider().overlay(Theme.separator)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .onChange(of: channel.id) { _, _ in day = cal.startOfDay(for: Date()) }
    }

    // MARK: Day navigation

    private var earliestDay: Date {
        cal.startOfDay(for: Date().addingTimeInterval(-Double(max(channel.recDays, 0)) * 86_400))
    }
    private var latestDay: Date {
        cal.startOfDay(for: Date().addingTimeInterval(2 * 86_400)) // a little future schedule
    }
    private var canGoBack: Bool { day > earliestDay }
    private var canGoForward: Bool { day < latestDay }

    private var dayBar: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(!canGoBack)
                .accessibilityIdentifier("timeline.prevDay")

            Spacer()
            VStack(spacing: 0) {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if channel.hasArchive {
                    Text("\(channel.recDays)-day archive").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()

            Button { day = cal.startOfDay(for: Date()) } label: { Text("Today") }
                .disabled(cal.isDateInToday(day))
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canGoForward)
                .accessibilityIdentifier("timeline.nextDay")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func step(_ days: Int) {
        if let d = cal.date(byAdding: .day, value: days, to: day) {
            day = min(max(d, earliestDay), latestDay)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.snapshot == nil {
            HStack { Spacer(); ProgressView(model.epgLoading ? "Loading guide…" : "Guide unavailable").controlSize(.small); Spacer() }
                .frame(maxHeight: .infinity)
        } else {
            let programmes = dayProgrammes()
            if programmes.isEmpty {
                Text("No guide data for this day.")
                    .foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(programmes) { programme in
                                ProgrammeCellView(channel: channel, programme: programme)
                                    .id(programme.id)
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .accessibilityIdentifier("timeline.list")
                    .onAppear { scrollToNow(programmes, proxy: proxy) }
                    .onChange(of: day) { _, _ in scrollToNow(programmes, proxy: proxy) }
                }
            }
        }
    }

    private func dayProgrammes() -> [Programme] {
        guard let index = model.snapshot?.index else { return [] }
        let start = day
        let end = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        return index.programmes(channelID: channel.id, in: start...end)
    }

    private func scrollToNow(_ programmes: [Programme], proxy: ScrollViewProxy) {
        let now = Date()
        if let current = programmes.first(where: { $0.contains(now) }) ?? programmes.first(where: { $0.start >= now }) {
            proxy.scrollTo(current.id, anchor: .center)
        }
    }
}

private struct ProgrammeCellView: View {
    @Environment(AppModel.self) private var model
    let channel: Channel
    let programme: Programme

    private var now: Date { Date() }
    private var isAiring: Bool { programme.isAiring(at: now) }
    private var isPast: Bool { programme.hasEnded(at: now) }
    private var playable: Bool { ArchiveURLBuilder.mode(for: channel, programme: programme, now: now) != nil || isAiring }

    var body: some View {
        Button {
            model.playCatchUp(programme, on: channel)
        } label: {
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
                        if isAiring {
                            Text("NOW").font(.caption2.bold()).foregroundStyle(Theme.live)
                        }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .opacity(playable ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .background(isAiring ? Theme.accent.opacity(0.14) : .clear)
        .accessibilityIdentifier("programme.\(Int(programme.start.timeIntervalSince1970))")
    }
}
