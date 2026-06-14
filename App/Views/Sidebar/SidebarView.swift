import SwiftUI
import ITVKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedChannelID) {
            if model.searchText.isEmpty && !model.recents.isEmpty {
                Section("Continue Watching") {
                    ForEach(model.recents.prefix(6)) { item in
                        Button { model.replay(item) } label: {
                            Label(item.title, systemImage: item.programmeStart == nil ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    if section.id == "__favorites" {
                        ForEach(section.channels) { channel in
                            ChannelRowView(channel: channel).tag(channel.id)
                                .contextMenu { favoriteMenu(channel) }
                        }
                        .onMove { offsets, dest in model.moveFavorites(from: offsets, to: dest) }
                    } else {
                        ForEach(section.channels) { channel in
                            ChannelRowView(channel: channel).tag(channel.id)
                                .contextMenu { favoriteMenu(channel) }
                        }
                    }
                }
            }

            if !model.searchProgrammeHits.isEmpty {
                Section("Programmes") {
                    ForEach(model.searchProgrammeHits) { hit in
                        ProgrammeHitRow(hit: hit)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search channels & programmes")
        .accessibilityIdentifier("sidebar.list")
        .onChange(of: model.selectedChannelID) { _, newValue in
            if let id = newValue { model.selectChannel(id) }
        }
        .overlay {
            if model.libraryPhase == .loading {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder private func favoriteMenu(_ channel: Channel) -> some View {
        Button(model.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") {
            model.toggleFavorite(channel.id)
        }
    }
}

private struct ProgrammeHitRow: View {
    @Environment(AppModel.self) private var model
    let hit: ProgrammeSearchIndex.Hit

    var body: some View {
        Button {
            if let programme = hit.programme, let channel = model.channel(for: hit.channelID) {
                model.playCatchUp(programme, on: channel)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).lineLimit(1)
                Text(model.channel(for: hit.channelID)?.name ?? hit.channelID)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
