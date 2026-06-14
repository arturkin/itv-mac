import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Playlist") {
                TextField("Playlist URL", text: $model.playlistURLString,
                          prompt: Text("https://ru.itv.live/p/<id>/hls.ssl.m3u8"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.playlistURL")
                    .onSubmit { Task { await model.loadLibrary() } }

                HStack {
                    Button("Load Channels") { Task { await model.loadLibrary() } }
                        .disabled(!model.hasPlaylistURL)
                        .accessibilityIdentifier("settings.load")
                    if model.libraryPhase == .loading { ProgressView().controlSize(.small) }
                    Spacer()
                    statusText
                }
            }

            Section {
                Button("Refresh EPG now") { Task { await model.loadEPG(forceRefresh: true) } }
                    .disabled(model.playlist == nil)
            } footer: {
                Text("The program guide is discovered automatically from the playlist and cached on disk.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540)
    }

    @ViewBuilder private var statusText: some View {
        switch model.libraryPhase {
        case .ready:
            if let count = model.playlist?.channels.count {
                Text("\(count) channels").foregroundStyle(Theme.textSecondary).font(.caption)
            }
        case .failed(let message):
            Text(message).foregroundStyle(Theme.live).font(.caption).lineLimit(2)
        default:
            EmptyView()
        }
    }
}
