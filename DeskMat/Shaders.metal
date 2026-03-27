#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Lava-lamp color effect.
/// Creates rising metaball-like bubbles that flow upward, preserving the input color's hue.
/// - position: pixel coordinate in user space
/// - color: the existing pixel color
/// - time: elapsed time for animation
/// - size: height of the view (used to normalize coordinates)
[[stitchable]] half4 lavaLamp(float2 position, half4 color, float time, float viewHeight) {
    // Skip transparent pixels
    if (color.a < 0.01) return color;

    // Normalize position (0..1 range, y inverted so 0 = bottom)
    float2 uv = float2(position.x / viewHeight, 1.0 - position.y / viewHeight);

    // Slow time for gentle movement
    float t = time * 0.4;

    // Accumulate metaball field from several rising blobs
    float field = 0.0;

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        // Each blob has a unique horizontal oscillation and rise speed
        float speed = 0.15 + fi * 0.06;
        float xCenter = 0.3 + 0.4 * sin(fi * 1.7 + t * 0.3);
        float yCenter = fract(t * speed + fi * 0.17);

        // Blob size varies
        float radius = 0.25 + 0.1 * sin(fi * 2.3 + t);

        float2 blobPos = float2(xCenter, yCenter);
        float dist = length(uv - blobPos);

        // Metaball contribution: smooth falloff
        field += (radius * radius) / (dist * dist + 0.001);
    }

    // Threshold the field to create distinct blob shapes with soft edges
    float blob = smoothstep(1.2, 2.5, field);

    // Create a lighter and darker shade from the input color
    half4 baseColor = color;
    half4 brightColor = half4(
        min(color.r * 1.6h, 1.0h),
        min(color.g * 1.6h, 1.0h),
        min(color.b * 1.6h, 1.0h),
        color.a
    );

    // Mix: blobs are brighter, background stays as base color
    return mix(baseColor, brightColor, half(blob));
}

/// Animated checkerboard color effect.
/// Pixels with alpha > 0 get a checkerboard pattern; transparent pixels pass through unchanged.
/// - position: pixel coordinate in user space
/// - color: the existing pixel color
/// - time: elapsed time for animation
/// - size: checker square size in points
[[stitchable]] half4 checkerboard(float2 position, half4 color, float time, float size) {
    // Scroll the pattern diagonally over time
    float2 shifted = position + float2(time * 20.0, time * 20.0);
    
    // Determine which checker square this pixel falls in
    int col = int(floor(shifted.x / size));
    int row = int(floor(shifted.y / size));
    bool isLight = (col + row) % 2 == 0;
    
    // Two checker colors
    half4 light = half4(1.0, 1.0, 1.0, color.a);
    half4 dark = half4(0.3, 0.3, 0.3, color.a);
    
    return isLight ? light : dark;
}

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

// --- CRT with Luminance Preservation ---
// Ported from Harrison Allen's Godot shader (public domain)

// sRGB <-> linear conversion
float3 crt_srgb_to_linear(float3 col) {
    float3 lo = col / 12.92;
    float3 hi = pow((col + 0.055) / 1.055, float3(2.4));
    return mix(hi, lo, step(col, float3(0.04045)));
}

float3 crt_linear_to_srgb(float3 col) {
    float3 lo = col * 12.92;
    float3 hi = pow(col, float3(1.0 / 2.4)) * 1.055 - 0.055;
    return mix(hi, lo, step(col, float3(0.0031308)));
}

// Barrel warp (matches Godot's warp function)
float2 crt_warp(float2 uv, float _aspect, float _curve) {
    uv -= 0.5;
    uv.x /= _aspect;
    float warping = dot(uv, uv) * _curve;
    warping -= _curve * 0.25;
    uv /= 1.0 - warping;
    uv.x *= _aspect;
    uv += 0.5;
    return uv;
}

// Sample with per-channel color offset and scanline interpolation
float3 crt_sample(float2 uv, float2 viewSize, float colorOffset, SwiftUI::Layer layer) {
    // Scale UV to pixel coordinates
    float2 pixCoord = uv * viewSize;

    int y = int(pixCoord.y + 0.5) - 1;
    float x = floor(pixCoord.x);
    float ax = x - 1.0;
    float dx = x + 1.0;

    // Sample upper scanline (6 samples for 3 horizontal positions)
    float3 upper_a = crt_srgb_to_linear(float3(layer.sample(float2(ax, float(y))).rgb));
    float3 upper_b = crt_srgb_to_linear(float3(layer.sample(float2(x, float(y))).rgb));
    float3 upper_c = crt_srgb_to_linear(float3(layer.sample(float2(dx, float(y))).rgb));

    // Sample lower scanline
    int y2 = y + 1;
    float3 lower_a = crt_srgb_to_linear(float3(layer.sample(float2(ax, float(y2))).rgb));
    float3 lower_b = crt_srgb_to_linear(float3(layer.sample(float2(x, float(y2))).rgb));
    float3 lower_c = crt_srgb_to_linear(float3(layer.sample(float2(dx, float(y2))).rgb));

    // Per-channel beam offset for chromatic aberration
    float3 beam = float3(pixCoord.x - 0.5);
    beam.r -= colorOffset;
    beam.b += colorOffset;

    // Weighted interpolation across horizontal neighbors
    float3 weight_a = smoothstep(float3(1.0), float3(0.0), beam - float3(ax));
    float3 weight_b = smoothstep(float3(1.0), float3(0.0), abs(beam - float3(x)));
    float3 weight_c = smoothstep(float3(1.0), float3(0.0), float3(dx) - beam);

    float3 upper_col = upper_a * weight_a + upper_b * weight_b + upper_c * weight_c;
    float3 lower_col = lower_a * weight_a + lower_b * weight_b + lower_c * weight_c;

    // Vertical scanline interpolation via sawtooth
    float sawtooth = (pixCoord.y + 0.5) - float(y2);
    sawtooth = smoothstep(0.0, 1.0, sawtooth);

    return mix(upper_col, lower_col, sawtooth);
}

// Generate phosphor mask pattern (dots pattern - typical PC CRT)
float4 crt_generate_mask(float2 fragcoord) {
    // Dots pattern: RGB subpixels + black in 2x2 rotation
    int2 icoords = int2(fragcoord);
    int idx = (icoords.y * 2 + icoords.x) % 4;
    if (idx == 0) return float4(1, 0, 0, 0.25);
    if (idx == 1) return float4(0, 1, 0, 0.25);
    if (idx == 2) return float4(0, 0, 1, 0.25);
    return float4(0, 0, 0, 0.25);
}

// Apply phosphor mask with luminance preservation
float3 crt_apply_mask(float3 linear_color, float2 fragcoord, float maskBrightness) {
    float4 mask = crt_generate_mask(fragcoord);

    // Dim color based on mask brightness setting
    linear_color *= mix(mask.w, 1.0, maskBrightness);

    // Target color to maintain brightness through mask
    float3 target_color = linear_color / mask.w;
    float3 primary_col = clamp(target_color, 0.0, 1.0);

    // Secondary subpixels fill in overflow brightness
    float3 secondary = target_color - primary_col;
    secondary /= 1.0 / mask.w - 1.0;

    primary_col *= mask.rgb;
    primary_col += secondary * (1.0 - mask.rgb);

    return primary_col;
}

/// CRT with luminance preservation layer effect.
/// Ported from Harrison Allen's Godot shader (public domain).
/// Features barrel distortion, per-channel color offset, phosphor dot mask,
/// and luminance-preserving color math.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - intensity: effect strength 0..1 (scales curve and color offset)
/// - viewWidth: width of the view in points
/// - viewHeight: height of the view in points
[[stitchable]] half4 crtEffect(
    float2 position,
    SwiftUI::Layer layer,
    float intensity,
    float viewWidth,
    float viewHeight
) {
    float2 viewSize = float2(viewWidth, viewHeight);
    float aspect = viewHeight / viewWidth;
    float2 uv = position / viewSize;

    // Scale parameters by intensity
    float curve = intensity * 0.3;
    float colorOffset = intensity * 3.0;
    float maskBrightness = mix(0.5, 1.0, 1.0 - intensity * 0.5);

    // Barrel distortion
    float2 warped = crt_warp(uv, aspect, curve);

    // Sample with chromatic aberration
    float3 col = crt_sample(warped, viewSize, colorOffset, layer);

    // Apply phosphor mask
    col = crt_apply_mask(col, position, maskBrightness);

    // Convert back to sRGB
    col = crt_linear_to_srgb(col);

    // Preserve alpha from center sample
    half alpha = layer.sample(position).a;

    return half4(half3(clamp(col, 0.0, 1.0)), alpha);
}
// --- VHS Glitch Effect ---
// Ported from a Godot canvas_item shader

float vhs_random(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453123);
}

float vhs_noise(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);

    float a = vhs_random(i);
    float b = vhs_random(i + float2(1.0, 0.0));
    float c = vhs_random(i + float2(0.0, 1.0));
    float d = vhs_random(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

/// VHS glitch layer effect.
/// Features horizontal slice displacement, RGB channel splitting, scanlines,
/// static noise, ghost image, and glow — all triggered by random glitch events.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - time: elapsed time for animation
/// - intensity: overall effect strength 0..1
/// - viewWidth: width of the view in points
/// - viewHeight: height of the view in points
[[stitchable]] half4 vhsGlitch(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity,
    float viewWidth,
    float viewHeight
) {
    float2 viewSize = float2(viewWidth, viewHeight);
    float2 uv = position / viewSize;

    // Tunable parameters scaled by intensity
    float glitchFrequency = 2.0;
    float redDisp = 0.02 * intensity;
    float greenDisp = 0.02 * intensity;
    float blueDisp = 0.02 * intensity;
    float scanlineInt = 0.3 * intensity;
    float noiseInt = 0.2 * intensity;
    float sliceInt = 0.4 * intensity;
    float ghostInt = 0.1 * intensity;

    // Determine if a glitch is currently active
    float glitchTime = time * glitchFrequency;
    float glitchNoise = vhs_noise(float2(glitchTime, 0.0));
    float glitchActive = step(1.0 - intensity, glitchNoise);

    float2 sampleUV = uv;

    if (glitchActive > 0.5) {
        // Horizontal slice displacement
        float sliceY = vhs_random(float2(glitchTime * 10.0, 0.0));
        if (abs(sampleUV.y - sliceY) < 0.02 * sliceInt) {
            float sliceOffset = (vhs_random(float2(glitchTime * 15.0, 0.0)) - 0.5) * 0.1 * sliceInt;
            sampleUV.x += sliceOffset;
        }

        // Vertical shift
        float vertShift = vhs_random(float2(glitchTime * 8.0, 0.0)) * 0.05 * intensity;
        sampleUV.y += vertShift;

        // Horizontal wave distortion
        float wave = sin(sampleUV.y * 100.0 + glitchTime * 5.0) * 0.01 * intensity;
        sampleUV.x += wave;
    }

    // Convert UV back to point space for layer sampling
    float2 samplePos = sampleUV * viewSize;

    half4 finalColor = layer.sample(samplePos);

    // RGB channel separation
    float shiftR = redDisp * glitchActive * viewWidth;
    float shiftG = greenDisp * glitchActive * viewWidth;
    float shiftB = blueDisp * glitchActive * viewWidth;

    half4 rChan = layer.sample(samplePos + float2(shiftR, 0.0));
    half4 gChan = layer.sample(samplePos + float2(-shiftG, 0.0));
    half4 bChan = layer.sample(samplePos + float2(shiftB, 0.0));

    finalColor.r = mix(finalColor.r, rChan.r, half(glitchActive));
    finalColor.g = mix(finalColor.g, gChan.g, half(glitchActive));
    finalColor.b = mix(finalColor.b, bChan.b, half(glitchActive));

    // Scanlines
    float scanline = sin(sampleUV.y * 300.0 + glitchTime * 2.0) * 0.5 + 0.5;
    finalColor.rgb *= half3(1.0h - half(scanline * scanlineInt));

    // Static noise
    float staticNoise = vhs_random(sampleUV + glitchTime) * noiseInt * glitchActive;
    finalColor.rgb += half3(half(staticNoise));

    // Ghost image
    if (ghostInt > 0.0) {
        float2 ghostOffset = float2(0.01, 0.01) * viewSize;
        half4 ghostColor = layer.sample(samplePos + ghostOffset);
        finalColor.rgb = mix(finalColor.rgb, ghostColor.rgb, half(ghostInt * 0.5));
    }

    // Glow during glitch
    float glow = glitchActive * 0.2 * intensity;
    finalColor.rgb += half3(half(glow));

    return finalColor;
}

// --- Radial Chromatic Aberration ---
// Ported from a Godot canvas_item shader.
// Splits RGB channels radially outward from center, with exponential
// falloff so the effect is stronger near edges.
float2 ca_rotate(float2 v, float cosTheta, float sinTheta) {
    return float2(
        v.x * cosTheta - v.y * sinTheta,
        v.x * sinTheta + v.y * cosTheta
    );
}

/// Radial chromatic aberration layer effect.
/// Red and blue channels are displaced radially from the view center,
/// with strength increasing exponentially toward the edges.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - intensity: effect strength 0..1 (mapped to 0..5 internally)
/// - viewWidth: width of the view in points
/// - viewHeight: height of the view in points
[[stitchable]] half4 chromaticAberration(
    float2 position,
    SwiftUI::Layer layer,
    float intensity,
    float viewWidth,
    float viewHeight
) {
    float2 viewSize = float2(viewWidth, viewHeight);
    float2 uv = position / viewSize;

    // Scale intensity to match Godot's 0..5 range
    float strength = intensity * 5.0;
    float threshold = 1.0;

    // Base displacement directions (red left, green center, blue right)
    float2 rDisp = float2(-1.0, 0.0);
    float2 gDisp = float2(0.0, 0.0);
    float2 bDisp = float2(1.0, 0.0);

    // Direction from center
    float2 center = float2(0.5);
    float2 dir = uv - center;
    float dist = 2.0 * length(dir);

    // Angle of the direction vector
    float angle = (abs(dir.x) < 0.0001 && abs(dir.y) < 0.0001)
        ? 0.0
        : atan2(dir.y, dir.x);

    // Exponential falloff: stronger near edges
    float effect = exp(strength * (dist - threshold));

    float cosA = cos(angle);
    float sinA = sin(angle);

    // Rotate displacement vectors to point radially outward
    rDisp = ca_rotate(effect * strength * rDisp, cosA, sinA);
    gDisp = ca_rotate(effect * strength * gDisp, cosA, sinA);
    bDisp = ca_rotate(effect * strength * bDisp, cosA, sinA);

    // Sample each channel at its displaced position (displacement is in pixels)
    half4 rSample = layer.sample(position + rDisp);
    half4 gSample = layer.sample(position + gDisp);
    half4 bSample = layer.sample(position + bDisp);
    half4 aSample = layer.sample(position);

    return half4(rSample.r, gSample.g, bSample.b, aSample.a);
}

// --- Hologram Effect ---
// Ported from a Godot canvas_item shader.
// Scrolling horizontal lines with color shifting, noise, and alpha fade.

/// Hologram layer effect.
/// Scrolling scan lines tinted between two colors, with horizontal color shift,
/// noise grain, and transparency — creating a sci-fi holographic projection look.
/// - position: pixel coordinate in user space
/// - layer: the rasterized SwiftUI layer
/// - time: elapsed time for animation
/// - intensity: overall effect strength 0..1
/// - viewWidth: width of the view in points
/// - viewHeight: height of the view in points
[[stitchable]] half4 hologram(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity,
    float viewWidth,
    float viewHeight
) {
    float2 viewSize = float2(viewWidth, viewHeight);
    float2 uv = position / viewSize;
    // Parameters scaled by intensity
    int lines = 100;
    float speed = 0.4 * intensity;
    float noiseAmount = 0.05 * intensity;
    float effectFactor = 0.4 * intensity;
    float alpha = mix(1.0, 0.5, intensity);

    // Hologram colors: blue and red
    float3 color1 = float3(0.0, 0.0, 1.0);
    float3 color2 = float3(1.0, 0.0, 0.0);

    // Scrolling line index and grade
    float lineN = floor((uv.y - time * speed) * float(lines));
    float lineGrade = abs(sin(lineN * M_PI_F / 4.0));
    float smoothLineGrade = abs(sin((uv.y - time * speed) * float(lines)));

    // Line color: mix between blue and red based on line position
    float3 lineColor = mix(color1, color2, lineGrade);

    // Color shift: sample with horizontal offset based on smooth line grade
    float shiftAmount = smoothLineGrade / 240.0 * effectFactor * viewWidth;
    half4 col = layer.sample(position - float2(shiftAmount, 0.0));

    // Noise grain
    float n = fract(sin(dot(uv * time, float2(12.9898, 78.233))) * 438.5453) * 1.9;
    col.rgb = mix(col.rgb, half3(half(n)), half(noiseAmount));

    // Mix in the line color
    col.rgb = mix(col.rgb, half3(lineColor), half(effectFactor));

    // Apply alpha
    col.a = half(alpha) * col.a;

    return col;
}


