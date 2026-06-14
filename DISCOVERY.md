# itv.live — verified service behaviour (2026-06-14)

Confirmed by live probes against the user's subscription. These facts are baked into the implementation.

## Playlist
- URL: `https://ru.itv.live/p/<id>/hls.ssl.m3u8` — 199 channels.
- **CRLF line endings** → the M3U parser must strip `\r`.
- Header: `#EXTM3U url-tvg="https://ru.itv.tools/epg/<id>/epgfull.xml.gz"`.
- Channel block:
  ```
  #EXTINF:-1 tvg-id="ch057" tvg-rec="10" tvg-logo="https://api.01cdn.wf/icon/ch057.png"  group-title="Спорт", Матч! HD
  #EXTGRP:1. Спорт
  https://cloud02.03cdn.wf/ch057/index.m3u8?token=<64hex>
  ```
- `tvg-rec` = days of archive (absent/0 ⇒ no archive). Note: two spaces before `group-title` (tolerant attr parsing).
- Token shares a per-subscription prefix + per-channel suffix; **use the live URL's token verbatim per channel** for archive too.

## Stream addressing (Flussonic, cloudNN.03cdn.wf)
Base = live URL minus `/index.m3u8?...` → `https://cloud02.03cdn.wf/ch057`. All variants share base + `?token=`.

| Purpose | URL (filename varies) | Child media playlist | Type |
|---|---|---|---|
| **Live** | `…/ch057/index.m3u8?token=` | `tracks-v1a1/mono.m3u8` | sliding, no ENDLIST |
| **Past programme** | `…/ch057/archive-<startUnix>-<durSec>.m3u8?token=` | `tracks-v1a1/index-<from>-<dur>.m3u8` | **`PLAYLIST-TYPE:VOD` + ENDLIST** (finite, seekable, stops at boundary) |
| **In-progress** | `…/ch057/index-<startUnix>-now.m3u8?token=` | growing | **`PLAYLIST-TYPE:EVENT`** |
| Fallback (unused) | `…/ch057/timeshift_abs-<unix>.m3u8?token=` | sliding | live |

- `archive-` master is **multivariant** with multiple audio tracks (`rus a1` AAC default, `AC3 a2`) ⇒ audio-track selection is real.
- Server **rounds `<startUnix>` to a segment/GOP boundary** (~tens of seconds). Acceptable for catch-up; optionally pad start a few seconds.
- AVPlayer resolves child playlists from the master — we only ever construct the **master** URL.
- **Decision:** primary catch-up = `archive-<start>-<dur>` (VOD); in-progress = `index-<start>-now` (EVENT); live = `index.m3u8`. `timeshift_abs` fallback not needed (builder keeps it for robustness).

## EPG
- `https://ru.itv.tools/epg/<id>/epgfull.xml.gz` — **23 MB gzip**, magic `1f8b`.
- **No `Content-Encoding: gzip` header** ⇒ URLSession won't decompress; we gunzip ourselves.
- Standard XMLTV: `<channel id="ch057"><display-name>…</display-name></channel>`,
  `<programme channel="ch057" start="YYYYMMDDHHmmss +0300" stop="…"><title>…</title><desc>…</desc></programme>`.
  No duration attr (compute stop − start). `id` ↔ `tvg-id`.

## No blockers
Plain HLS, no DRM, no special User-Agent, HTTPS, no geo-block. AVKit/AVFoundation plays everything natively.
