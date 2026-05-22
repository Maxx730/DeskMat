#include <metal_stdlib>
using namespace metal;

// Must match ReactiveUniforms in ReactiveBackgroundView.swift
struct Uniforms {
    float2 mousePosition;    // logical points, top-left origin
    float2 resolution;       // view size in logical points
    float  time;
    float  indicatorOpacity;
    float  cornerRadius;
};

// Signed distance function for a rounded rectangle.
// Returns < 0 inside, > 0 outside, 0 on the edge.
float roundedRectSDF(float2 pixelPos, float2 resolution, float radius) {
    float2 halfSize = resolution * 0.5;
    float2 q        = abs(pixelPos - halfSize) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Alpha mask — 1.0 inside, 0.0 outside, anti-aliased at the edge.
float roundedRectAlpha(float2 uv, float2 resolution, float radius) {
    float2 pixelPos = uv * resolution;
    float  sdf      = roundedRectSDF(pixelPos, resolution, radius);
    return 1.0 - smoothstep(-1.0, 0.0, sdf);
}

struct VertexOut {
    float4 position [[position]];
    float2 uv;               // (0,0) = top-left, (1,1) = bottom-right
};

// Full-screen triangle — covers the viewport with no vertex buffer.
// NDC: (-1,+1) = top-left, so UV (0,0) maps to top-left, matching
// the NSView coordinate system (isFlipped = true).
vertex VertexOut reactiveVertex(uint vid [[vertex_id]]) {
    const float2 positions[3] = {
        float2(-1,  1),   // top-left
        float2( 3,  1),   // top-right (beyond viewport)
        float2(-1, -3)    // bottom-left (beyond viewport)
    };
    const float2 uvs[3] = {
        float2(0, 0),
        float2(2, 0),
        float2(0, 2)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv       = uvs[vid];
    return out;
}

// MARK: - Shared helpers

float liquidWave(float x, float t, float speed, float amp) {
    return sin((x * 2.0 + t * speed) * 2.0) * amp;
}

// MARK: - Lock-On
// Ported from Godot shader by author on godotshaders.com/shader/scan-lines/

float highlight_sl(float point, float progress, float thickness) {
    return smoothstep(progress - thickness, progress, point)
         - smoothstep(progress, progress + thickness, point);
}

fragment float4 lockOnFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    const float3 line_color   = float3(0.0, 1.0, 0.0);
    const float3 bg_color     = line_color * 0.07;
    const float3 border_color = line_color * 0.18;
    const float  border_px    = 4.5;

    // Shared SDF — used for both the border and the corner alpha mask
    float2 pixelPos = in.uv * u.resolution;
    float  sdf      = roundedRectSDF(pixelPos, u.resolution, u.cornerRadius);

    // Border highlight — pixels within border_px of the rounded edge, on the inside
    float border = smoothstep(-border_px, 0.0, sdf);

    // Rounded rect alpha — 1 inside, 0 outside, anti-aliased at the edge
    float alpha = 1.0 - smoothstep(-1.0, 0.0, sdf);

    // Scan lines
    float thickness_x = 1.0 / u.resolution.x;
    float thickness_y = 1.0 / u.resolution.y;
    float2 mouse_uv   = u.mousePosition / u.resolution;
    float  lines      = highlight_sl(in.uv.y, mouse_uv.y, thickness_y)
                      + highlight_sl(in.uv.x, mouse_uv.x, thickness_x);

    // Hologram pulse — smooth uniform oscillation
    float pulse = sin(u.time * 50.0) * 0.05 + 0.45;
    lines      *= pulse;

    // Lock-on square outline centered on mouse position
    // Uses Chebyshev distance (max of x/y) to produce a perfect square
    const float lock_size = 20.0;
    float2 lock_d   = abs(pixelPos - u.mousePosition);
    float  lock_sdf = max(lock_d.x, lock_d.y) - lock_size;
    float  lock_on   = 1.0 - smoothstep(0.0, 1.5, abs(lock_sdf));
    float  lock_fill = 1.0 - smoothstep(-1.0, 0.0, lock_sdf);

    float3 color = bg_color
                 + border * (border_color - bg_color)
                 + lines   * line_color * pulse * u.indicatorOpacity
                 + lock_on   * line_color * pulse * u.indicatorOpacity
                 + lock_fill * line_color * 0.08 * u.indicatorOpacity;

    // CRT scanlines — subtle horizontal bands every 2 pixels
    float crt = sin(pixelPos.y * 3.14159265) * 0.16 + 0.92;
    color *= crt;

    return float4(color, alpha);
}

// MARK: - Liquid Fill
// Adapted from "2D Liquid Fill Inside Sphere" by Mirza Beig / RuverQ
// (godotshaders.com/shader/2d-liquid-fill-inside-sphere/)
// Ported to the dock's rounded rectangle instead of a circle.

fragment float4 liquidFillFragment(VertexOut in [[stage_in]],
                                    constant Uniforms& u [[buffer(0)]]) {
    const float3 frontColor = float3(0.10, 0.55, 1.00);
    const float3 backColor  = frontColor * 0.65;
    const float3 bgColor    = frontColor * 0.04;

    float2 uv = in.uv; // (0,0) top-left, (1,1) bottom-right

    // Rounded rect mask
    float alpha = roundedRectAlpha(uv, u.resolution, u.cornerRadius);

    // Fill level: base + idle oscillation + hover swell
    float idleOsc   = sin(u.time * 0.8) * 0.03;
    float hoverSwell = u.indicatorOpacity * 0.12;
    float fP = 0.50 + idleOsc + hoverSwell;

    // Wave envelope — stronger in the horizontal centre, fades at edges
    float vB = smoothstep(0.1, 0.9, sin(uv.x * 3.14159265)) - 0.3;

    // Front wave (rightward) and back wave (leftward)
    float fW = liquidWave(uv.x,  u.time, 2.0, 0.025) + vB * sin(u.time * 4.0) * 0.015;
    float bW = liquidWave(uv.x, -u.time, 2.0, 0.025) - vB * sin(u.time * 4.0) * 0.015;

    // Surface amplitude oscillation
    float fA = sin(u.time * 4.0) * 0.02 * max(vB, 0.0);

    // Liquid fills from the bottom: pixels with uv.y > surface Y are submerged
    float frontFill = step((fA + fW) + fP, uv.y);
    float backFill  = step((-fA + bW) + fP, uv.y);

    // Subtle highlight band just below the front wave surface
    float surfaceY  = fP + fW + fA;
    float highlight = smoothstep(0.012, 0.0, abs(uv.y - surfaceY)) * frontFill * 0.4;

    float3 color = bgColor
                 + frontFill                          * frontColor
                 + clamp(backFill - frontFill, 0.0, 1.0) * backColor * 0.8
                 + highlight                          * 1.0;

    return float4(color, alpha);
}
