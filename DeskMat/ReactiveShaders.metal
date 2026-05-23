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

    return float4(color, 1.0);
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

    return float4(color, 1.0);
}

// MARK: - Rainbow Outline

float3 hsv2rgb(float h, float s, float v) {
    float3 rgb = clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
                       0.0, 1.0);
    return v * mix(float3(1.0), rgb, s);
}

fragment float4 rainbowFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    const float borderWidth = 2.0;
    const float speed       = 0.15;

    float2 uv       = in.uv;
    float2 pixelPos = uv * u.resolution;

    // SDF is in pixel space — negative inside, positive outside
    float sdf    = roundedRectSDF(pixelPos, u.resolution, u.cornerRadius);
    float outerA = 1.0 - smoothstep(0.0, 1.0, sdf);                     // fades at outer edge
    float innerA = smoothstep(-borderWidth - 1.0, -borderWidth, sdf);    // fades at inner edge
    float mask   = outerA * innerA;

    if (mask < 0.001) { return float4(0.0); }

    float angle = atan2(uv.y - 0.5, uv.x - 0.5);
    float hue   = fract(angle / 6.28318530 + u.time * speed);

    float3 color = hsv2rgb(hue, 1.0, 1.0);
    return float4(color * mask, mask);
}

// MARK: - DVD Bounce
// Adapted from shadertoy.com/view/scjSDz
// Logo SDF credited to tdhooper (shadertoy.com/view/wtcSzN)

float dvd_vmin(float2 v) { return min(v.x, v.y); }

float dvd_ellip(float2 p, float2 s) {
    float m = dvd_vmin(s);
    return (length(p / s) * m) - m;
}

float dvd_halfEllip(float2 p, float2 s) {
    p.x = max(0.0, p.x);
    float m = dvd_vmin(s);
    return (length(p / s) * m) - m;
}

float dvd_glyph_d(float2 p) {
    float d  = dvd_halfEllip(p, float2(0.8, 0.5));
    d        = max(d, -p.x - 0.5);
    float d2 = dvd_halfEllip(p, float2(0.45, 0.3));
    d2       = max(d2, min(-p.y + 0.2, -p.x - 0.15));
    d        = max(d, -d2);
    return d;
}

float dvd_glyph_v(float2 p) {
    float2 pp = p;
    p.y += 0.7;
    p.x  = abs(p.x);
    float2 a = normalize(float2(1.0, -0.55));
    float d  = dot(p, a);
    float d2 = d + 0.3;
    p  = pp;
    d  = min(d,  -p.y + 0.3);
    d2 = min(d2, -p.y + 0.5);
    d  = max(d, -d2);
    d  = max(d, abs(p.x + 0.3) - 1.1);
    return d;
}

float dvd_glyph_c(float2 p) {
    p.y     += 0.95;
    float d  = dvd_ellip(p, float2(1.8, 0.25));
    float d2 = dvd_ellip(p, float2(0.45, 0.09));
    d        = max(d, -d2);
    return d;
}

float dvd_logo(float2 p) {
    p.y -= 0.345;
    p.x -= 0.035;
    p    = p * float2x2(float2(1.0, -0.2), float2(0.0, 1.0));
    float d = dvd_glyph_v(p);
    d = min(d, dvd_glyph_c(p));
    p.x += 1.3;
    d = min(d, dvd_glyph_d(p));
    p.x -= 2.4;
    d = min(d, dvd_glyph_d(p));
    return d;
}

float3 dvd_pal(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318 * (c * t + d));
}

float3 dvd_spectrum(float n) {
    return dvd_pal(n,
        float3(0.5, 0.5, 0.5),
        float3(0.5, 0.5, 0.5),
        float3(1.0, 1.0, 1.0),
        float3(0.0, 0.33, 0.67));
}

#define DVD_SCALE 0.32
#define DVD_SPD_X 0.23
#define DVD_SPD_Y 0.16

float2 dvd_bounce(float t, float2 res) {
    float aspect = res.x / res.y;
    float halfW  = 1.55 * DVD_SCALE / (2.0 * aspect);
    float halfH  = 0.85 * DVD_SCALE / 2.0;
    float yBias  = 0.2  * DVD_SCALE / 2.0;
    float2 lo    = float2(halfW, halfH - yBias);
    float2 hi    = float2(1.0 - halfW, 1.0 - halfH - yBias);
    float2 rng   = hi - lo;
    float px = fmod(t * DVD_SPD_X, rng.x * 2.0);
    float py = fmod(t * DVD_SPD_Y + rng.y * 0.61803, rng.y * 2.0);
    float cx = (px < rng.x) ? px : rng.x * 2.0 - px;
    float cy = (py < rng.y) ? py : rng.y * 2.0 - py;
    return lo + float2(cx, cy);
}

fragment float4 dvdFragment(VertexOut in [[stage_in]],
                             constant Uniforms& u [[buffer(0)]]) {
    float2 uv       = in.uv;
    float2 pixelPos = uv * u.resolution;

    // Flip y to match Shadertoy convention (y=0 at bottom)
    float2 fc = float2(pixelPos.x, u.resolution.y - pixelPos.y);

    // Centred normalised coords, height mapped to [-1, 1]
    float2 p = (-u.resolution + 2.0 * fc) / u.resolution.y;

    // Bouncing logo centre → centred coords
    float2 uvCenter = dvd_bounce(u.time, u.resolution);
    float2 move     = (uvCenter - 0.5) * float2(u.resolution.x / u.resolution.y, 1.0) * 2.0;

    // Spectrum colour cycling
    float hue    = fmod(u.time * 0.06, 1.0);
    float3 logoc = dvd_spectrum(hue);

    // CRT scanlines
    float scan = 0.96 + 0.04 * sin(fc.y * 3.14159265 * 1.8);

    float3 col = float3(0.03);

    // DVD logo SDF
    float d  = dvd_logo((p - move) / DVD_SCALE);
    float aa = abs(dfdx(d)) + abs(dfdy(d));
    float mask = 1.0 - clamp(d / aa, 0.0, 1.0);

    col = mix(col, logoc, mask);

    // Inner shadow
    float innerMask = 1.0 - clamp((d + 0.06) / aa, 0.0, 1.0);
    col = mix(col, logoc * 0.25, innerMask * mask);

    col *= scan;

    // Gamma
    col = pow(max(col, float3(0.0)), float3(1.0 / 1.5));

    return float4(col, 1.0);
}

// MARK: - 80s Grid
// Adapted from Shadertoy retro perspective grid shader.

fragment float4 eightiesFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]]) {
    float2 uv       = in.uv;
    float2 pixelPos = uv * u.resolution;
    float2 R        = u.resolution;

    // Flip y to match Shadertoy convention (y=0 at bottom)
    float2 fc = float2(pixelPos.x, R.y - pixelPos.y);

    // Vertical fade: 1 at bottom (near viewer), 0 at top (horizon)
    float C = 1.0 - pow(fc.y / R.y, 3.0);

    // Centre and normalise coordinates
    float2 U = 5.0 * (fc + fc - R) / R.y;

    // Flip vertical and apply perspective
    U.y = 1.0 - U.y * 2.0;
    U  /= 1.0 + U.y / 8.0;

    // Scroll forward over time
    U.y -= u.time;

    // Three chroma-offset copies
    float2 UA = U + C / 15.0;
    float2 UB = U + C / 30.0;

    // Distance to nearest grid axis
    U  = abs(fract(U)  - 0.5);
    UA = abs(fract(UA) - 0.5);
    UB = abs(fract(UB) - 0.5);

    // Glow: inverse-sqrt falloff from each axis
    float gVal = 0.1;
    U  = gVal * C / sqrt(U);
    UA = gVal * C / sqrt(UA);
    UB = gVal * C / sqrt(UB);

    // Combine layers with blue / red / green weights
    float4 O = (U.x  + U.y)  * float4(0.0, 0.0, 0.8, 0.0)
             +                  float4(0.22, 0.20, 0.20, 0.0)
             + (UA.x + UA.y) * float4(0.8, 0.0, 0.0, 0.0)
             + (UB.x + UB.y) * float4(0.0, 0.7, 0.0, 0.0);

    O *= C;
    O  = clamp(O, 0.0, pow(C, 1.8));
    O *= 1.5 * O;

    return float4(O.rgb, 1.0);
}

// MARK: - CRT Overlay
// Post-process pass applied on top of every reactive style.
// Reads the previous pass from channel0 and adds scanlines,
// chromatic screen waves, and RGB channel aberration.

fragment float4 crtFragment(VertexOut in [[stage_in]],
                             constant Uniforms& u [[buffer(0)]],
                             texture2d<float> channel0 [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 uv = in.uv;
    float2 U  = uv * u.resolution;
    float2 R  = u.resolution;

    // Horizontal scanlines — divide U.y to widen band period
    float US1 = sin(U.y * 3.0) / 2.0 + 0.7;

    // Per-channel vertical waves (slight phase offset → chromatic ripple)
    float3 US2;
    US2.x = sin(20.0 / R.y * U.y + (-u.time * 2.0 - 0.4)) / 10.0 + 0.85;
    US2.y = sin(20.0 / R.y * U.y + (-u.time * 2.0      )) / 10.0 + 0.85;
    US2.z = sin(20.0 / R.y * U.y + (-u.time * 2.0 + 0.4)) / 10.0 + 0.85;
    float3 US = US1 * US2;

    // Chromatic aberration — R/G/B sampled from slightly offset UVs
    float3 CR = channel0.sample(s, uv + float2( 0.001, 0.0)).rgb * float3(0.8, 0.1, 0.1);
    float3 CG = channel0.sample(s, uv                       ).rgb * float3(0.1, 0.8, 0.1);
    float3 CB = channel0.sample(s, uv + float2(-0.001, 0.0)).rgb * float3(0.1, 0.1, 0.8);

    float3 col = (CR + CG + CB) / 1.2;  // contrast loss
    col *= US * 1.1;

    float srcAlpha = channel0.sample(s, uv).a;
    return float4(col, srcAlpha);
}

// MARK: - CRT Warp (pass 3)
// Barrel distortion, vignette, scanlines, and film noise applied over pass 2.

float2 crt_coords(float2 uv, float bend) {
    uv -= 0.5;
    uv *= 2.0;
    uv.x *= 1.0 + pow(abs(uv.y) / bend, 2.0);
    uv.y *= 1.0 + pow(abs(uv.x) / bend, 2.0);
    uv /= 2.5;
    return uv + 0.5;
}

float crt_vignette(float2 uv, float size, float smoothness, float edgeRounding) {
    uv -= 0.5;
    uv *= size;
    float amount = sqrt(pow(abs(uv.x), edgeRounding) + pow(abs(uv.y), edgeRounding));
    return smoothstep(0.0, smoothness, 1.0 - amount);
}

float crt_scanline(float2 uv, float lines, float speed, float t) {
    return sin(uv.y * lines + t * speed);
}

float crt_random(float2 uv, float t) {
    return fract(sin(dot(uv, float2(15.5151, 42.2561))) * 12341.14122 * sin(t * 0.03));
}

float crt_noise(float2 uv, float t) {
    float2 i = floor(uv);
    float2 f = fract(uv);
    float a = crt_random(i,                    t);
    float b = crt_random(i + float2(1.0, 0.0), t);
    float c = crt_random(i + float2(0.0, 1.0), t);
    float d = crt_random(i + float2(1.0, 1.0), t);
    float2 u = smoothstep(float2(0.0), float2(1.0), f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

fragment float4 crtWarpFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]],
                                 texture2d<float> channel0 [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 uv     = in.uv;
    float2 crtUV  = crt_coords(uv, 4.0);

    // Vertical chromatic aberration + sample warped UVs
    float4 col;
    col.r = channel0.sample(s, crtUV + float2(0.0,  0.01)).r;
    col.g = channel0.sample(s, crtUV).r;
    col.b = channel0.sample(s, crtUV + float2(0.0, -0.01)).b;
    col.a = channel0.sample(s, crtUV).a;

    float srcAlpha = col.a;


    return float4(col.rgb, srcAlpha);
}

// MARK: - Voronoi CRT Defrag & Refrag

float voronoi_random_f(float x) {
    return fract(tan(x) * 1e3);
}

float2 voronoi_random_v2(float2 uv) {
    return fract(
        float2(
            cos(dot(uv.xy, float2(12.9898, 78.2337))),
            sin(dot(uv.yx, float2(86.2361, 55.5983)))
        ) * 81839.41256
    );
}

fragment float4 voronoiFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;

    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = fragCoord / resolution;

    float2 uv3 = uv * 2.0 - 1.0;
    uv3.x *= resolution.x / resolution.y;

    float pixelation = 1.0;
    uv = (ceil(fragCoord / pixelation + 0.5) * pixelation) / resolution;

    uv = uv * 2.0 - 1.0;
    uv.x *= resolution.x / resolution.y;

    uv *= sin(u.time) / 2.0 + 3.0;

    float2 iuv = floor(uv);
    float2 fuv = fract(uv);

    float  minDist  = 0.6;
    float2 minPoint = float2(0.0);

    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float2 neighbour = float2(float(i), float(j));
            float2 point     = float2(voronoi_random_v2(iuv + neighbour));
            point = 0.5 + (sin(u.time) / 2.0 + 0.5) * cos(u.time + 8.6236 * point);
            float2 diff = neighbour + point - fuv;
            float  dist = length(diff);
            if (dist < minDist) {
                minDist  = dist;
                minPoint = point;
            }
        }
    }

    float3 color = float3(0.0);
    color.xy += dot(minPoint, float2(0.25, 0.75));
    color.x  -= abs(sin(3.0 * minDist)) * 0.25;
    color.y  += 1.0 - step(0.15 - sin(u.time) / 10.0, minDist);
    color.xz += 0.75 - step(0.15 - sin(u.time) / 10.0, minDist);

    float4 background = float4(color, 1.0);

    float4 foreground = float4(1.0);

    foreground.xyz -= abs(sin(0.5)) * 0.333;

    float count = resolution.y * 4.0;
    float2 sl = float2(sin(uv3.y * count), cos(uv3.y * count));
    float3 scanlines = float3(sl.x, sl.y, sl.x);
    foreground = mix(foreground, float4(scanlines, 1.0), foreground.a);

    float4 O = mix(foreground, background, foreground.a);

    float  hue = u.time * 2.094;
    float3 k   = float3(0.57735);
    float  c   = cos(hue);
    float  s   = sin(hue);
    float3 rgb = O.rgb * c + cross(k, O.rgb) * s + k * dot(k, O.rgb) * (1.0 - c);

    return float4(rgb, 1.0);
}

// MARK: - Subpixel RGB Grid

float subpixel_hash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float3 subpixel_dot_grid_pattern(float2 p, float t) {
    float2 cell_idx = floor(p);

    float animation_offset = subpixel_hash(float3(cell_idx, 0.0));
    float animation        = floor(t * 0.125 + animation_offset);
    float rnd              = subpixel_hash(float3(cell_idx, animation));

    float subpix = floor(fract(p.x) * 3.0);

    float r = subpixel_hash(float3(cell_idx, rnd + 1.0));
    float g = subpixel_hash(float3(cell_idx, rnd + 2.0));
    float b = subpixel_hash(float3(cell_idx, rnd + 3.0));
    float3 RGB = float3(r, g, b);

    float3 mask  = float3(float(subpix == 0.0), float(subpix == 1.0), float(subpix == 2.0));
    float3 color = RGB * mask;

    float2 q = 0.5 + 0.5 * cos(2.0 * M_PI_F * p * float2(3.0, 1.0) - M_PI_F);
    return color * (q.x * q.y) * float(rnd > 0.5);
}

fragment float4 subpixelFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = (2.0 * fragCoord - resolution) / resolution.y;

    float zoom = 1.0 + u.indicatorOpacity * 0.5;

    const float grid_dim = 5.0;
    float2 p = grid_dim * (zoom * uv + u.time * 0.25);

    float3 color = subpixel_dot_grid_pattern(p, u.time);

    color = pow(color, float3(1.0 / 2.2));

    return float4(color, 1.0);
}

// MARK: - Joker (Balatro spin shader)
// Original by localthunk (https://www.playbalatro.com)

float4 joker_effect(float2 screenSize, float2 screen_coords, float t) {
    const float SPIN_ROTATION = -2.0;
    const float SPIN_SPEED    =  7.0;
    const float CONTRAST      =  3.5;
    const float LIGHTING      =  0.4;
    const float SPIN_AMOUNT   =  0.25;
    const float PIXEL_FILTER  =  745.0;
    const float SPIN_EASE     =  1.0;
    const float4 COLOUR_1 = float4(0.871, 0.267, 0.231, 1.0);
    const float4 COLOUR_2 = float4(0.0,   0.42,  0.706, 1.0);
    const float4 COLOUR_3 = float4(0.086, 0.137, 0.145, 1.0);

    float pixel_size = length(screenSize) / PIXEL_FILTER;
    float2 uv = (floor(screen_coords * (1.0 / pixel_size)) * pixel_size
                 - 0.5 * screenSize) / length(screenSize);
    float uv_len = length(uv);

    float speed = (SPIN_ROTATION * SPIN_EASE * 0.2) + 302.2;
    float new_pixel_angle = atan2(uv.y, uv.x) + speed
                          - SPIN_EASE * 20.0 * (SPIN_AMOUNT * uv_len + (1.0 - SPIN_AMOUNT));

    float2 mid = (screenSize / length(screenSize)) / 2.0;
    uv = float2(uv_len * cos(new_pixel_angle) + mid.x,
                uv_len * sin(new_pixel_angle) + mid.y) - mid;

    uv   *= 30.0;
    speed = t * SPIN_SPEED;
    float2 uv2 = float2(uv.x + uv.y);

    for (int i = 0; i < 5; i++) {
        uv2 += sin(max(uv.x, uv.y)) + uv;
        uv  += 0.5 * float2(cos(5.1123314 + 0.353 * uv2.y + speed * 0.131121),
                             sin(uv2.x - 0.113 * speed));
        uv  -= 1.0 * cos(uv.x + uv.y) - 1.0 * sin(uv.x * 0.711 - uv.y);
    }

    float contrast_mod = 0.25 * CONTRAST + 0.5 * SPIN_AMOUNT + 1.2;
    float paint_res    = min(2.0, max(0.0, length(uv) * 0.035 * contrast_mod));
    float c1p   = max(0.0, 1.0 - contrast_mod * abs(1.0 - paint_res));
    float c2p   = max(0.0, 1.0 - contrast_mod * abs(paint_res));
    float c3p   = 1.0 - min(1.0, c1p + c2p);
    float light = (LIGHTING - 0.2) * max(c1p * 5.0 - 4.0, 0.0)
                +  LIGHTING        * max(c2p * 5.0 - 4.0, 0.0);

    return (0.3 / CONTRAST) * COLOUR_1
         + (1.0 - 0.3 / CONTRAST) * (COLOUR_1 * c1p
                                    + COLOUR_2 * c2p
                                    + float4(c3p * COLOUR_3.rgb, c3p * COLOUR_1.a))
         + light;
}

fragment float4 jokerFragment(VertexOut in [[stage_in]],
                               constant Uniforms& u [[buffer(0)]]) {
    float4 color = joker_effect(u.resolution, in.uv * u.resolution, u.time);
    return float4(color.rgb, 1.0);
}

// MARK: - Corner Mask
// Final pass applied to every style. Clips the rendered output to the dock's
// rounded rect shape so individual shaders don't need to manage their own alpha.

fragment float4 cornerMaskFragment(VertexOut in [[stage_in]],
                                    constant Uniforms& u [[buffer(0)]],
                                    texture2d<float> channel0 [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 col   = channel0.sample(s, in.uv);
    float  alpha = roundedRectAlpha(in.uv, u.resolution, u.cornerRadius);
    return float4(col.rgb, col.a * alpha);
}
