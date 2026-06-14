# Distributing itv.live to other Macs (Developer ID + notarization)

`Scripts/release.sh` produces an **ad-hoc–signed** Release build. It runs on *this*
Mac, but Gatekeeper will block it on any other Mac ("can't be opened because Apple
cannot check it…"). To hand the `.app` to other machines cleanly, sign it with a
**Developer ID Application** certificate, enable the **Hardened Runtime**, and
**notarize** it. This guide is copy-paste; replace `TEAMID` and the Apple ID.

---

## 0. One-time prerequisites

1. **Apple Developer Program** membership ($99/yr) — <https://developer.apple.com/programs/>.
2. A **Developer ID Application** certificate in your login keychain:
   - Xcode → **Settings → Accounts** → select your Apple ID → **Manage Certificates…**
     → **+** → **Developer ID Application**.
   - Confirm it's installed and note your Team ID (the 10 chars in parentheses):
     ```sh
     security find-identity -v -p codesigning
     # → "Developer ID Application: Your Name (TEAMID)"
     ```
3. **Store notarization credentials once** (so you don't paste them each time):
   - Create an app-specific password at <https://appleid.apple.com> → *Sign-In & Security
     → App-Specific Passwords*.
   - Then:
     ```sh
     xcrun notarytool store-credentials itvlive-notary \
       --apple-id "you@example.com" --team-id "TEAMID" --password "abcd-efgh-ijkl-mnop"
     ```
     (`itvlive-notary` is just a local keychain profile name used in step 3.)

---

## 1. Switch signing in `project.yml`

Change the app's signing from ad-hoc to Developer ID + Hardened Runtime. In
`project.yml` under `settings.base`, replace:

```yaml
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: "NO"
```

with:

```yaml
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Developer ID Application"
    DEVELOPMENT_TEAM: "TEAMID"
    ENABLE_HARDENED_RUNTIME: "YES"
```

Then regenerate the project:

```sh
xcodegen generate
```

> The existing entitlements (`App/ITVLive.entitlements` — App Sandbox + `network.client`)
> are compatible with the Hardened Runtime. Sandbox is *optional* for Developer ID
> distribution (it's only mandatory for the Mac App Store), but keeping it is harmless.

---

## 2. Build, archive & export (Developer ID signed)

```sh
# Clean Release archive
xcodebuild -project itvlive.xcodeproj -scheme ITVLive -configuration Release \
  -archivePath build/ITVLive.xcarchive archive

# Export a Developer-ID-signed .app from the archive
xcodebuild -exportArchive -archivePath build/ITVLive.xcarchive \
  -exportPath build/export -exportOptionsPlist exportOptions.plist
```

Create `exportOptions.plist` once (commit it — no secrets):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>method</key>        <string>developer-id</string>
  <key>teamID</key>        <string>TEAMID</string>
  <key>signingStyle</key>  <string>manual</string>
</dict></plist>
```

Output: `build/export/ITVLive.app` — Developer ID signed, hardened runtime on.

Verify the signature/runtime before notarizing:

```sh
codesign -dvvv --verbose=4 build/export/ITVLive.app 2>&1 | grep -E "Authority|flags|TeamIdentifier"
# Expect: Authority=Developer ID Application…, flags=…runtime, TeamIdentifier=TEAMID
```

---

## 3. Notarize

```sh
ditto -c -k --keepParent build/export/ITVLive.app build/ITVLive.zip
xcrun notarytool submit build/ITVLive.zip --keychain-profile itvlive-notary --wait
```

Wait for `status: Accepted`. If it's `Invalid`, read the log:

```sh
xcrun notarytool log <submission-id> --keychain-profile itvlive-notary
```

---

## 4. Staple & verify

```sh
xcrun stapler staple build/export/ITVLive.app
spctl -a -vvv -t install build/export/ITVLive.app
# Expect: accepted  source=Notarized Developer ID
```

Stapling embeds the notarization ticket so the app opens cleanly even offline.

---

## 5. Distribute

Zip the stapled app (or wrap it in a `.dmg`) and send it:

```sh
ditto -c -k --keepParent build/export/ITVLive.app build/ITVLive-notarized.zip
```

Recipients unzip and open it with no Gatekeeper warning. They still paste **their own**
playlist URL in Settings on first launch.

---

## Reverting to the personal ad-hoc build

Put `project.yml` back to:

```yaml
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: "NO"
```

(remove `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE`), `xcodegen generate`, then
`Scripts/release.sh`.

---

## Notes

- **Re-notarize whenever the binary changes.** A stapled ticket is tied to that exact build.
- **Never ship `.env.qa`** — the playlist URL embeds your private subscription token, and it
  is git-ignored for that reason (see `.gitignore`). The token is *not* compiled into the
  binary; every user enters their own URL in Settings.
- The hidden `--snapshot` / `-uitest` launch flags are inert without those arguments. If you'd
  rather not ship them in a widely-distributed build, wrap `SnapshotMode` and
  `loadFixtureForUITests()` in `#if DEBUG` before archiving (this disables Release snapshot QA).
- Apple Silicon + Intel: add `-destination 'generic/platform=macOS'` to the `archive` step to
  produce a universal binary if you need to support Intel Macs.
