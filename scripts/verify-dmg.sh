#!/bin/bash
set -euo pipefail

PROJECT="DeskMat.xcodeproj"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/DeskMat.app"

VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings 2>/dev/null \
  | grep "^\s*MARKETING_VERSION" | awk '{print $3}')
DMG="build/DeskMat-$VERSION.dmg"

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" &>/dev/null; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "==> Verifying DeskMat $VERSION"
echo ""

# --- .app checks ---
echo "[ App ]"

check "Code signature valid" \
  codesign --verify --deep --strict "$APP"

check "Notarization staple present" \
  xcrun stapler validate "$APP"

check "Gatekeeper accepts app" \
  spctl --assess --type exec "$APP"

check "Signed with Developer ID (not dev cert)" \
  bash -c "codesign -dv '$APP' 2>&1 | grep -q 'Developer ID Application'"

echo ""

# --- DMG checks ---
echo "[ DMG ]"

check "DMG exists" \
  test -f "$DMG"

check "Notarization staple present on DMG" \
  xcrun stapler validate "$DMG"

check "Gatekeeper accepts DMG" \
  spctl --assess --type open --context context:primary-signature "$DMG"

echo ""

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo "==> $PASS/$TOTAL checks passed"

if [ "$FAIL" -gt 0 ]; then
  echo "    $FAIL check(s) failed — do not distribute this build."
  exit 1
else
  echo "    All checks passed — safe to distribute."
fi
