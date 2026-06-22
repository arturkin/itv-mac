import Foundation
import Observation
import ITVKit

struct SidebarSection: Identifiable, Hashable {
    let id: String
    let title: String
    let channels: [Channel]
}

@MainActor
@Observable
final class AppModel {
    enum LoadPhase: Equatable { case idle, loading, ready, failed(String) }

    // Library
    private(set) var playlist: Playlist?
    private(set) var snapshot: EPGSnapshot?
    private(set) var libraryPhase: LoadPhase = .idle
    private(set) var epgLoading = false

    // Selection / search / persisted UX
    var selectedChannelID: String?
    var searchText = ""
    private(set) var favorites: [String] = []

    let player = PlayerController()

    // Settings — persisted playlist URL.
    var playlistURLString: String {
        didSet { UserDefaults.standard.set(playlistURLString, forKey: Self.urlKey) }
    }
    private static let urlKey = "playlistURL"

    /// Persisted height of the resizable bottom EPG/timeline panel (points).
    var timelineHeight: Double {
        didSet { UserDefaults.standard.set(timelineHeight, forKey: Self.timelineHeightKey) }
    }
    private static let timelineHeightKey = "timelineHeight"
    static let minTimelineHeight: Double = 120
    static let maxTimelineHeight: Double = 520

    /// How often the playlist (fresh tokens) and EPG are auto-refreshed.
    static let autoRefreshInterval: TimeInterval = 60 * 60

    private let loader: PlaylistLoader
    private let epgStore: EPGStore
    private let persistence: PersistenceStore?
    private var resumeMap: [String: Double] = [:]
    private let isUITest: Bool
    private var isRecovering = false
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        let cacheDir = Self.cachesDirectory()
        loader = PlaylistLoader()
        // Keep the cached guide fresh: re-fetch when older than the auto-refresh
        // cadence so a cold start never shows a badly stale EPG.
        epgStore = EPGStore(cacheDirectory: cacheDir, maxAge: Self.autoRefreshInterval)
        persistence = try? PersistenceStore(directory: Self.supportDirectory())
        playlistURLString = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        let savedHeight = UserDefaults.standard.object(forKey: Self.timelineHeightKey) as? Double
        timelineHeight = min(max(savedHeight ?? 210, Self.minTimelineHeight), Self.maxTimelineHeight)
        isUITest = CommandLine.arguments.contains("-uitest")

        // Test/QA seam: an env override lets the QA harness drive the real app
        // without UI typing. It also persists (via didSet) for convenience.
        if let override = ProcessInfo.processInfo.environment["ITV_PLAYLIST_URL"], !override.isEmpty {
            playlistURLString = override
        }

        wirePlayer()
        if isUITest { loadFixtureForUITests() }
    }

    var hasPlaylistURL: Bool { URL(string: playlistURLString)?.scheme != nil }

    // MARK: - Loading

    func bootstrap() async {
        guard !isUITest else { return }
        await loadFavorites()
        if hasPlaylistURL { await loadLibrary() }
        startAutoRefresh()
    }

    /// Periodically re-fetch the playlist (fresh stream tokens) and EPG so the
    /// next session — and a long-running one — starts with valid, current data
    /// and playback isn't interrupted by stale tokens. Non-disruptive: it never
    /// touches the currently-playing item.
    func startAutoRefresh(interval: TimeInterval = autoRefreshInterval) {
        guard !isUITest else { return }
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                _ = await self.refreshPlaylist()
                await self.loadEPG(forceRefresh: true)
            }
        }
    }

    func loadLibrary() async {
        guard let url = URL(string: playlistURLString), url.scheme != nil else {
            libraryPhase = .failed("Enter a valid playlist URL in Settings.")
            return
        }
        libraryPhase = .loading
        do {
            let pl = try await loader.load(from: url)
            playlist = pl
            libraryPhase = .ready
            if selectedChannelID == nil { selectedChannelID = pl.channels.first?.id }
            await loadEPG()
        } catch {
            libraryPhase = .failed(error.localizedDescription)
        }
    }

    func loadEPG(forceRefresh: Bool = false) async {
        guard let pl = playlist, pl.epgURL != nil else { return }
        epgLoading = true
        defer { epgLoading = false }
        snapshot = try? await epgStore.snapshot(for: pl, forceRefresh: forceRefresh)
    }

    /// Lightweight playlist re-fetch (fresh tokens) without resetting selection/EPG.
    func refreshPlaylist() async -> Bool {
        guard let url = URL(string: playlistURLString), url.scheme != nil else { return false }
        guard let pl = try? await loader.load(from: url) else { return false }
        playlist = pl
        return true
    }

    private func loadFavorites() async {
        guard let persistence else { return }
        favorites = await persistence.loadFavorites()
        resumeMap = await persistence.loadResume()
    }

    // MARK: - Selection & playback

    func channel(for id: String?) -> Channel? {
        guard let id else { return nil }
        return playlist?.channels.first { $0.id == id }
    }

    var selectedChannel: Channel? { channel(for: selectedChannelID) }

    func selectChannel(_ id: String) {
        selectedChannelID = id
        if let channel = channel(for: id) { player.playLive(channel) }
    }

    @discardableResult
    func playCatchUp(_ programme: Programme, on channel: Channel) -> Bool {
        selectedChannelID = channel.id
        return player.playCatchUp(channel, programme: programme)
    }

    // MARK: - Favorites

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let idx = favorites.firstIndex(of: id) { favorites.remove(at: idx) } else { favorites.append(id) }
        persist { await $0.saveFavorites(self.favorites) }
    }

    func moveFavorites(from offsets: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        persist { await $0.saveFavorites(self.favorites) }
    }

    // MARK: - Sidebar model

    var sidebarSections: [SidebarSection] {
        guard let playlist else { return [] }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return searchSections(playlist: playlist)
        }
        var sections: [SidebarSection] = []
        let favChannels = favorites.compactMap { id in playlist.channels.first { $0.id == id } }
        if !favChannels.isEmpty {
            sections.append(SidebarSection(id: "__favorites", title: "Favorites", channels: favChannels))
        }
        for group in playlist.groupOrder {
            let chans = playlist.channels(in: group)
            guard !chans.isEmpty else { continue }
            sections.append(SidebarSection(id: group, title: group.isEmpty ? "Other" : group, channels: chans))
        }
        return sections
    }

    /// Search hits across channels + (when EPG is loaded) past/future programme titles.
    private(set) var searchProgrammeHits: [ProgrammeSearchIndex.Hit] = []

    private func searchSections(playlist: Playlist) -> [SidebarSection] {
        let query = searchText
        if let search = snapshot?.search {
            let hits = search.search(query, limit: 60)
            searchProgrammeHits = hits.filter { $0.kind == .programme }
            let channelHits = hits.compactMap { hit -> Channel? in
                hit.kind == .channel ? playlist.channels.first { $0.id == hit.channelID } : nil
            }
            return [SidebarSection(id: "__search", title: "Channels", channels: channelHits)]
        } else {
            let hits = playlist.channels.filter { $0.name.localizedCaseInsensitiveContains(query) }
            searchProgrammeHits = []
            return [SidebarSection(id: "__search", title: "Channels", channels: hits)]
        }
    }

    // MARK: - Player wiring

    private func wirePlayer() {
        player.resumeLookup = { [weak self] channel, programme in
            self?.resumeMap[ResumeKey.make(channelID: channel.id, programmeStart: programme.start)]
        }
        player.onProgress = { [weak self] channel, programme, seconds in
            guard let self else { return }
            let key = ResumeKey.make(channelID: channel.id, programmeStart: programme.start)
            self.resumeMap[key] = seconds
            self.persist { await $0.setResume(key: key, seconds: seconds) }
        }
        player.onPlaybackFailed = { [weak self] channel, programme in
            // In UI-test mode the fixture is fully offline; never reach out to the
            // network on a (expected) playback failure or it would clobber the
            // deterministic fixture with the real playlist.
            guard let self, !self.isRecovering, !self.isUITest else { return }
            self.isRecovering = true
            Task {
                // A failure may be a stale token; re-fetch the playlist once and retry.
                if await self.refreshPlaylist(), let fresh = self.channel(for: channel.id) {
                    if let programme { _ = self.player.playCatchUp(fresh, programme: programme) }
                    else { self.player.playLive(fresh) }
                }
                self.isRecovering = false
            }
        }
    }

    private func persist(_ work: @escaping @Sendable (PersistenceStore) async -> Void) {
        guard let persistence else { return }
        Task { await work(persistence) }
    }

    // MARK: - Directories

    private static func cachesDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("itv.live/epg", isDirectory: true)
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("itv.live", isDirectory: true)
    }

    // MARK: - Snapshot seam

    /// Seeds favorites **in memory only** (no disk write) so the headless snapshot
    /// harness can render the Favorites section without polluting the user's real
    /// persisted state. Snapshot-mode only.
    func seedForSnapshot(favorites: [String]) {
        self.favorites = favorites
    }

    // MARK: - UI-test fixture (deterministic, offline)

    private func loadFixtureForUITests() {
        let m3u = """
        #EXTM3U url-tvg="https://epg.example/epg.xml.gz"
        #EXTINF:-1 tvg-id="ch057" tvg-rec="10" tvg-logo="https://logo.example/a.png" group-title="Спорт", Матч! HD
        https://cloud.example/ch057/index.m3u8?token=T1
        #EXTINF:-1 tvg-id="ch003" tvg-rec="5" tvg-logo="https://logo.example/b.png" group-title="Новости", Первый Канал HD
        https://cloud.example/ch003/index.m3u8?token=T2
        #EXTINF:-1 tvg-id="ch500" group-title="Кино", Кинокомедия
        https://cloud.example/ch500/index.m3u8?token=T3
        """
        guard let pl = try? M3UPlaylistParser.parse(m3u) else { return }
        playlist = pl
        selectedChannelID = "ch057"

        let now = Date()
        var progs: [Programme] = []
        for ch in ["ch057", "ch003"] {
            for i in -8..<8 {
                let start = now.addingTimeInterval(Double(i) * 1800)
                progs.append(Programme(channelID: ch,
                                       start: start,
                                       stop: start.addingTimeInterval(1800),
                                       title: "\(ch) Show \(i + 8)",
                                       desc: "Synthetic programme for UI tests."))
            }
        }
        let index = EPGIndex(programmes: progs, channelNames: ["ch057": "Матч! HD", "ch003": "Первый Канал HD"])
        let search = ProgrammeSearchIndex(channels: pl.channels, programmes: progs)
        snapshot = EPGSnapshot(index: index, search: search, builtAt: now)
        libraryPhase = .ready
    }
}
