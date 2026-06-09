#!/bin/bash
set -euo pipefail

PROJECT="DeskMat.xcodeproj"
SCHEME="DeskMat"
ARCHIVE="build/DeskMat.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/DeskMat.app"
APP_ZIP="build/DeskMat-app.zip"

# Read version directly from Xcode project
VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings 2>/dev/null \
  | grep "^\s*MARKETING_VERSION" | awk '{print $3}')
DMG="build/DeskMat-$VERSION.dmg"

echo "==> Building DeskMat $VERSION"

# Clean any existing DMGs from previous builds
rm -f build/*.dmg

# 1. Archive
echo "==> Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  | xcpretty 2>/dev/null || true

# 2. Export (Developer ID signed)
echo "==> Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist scripts/exportOptions.plist

# 3. Zip the .app for notarization (notarytool requires zip/pkg/dmg)
echo "==> Zipping app for notarization..."
ditto -c -k --keepParent "$APP" "$APP_ZIP"

# 4. Notarize the zipped .app
echo "==> Notarizing app..."
xcrun notarytool submit "$APP_ZIP" \
  --keychain-profile "deskmat-notarytool" \
  --wait

# 5. Staple the .app (staple goes on the .app, not the zip)
echo "==> Stapling app..."
xcrun stapler staple "$APP"

# 6. Create DMG
echo "==> Creating DMG..."
create-dmg \
  --volname "DeskMat" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "DeskMat.app" 150 185 \
  --hide-extension "DeskMat.app" \
  --app-drop-link 450 185 \
  "$DMG" \
  "$APP"

# 7. Notarize the DMG
echo "==> Notarizing DMG..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "deskmat-notarytool" \
  --wait

# 8. Staple the DMG
echo "==> Stapling DMG..."
xcrun stapler staple "$DMG"

echo ""
echo "==> Done: $DMG"
