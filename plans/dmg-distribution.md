# Plan: DMG Distribution

## Background

DeskMat is currently signed with an **Apple Development** certificate (used for
local testing only). Distributing outside the Mac App Store requires:

1. A **Developer ID Application** certificate — proves to Gatekeeper that the
   app came from a known developer
2. **Notarization** — Apple scans the binary and staples a ticket so Gatekeeper
   passes on any Mac without a warning dialog
3. A **DMG** — the standard drag-to-install container for Mac apps

Relevant facts gathered from the project:

| Property | Value |
|---|---|
| Bundle ID | `com.kinghorn.deskmat` |
| Team ID | `PMNC24R94X` |
| Version | 1.3 (build 8) |
| Hardened Runtime | Enabled ✓ |
| App Sandbox | Enabled ✓ |
| Entitlements | user-selected files, pictures, network client |

No existing build scripts — everything will be created from scratch.

---

## Phases

### Phase 1 — Prerequisites

These are one-time account/tooling steps, not code changes.

**1a — Developer ID Application certificate**

In Xcode → Settings → Accounts → your Apple ID → Manage Certificates, create a
**Developer ID Application** certificate if one doesn't already exist. This is
separate from the "Apple Development" cert used for testing.

**1b — App-specific password for notarytool**

Go to appleid.apple.com → App-Specific Passwords → generate one labelled
`deskmat-notarytool`. Store it in the macOS Keychain with:

```bash
xcrun notarytool store-credentials "deskmat-notarytool" \
  --apple-id "max.kinghorn@gmail.com" \
  --team-id "PMNC24R94X" \
  --password <app-specific-password>
```

This saves the profile so future notarytool calls just reference
`"deskmat-notarytool"` — no password in scripts.

**1c — Install create-dmg**

```bash
brew install create-dmg
```

---

### Phase 2 — Export Options plist

Create `scripts/exportOptions.plist` at the project root. This tells
`xcodebuild -exportArchive` to sign with Developer ID rather than the App Store:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>PMNC24R94X</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

---

### Phase 3 — Build script (`scripts/build-dmg.sh`)

A single shell script that runs the full pipeline end to end:

```
Archive → Export → Notarize app → Staple app → Create DMG → Notarize DMG → Staple DMG
```

**Step-by-step breakdown:**

```bash
VERSION="1.3"
SCHEME="DeskMat"
PROJECT="DeskMat.xcodeproj"
ARCHIVE="build/DeskMat.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/DeskMat.app"
DMG="build/DeskMat-$VERSION.dmg"

# 1. Archive
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE"

# 2. Export (Developer ID signed)
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/exportOptions.plist

# 3. Notarize the .app
xcrun notarytool submit "$APP" \
  --keychain-profile "deskmat-notarytool" \
  --wait

# 4. Staple the .app
xcrun stapler staple "$APP"

# 5. Create DMG
create-dmg \
  --volname "DeskMat" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "DeskMat.app" 150 185 \
  --hide-extension "DeskMat.app" \
  --app-drop-link 450 185 \
  "$DMG" \
  "$EXPORT_DIR/"

# 6. Notarize the DMG
xcrun notarytool submit "$DMG" \
  --keychain-profile "deskmat-notarytool" \
  --wait

# 7. Staple the DMG
xcrun stapler staple "$DMG"
```

The finished artifact is `build/DeskMat-1.3.dmg`.

---

### Phase 4 — Verify

Before distributing, verify the DMG on a separate Mac (or a new user account)
that has never run a dev build of DeskMat:

- Mount the DMG — Gatekeeper should open it with no warning
- Drag app to `/Applications` and launch — no "unidentified developer" dialog
- Check notarization staple: `xcrun stapler validate DeskMat.app`
- Check code signature: `codesign --verify --deep --strict DeskMat.app`
- Check Gatekeeper: `spctl --assess --type exec DeskMat.app`

All three commands should exit cleanly with no errors.

---

### Phase 5 — Automate version bumping (optional, post-ship)

Once the pipeline is working, add a helper at the top of `build-dmg.sh` that
reads `MARKETING_VERSION` from the Xcode project automatically so the script
never needs to be edited between releases:

```bash
VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings \
  | grep MARKETING_VERSION | awk '{print $3}')
```

---

## Files created

| File | Purpose |
|---|---|
| `scripts/exportOptions.plist` | Tells xcodebuild to export with Developer ID |
| `scripts/build-dmg.sh` | Full archive → notarize → DMG pipeline |

`build/` is already gitignored (or should be added to `.gitignore`).

---

## Risks / Notes

- The **Developer ID Application** cert must be on the Mac running the build.
  It cannot be shared across machines without exporting the private key.
- Notarization requires an internet connection and typically takes 30–120
  seconds with `--wait`.
- The app sandbox entitlements are already correct for Developer ID distribution
  — no changes to `DeskMat.entitlements` are needed.
- `create-dmg` produces a UDIF-format DMG compatible with all supported macOS
  versions. The window layout (icon positions, size) can be refined once the
  script is running.
- Do **not** commit `scripts/exportOptions.plist` with any credentials —
  the team ID is public but passwords must stay in Keychain only.
