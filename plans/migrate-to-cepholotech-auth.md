# Migration Plan: Lemon Squeezy → cepholotech-auth

Migrate DeskMat's license system from the Lemon Squeezy API to the self-hosted
`cepholotech-auth` service at `auth.cepholotech.com`.

---

## Context

**Current state:** `LicenseManager.swift` calls three Lemon Squeezy endpoints —
`/activate`, `/validate`, and `/deactivate` — and stores a `licenseKey` +
`instanceId` pair in the Keychain. Key format is UUID-style (contains `-`).

**Target state:** All license traffic goes to `auth.cepholotech.com`. The public
`POST /verify` endpoint handles both initial activation and ongoing validation via
a stable `hardware_id`. A separate deactivate endpoint (added in Phase 1) handles
seat release. Key format becomes `ceph_deskmat_<base62>`.

---

## Phase 1 — Server: Prepare cepholotech-auth

**Repo:** `/Users/johnkinghorn/Desktop/Projects/cepholotech-auth` (branch `master`)

### 1.1 — Register DeskMat as a product

Using the admin API (requires `Authorization: Bearer <ADMIN_SECRET>`):

```
POST /products
{ "name": "DeskMat", "slug": "deskmat" }
```

Save the returned `product_id` — it will be baked into the app as a constant.

### 1.2 — Add a `DELETE /licenses/activations` (deactivate) endpoint

The current `/verify` endpoint increments seat usage but offers no way for a
user to release their seat. Add a new public-facing endpoint:

```
POST /verify/deactivate
{ "key": "ceph_deskmat_xxxx", "hardware_id": "machine-uuid" }
→ 200 { "deactivated": true } | 400/404
```

Implementation notes:
- Look up the activation row by `(license_id, hardware_id)` in the `activations` table.
- Delete the row and decrement `seats_used` on the license.
- Return 404 if no matching activation is found (key not active on this machine).
- No admin auth required — a user can only deactivate their own machine because
  they must supply the correct `hardware_id` that was used at activation time.

### 1.3 — Seed a DeskMat license for local testing

Issue a test license via:

```
POST /licenses
{
  "product_id": "<deskmat-product-id>",
  "customer_name": "Dev",
  "customer_email": "dev@local",
  "seat_limit": 3
}
```

The plaintext key returned is used only during development.

**Deliverable:** Server deployed to production on DO with the new endpoint live.

---

## Phase 2 — Client: Rewrite LicenseManager.swift

All changes are in `DeskMat/LicenseManager.swift`.

### 2.1 — Replace base URL constant

```swift
// Before
private static let baseURL = "https://api.lemonsqueezy.com/v1/licenses"

// After
private static let baseURL = "https://auth.cepholotech.com"
```

Keep the `#if DEBUG` override via `DESKMAT_API_URL` env var so local testing
against a local server instance still works.

### 2.2 — Derive a stable `hardware_id` from the machine

Replace the `instanceId` stored in Keychain with a hardware-derived ID so the
app doesn't need the server to assign one:

```swift
private static var hardwareId: String {
    var size = 0
    sysctlbyname("kern.uuid", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("kern.uuid", &buffer, &size, nil, 0)
    return String(cString: buffer)
}
```

This is stable across reinstalls on the same hardware and requires no server
round-trip to obtain.

### 2.3 — Rewrite `activate(licenseKey:)`

The new flow is a single `POST /verify` call. If `/verify` returns `valid: true`
and the seat count is within limit, treat it as an activation success.

```
POST /verify
{ "key": "ceph_deskmat_xxxx", "hardware_id": "<kern.uuid>" }
```

- `valid: true` → save key to Keychain, set `isPro = true`
- `valid: false` → return `.invalid`
- `seats_used >= seat_limit` in response → return `.error("Seat limit reached")`

Update key format validation: remove the `trimmed.contains("-")` check and
replace with a prefix check: `trimmed.hasPrefix("ceph_")`.

### 2.4 — Rewrite `refreshFromKeychain()`

Replace the Lemon Squeezy `/validate` call with `POST /verify` using the stored
key and `hardwareId`. The response shape is identical for the happy path
(`valid: true/false`). The soft-fail-offline behavior remains unchanged.

### 2.5 — Rewrite `deactivate()`

Call the new Phase 1 endpoint:

```
POST /verify/deactivate
{ "key": "<stored-key>", "hardware_id": "<kern.uuid>" }
```

On success, clear Keychain and set `isPro = false` — same as today.

### 2.6 — Update Keychain storage shape

Remove `instanceId` from `StoredLicense`. The hardware ID is always derived
at runtime; there is nothing extra to persist.

```swift
private struct StoredLicense: Codable {
    let licenseKey: String
    // version kept for forward-compat
    let version: Int
}
```

Add a migration in `readFromKeychain()`: if the existing Keychain record decodes
with an `instanceId` field, re-save without it so the schema is clean.

**Deliverable:** `LicenseManager.swift` compiles, all existing unit tests pass,
manual smoke test with a real `ceph_deskmat_*` key activates successfully.

---

## Phase 3 — UI: Update Purchase Flow and Strings

### 3.1 — Replace the Lemon Squeezy buy URL

In `SettingsView.swift` (`ProUnlockTab`), replace:

```swift
URL(string: "https://cepholotech.lemonsqueezy.com/checkout/buy/e76ff2c0-32cd-41b7-b770-7b6b9873ab23")!
```

with the new checkout URL (to be determined once the DeskMat product is live in
the store — update this plan when the URL is known).

### 3.2 — Update the license key hint format

`licenseKeyHint` currently shows `••••-••••-••••-AB12`. The new key format is
`ceph_deskmat_<base62>`. Update the hint to match:

```swift
var licenseKeyHint: String? {
    guard let key = storedKey else { return nil }
    return "ceph_deskmat_••••••\(key.suffix(4))"
}
```

### 3.3 — Update placeholder text in Strings.swift

Review `Strings.Pro.licenseKeyPlaceholder` — change it from a UUID-style hint
to something like `ceph_deskmat_…` so users know what to expect.

**Deliverable:** UI reflects the new key format; buy button points to the correct
checkout; no Lemon Squeezy references remain in user-facing text.

---

## Phase 4 — Cleanup and Tests

### 4.1 — Remove Lemon Squeezy dead code

- Delete the Lemon Squeezy URL from `LicenseManager.swift`.
- Remove `DeskMat.storekit` from the project if it is no longer referenced
  (check `DeskMatApp.swift` and `DeskMat.xcodeproj/project.pbxproj` first).

### 4.2 — Update `EntitlementTests.swift`

Current test file likely mocks the Lemon Squeezy response shape. Update mocks
to match the cepholotech-auth `/verify` response:

```json
{ "valid": true, "product": "deskmat", "license_id": "uuid",
  "customer_name": "Jane", "expires_at": null,
  "seats_used": 1, "seat_limit": 3 }
```

### 4.3 — Add environment variable for test server

The `DESKMAT_API_URL` override (Phase 2.1) enables pointing tests at a local
instance of cepholotech-auth or a mock server. Document this in the scheme's
environment variable list.

### 4.4 — Manual end-to-end checklist

- [ ] Fresh install: enter key → activates, `isPro = true`
- [ ] Relaunch: `refreshFromKeychain` validates silently in background
- [ ] Offline relaunch: `isPro` stays `true` (soft-fail)
- [ ] Revoked key: server returns `valid: false` → `isPro = false`, Keychain cleared
- [ ] Seat limit full: server responds correctly → UI shows error
- [ ] Deactivate: seat released, `isPro = false`, re-activation on another machine succeeds
- [ ] Key format hint renders correctly in the activated state view

**Deliverable:** All unit tests green, end-to-end checklist passed, no references
to Lemon Squeezy remain in code or UI.

---

## Dependency Order

```
Phase 1 (server)
    └─► Phase 2 (client core) ──► Phase 3 (UI)
                                       └─► Phase 4 (cleanup + tests)
```

Phase 2 can be developed against the test key from Phase 1.3 before the
production endpoint is deployed. Phases 3 and 4 are independent of each other
and can be done in parallel once Phase 2 is stable.
