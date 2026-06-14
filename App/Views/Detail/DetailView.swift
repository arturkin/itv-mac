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
        VStack(spacing: 0) {
            NowPlayingHeader(channel: channel)
            Divider().overlay(Theme.separator)
            AVPlayerViewRepresentable(player: model.player.player)
                .background(Theme.background)
                .accessibilityIdentifier("player.view")
            // Phase 5 inserts the program timeline here.
            ProgramTimelineView(channel: channel)
        }
        .background(Theme.background)
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
