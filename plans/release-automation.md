# Plan: Release Automation Script

## Goal

A single `scripts/release.sh` that runs from the terminal and handles the full release pipeline:

```
build-dmg.sh → GitHub Release upload → register version with cepholotech API
```

After running it, the new version is publicly downloadable from GitHub and the in-app update checker immediately reports it as available.

---

## What Already Exists

- `scripts/build-dmg.sh` — full pipeline: archive → export → notarize app → staple → create-dmg → notarize DMG → staple. Outputs `build/DeskMat-<version>.dmg`. No changes needed.
- `scripts/exportOptions.plist` — used internally by `build-dmg.sh`.
- `UpdateService.swift` — already calls `GET /versions/check` on launch and manually.

---

## Prerequisites (One-Time Setup — Not Scripted)

Before `release.sh` can run, two things must be set up manually once:

1. **`gh` authenticated** — `gh auth login` with a GitHub account that has write access to `Maxx730/DeskMat`. Verify with `gh auth status`.

2. **`RELEASE_API_TOKEN` env var** — the `ADMIN_SECRET` value from DigitalOcean Control Panel → Apps → `cepholotech-auth` → Settings → Environment Variables. Add to `~/.zshrc`:
   ```bash
   export RELEASE_API_TOKEN="..."
   ```

These are documented in the plan but not automated — they're one-time machine setup, not per-release work.

---

## Phases

---

### Phase 1 — Script skeleton + GitHub Release upload

**File:** `scripts/release.sh` (new)

**Scope:** Everything up to and including the GitHub upload. The script should be fully runnable after this phase without Phase 2.

#### Steps the script performs:

1. **Preflight checks** — fail early with a clear message if:
   - `RELEASE_API_TOKEN` is not set
   - `gh auth status` fails (not authenticated)
   - The repo is not `Maxx730/DeskMat` (safety check against running in wrong repo)

2. **Build** — call `bash scripts/build-dmg.sh`. Let it own the entire build pipeline. If it exits non-zero, the release script stops.

3. **Read version** — same method as `build-dmg.sh`:
   ```bash
   VERSION=$(xcodebuild -project DeskMat.xcodeproj -showBuildSettings 2>/dev/null \
     | grep "^\s*MARKETING_VERSION" | awk '{print $3}')
   DMG="build/DeskMat-$VERSION.dmg"
   ```

4. **Gather release notes** — checked in order:
   - CLI argument: `bash scripts/release.sh "Bug fixes and improvements."`
   - `RELEASE_NOTES.md` file in repo root (if present, read and clear after use)
   - Interactive: prompt the user (Ctrl-D to finish)

5. **Compute DMG metadata:**
   ```bash
   FILE_SIZE=$(stat -f%z "$DMG")
   FILE_HASH=$(shasum -a 256 "$DMG" | awk '{print $1}')
   ```

6. **Create GitHub Release:**
   ```bash
   gh release create "v$VERSION" \
     "$DMG#DeskMat-$VERSION.dmg" \
     --title "DeskMat $VERSION" \
     --notes "$RELEASE_NOTES"

   # Upload fixed-name alias for the website's static download button
   cp "$DMG" "build/DeskMat.dmg"
   gh release upload "v$VERSION" "build/DeskMat.dmg" --clobber
   rm "build/DeskMat.dmg"
   ```

   This produces two assets on the release:
   - `DeskMat-1.4.0.dmg` — versioned, for direct links and release history
   - `DeskMat.dmg` — fixed name, so the website button URL never changes:
     `https://github.com/Maxx730/DeskMat/releases/latest/download/DeskMat.dmg`

7. **Derive the canonical download URL** for Phase 2:
   ```bash
   DOWNLOAD_URL="https://github.com/Maxx730/DeskMat/releases/download/v$VERSION/DeskMat-$VERSION.dmg"
   ```

**End state:** `gh release view v$VERSION` shows the new release with both assets attached.

---

### Phase 2 — Register version with cepholotech API

**File:** `scripts/release.sh` (extend)

**Scope:** After a successful GitHub upload, call `POST /versions` so the in-app update checker knows about the new release.

#### The API call:

```bash
CHANNEL="${RELEASE_CHANNEL:-stable}"
PRODUCT_ID="784415ba-f43c-4a21-91c7-ec9ad1968406"

NOTES_JSON=$(echo "$RELEASE_NOTES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')

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
```

#### Error handling:

| Status | Behavior |
|---|---|
| 201 | Continue |
| 409 | Print warning ("version already registered — skipping API step") and continue without failing. GitHub release is already live. |
| 401 | Print error ("bad RELEASE_API_TOKEN — check DO dashboard") and exit 1 |
| Any other | Print status + response body and exit 1 |

The 409 case is important: if the GitHub upload succeeded but the API call failed mid-run and you re-run the script, it shouldn't fail the whole release just because the version record already exists.

---

### Phase 3 — Post-release verification + `.gitignore` guard

**Files:** `scripts/release.sh` (extend), `.gitignore` (update)

**Scope:** Confirm the release is actually live before printing success, and prevent accidental secret commits.

#### Verification steps (run after Phase 2):

1. **Confirm download URL is live:**
   ```bash
   HTTP=$(curl -sI "$DOWNLOAD_URL" -o /dev/null -w "%{http_code}")
   if [ "$HTTP" != "200" ] && [ "$HTTP" != "302" ]; then
       echo "WARNING: download URL returned HTTP $HTTP — asset may not be public yet"
   fi
   ```

2. **Confirm API sees the new version:**
   ```bash
   CHECK=$(curl -s "https://auth.cepholotech.com/versions/check\
?product_id=$PRODUCT_ID&platform=mac&current_version=0.0.0")
   REPORTED=$(echo "$CHECK" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("latest_version","?"))')
   if [ "$REPORTED" != "$VERSION" ]; then
       echo "WARNING: API reports latest as $REPORTED, expected $VERSION"
   fi
   ```

3. **Final summary:**
   ```
   ==> Release complete!
       Version:       1.4.0
       Channel:       stable
       GitHub:        https://github.com/Maxx730/DeskMat/releases/tag/v1.4.0
       Download URL:  https://github.com/Maxx730/DeskMat/releases/download/v1.4.0/DeskMat-1.4.0.dmg
       Website link:  https://github.com/Maxx730/DeskMat/releases/latest/download/DeskMat.dmg
       File size:     48.2 MB
       SHA-256:       abc123...
   ```

#### `.gitignore` update:

Add `scripts/.env` to `.gitignore` so a local secrets file can never be accidentally committed. (The env vars live in `~/.zshrc`, but this guards against someone creating a local `.env` file in the scripts directory.)

---

## Files Changed

| File | Change |
|---|---|
| `scripts/release.sh` | New — full release pipeline |
| `.gitignore` | Add `scripts/.env` |

`build-dmg.sh`, `UpdateService.swift`, and all other files are untouched.

---

## Dry Run Flag

Pass `--dry-run` (or `-n`) to walk through the entire script without publishing anything. Useful for verifying the version, metadata, release notes, and API payload look correct before committing to a real release.

### What dry run does

| Step | Normal | Dry run |
|---|---|---|
| Preflight checks | Run normally | Run normally — catch auth issues early |
| `build-dmg.sh` | Runs full build | **Skipped** — build takes 5+ minutes; use existing DMG if present |
| Version detection | Read from Xcode project | Same |
| Release notes | Arg / file / interactive | Same |
| DMG metadata | Computed from built DMG | Computed from existing `build/DeskMat-$VERSION.dmg` if present; otherwise shows `[no DMG found — run without --dry-run to build]` |
| `gh release create` | Creates real release | **Skipped** — prints the exact command that would run |
| `POST /versions` | Calls live API | **Skipped** — prints the exact `curl` command and JSON payload that would be sent |
| Verification | Checks live URLs | **Skipped** — prints the verification commands that would run |

### Implementation

Parse the flag at the top of the script:

```bash
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
    esac
done
```

Wrap each side-effecting step with a helper that either runs the command or prints it:

```bash
run() {
    if [ "$DRY_RUN" = true ]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}
```

For multi-line commands (like `gh release create` and `curl`), print a formatted preview block instead of running them:

```bash
if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would create GitHub release:"
    echo "  gh release create \"v$VERSION\" \"$DMG\" \\"
    echo "    --title \"DeskMat $VERSION\" \\"
    echo "    --notes \"$RELEASE_NOTES\""
else
    gh release create "v$VERSION" ...
fi
```

The build skip is the only structural difference — everything else uses the same `run` wrapper.

### Example dry-run output

```
==> [DRY RUN — no changes will be made]
==> Checking prerequisites...
    gh auth: ok (Maxx730)
    RELEASE_API_TOKEN: set
==> Skipping build (dry run) — looking for existing DMG...
    Found: build/DeskMat-1.4.0.dmg
==> Version: 1.4.0 (stable)
==> Release notes: "Bug fixes and performance improvements."
==> Metadata:
    File size: 48.2 MB
    SHA-256:   abc123def456...
==> [dry-run] Would create GitHub release:
    gh release create "v1.4.0" "build/DeskMat-1.4.0.dmg" \
      --title "DeskMat 1.4.0" --notes "..."
    gh release upload "v1.4.0" "build/DeskMat.dmg" --clobber
==> [dry-run] Would call POST /versions with:
    {
      "product_id":   "784415ba-f43c-4a21-91c7-ec9ad1968406",
      "version":      "1.4.0",
      "platform":     "mac",
      "channel":      "stable",
      "download_url": "https://github.com/Maxx730/DeskMat/releases/download/v1.4.0/DeskMat-1.4.0.dmg",
      "release_notes": "Bug fixes and performance improvements.",
      "file_size":    50544640,
      "file_hash":    "abc123def456...",
      "is_latest":    true
    }
==> [dry-run] Would verify:
    curl -sI "https://github.com/Maxx730/DeskMat/releases/download/v1.4.0/DeskMat-1.4.0.dmg"
    curl -s "https://auth.cepholotech.com/versions/check?..."
==> Dry run complete. Run without --dry-run to publish.
```

---

## Running It

```bash
# Dry run — verify everything looks right without publishing
bash scripts/release.sh --dry-run
bash scripts/release.sh --dry-run "Bug fixes and performance improvements."

# Standard release (prompts for release notes)
bash scripts/release.sh

# Pass release notes inline
bash scripts/release.sh "Bug fixes and performance improvements."

# Beta channel
RELEASE_CHANNEL=beta bash scripts/release.sh "Beta build."
```

---

## Open Items

| Item | Status |
|---|---|
| `RELEASE_API_TOKEN` value | Must retrieve from DO dashboard before first run |
| `gh auth login` | Must run once on the machine if not already done |
| `RELEASE_NOTES.md` workflow | Optional — can skip and enter notes interactively |
