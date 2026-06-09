# Exploration: Automated Release Script

## Goal

A single script (`scripts/release.sh`) that runs from the terminal and handles the full release pipeline end to end:

```
build-dmg.sh → upload DMG → register version with cepholotech API
```

---

## What Already Exists

`scripts/build-dmg.sh` is complete and handles:
- Reading `VERSION` automatically from the Xcode project (`MARKETING_VERSION`)
- Archive → Developer ID export → notarize .app → staple .app
- `create-dmg` → notarize DMG → staple DMG
- Output: `build/DeskMat-<version>.dmg`

`release.sh` calls this script then performs the two additional steps.

---

## API: Registering a New Version

This is fully known from the backend source at `cepholotech-auth/src/routes/versions.js`.

### Endpoint

```
POST https://auth.cepholotech.com/versions
Authorization: Bearer <ADMIN_SECRET>
Content-Type: application/json
```

### Request Body

```json
{
  "product_id":    "784415ba-f43c-4a21-91c7-ec9ad1968406",
  "version":       "1.4.0",
  "platform":      "mac",
  "channel":       "stable",
  "download_url":  "https://yourhost.com/DeskMat-1.4.0.dmg",
  "release_notes": "Bug fixes and performance improvements.",
  "file_size":     52428800,
  "file_hash":     "abc123def456...",
  "is_latest":     true
}
```

| Field | Required | Notes |
|---|---|---|
| `product_id` | Yes | Always `784415ba-f43c-4a21-91c7-ec9ad1968406` for DeskMat |
| `version` | Yes | Must match `CFBundleShortVersionString` exactly |
| `platform` | Yes | Always `"mac"` for this script |
| `channel` | No | Defaults to `"stable"`; can pass `"beta"` |
| `download_url` | Yes | Public URL to the hosted DMG |
| `release_notes` | No | Plain text or markdown changelog |
| `file_size` | No | Bytes — for display in UI |
| `file_hash` | No | SHA-256 hex of the DMG — for client integrity check |
| `is_latest` | No | Pass `true` to automatically mark this as the current version and demote the previous latest |

### Response (201 Created)

```json
{
  "id":           "uuid",
  "product_id":   "784415ba-f43c-4a21-91c7-ec9ad1968406",
  "version":      "1.4.0",
  "platform":     "mac",
  "channel":      "stable",
  "is_latest":    true,
  "published_at": "2026-06-08T00:00:00.000Z"
}
```

### Error Cases

| Status | Meaning |
|---|---|
| 400 | Missing/invalid fields, bad URL, invalid platform/channel value |
| 401 | Missing or wrong `ADMIN_SECRET` token |
| 404 | `product_id` not found in the database |
| 409 | A version with this `(product_id, platform, channel, version)` combination already exists |

### Auth: Where to Get `ADMIN_SECRET`

The token is the `ADMIN_SECRET` environment variable set on the DigitalOcean App Platform deployment of `cepholotech-auth`.

**Where to find it:** DigitalOcean Control Panel → Apps → cepholotech-auth → Settings → Environment Variables → `ADMIN_SECRET`

This value never appears in the codebase — it was generated at deploy time with `openssl rand -base64 32`.

---

## File Hosting: The One Remaining Unknown

The auth service stores metadata only — it never proxies or stores binary files. The `download_url` you pass to `POST /versions` must be a publicly accessible URL where the DMG is already uploaded.

**The hosting location is not defined in the cepholotech-auth codebase.** You need to decide where DMGs live. The most natural fit given you're already on DigitalOcean:

| Option | Upload command | URL pattern | Cost |
|---|---|---|---|
| **DigitalOcean Spaces** (S3-compatible) | `aws s3 cp` with DO endpoint | `https://<bucket>.nyc3.digitaloceanspaces.com/DeskMat-1.4.0.dmg` | ~$5/mo |
| **Cloudflare R2** | `aws s3 cp` with R2 endpoint | `https://<account>.r2.cloudflarestorage.com/...` | Free up to 10GB |
| **GitHub Releases** | `gh release upload` | `https://github.com/Maxx730/DeskMat/releases/download/v1.4.0/DeskMat-1.4.0.dmg` | Free |

**GitHub Releases** is the fastest to set up (no new service, no credentials beyond your existing `gh` auth) and free. The tradeoff is files live on GitHub rather than your own domain.

**DigitalOcean Spaces** keeps everything under one provider and gives you a custom domain if wanted.

---

## The Script

Once you have the `ADMIN_SECRET` and decide on hosting, the script is complete. Here it is with the real values filled in:

```bash
#!/bin/bash
set -euo pipefail

# ── Load secrets from environment or .env ─────────────────────────────────────
# Set these in ~/.zshrc or a gitignored scripts/.env file:
#
#   export RELEASE_API_TOKEN="<value of ADMIN_SECRET from DigitalOcean>"
#   export RELEASE_DOWNLOAD_BASE_URL="https://yourhost.com/releases"
#
# And for DO Spaces uploads (if chosen):
#   export AWS_ACCESS_KEY_ID="..."
#   export AWS_SECRET_ACCESS_KEY="..."

: "${RELEASE_API_TOKEN:?Set RELEASE_API_TOKEN to the cepholotech ADMIN_SECRET}"
: "${RELEASE_DOWNLOAD_BASE_URL:?Set RELEASE_DOWNLOAD_BASE_URL to where DMGs are publicly accessible}"

PRODUCT_ID="784415ba-f43c-4a21-91c7-ec9ad1968406"
CHANNEL="${RELEASE_CHANNEL:-stable}"

# ── Step 1: Build DMG ─────────────────────────────────────────────────────────
echo "==> Building..."
bash scripts/build-dmg.sh

# ── Resolve version and DMG path (same logic as build-dmg.sh) ─────────────────
VERSION=$(xcodebuild -project DeskMat.xcodeproj -showBuildSettings 2>/dev/null \
  | grep "^\s*MARKETING_VERSION" | awk '{print $3}')
DMG="build/DeskMat-$VERSION.dmg"

echo "==> Releasing DeskMat $VERSION ($CHANNEL)"

# ── Step 2: Compute DMG metadata ──────────────────────────────────────────────
FILE_SIZE=$(stat -f%z "$DMG")
FILE_HASH=$(shasum -a 256 "$DMG" | awk '{print $1}')
DOWNLOAD_URL="$RELEASE_DOWNLOAD_BASE_URL/DeskMat-$VERSION.dmg"

# ── Step 3: Gather release notes ──────────────────────────────────────────────
if [ -n "${1:-}" ]; then
    RELEASE_NOTES="$1"
elif [ -f "RELEASE_NOTES.md" ]; then
    RELEASE_NOTES=$(cat RELEASE_NOTES.md)
else
    echo "Enter release notes (Ctrl-D when done):"
    RELEASE_NOTES=$(cat)
fi

# ── Step 4: Upload DMG ────────────────────────────────────────────────────────
echo "==> Uploading $DMG..."

# Option A — DigitalOcean Spaces (uncomment and set DO_SPACES_BUCKET):
# aws s3 cp "$DMG" "s3://$DO_SPACES_BUCKET/DeskMat-$VERSION.dmg" \
#   --endpoint-url "https://nyc3.digitaloceanspaces.com" \
#   --acl public-read

# Option B — GitHub Releases (uncomment):
# gh release create "v$VERSION" "$DMG" \
#   --title "DeskMat $VERSION" \
#   --notes "$RELEASE_NOTES"

# Option C — SCP to server (uncomment and set RELEASE_UPLOAD_HOST/PATH):
# scp "$DMG" "$RELEASE_UPLOAD_HOST:$RELEASE_UPLOAD_PATH/DeskMat-$VERSION.dmg"

echo "  Uploaded to $DOWNLOAD_URL"

# ── Step 5: Register version with cepholotech API ────────────────────────────
echo "==> Registering version with API..."

# Escape release notes for JSON
NOTES_JSON=$(echo "$RELEASE_NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

RESPONSE=$(curl -sf -w "\n%{http_code}" -X POST "https://auth.cepholotech.com/versions" \
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

if [ "$HTTP_STATUS" != "201" ]; then
    echo "ERROR: API returned HTTP $HTTP_STATUS"
    echo "$BODY"
    exit 1
fi

echo ""
echo "==> Release complete!"
echo "    Version:      $VERSION"
echo "    Channel:      $CHANNEL"
echo "    Download URL: $DOWNLOAD_URL"
echo "    File size:    $FILE_SIZE bytes"
echo "    SHA-256:      $FILE_HASH"
```

---

## Verify After Each Release

```bash
# Confirm the API sees the new version
curl -s "https://auth.cepholotech.com/versions/check?product_id=784415ba-f43c-4a21-91c7-ec9ad1968406&platform=mac&current_version=<previous>" | jq .

# Confirm download URL is live
curl -I "$DOWNLOAD_URL"
```

Both should succeed before telling anyone about the release.

---

## Secrets Setup (One-Time)

Add to `~/.zshrc` (or a gitignored `scripts/.env`):

```bash
# cepholotech ADMIN_SECRET — get from DO Control Panel → Apps → cepholotech-auth → Env Vars
export RELEASE_API_TOKEN="..."

# Base URL where DMG files are publicly reachable
export RELEASE_DOWNLOAD_BASE_URL="https://yourhost.com/releases"
```

Never commit either of these to git.

---

## Open Items

| Item | Status | Action needed |
|---|---|---|
| `build-dmg.sh` | ✅ Done | — |
| `POST /versions` endpoint shape | ✅ Known | — |
| API auth mechanism | ✅ Known (Bearer ADMIN_SECRET) | Retrieve value from DO dashboard |
| DMG hosting location | ❓ Open | Pick one: DO Spaces, GitHub Releases, or SCP |
| Upload credentials | ❓ Blocked on hosting choice | Set up once hosting is decided |
| `release.sh` script | 🔧 Skeleton ready | Uncomment the right upload block |
