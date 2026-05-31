# Caustic Shader — Implementation Plan

Port the water caustic shader by David Hoskins to Metal as a selectable style named **Caustic**.

---

## ⚠️ License Notice

Licensed under **CC BY-NC-SA 3.0** (Attribution, Non-Commercial, Share-Alike).  
Original: https://www.shadertoy.com/view/MdKXDm by David Hoskins.

**Non-commercial** — same concern as the Electro simplex noise. Confirm licensing
before shipping in DeskMat Pro, or replace with a public-domain caustic implementation.

---

## What the shader does

Three iterations of a matrix-fold-fract-length operation on a 3D vector `(x, y, time)`
produce a caustic-like interference pattern. Each iteration multiplies the running vector
by a fixed 3×3 matrix and a scale factor (0.5 → 0.4 → 0.3), then measures the distance
of the fracted result from 0.5. The minimum of the three distances, raised to the 7th power
and scaled, gives bright hotspots with a soft teal base: `(d⁷·25, d⁷·25+0.35, d⁷·25+0.5)`.
The UV breathes gently with `sin(time)`, producing a slow zoom-in/out.

---

## Macro expansion

The original `#define F` expands `F.5)`, `F.4)`, `F.3)` to:
```glsl
length(0.5 - fract(k.xyw *= mat3(-2,-1,2, 3,-2,1, 1,2,2) * N))
```
Each call **mutates** `k.xyw` before computing the length — the next call operates
on the already-multiplied value, not the fracted one.

---

## Key adaptations

| Concern | Decision |
|---|---|
| `iDate.w * 0.2` (seconds-in-day × 0.2) | `u.time * 0.2` |
| `iDate.z * 0.2` (day × 0.2, feeds k.z) | k.z never appears in `.xyw` swizzle — irrelevant, omitted |
| `k.xyw *= mat3(...) * N` mutation | Local `float3 xyw`; `xyw = xyw * m * N` each iteration |
| `fract` applied for distance only | Compute `length(0.5 - fract(xyw))` without reassigning xyw |
| `pow(scalar, 7.) * 25. + vec4(...)` | `float b = pow(d,7.)*25.0; float4(b, b+0.35, b+0.5, 1.0)` |
| `mat3(-2,-1,2, 3,-2,1, 1,2,2)` (col-major) | `float3x3(float3(-2,-1,2), float3(3,-2,1), float3(1,2,2))` |
| `v *= mat3` row-vector semantics | `v * float3x3` — same row-vector × matrix in MSL |
| Y-axis | Not sensitive to orientation (radially symmetric pattern); use `in.uv` directly |

---

## Phase 1 — Add `caustic` case to `ReactiveStyle`

**File:** `DeskMat/AppEnums.swift`

```swift
case discoHallway = "Disco Hallway"
case caustic      = "Caustic"
```

---

## Phase 2 — Route `fragmentShaderName`

**File:** `DeskMat/ReactiveBackgroundView.swift`

```swift
case .caustic: return "causticFragment"
```

---

## Phase 3 — Write `causticFragment` in Metal

**File:** `DeskMat/ReactiveShaders.metal` — append after `discoHallwayFragment`.

**Acceptance criteria:**
- Selecting Caustic shows animated water-caustic hotspots in a teal palette.
- Pattern breathes slowly with a sin-driven zoom.
- Dock corners are masked by the corner mask pass.
- All other styles still work correctly.

---

## Phase 4 — Polish (optional / post-ship)

| Idea | Notes |
|---|---|
| Palette | Replace `(0, 0.35, 0.5)` base with a configurable tint |
| Speed | Scale `u.time * 0.2` with a configurable factor |
| Hover ripple | Add `u.indicatorOpacity * offset` to xyw on hover |
| License | Replace with a public-domain caustic before commercial release |
