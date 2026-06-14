# itv.live — native macOS TV client

A native SwiftUI / AVKit app for watching itv.live: live channels, the full EPG,
and catch-up/archive playback — with favorites, search, continue-watching,
Picture-in-Picture and audio/subtitle track selection. Zero external runtime
dependencies (Apple AVFoundation plays the HLS streams directly).

## Layout

- **Sidebar** — channel groups, a pinned **Favorites** section (drag to reorder),
  **Continue Watching**, and a search field (channels + programme titles).
- **Player** — large AVKit player with native transport, PiP button, full-screen,
  and the audio/subtitle menu.
- **Program timeline** (below the player) — scroll a channel's history day by day
  back to its archive limit **without starting playback**; click a past programme
  to play catch-up, or "Go Live".

## Requirements

- macOS 15+, Xcode 26 / Swift 6.2, and [XcodeGen](https://github.com/yonyz/XcodeGen)
  (`brew install xcodegen`). `xcbeautify` is optional (prettier logs).

## Build & run

```bash
xcodegen generate
xcodebuild -project itvlive.xcodeproj -scheme ITVLive -destination 'platform=macOS,arch=arm64' build
open "$(xcodebuild -project itvlive.xcodeproj -scheme ITVLive -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')"
```

On first launch, open **Settings (⌘,)** and paste your playlist URL
(`https://ru.itv.live/p/<id>/hls.ssl.m3u8`). The EPG URL is discovered
automatically from the playlist and cached on disk. ⌘R refreshes the guide.

## Project structure

- `Packages/ITVKit/` — all pure, testable logic (no UI): M3U + XMLTV parsers,
  `Gunzip`, `ArchiveURLBuilder` (catch-up correctness core), `EPGIndex`,
  `ProgrammeSearchIndex`, `EPGStore` (fetch → gunzip → parse → index + cache),
  `PersistenceStore`.
- `App/` — SwiftUI views, `AppModel`, and `PlayerController` (AVPlayer wrapper).
- `DISCOVERY.md` — the verified itv.live service behaviour the app is built on.

## Tests / QA

```bash
swift test --package-path Packages/ITVKit          # fast hermetic unit tests
Scripts/qa.sh                                       # full 3-layer harness → qa-report.md
```

`Scripts/qa.sh` runs:
1. **Unit + live data** (`swift test`) — parsers, archive URLs, EPG, search,
   persistence, plus live playlist/EPG/archive checks against the real service.
2. **App functional** — main-window creation and **real AVPlayer** live +
   catch-up playback (readyToPlay, time advances, finite seekable VOD).
3. **UI (XCUITest)** — sidebar, channel selection, timeline browse-without-play,
   search. Needs UI-automation permission; skipped/blocked in headless sessions.

Live layers read the playlist URL from `.env.qa` (untracked — copy `.env.qa.example`).
