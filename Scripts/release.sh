#!/usr/bin/env bash
#
# Builds the shippable **Release** (ad-hoc signed) .app, smoke-validates the
# optimized binary against the real playlist via the headless snapshot harness,
# and installs it to ~/Applications. This is the "prod build for personal use"
# path — it runs on this Mac but is not notarized for other Macs.
#
# For Developer-ID + notarized distribution to OTHER machines, see DISTRIBUTION.md.
#
# Usage: Scripts/release.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROJ="itvlive.xcodeproj"
SCHEME="ITVLive"
DEST='platform=macOS,arch=arm64'
LOGDIR="$ROOT/.qa-logs"; mkdir -p "$LOGDIR"
[ -f "$ROOT/.env.qa" ] && . "$ROOT/.env.qa"
PLAYLIST="${ITV_PLAYLIST_URL:-}"

echo "▶ Regenerating project…"
command -v xcodegen >/dev/null 2>&1 && xcodegen generate --spec "$ROOT/project.yml" >/dev/null 2>&1

echo "▶ Building Release (clean)…"
BUILD_LOG="$LOGDIR/release-build.log"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -destination "$DEST" clean build > "$BUILD_LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Release build FAILED — last lines:"; grep -E "error:" "$BUILD_LOG" | grep -vi appintents | tail -20
    exit 1
fi

APP="$(xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')"
echo "  built: $APP"

echo "▶ Verifying code signature…"
codesign --verify --strict --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
SIGN="$(codesign -dvv "$APP" 2>&1 | grep -E 'Signature|flags' | tr '\n' ' ')"
echo "  $SIGN"

echo "▶ Confirming this is an optimized Release build (no debug Swift runtime)…"
if otool -L "$APP/Contents/MacOS/ITVLive" 2>/dev/null | grep -qi "lib.*Debug.dylib"; then
    echo "  ⚠️ debug runtime linked — not a clean Release build"; else echo "  ✓ no debug runtime linked"; fi

# ── Smoke test: drive the real Release binary headlessly (renders + decodes video) ─
SMOKE="skipped (no ITV_PLAYLIST_URL)"
if [ -n "$PLAYLIST" ]; then
    echo "▶ Smoke-validating the Release binary against the real playlist…"
    BIN="$APP/Contents/MacOS/ITVLive"
    pkill -9 -f "ITVLive.app" 2>/dev/null; sleep 1
    SNAP_OUT="$LOGDIR/release-snapshot.out"
    ITV_PLAYLIST_URL="$PLAYLIST" "$BIN" --snapshot "$ROOT/qa-snapshots" > "$SNAP_OUT" 2>&1 &
    PID=$!
    for _ in $(seq 1 120); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
    kill -0 "$PID" 2>/dev/null && { echo "  watchdog: killing stalled run"; kill -9 "$PID" 2>/dev/null; }
    SNAP_DIR="$(grep -E '^SNAPSHOT_DIR=' "$SNAP_OUT" 2>/dev/null | tail -1 | cut -d= -f2-)"
    if [ -n "$SNAP_DIR" ] && grep -q "window=ok(" "$SNAP_DIR/log.txt" 2>/dev/null; then
        cp -f "$SNAP_DIR"/*.png "$ROOT/qa-snapshots/" 2>/dev/null
        CH=$(grep -E '^channels=' "$SNAP_DIR/log.txt" | cut -d= -f2)
        LF=$(grep -q 'liveFrame=ok' "$SNAP_DIR/log.txt" && echo "live✓" || echo "live—")
        AF=$(grep -q 'archiveFrame=ok' "$SNAP_DIR/log.txt" && echo "catch-up✓" || echo "catch-up—")
        SMOKE="PASS — rendered from $CH real channels; decoded frames: $LF $AF"
    else
        echo "❌ Smoke validation FAILED — Release binary did not render. See $SNAP_OUT"
        exit 1
    fi
    echo "  $SMOKE"
fi

echo "▶ Installing to ~/Applications…"
pkill -9 -f "ITVLive.app" 2>/dev/null; sleep 1
rm -rf ~/Applications/ITVLive.app
cp -R "$APP" ~/Applications/

echo
echo "════ RELEASE SUMMARY ════"
echo "Config:   Release (ad-hoc signed, runs on this Mac; not notarized)"
echo "Built:    $APP"
echo "Smoke:    $SMOKE"
echo "Installed: ~/Applications/ITVLive.app"
echo "Note:     run Scripts/qa.sh for the full test suite; see DISTRIBUTION.md to notarize for other Macs."
