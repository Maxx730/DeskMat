# Update Checking Strategies for Self-Distributed DeskMat

## Context

DeskMat is a sandboxed macOS app distributed as a signed/notarized DMG — not
through the Mac App Store. The App Sandbox is enabled with the `network.client`
entitlement, so outbound HTTP is permitted. The app already has a running
backend at `auth.cepholotech.com`.

The goal is: on launch (or on a timer), silently check whether a newer version
exists and notify the user if so.

---

## Option 1 — Sparkle Framework (Appcast)

**What it is:** Sparkle is the de-facto macOS update framework, used by the
vast majority of self-distributed Mac apps (Homebrew, iTerm2, BBEdit, etc.).
You host an XML "appcast" file somewhere, Sparkle polls it, compares versions,
and shows a native update UI with release notes and a one-click installer.

**How it works:**
1. Add Sparkle via Swift Package Manager.
2. Host an `appcast.xml` file (RSS 2.0 format) on any web server or CDN.
3. Sign each release's appcast entry with your EdDSA key (`generate_keys`
   provided by Sparkle; private key stays on your build machine).
4. Add `SUFeedURL` (pointing to your appcast) and `SUPublicEDKey` to
   `Info.plist`.
5. Call `SPUStandardUpdaterController` from the app delegate. Sparkle handles
   the rest — polling, UI, downloading, replacing the app bundle.

**Appcast entry shape:**
```xml
<item>
  <title>DeskMat 1.4</title>
  <sparkle:version>14</sparkle:version>
  <sparkle:shortVersionString>1.4</sparkle:shortVersionString>
  <description><![CDATA[<h3>What's new</h3><ul><li>...</li></ul>]]></description>
  <pubDate>Mon, 02 Jun 2025 00:00:00 +0000</pubDate>
  <enclosure url="https://yourhost.com/DeskMat-1.4.dmg"
             length="12345678"
             type="application/octet-stream"
             sparkle:edSignature="…" />
</item>
```

**Pros:**
- Battle-tested, used by thousands of apps — known-good UX.
- Ships a native update sheet (or a menu bar badge) with release notes.
- Supports delta updates (only download a diff, not the full DMG).
- All cryptographic verification handled for you (EdDSA).
- Background downloads, automatic install on quit.
- Handles app sandbox correctly; no special entitlements needed beyond
  `network.client`.

**Cons:**
- Adds an SPM dependency (~3 MB framework).
- Appcast XML is slightly verbose to maintain; must be updated manually (or
  via a script) for every release.
- Private EdDSA key must be kept safe — loss means you cannot ship signed
  updates.
- First-launch permission prompt ("Check for updates automatically?") adds
  friction during onboarding.

**Fit for DeskMat:** Very high. This is the path of least resistance for a
macOS DMG app with Pro licensing. Sparkle can even pass the license key as a
parameter in the feed URL so the appcast can serve different release notes
to free vs. Pro users.

---

## Option 2 — GitHub Releases API

**What it is:** Use GitHub's public REST API to query the latest release tag on
your repo and compare it with the running bundle version.

**How it works:**
```
GET https://api.github.com/repos/Maxx730/DeskMat/releases/latest
→ { "tag_name": "v1.4", "html_url": "...", "assets": [...] }
```
On launch, fetch this JSON, parse `tag_name`, compare to
`Bundle.main.infoDictionary["CFBundleShortVersionString"]`, and show an
alert/banner if newer.

**Pros:**
- Zero hosting cost — GitHub is the CDN.
- No extra backend code. Release assets (the DMG) live directly in the same
  GitHub Release.
- Very simple to implement — one `URLSession` call and a version comparison.
- Works naturally with a public repo. Even a private repo works with a PAT
  (though embedding a PAT in the binary is a risk).

**Cons:**
- Unauthenticated API rate limit: 60 requests/hour per IP. Unlikely to hit in
  practice for a small user base, but possible if a machine hammers it.
- GitHub is a third-party dependency — if the API changes or the repo moves,
  updates break.
- No release notes, no built-in UI, no automatic download — you must build all
  of that yourself.
- Redirects the user to a browser (or you download the DMG manually) — no
  silent background install.
- Requires a public repo for the API to work without auth.

**Fit for DeskMat:** Good for a quick MVP with minimal code. Not ideal long-term
because it puts you on GitHub's API contract and gives you no update UI out of
the box.

---

## Option 3 — Custom JSON Version Manifest (Self-hosted)

**What it is:** Host a static JSON file (e.g., `version.json`) at a URL you
control. The app fetches it, compares versions, and notifies the user.

**Example manifest:**
```json
{
  "version": "1.4",
  "build": 9,
  "releaseNotesURL": "https://yourhost.com/changelog",
  "downloadURL": "https://yourhost.com/DeskMat-1.4.dmg",
  "minOSVersion": "13.0",
  "critical": false
}
```

**Pros:**
- Full control over the schema — add whatever fields you need (e.g.,
  `critical: true` to force a blocking update prompt).
- No framework dependency.
- Easy to cache with a CDN (Cloudflare, Bunny, Fastly) for near-zero cost.
- Can serve different manifests to free vs. Pro users via URL path or query
  param.
- Simple to update via a one-line `curl` PUT or CI script on every release.

**Cons:**
- You must build and maintain: the network call, version parsing, comparison
  logic, UI (alert, banner, badge), and download flow.
- Needs hosting — a server, S3 bucket, or CDN. Not free but very cheap
  ($0–$5/month).
- No cryptographic verification of the manifest itself — a MITM could serve
  a fake version (mitigated if served over HTTPS with cert pinning, or by
  verifying the DMG signature post-download).
- No delta updates.

**Fit for DeskMat:** Good middle ground. Can be wired into the existing
`auth.cepholotech.com` backend (see Option 4) to avoid separate hosting.

---

## Option 4 — Piggyback on the cepholotech-auth Backend

**What it is:** Add a `/version` (or `/latest`) endpoint to the existing
`auth.cepholotech.com` server that the app already calls. The app hits this
endpoint on launch alongside its license check and acts on the response.

**Example response:**
```json
{
  "latest_version": "1.4",
  "latest_build": 9,
  "download_url": "https://yourhost.com/DeskMat-1.4.dmg",
  "changelog": "Bug fixes and performance improvements.",
  "force_update": false
}
```

**Pros:**
- Zero new hosting — infrastructure already exists.
- Can bundle the version check into the same network call as the license
  validation (one round trip on launch).
- Can enforce update policy per-license tier (e.g., free users must update
  to access new Pro features).
- Full schema control; easy to add `force_update` flags for critical security
  patches.
- Keeps telemetry in one place — the auth server can log which app versions
  are still active in the wild.

**Cons:**
- Couples update availability to auth server uptime. If `auth.cepholotech.com`
  is down, update checks fail silently or show errors.
- Adds backend maintenance responsibility — updating the version record must be
  part of your release checklist.
- Still requires building all client-side UI and download logic.
- No cryptographic manifest signing (same as Option 3).

**Fit for DeskMat:** Very natural given the existing infra. A `/version`
endpoint is a 10-line addition to the auth server. Best combined with
a UI layer on the client (a banner in SettingsView or a badge on the
menu bar icon).

---

## Option 5 — GitHub Pages / Netlify / Cloudflare Pages Static File

**What it is:** A variant of Option 3 where the `version.json` is committed
to a git repo and served via a free static hosting service rather than a
paid server.

**How it works:** Commit `version.json` to a `/public` folder in a GitHub
repo. GitHub Pages (or Netlify/CF Pages) serves it at a stable URL for free.
To cut a release, update the JSON and push.

**Pros:**
- Completely free.
- Git history gives you an automatic audit trail of every version change.
- Can co-locate a human-readable changelog HTML page.
- Cloudflare Pages has a global CDN with no egress cost.

**Cons:**
- Same implementation burden as Option 3 (all client code must be written).
- Propagation delay — GitHub Pages can take up to 10 minutes to reflect a
  push.
- Yet another service in the release checklist.
- If the repo is private, GitHub Pages requires a paid plan.

**Fit for DeskMat:** Reasonable for a zero-cost setup. Cloudflare Pages is
probably the best choice here given its speed and free tier.

---

## Option 6 — DIY Silent Background Check (No Framework, Custom UI)

**What it is:** A minimal hand-rolled implementation regardless of the backend
(Options 2–5 above). The app periodically fires a `URLSession` call in the
background, caches the last-seen latest version in `UserDefaults`, and shows
a subtle "Update available" badge on the settings gear icon or menu bar item.

**Key implementation points:**
- Check on launch + every 24 hours via a `DispatchSourceTimer`.
- Cache `latestVersion` and `lastChecked` in `UserDefaults` so repeat launches
  don't re-fetch unnecessarily.
- Never block the UI — fire the check asynchronously and update the UI only
  from the main actor.
- On update available: show a badge on the status bar icon and a banner in
  `SettingsView`, not a modal alert.
- Opening the download is a `NSWorkspace.open(url)` to the browser — do not
  try to replace the running app bundle from within a sandboxed app.

**Pros:**
- No framework dependency.
- Fully custom UX — fits DeskMat's existing UI conventions exactly.
- No user-facing permission prompt on first launch.

**Cons:**
- Replacing the bundle from within a sandboxed app is impossible — the user
  always has to manually drag-replace. This is a UX regression vs. Sparkle.
- Significant implementation work for something Sparkle provides for free.
- Version comparison logic is easy to get subtly wrong (semver edge cases).

**Fit for DeskMat:** Best used as the *notification layer* on top of Options
2–5, with the actual install left to the user (open browser / open DMG).

---

## Comparison Table

| | Sparkle | GitHub API | Custom JSON | Auth Backend | Static Host |
|---|---|---|---|---|---|
| **Hosting needed** | Yes (appcast) | No | Yes | Already have | Free |
| **Auto-install** | Yes | No | No | No | No |
| **Release notes UI** | Built-in | DIY | DIY | DIY | DIY |
| **Crypto verification** | EdDSA | TLS only | TLS only | TLS only | TLS only |
| **Delta updates** | Yes | No | No | No | No |
| **Implementation effort** | Low | Low | Medium | Medium | Medium |
| **External dependency** | Sparkle SPM | GitHub API | None | None | None |
| **Cost** | Free | Free | $0–5/mo | Free | Free |

---

## Recommendation

**Short term:** Add a `/version` endpoint to `auth.cepholotech.com` (Option 4)
and wire a lightweight notification badge into the existing Settings UI (Option
6 as the UI layer). This leverages infrastructure already in production, costs
nothing, and ships fast. The user still manually installs updates via DMG.

**Long term:** If the user base grows and the manual-install UX becomes a
friction point, adopt Sparkle (Option 1). Sparkle's delta updates and
auto-install flow justify the dependency at scale. The appcast XML can be
generated as part of the existing `build-dmg.sh` script with a one-line
`sed` command.

**Avoid:** GitHub Releases API as the permanent solution — it ties you to
GitHub's API rate limits and contract, and there is no meaningful benefit over
a self-hosted JSON file once the auth backend already exists.

---

## Notes Specific to DeskMat's Sandbox

- The `com.apple.security.network.client` entitlement is already present —
  outbound HTTPS requires no entitlement changes.
- A sandboxed app **cannot** overwrite its own bundle. Any auto-update that
  writes to `/Applications` must use a privileged helper (Sparkle's `Autoupdate`
  XPC service handles this for you; DIY would require a separate SMAppService
  daemon — significant complexity).
- If you adopt Sparkle, its `Autoupdate` XPC service must be included in the
  DMG and signed with Developer ID.
