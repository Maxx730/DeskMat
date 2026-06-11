// SwiftUI Shaders
// ---------------
// These functions are called via SwiftUI's ShaderLibrary API:
//   ShaderLibrary.functionName(.float(x), ...)
// They are applied as post-process overlays on rasterized SwiftUI views using
// .layerEffect() or .colorEffect(). Each function operates on already-rendered
// pixels — there is no vertex stage, no multi-pass rendering, and no access to
// mouse position or other AppKit state.
//
// For background shaders that need mouse input, multi-pass rendering, or a
// custom vertex stage, see ReactiveShaders.metal + ReactiveBackgroundView.swift.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// --- YUV conversion helpers ---

float3 rgb_to_yuv(float3 rgb) {
    // BT.601 conversion
    float y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    float u = -0.14713 * rgb.r - 0.28886 * rgb.g + 0.436 * rgb.b;
    float v = 0.615 * rgb.r - 0.51499 * rgb.g - 0.10001 * rgb.b;
    return float3(y, u, v);
}

float3 yuv_to_rgb(float3 yuv) {
    float r = yuv.x + 1.13983 * yuv.z;
    float g = yuv.x - 0.39465 * yuv.y - 0.58060 * yuv.z;
    float b = yuv.x + 2.03211 * yuv.y;
    return clamp(float3(r, g, b), 0.0, 1.0);
}

float scanlineNoise(float2 uv, float offset) {
    return (fract(sin(dot(uv * offset, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
}

/// VHS/CRT scanline wiggle layer effect.
/// Ported from a Godot shader — offsets chrominance channels relative to
/// luminance using YUV conversion, creating a retro color-bleed look.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer (allows sampling neighbors)
/// - time: elapsed time for animation
/// - colorOffsetMultiplier: noise amplitude for chroma offset (Godot default 0.004)
/// - blackOffsetMultiplier: noise amplitude for luma offset (Godot default 0.1)
/// - colorOffset: base horizontal chroma shift in pixels (Godot default 0.005 of UV, here in pts)
/// - viewWidth: width of the view in points (for normalizing offsets)
[[stitchable]] half4 scanlineWiggle(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float colorOffsetMultiplier,
    float blackOffsetMultiplier,
    float colorOffset,
    float viewWidth
) {
    // Normalize to 0..1 UV space for noise calculation (matches Godot's UV)
    float2 uv = position / viewWidth;

    // Scanline row — quantize Y to create horizontal bands (487 matches Godot)
    float2 scanlineCoord = float2(floor(uv.y * 487.0), fract(uv.y * 487.0));

    // Compute horizontal offsets (in points, not UV)
    float xOffset = colorOffset + scanlineNoise(scanlineCoord, time) * colorOffsetMultiplier;
    float blackOffset = scanlineNoise(scanlineCoord, time + 69.420) * (blackOffsetMultiplier * 0.01);

    // Scale offsets from UV-space to point-space
    float xOffsetPts = xOffset * viewWidth;
    float blackOffsetPts = blackOffset * viewWidth;

    // Sample: luminance from black-offset position, chrominance from color-offset position
    half4 baseSample = layer.sample(position + float2(blackOffsetPts, 0.0));
    half4 chromaSample = layer.sample(position + float2(xOffsetPts, 0.0));

    // Convert both samples to YUV
    float3 yuv1 = rgb_to_yuv(float3(baseSample.rgb));
    float3 yuv2 = rgb_to_yuv(float3(chromaSample.rgb));

    // Take luminance from base, chrominance from offset sample
    float3 result = yuv_to_rgb(float3(yuv1.x, yuv2.yz));

    return half4(half3(result), baseSample.a);
}

/// Soft bloom layer effect.
/// Blurs a 7x7 Gaussian neighborhood (Pascal row-6 weights, 1-pixel step) and
/// adds bright regions back additively — producing a smooth, non-pixelated glow.
/// Using 1-pixel steps keeps the kernel dense so there are no visible grid gaps.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - intensity: bloom strength 0..1
[[stitchable]] half4 softBloom(float2 position, SwiftUI::Layer layer, float intensity) {
    half4 center = layer.sample(position);
    if (center.a < 0.01h) return center;

    // Pascal row-6 Gaussian weights (7 taps, sigma ≈ 1.5, sums to 1.0)
    const float gw[7] = { 0.015625, 0.09375, 0.234375, 0.3125, 0.234375, 0.09375, 0.015625 };

    // Dense 7x7 kernel at 1-pixel steps — no gaps, smooth result.
    // The glow radius is fixed at 3 px; intensity controls how much is added back.
    half4 blur = half4(0.0h);
    for (int i = 0; i < 7; i++) {
        for (int j = 0; j < 7; j++) {
            float w = gw[i] * gw[j];
            float2 offset = float2(float(i - 3), float(j - 3));
            blur += half(w) * layer.sample(position + offset);
        }
    }
    // 2D weights are products of 1D weights which sum to 1, so no division needed.

    // Only add bloom to pixels above a brightness threshold so dark areas stay clean
    half luma = dot(blur.rgb, half3(0.299h, 0.587h, 0.114h));
    half bloomStrength = smoothstep(0.2h, 0.9h, luma) * half(intensity);

    half3 bloomed = clamp(center.rgb + blur.rgb * bloomStrength, 0.0h, 1.0h);
    return half4(bloomed, center.a);
}

/// Pixelate layer effect.
/// Snaps pixels to a coarser grid, giving icons a retro lo-fi look.
/// At small block sizes (2–4 pts) it reads as texture rather than obvious pixelation.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - blockSize: grid cell size in points
[[stitchable]] half4 pixelate(float2 position, SwiftUI::Layer layer, float blockSize) {
    float2 snapped = floor(position / blockSize) * blockSize + blockSize * 0.5;
    return layer.sample(snapped);
}

/// Film grain color effect.
/// Adds animated per-pixel luminance noise, giving icons a textured,
/// cinematic quality. At low intensity the grain is barely perceptible.
/// - position: pixel coordinate in user space
/// - color: the existing pixel color
/// - time: elapsed time for animation
/// - intensity: noise amplitude (0.02–0.12 is tasteful)
[[stitchable]] half4 filmGrain(float2 position, half4 color, float time, float intensity) {
    if (color.a < 0.01) return color;
    // Shift the hash seed each frame so the grain animates
    float2 uv = position + fract(time * 100.0);
    float noise = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    float3 result = clamp(float3(color.rgb) + noise * intensity, 0.0, 1.0);
    return half4(half3(result), color.a);
}

/// Heat shimmer layer effect.
/// Displaces pixels vertically with two octaves of sine waves, simulating the
/// look of air distorted by heat rising from a hot surface. At low intensity
/// the icon gently breathes; at high intensity it warps noticeably.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - time: elapsed time for animation
/// - intensity: distortion strength 0..1
[[stitchable]] half4 heatShimmer(float2 position, SwiftUI::Layer layer, float time, float intensity) {
    float amplitude = intensity * 3.0;

    // Primary wave: wide, slow horizontal variation
    float dy1 = sin(position.x * 0.08 + time * 1.2) * amplitude;
    // Secondary octave: narrower and slightly faster for organic complexity
    float dy2 = sin(position.x * 0.04 + time * 0.7 + 1.5) * amplitude * 0.5;

    return layer.sample(position + float2(0.0, dy1 + dy2));
}

/// Old film layer effect.
/// Combines four classic film-damage signals: sepia tone, edge vignette,
/// animated grain, periodic flicker, and occasional vertical scratch lines.
/// Gate weave (per-row horizontal jitter) adds the final touch of analogue instability.
/// - position:   pixel coordinate in user space
/// - layer:      the rasterized SwiftUI layer
/// - time:       elapsed time for animation
/// - intensity:  overall effect strength 0..1
/// - viewWidth:  view width in points (for vignette UV and scratch placement)
/// - viewHeight: view height in points (for vignette UV)
[[stitchable]] half4 oldFilm(
    float2 position,
    SwiftUI::Layer layer,
    float  time,
    float  intensity,
    float  viewWidth,
    float  viewHeight
) {
    // Gate weave: quantise rows into 2-pt bands and jitter each band horizontally,
    // simulating film slipping slightly in the projector gate.
    float rowSeed = floor(position.y / 2.0);
    float weave   = sin(rowSeed * 127.1 + time * 2.5) * intensity * 0.8;
    half4 color   = layer.sample(position + float2(weave, 0.0));
    if (color.a < 0.01h) return color;

    float3 rgb = float3(color.rgb);

    // Sepia: convert to luminance then re-tint with warm brown
    float luma   = dot(rgb, float3(0.299, 0.587, 0.114));
    float3 sepia = clamp(float3(luma * 1.15 + 0.05, luma * 0.88, luma * 0.55), 0.0, 1.0);
    rgb = mix(rgb, sepia, intensity * 0.85);

    // Vignette: darken towards the edges using normalised UV distance
    float2 uv       = (position / float2(viewWidth, viewHeight)) * 2.0 - 1.0;
    float  vignette = 1.0 - clamp(dot(uv * 0.8, uv * 0.8) * intensity, 0.0, 0.65);
    rgb *= vignette;

    // Grain: hash-based per-pixel noise that shifts each frame
    float2 grainPos = position + fract(time * 97.3);
    float  grain    = fract(sin(dot(grainPos, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    rgb = clamp(rgb + grain * (0.04 + intensity * 0.06), 0.0, 1.0);

    // Flicker: two beating sine waves produce an irregular brightness pulse
    float flicker = 1.0 + sin(time * 8.1 + 0.5) * sin(time * 3.7) * 0.025 * intensity;
    rgb = clamp(rgb * flicker, 0.0, 1.0);

    // Scratch: a random thin vertical line that appears ~25% of the time
    float scratchFrame = floor(time * 1.5);
    float scratchRand  = fract(sin(scratchFrame * 127.1 + 31.4) * 43758.5453);
    if (scratchRand > 0.75) {
        float scratchX = fract(sin(scratchFrame * 93.989) * 43758.5) * viewWidth;
        float dist     = abs(position.x - scratchX);
        if (dist < 1.0) {
            float brightness = 0.75 + grain * 0.25;
            rgb = mix(rgb, float3(brightness), intensity * 0.6 * (1.0 - dist));
        }
    }

    return half4(half3(rgb), color.a);
}

/// Shine glint layer effect — faithful port of the Godot canvas_item shine shader.
///
/// Algorithm:
///   1. Compute an inverted Chebyshev-distance vignette that tapers the band
///      towards the icon corners (gradient_to_edge).
///   2. Rotate UV around the icon center by SHINE_ROTATION_DEG.
///   3. Advance a sweep position with fract(time * speed) so the band loops
///      continuously while the cursor hovers.
///   4. Remap line distance to a brightness factor (smoothstep-equivalent via
///      linear remap + sqrt, matching the Godot maths exactly).
///   5. Lerp each pixel towards white by shine * alpha so transparent areas
///      (outside the rounded-rect mask) are never illuminated.
///
/// Loops while active; stopped by clearing hoverStartDate in AppShortcutButton.
/// - position:   pixel coordinate in user space
/// - layer:      the rasterized SwiftUI layer
/// - time:       elapsed seconds since hover began
/// - viewWidth:  view width in points (for UV normalisation)
/// - viewHeight: view height in points (for UV normalisation)

#define SHINE_LINE_SMOOTHNESS  0.045f
#define SHINE_LINE_WIDTH       0.09f
#define SHINE_BRIGHTNESS       3.0f
#define SHINE_ROTATION_DEG     30.0f
#define SHINE_DISTORTION       1.8f
#define SHINE_SPEED            1.4f
#define SHINE_POSITION         0.0f
#define SHINE_POSITION_MIN     0.25f
#define SHINE_POSITION_MAX     0.5f

[[stitchable]] half4 shineGlint(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float viewWidth,
    float viewHeight
) {
    half4 col = layer.sample(position);
    if (col.a < 0.01h) return col;

    float2 uv = position / float2(viewWidth, viewHeight);

    // --- Gradient to edge (inverted Chebyshev + distortion) ---
    // 1 at center, falls to 0 (and negative) at corners — tapers the shine band.
    float2 center_uv = uv - float2(0.5f, 0.5f);
    float gradient_to_edge = max(abs(center_uv.x), abs(center_uv.y));
    gradient_to_edge = 1.0f - gradient_to_edge * SHINE_DISTORTION;

    // --- Rotate UV around center ---
    float angle_rad = SHINE_ROTATION_DEG * (M_PI_F / 180.0f);
    float cosA = cos(angle_rad);
    float sinA = sin(angle_rad);
    float2 rotated_uv = float2(
        center_uv.x * cosA - center_uv.y * sinA + 0.5f,
        center_uv.x * sinA + center_uv.y * cosA + 0.5f
    );

    // --- Sweep position (single pass) ---
    float remapped_position = SHINE_POSITION_MIN
                            + (SHINE_POSITION_MAX - SHINE_POSITION_MIN) * SHINE_POSITION;
    float t = clamp(time * SHINE_SPEED + remapped_position, 0.0f, 1.0f); // 0..1, no loop
    float remapped_time = -2.0f + 4.0f * t;                 // remap to -2..2

    // --- Line distance in rotated UV space ---
    float line = abs(rotated_uv.x + remapped_time);
    line = gradient_to_edge * line;
    line = sqrt(max(line, 0.0f));   // sqrt of a clipped non-negative value

    // --- Remap to brightness (matches Godot's manual smoothstep-equivalent) ---
    float offset_plus  = SHINE_LINE_WIDTH + SHINE_LINE_SMOOTHNESS;
    float offset_minus = SHINE_LINE_WIDTH - SHINE_LINE_SMOOTHNESS;
    float input_range  = offset_minus - offset_plus; // always negative
    float shine = (line - offset_plus) / input_range; // 1 at centre, 0 at outer edge
    shine = clamp(shine * SHINE_BRIGHTNESS, 0.0f, 1.0f);

    // --- Blend towards white, respecting per-pixel alpha ---
    // Lerping towards white at shine intensity — transparent pixels stay unlit.
    float3 result = mix(float3(col.rgb), float3(1.0f), shine * float(col.a));
    return half4(half3(result), col.a);
}

/// Eve Online hologram layer effect.
/// Stacks seven passes over the source layer to produce a CRT-style holographic look:
///   0. Glitch                — discrete events displace horizontal slices sideways
///   1. Chromatic aberration  — R channel shifted left, B channel shifted right (enhanced during glitch)
///   2. Scan lines            — smoothstep dark bands every 4 px scrolling over time
///   3. Sweep band            — a brighter horizontal band that scrolls top→bottom
///   4. Faction tint          — dark areas nudged toward the faction colour
///   5. Flicker               — beating sine waves for irregular global brightness pulse
///   6. Noise                 — low-amplitude per-frame grain for phosphor instability
/// At intensity == 0 the shader returns the source pixel unchanged.
/// - position:   pixel coordinate in user space
/// - layer:      the rasterized SwiftUI layer
/// - time:       elapsed time for animation
/// - intensity:  overall effect strength 0..1
/// - viewWidth:  view width in points (for UV normalisation)
/// - viewHeight: view height in points (for UV normalisation)
/// - tintR/G/B:  faction colour components for the dark-area tint pass
[[stitchable]] half4 eveHologram(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity,
    float viewWidth,
    float viewHeight,
    float tintR, float tintG, float tintB
) {
    if (intensity < 0.001) return layer.sample(position);

    float2 uv = position / float2(viewWidth, viewHeight);

    // 0. Glitch — fire discrete events at ~15 Hz; displace random horizontal slices
    float glitchFrame  = floor(time * 15.0);
    float glitchSeed   = fract(sin(glitchFrame * 127.1) * 43758.5453);
    float glitchShift = 0.0;
    if (glitchSeed > 0.80) {  // active ~20% of events (~3 times/sec)
        float sliceH    = 3.0 + floor(fract(sin(glitchFrame * 93.9) * 43758.5) * 6.0);
        float sliceIdx  = floor(position.y / sliceH);
        float sliceRand = fract(sin(sliceIdx * 311.7 + glitchFrame * 57.3) * 43758.5453);
        if (sliceRand > 0.55) {
            glitchShift = (sliceRand - 0.55) / 0.45 * viewWidth * 0.025 * intensity;
        }
    }
    float2 samplePos = position + float2(glitchShift, 0.0);

    // 1. Chromatic aberration — aberration widens during a glitch
    float aberration = (1.5 + abs(glitchShift) * 0.25) * intensity;
    half4 center = layer.sample(samplePos);
    if (center.a < 0.01h) return layer.sample(position);

    half rCh = layer.sample(samplePos + float2(-aberration, 0.0)).r;
    half bCh = layer.sample(samplePos + float2( aberration, 0.0)).b;
    float3 rgb = float3(rCh, center.g, bCh);

    // 2. Scan lines — smoothstep fade creates soft dark bands every 4 px, scrolling over time
    float scanBand  = fract((position.y + time * 8.0) * 0.25);
    float scanLight = smoothstep(0.0, 0.45, scanBand) * smoothstep(1.0, 0.55, scanBand);
    rgb *= 1.0 - (1.0 - scanLight) * 0.35 * intensity;

    // 3. Sweep band — sharp leading edge, long trailing glow, horizontal shimmer
    float sweepY    = fract(time * 0.22);
    float sweepRelY = uv.y - sweepY;
    sweepRelY -= floor(sweepRelY + 0.5);  // wrap to [-0.5, 0.5] for continuity at edges

    float aboveDist = max(-sweepRelY, 0.0);
    float belowDist = max( sweepRelY, 0.0);
    float leadEdge  = smoothstep(0.018, 0.0, aboveDist);   // crisp upper edge
    float trailGlow = smoothstep(0.12,  0.0, belowDist);   // soft trailing tail
    float sweepAmt  = leadEdge * 0.30 + trailGlow * 0.14;

    // Horizontal shimmer — slow sine wave blended with per-column grain
    float shimmer = 0.88 + sin(position.x * 0.35 + time * 6.0) * 0.07
                  + fract(sin(position.x * 127.1) * 43758.5) * 0.05;
    sweepAmt *= shimmer;

    // Tint toward faction colour on the bright band
    float3 sweepColor = mix(float3(1.0), float3(tintR, tintG, tintB), 0.30);
    rgb = clamp(rgb + sweepAmt * sweepColor * intensity, 0.0, 1.0);

    // 4. Faction tint — push dark areas toward the faction colour
    float luma  = dot(rgb, float3(0.299, 0.587, 0.114));
    float3 tint = float3(tintR, tintG, tintB);
    rgb = mix(rgb, tint, (1.0 - luma) * 0.18 * intensity);

    // 5. Flicker — beating sine waves produce an irregular global brightness pulse
    float flicker = 1.0 + (sin(time * 23.7) * sin(time * 7.3) * 0.10
                         + sin(time * 47.1) * 0.03) * intensity;
    rgb = clamp(rgb * flicker, 0.0, 1.0);

    // 6. Noise — hash-based per-frame grain for phosphor instability
    float2 noiseUV = position + fract(time * 317.0);
    float  noise   = fract(sin(dot(noiseUV, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    rgb = clamp(rgb + noise * 0.025 * intensity, 0.0, 1.0);

    return half4(half3(rgb), center.a);
}

/// Hue drift color effect.
/// Slowly rotates the hue of each pixel over time using YUV hue rotation.
/// At low speed the shift is nearly subliminal — icons feel alive without
/// any obvious movement.
/// - position: pixel coordinate in user space
/// - color: the existing pixel color
/// - time: elapsed time for animation
/// - speed: rotation speed in radians per second (0.05–0.15 is subtle)
[[stitchable]] half4 hueDrift(float2 position, half4 color, float time, float speed) {
    if (color.a < 0.01) return color;
    float angle = time * speed;
    float c = cos(angle);
    float s = sin(angle);
    float3 yuv = rgb_to_yuv(float3(color.rgb));
    yuv.yz = float2(yuv.y * c - yuv.z * s, yuv.y * s + yuv.z * c);
    return half4(half3(yuv_to_rgb(yuv)), color.a);
}
