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
/// Blurs a neighborhood of pixels, extracts the bright regions, and adds them
/// back additively — creating a gentle luminous glow around highlights.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - intensity: bloom strength 0..1
[[stitchable]] half4 softBloom(float2 position, SwiftUI::Layer layer, float intensity) {
    half4 center = layer.sample(position);

    // Accumulate a blurred sample over a 5x5 neighborhood
    half4 blur = half4(0.0h);
    float radius = 2.0 + intensity * 3.0;
    for (int dx = -2; dx <= 2; dx++) {
        for (int dy = -2; dy <= 2; dy++) {
            blur += layer.sample(position + float2(float(dx), float(dy)) * radius);
        }
    }
    blur /= 25.0h;

    // Only bloom pixels above a brightness threshold so darks stay clean
    half brightness = (blur.r * 0.299h + blur.g * 0.587h + blur.b * 0.114h);
    half bloomStrength = smoothstep(0.25h, 0.9h, brightness) * half(intensity);

    half3 bloomed = clamp(center.rgb + blur.rgb * bloomStrength * 0.8h, 0.0h, 1.0h);
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
