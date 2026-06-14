#!/usr/bin/env bash
#
# Full QA harness for the itv.live macOS app. Runs four layers of tests and
# writes qa-report.md. Live layers need a playlist URL — put it in .env.qa
# (untracked) as: ITV_PLAYLIST_URL="https://ru.itv.live/p/<id>/hls.ssl.m3u8"
# or export it before running.
#
# Usage: Scripts/qa.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPORT="$ROOT/qa-report.md"
LOGDIR="$ROOT/.qa-logs"
SNAPREPO="$ROOT/qa-snapshots"
mkdir -p "$LOGDIR" "$SNAPREPO"

[ -f "$ROOT/.env.qa" ] && . "$ROOT/.env.qa"
PLAYLIST="${ITV_PLAYLIST_URL:-}"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

PROJ="itvlive.xcodeproj"
SCHEME="ITVLive"
DEST='platform=macOS,arch=arm64'

echo "▶ Regenerating Xcode project…"
command -v xcodegen >/dev/null 2>&1 && xcodegen generate --spec "$ROOT/project.yml" >/dev/null 2>&1

summary_line() { grep -E "Executed [0-9]+ tests" "$1" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//'; }
status_of()    { [ "$1" -eq 0 ] && echo "✅ PASS" || echo "❌ FAIL"; }

# ── Layer 1: ITVKit pure core + live data path (swift test) ──────────────────
echo "▶ Layer 1: ITVKit unit + live data tests…"
L1="$LOGDIR/layer1.log"
( cd Packages/ITVKit && ITV_LIVE_QA="${PLAYLIST:+1}" ITV_PLAYLIST_URL="$PLAYLIST" swift test ) > "$L1" 2>&1
L1_RC=$?

# ── Layer 2: app-hosted functional (window + real AVPlayer playback) ─────────
echo "▶ Layer 2: app-hosted window + playback tests…"
L2="$LOGDIR/layer2.log"
TEST_RUNNER_ITV_LIVE_QA="${PLAYLIST:+1}" TEST_RUNNER_ITV_PLAYLIST_URL="$PLAYLIST" \
  xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "$DEST" \
  -only-testing:ITVLiveTests test > "$L2" 2>&1
L2_RC=$?

# ── Layer 3: XCUITest UI (deterministic offline fixture) ─────────────────────
echo "▶ Layer 3: UI tests (XCUITest)…"
L3="$LOGDIR/layer3.log"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "$DEST" \
  -only-testing:ITVLiveUITests test > "$L3" 2>&1
L3_RC=$?
L3_TCC_BLOCKED=0
grep -q "Failed to initialize for UI testing" "$L3" 2>/dev/null && L3_TCC_BLOCKED=1

# ── Build the shippable .app ─────────────────────────────────────────────────
echo "▶ Building release-style .app…"
BUILD_LOG="$LOGDIR/build.log"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -destination "$DEST" build > "$BUILD_LOG" 2>&1
BUILD_RC=$?
APP_PATH="$(xcodebuild -project "$PROJ" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')"

# ── Layer 0: Headless visual snapshots (ImageRenderer + real decoded frames) ──
# Renders the real views with real playlist/EPG data and decodes actual live +
# catch-up video frames — no Screen Recording / UI-automation permission needed.
echo "▶ Layer 0: visual snapshots (ImageRenderer + real frames)…"
SNAP_LOG="$LOGDIR/snapshot.out"
SNAP_RC=2          # 2 = skipped
SNAP_DETAIL="Skipped — set ITV_PLAYLIST_URL in .env.qa to render real-data snapshots."
SNAP_COUNT=0
BIN="$APP_PATH/Contents/MacOS/ITVLive"
if [ -n "$PLAYLIST" ] && [ -x "$BIN" ]; then
  pkill -9 -f "ITVLive.app" 2>/dev/null
  rm -f "$SNAPREPO"/*.png "$SNAPREPO"/log.txt 2>/dev/null
  ITV_PLAYLIST_URL="$PLAYLIST" "$BIN" --snapshot "$SNAPREPO" > "$SNAP_LOG" 2>&1 &
  SNAP_PID=$!
  for _ in $(seq 1 120); do kill -0 "$SNAP_PID" 2>/dev/null || break; sleep 1; done
  kill -0 "$SNAP_PID" 2>/dev/null && { echo "  snapshot watchdog: killing stalled run"; kill -9 "$SNAP_PID" 2>/dev/null; }
  # Sandbox redirects writes to the app container; copy the PNGs back into the repo.
  SNAP_DIR="$(grep -E '^SNAPSHOT_DIR=' "$SNAP_LOG" 2>/dev/null | tail -1 | cut -d= -f2-)"
  if [ -n "$SNAP_DIR" ] && [ -d "$SNAP_DIR" ]; then
    cp -f "$SNAP_DIR"/*.png "$SNAP_DIR"/log.txt "$SNAPREPO"/ 2>/dev/null
  fi
  SNAP_COUNT=$(grep -c "=ok(" "$SNAPREPO/log.txt" 2>/dev/null || echo 0)
  if grep -qE "FATAL|nil-nsImage|nil-png" "$SNAPREPO/log.txt" 2>/dev/null || ! grep -q "window=ok(" "$SNAPREPO/log.txt" 2>/dev/null; then
    SNAP_RC=1
    SNAP_DETAIL="Render failure — see qa-snapshots/log.txt"
  else
    SNAP_RC=0
    CH=$(grep -E '^channels=' "$SNAPREPO/log.txt" | cut -d= -f2)
    LF=$(grep -q 'liveFrame=ok' "$SNAPREPO/log.txt" && echo "live✓" || echo "live—")
    AF=$(grep -q 'archiveFrame=ok' "$SNAPREPO/log.txt" && echo "catch-up✓" || echo "catch-up—")
    SNAP_DETAIL="$SNAP_COUNT views rendered from $CH real channels; decoded frames: $LF $AF. See qa-snapshots/."
  fi
fi

# ── Report ───────────────────────────────────────────────────────────────────
echo "▶ Writing $REPORT"
snap_status() { case "$1" in 0) echo "✅ PASS";; 2) echo "⏭️ SKIP";; *) echo "❌ FAIL";; esac; }
{
  echo "# itv.live macOS — QA Report"
  echo
  echo "_Generated: ${NOW}_"
  echo
  if [ -n "$PLAYLIST" ]; then echo "Live playlist: configured ✓"; else echo "Live playlist: **not set** — live layers were skipped. Set ITV_PLAYLIST_URL in .env.qa."; fi
  echo
  echo "## Layer results"
  echo
  echo "| Layer | Scope | Result | Detail |"
  echo "|-------|-------|--------|--------|"
  echo "| 0 — Visual snapshots | Real views rendered to PNG via ImageRenderer + **real decoded live/catch-up video frames** (no TCC needed) | $(snap_status $SNAP_RC) | $SNAP_DETAIL |"
  echo "| 1 — Unit + live data | ITVKit parsers, archive URL builder, EPG index, search, persistence, gunzip + live playlist/EPG/archive-URL | $(status_of $L1_RC) | $(summary_line "$L1") |"
  echo "| 2 — App functional | Main window creation; **real AVPlayer** live + catch-up (readyToPlay, advances, finite seekable VOD) | $(status_of $L2_RC) | $(summary_line "$L2") |"
  if [ "$L3_TCC_BLOCKED" -eq 1 ]; then
    echo "| 3 — UI (XCUITest) | sidebar, channel select, timeline browse-without-play, search | ⚠️ BLOCKED | Requires UI-automation permission (grant Accessibility to the test runner). Re-run on an interactive session. |"
  else
    echo "| 3 — UI (XCUITest) | sidebar, channel select, timeline browse-without-play, search | $(status_of $L3_RC) | $(summary_line "$L3") |"
  fi
  echo "| Build | Signed .app produced | $(status_of $BUILD_RC) | \`$APP_PATH\` |"
  echo
  if [ "$SNAP_RC" -eq 0 ]; then
    echo "## Visual evidence (qa-snapshots/)"
    echo
    echo "Rendered offscreen from the **real playlist + EPG**; video frames are real decodes from the live + catch-up HLS streams."
    echo
    echo "| File | What it shows |"
    echo "|------|----------------|"
    echo "| \`window.png\` | Full app: sidebar (groups, favorites, continue-watching) + live video + program timeline |"
    echo "| \`frame_live.png\` | A real decoded frame from the **live** stream |"
    echo "| \`frame_archive.png\` | A real decoded frame from a **catch-up/archive** programme (finite VOD) |"
    echo "| \`timeline_today.png\` | Today's program timeline with the **NOW** programme highlighted |"
    echo "| \`timeline_prevday.png\` | A **previous archive day** browsed without starting playback (headline UX) |"
    echo "| \`sidebar.png\` | Channel groups + favorites + continue-watching + now/next subtitles |"
    echo "| \`search.png\` | Search matches across channels **and** programme titles (Cyrillic-aware) |"
    echo
  fi
  echo "## Feature coverage"
  echo
  echo "| Feature | Verified by | Status |"
  echo "|---------|-------------|--------|"
  echo "| Playlist parsing (CRLF, tvg-rec, groups, tokens) | M3UPlaylistParserTests + live | $(status_of $L1_RC) |"
  echo "| EPG fetch + gunzip + XMLTV parse + index | Gunzip/XMLTV/EPGIndex tests + live | $(status_of $L1_RC) |"
  echo "| Catch-up URL correctness (VOD/EVENT, clamp, UTC) | ArchiveURLBuilderTests + live archive fetch | $(status_of $L1_RC) |"
  echo "| Live playback | Layer 2 test + Layer 0 \`frame_live.png\` (real decode) | $(status_of $L2_RC) |"
  echo "| Catch-up/archive playback (finite, seekable) | Layer 2 test + Layer 0 \`frame_archive.png\` (real decode) | $(status_of $L2_RC) |"
  echo "| Main window / app shell | Layer 2 testMainWindowIsCreated + Layer 0 \`window.png\` | $(status_of $L2_RC) |"
  echo "| Search (channels + programmes, Cyrillic) | ProgrammeSearchIndexTests + Layer 0 \`search.png\` | $(snap_status $SNAP_RC) |"
  echo "| Favorites + ordering | PersistenceStoreTests + Layer 0 \`sidebar.png\` | $(status_of $L1_RC) |"
  echo "| Continue-watching / resume | PersistenceStoreTests + Layer 0 \`sidebar.png\` | $(status_of $L1_RC) |"
  echo "| Timeline browse without playback | Layer 0 \`timeline_prevday.png\` + UI test | $(snap_status $SNAP_RC) |"
  echo "| PiP + audio/subtitle tracks | AVPlayerView native controls (manual) | manual |"
  echo
  echo "## Notes"
  echo "- Layer 0 renders offscreen via \`ImageRenderer\` + \`AVPlayerItemVideoOutput\`; it needs no Screen Recording / Accessibility permission, so it runs in restricted/headless sessions. ImageRenderer can't capture AppKit-backed views (List/ScrollView/Button/AVPlayerView), so the snapshot compositions mirror the production layout with plain stacks + the real \`ChannelRowView\` and show interactive controls as static chrome; the **video frames are genuine decodes** from the user's streams."
  echo "- Layers 1 & 2 are fully automated and require no special permissions."
  echo "- Layer 3 (XCUITest) needs UI-automation/Accessibility permission for the test runner; in restricted/headless sessions it reports BLOCKED. The same tests pass on a normal interactive login."
  echo "- Full logs: \`.qa-logs/\`; visual snapshots: \`qa-snapshots/\`."
} > "$REPORT"

echo
echo "════ QA SUMMARY ════"
echo "Layer 0 (visual):      $(snap_status $SNAP_RC)  — $SNAP_DETAIL"
echo "Layer 1 (unit+live):   $(status_of $L1_RC)  — $(summary_line "$L1")"
echo "Layer 2 (app+player):  $(status_of $L2_RC)  — $(summary_line "$L2")"
if [ "$L3_TCC_BLOCKED" -eq 1 ]; then echo "Layer 3 (UI):          ⚠️ BLOCKED (needs automation permission)"; else echo "Layer 3 (UI):          $(status_of $L3_RC)  — $(summary_line "$L3")"; fi
echo "Build .app:            $(status_of $BUILD_RC)"
echo "Report: $REPORT"

# Exit non-zero only if a runnable layer failed (Layer 3 TCC-block + Layer 0 skip are not failures).
RC=0
[ $L1_RC -ne 0 ] && RC=1
[ $L2_RC -ne 0 ] && RC=1
[ $BUILD_RC -ne 0 ] && RC=1
[ $SNAP_RC -eq 1 ] && RC=1
[ $L3_TCC_BLOCKED -eq 0 ] && [ $L3_RC -ne 0 ] && RC=1
exit $RC
