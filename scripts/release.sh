#!/bin/bash
set -euo pipefail

# ── Parse flags ───────────────────────────────────────────────────────────────
DRY_RUN=false
RELEASE_NOTES_ARG=""

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        -*) echo "Unknown flag: $arg"; exit 1 ;;
        *) RELEASE_NOTES_ARG="$arg" ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo "==> [DRY RUN — no changes will be made]"
fi

# ── Preflight checks ──────────────────────────────────────────────────────────
echo "==> Checking prerequisites..."

if [ -z "${RELEASE_API_TOKEN:-}" ]; then
    echo "ERROR: RELEASE_API_TOKEN is not set."
    echo "       Get ADMIN_SECRET from DigitalOcean → Apps → cepholotech-auth → Env Vars"
    echo "       Then add to ~/.zshrc: export RELEASE_API_TOKEN=\"...\""
    exit 1
fi
echo "    RELEASE_API_TOKEN: set"

if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh is not authenticated. Run: gh auth login"
    exit 1
fi
GH_USER=$(gh api user --jq '.login' 2>/dev/null)
echo "    gh auth: ok ($GH_USER)"

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
if [ "$REPO" != "Maxx730/DeskMat" ]; then
    echo "ERROR: Expected repo Maxx730/DeskMat, got \"$REPO\""
    echo "       Run this script from the DeskMat project root."
    exit 1
fi
echo "    repo: $REPO"

# ── Read version ──────────────────────────────────────────────────────────────
VERSION=$(xcodebuild -project DeskMat.xcodeproj -showBuildSettings 2>/dev/null \
  | grep "^\s*MARKETING_VERSION" | awk '{print $3}')

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read MARKETING_VERSION from DeskMat.xcodeproj"
    exit 1
fi

DMG="build/DeskMat-$VERSION.dmg"
CHANNEL="${RELEASE_CHANNEL:-stable}"

# ── Build (or skip in dry run) ────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "==> Skipping build (dry run) — looking for existing DMG..."
    if [ -f "$DMG" ]; then
        echo "    Found: $DMG"
    else
        echo "    WARNING: $DMG not found — metadata will be unavailable"
        echo "             Run without --dry-run to build first, then re-run with --dry-run"
    fi
else
    echo "==> Building DeskMat $VERSION..."
    bash scripts/build-dmg.sh
fi

echo "==> Version: $VERSION ($CHANNEL)"

# ── Gather release notes ──────────────────────────────────────────────────────
if [ -n "$RELEASE_NOTES_ARG" ]; then
    RELEASE_NOTES="$RELEASE_NOTES_ARG"
elif [ -f "RELEASE_NOTES.md" ]; then
    RELEASE_NOTES=$(cat RELEASE_NOTES.md)
    echo "==> Release notes loaded from RELEASE_NOTES.md"
else
    echo "==> Enter release notes (Ctrl-D when done):"
    RELEASE_NOTES=$(cat)
fi

echo "==> Release notes: \"${RELEASE_NOTES:0:80}$([ ${#RELEASE_NOTES} -gt 80 ] && echo '...')\""

# ── Compute DMG metadata ──────────────────────────────────────────────────────
if [ -f "$DMG" ]; then
    FILE_SIZE=$(stat -f%z "$DMG")
    FILE_HASH=$(shasum -a 256 "$DMG" | awk '{print $1}')
    FILE_SIZE_MB=$(echo "scale=1; $FILE_SIZE / 1048576" | bc)
    echo "==> Metadata:"
    echo "    File size: ${FILE_SIZE_MB} MB"
    echo "    SHA-256:   $FILE_HASH"
else
    FILE_SIZE=0
    FILE_HASH="unknown"
fi

# ── Derive download URL ───────────────────────────────────────────────────────
DOWNLOAD_URL="https://github.com/Maxx730/DeskMat/releases/download/v$VERSION/DeskMat-$VERSION.dmg"

# ── GitHub Release upload ─────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "==> [dry-run] Would create GitHub release:"
    echo "    gh release create \"v$VERSION\" \"$DMG\" \\"
    echo "      --title \"DeskMat $VERSION\" \\"
    echo "      --notes \"${RELEASE_NOTES:0:60}...\""
    echo "    gh release upload \"v$VERSION\" \"build/DeskMat.dmg\" --clobber"
else
    echo "==> Creating GitHub release v$VERSION..."
    gh release create "v$VERSION" \
      "$DMG" \
      --title "DeskMat $VERSION" \
      --notes "$RELEASE_NOTES"

    echo "==> Uploading DeskMat.dmg alias..."
    cp "$DMG" "build/DeskMat.dmg"
    gh release upload "v$VERSION" "build/DeskMat.dmg" --clobber
    rm "build/DeskMat.dmg"

    echo "    GitHub release live: https://github.com/Maxx730/DeskMat/releases/tag/v$VERSION"
fi

# ── Register version with cepholotech API ────────────────────────────────────
PRODUCT_ID="784415ba-f43c-4a21-91c7-ec9ad1968406"
NOTES_JSON=$(echo "$RELEASE_NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

if [ "$DRY_RUN" = true ]; then
    echo "==> [dry-run] Would call POST /versions with:"
    echo "    {"
    echo "      \"product_id\":    \"$PRODUCT_ID\","
    echo "      \"version\":       \"$VERSION\","
    echo "      \"platform\":      \"mac\","
    echo "      \"channel\":       \"$CHANNEL\","
    echo "      \"download_url\":  \"$DOWNLOAD_URL\","
    echo "      \"release_notes\": $(echo \"$NOTES_JSON\" | cut -c1-52)...,"
    echo "      \"file_size\":     $FILE_SIZE,"
    echo "      \"file_hash\":     \"$FILE_HASH\","
    echo "      \"is_latest\":     true"
    echo "    }"
else
    echo "==> Registering version with cepholotech API..."

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://auth.cepholotech.com/versions" \
      -H "Authorization: Bearer $RELEASE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"product_id\":    \"$PRODUCT_ID\",
        \"version\":       \"$VERSION\",
        \"platform\":      \"mac\",
        \"channel\":       \"$CHANNEL\",
        \"download_url\":  \"$DOWNLOAD_URL\",
        \"release_notes\": $NOTES_JSON,
        \"file_size\":     $FILE_SIZE,
        \"file_hash\":     \"$FILE_HASH\",
        \"is_latest\":     true
      }")

    HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | head -1)

    case "$HTTP_STATUS" in
        201)
            echo "    API: version registered"
            ;;
        409)
            echo "    WARNING: version $VERSION already registered in API — skipping"
            ;;
        401)
            echo "ERROR: API returned 401 — bad RELEASE_API_TOKEN"
            echo "       Check DO Control Panel → Apps → cepholotech-auth → Env Vars"
            exit 1
            ;;
        *)
            echo "ERROR: API returned HTTP $HTTP_STATUS"
            echo "$BODY"
            exit 1
            ;;
    esac
fi

# ── Verify release ────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    echo "==> [dry-run] Would verify:"
    echo "    curl -sI \"$DOWNLOAD_URL\""
    echo "    curl -s \"https://auth.cepholotech.com/versions/check?product_id=$PRODUCT_ID&platform=mac&current_version=0.0.0\""
else
    echo "==> Verifying release..."

    DL_STATUS=$(curl -sI "$DOWNLOAD_URL" -o /dev/null -w "%{http_code}" --max-time 10 || true)
    if [ "$DL_STATUS" = "200" ] || [ "$DL_STATUS" = "302" ]; then
        echo "    Download URL: ok (HTTP $DL_STATUS)"
    else
        echo "    WARNING: Download URL returned HTTP $DL_STATUS — asset may still be propagating"
    fi

    CHECK=$(curl -s --max-time 10 \
      "https://auth.cepholotech.com/versions/check?product_id=$PRODUCT_ID&platform=mac&current_version=0.0.0" \
      || true)
    REPORTED=$(echo "$CHECK" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("latest_version","?"))' 2>/dev/null || echo "?")
    if [ "$REPORTED" = "$VERSION" ]; then
        echo "    API latest:   ok ($REPORTED)"
    else
        echo "    WARNING: API reports latest as \"$REPORTED\", expected \"$VERSION\""
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [ "$DRY_RUN" = true ]; then
    echo "==> Dry run complete. Run without --dry-run to publish."
else
    echo "==> Release complete!"
fi
echo "    Version:      $VERSION"
echo "    Channel:      $CHANNEL"
if [ "$DRY_RUN" = false ]; then
    echo "    GitHub:       https://github.com/Maxx730/DeskMat/releases/tag/v$VERSION"
fi
echo "    Download URL: $DOWNLOAD_URL"
echo "    Website link: https://github.com/Maxx730/DeskMat/releases/latest/download/DeskMat.dmg"
if [ -f "$DMG" ]; then
    echo "    File size:    ${FILE_SIZE_MB} MB"
    echo "    SHA-256:      $FILE_HASH"
fi
