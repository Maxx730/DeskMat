# DeskMat — cepholotech-auth Integration Plan

Migrate DeskMat's license system from Lemon Squeezy to the self-hosted
`cepholotech-auth` service at `auth.cepholotech.com`.

The server is **fully built and deployed**. All work below is client-side
(Swift) except for one admin API call to register the DeskMat product.

---

## Current state

| Layer | Status |
|---|---|
| `LicenseManager.swift` | Calls Lemon Squeezy `/activate`, `/validate`, `/deactivate` |
| Key format validation | Requires `contains("-")` — rejects `ceph_` keys |
| Keychain storage | Stores `licenseKey` + `instanceId` (server-assigned) |
| Buy CTA | Points to `cepholotech.lemonsqueezy.com` checkout |
| Server: `POST /verify` | Live at `auth.cepholotech.com` |
| Server: `POST /deactivate` | Live at `auth.cepholotech.com` |
| Server: DeskMat product | **Not yet registered** |

---

## Phase 1 — Register the DeskMat product (admin, one-time)

This is a single API call against the live server. It must happen before
any key can be issued for DeskMat.

```bash
curl -X POST https://auth.cepholotech.com/products \
  -H "Authorization: Bearer <ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{"name": "DeskMat", "slug": "deskmat"}'
```

Save the returned `id` (UUID) — it is needed to issue licenses.

Then issue a development test license:

```bash
curl -X POST https://auth.cepholotech.com/licenses \
  -H "Authorization: Bearer <ADMIN_SECRET>" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": "<deskmat-product-uuid>",
    "customer_name": "Dev",
    "customer_email": "dev@local",
    "seat_limit": 5
  }'
```

The plaintext `ceph_deskmat_…` key in the response is used only during
development. It is not stored server-side after this response.

**Deliverable:** DeskMat product exists in production DB; dev key in hand
for local smoke testing.

---

## Phase 2 — Rewrite LicenseManager.swift

All changes are confined to `DeskMat/LicenseManager.swift`.

### 2.1 Replace the base URL

```swift
// Before
private static let baseURL = "https://api.lemonsqueezy.com/v1/licenses"

// After
private static let baseURL = "https://auth.cepholotech.com"
```

Keep the `#if DEBUG` env-var override (`DESKMAT_API_URL`) so tests can
point at a local server.

### 2.2 Derive a stable hardware ID at runtime

Replace the server-assigned `instanceId` with a hardware-derived value
that is the same across app reinstalls on the same machine:

```swift
private static var hardwareId: String {
    var size = 0
    sysctlbyname("kern.uuid", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("kern.uuid", &buffer, &size, nil, 0)
    return String(cString: buffer)
}
```

### 2.3 Rewrite `activate(licenseKey:)`

Call `POST /verify` with the key and `hardware_id`. The server registers
the seat on first call and returns the full license record.

```
POST /verify
{ "key": "ceph_deskmat_xxxx", "hardware_id": "<kern.uuid>" }
→ { "valid": true, "seats_used": N, "seat_limit": N, ... }
  or { "valid": false }
```

Result mapping:
- `valid: true` → save key to Keychain, `isPro = true`, return `.success`
- `valid: false` → return `.invalid`
- HTTP 200 but `valid: false` AND `seats_used >= seat_limit` in a prior
  call → server already returns `valid: false` for this case; no extra
  client logic needed

Update key format validation: replace `trimmed.contains("-")` with
`trimmed.hasPrefix("ceph_")`.

### 2.4 Rewrite `refreshFromKeychain()`

Replace the Lemon Squeezy `/validate` call with `POST /verify`:

```
POST /verify
{ "key": "<stored-key>", "hardware_id": "<kern.uuid>" }
```

Same soft-fail-offline behavior: any thrown error keeps `isPro = true`.
Only a `200 { valid: false }` response clears the license.

### 2.5 Rewrite `deactivate()`

Call `POST /deactivate`:

```
POST /deactivate
{ "key": "<stored-key>", "hardware_id": "<kern.uuid>" }
→ { "success": true, "seats_used": N }
  or { "success": false }           (key invalid / not active here)
  or { "success": false, "error": "Activation not found" }  (404)
```

On `success: true`: clear Keychain, set `isPro = false`.
On `success: false` with HTTP 401: return `.invalid` (key rejected).
On `success: false` with HTTP 404: return `.error("Not active on this machine.")`.

### 2.6 Slim down Keychain storage

Remove `instanceId` from `StoredLicense` — it is no longer persisted:

```swift
private struct StoredLicense: Codable {
    let licenseKey: String
    let version: Int
}
```

Add a one-time migration in `readFromKeychain()`: if the record decodes
with an `instanceId` field (old format), re-save without it on the first
successful read. This avoids a forced logout for existing users.

**Deliverable:** `LicenseManager.swift` compiles, smoke test with a real
`ceph_deskmat_*` key activates and shows `isPro = true`.

---

## Phase 3 — UI updates

### 3.1 Update the buy URL

In `SettingsView.swift` (`ProUnlockTab`), replace:
```swift
URL(string: "https://cepholotech.lemonsqueezy.com/checkout/buy/e76ff2c0-32cd-41b7-b770-7b6b9873ab23")!
```
with the new checkout URL once the DeskMat product is live in the store.
Leave a `// TODO: update checkout URL` comment as a placeholder if the
URL is not ready at the time of this phase.

### 3.2 Update the license key hint

`licenseKeyHint` currently renders `••••-••••-••••-AB12`. Update to match
the new key format:

```swift
var licenseKeyHint: String? {
    guard let (key, _) = readFromKeychain() else { return nil }
    let suffix = String(key.suffix(4))
    return "ceph_deskmat_••••••\(suffix)"
}
```

### 3.3 Update placeholder text in Strings.swift

Change `Strings.Pro.licenseKeyPlaceholder` from a UUID-style hint to
`ceph_deskmat_…` so users know the expected key format.

**Deliverable:** No Lemon Squeezy text visible in the UI; key hint and
placeholder reflect the `ceph_` format.

---

## Phase 4 — Cleanup and tests

### 4.1 Remove dead code

- Delete the Lemon Squeezy URL string from `LicenseManager.swift`.
- Check if `DeskMat.storekit` is still referenced in Xcode (`DeskMatApp.swift`,
  `project.pbxproj`). If not, remove it from the project.

### 4.2 Update mock response shapes in `EntitlementTests.swift`

Current mocks likely reflect the Lemon Squeezy `{ valid, activated, instance }` shape.
Update to match `POST /verify`:

```json
{ "valid": true, "product": "deskmat", "license_id": "uuid",
  "customer_name": "Dev", "expires_at": null,
  "seats_used": 1, "seat_limit": 5 }
```

And for `POST /deactivate`:
```json
{ "success": true, "seats_used": 0 }
```

### 4.3 End-to-end checklist

- [ ] Fresh install: enter `ceph_deskmat_…` key → activates, `isPro = true`
- [ ] Relaunch: background validation succeeds silently
- [ ] Offline relaunch: `isPro` stays `true` (soft-fail)
- [ ] Revoked key: server returns `valid: false` → `isPro = false`, Keychain cleared
- [ ] Seat limit full: `valid: false`, UI shows appropriate error
- [ ] Deactivate: `POST /deactivate` succeeds, `isPro = false`, seat freed
- [ ] Re-activate on same machine after deactivate: works
- [ ] Key hint shows `ceph_deskmat_••••••XXXX` in the activated state view
- [ ] Old Keychain record (with `instanceId`) migrates silently on first launch

**Deliverable:** All unit tests green, checklist passed, no Lemon Squeezy
references remain anywhere in the codebase.

---

## Dependency order

```
Phase 1 (admin API call — one-time)
    └─► Phase 2 (LicenseManager rewrite)
              └─► Phase 3 (UI)
              └─► Phase 4 (cleanup + tests)
```

Phases 3 and 4 are independent of each other and can be done in parallel
once Phase 2 is stable.
