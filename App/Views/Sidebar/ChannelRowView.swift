import SwiftUI
import ITVKit

struct ChannelRowView: View {
    @Environment(AppModel.self) private var model
    let channel: Channel

    var body: some View {
        HStack(spacing: 8) {
            ChannelLogo(url: channel.logoURL)
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name)
                    .lineLimit(1)
                if let now = model.snapshot?.index.nowNext(channelID: channel.id, at: Date()).now {
                    Text(now.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if model.isFavorite(channel.id) {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Theme.star)
            }
            if channel.hasArchive {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .help("\(channel.recDays)-day archive")
            }
        }
        .accessibilityIdentifier("channel.\(channel.id)")
    }
}

struct ChannelLogo: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
            default:
                Image(systemName: "tv").foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 5))
    }
}
