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

// MARK: - Electro
// Port of Humus Electro demo (http://humus.name/index.php?page=3D&ID=35)
// Simplex noise by Nikita Miropolskiy (CC BY-NC-SA 3.0)
// https://www.shadertoy.com/view/XsX3zB

float3 electro_random3(float3 c) {
    float j = 4096.0 * sin(dot(c, float3(17.0, 59.4, 15.0)));
    float3 r;
    r.z = fract(512.0 * j);
    j *= 0.125;
    r.x = fract(512.0 * j);
    j *= 0.125;
    r.y = fract(512.0 * j);
    return r - 0.5;
}

float electro_simplex3d(float3 p) {
    const float F3 = 0.3333333;
    const float G3 = 0.1666667;

    float3 s = floor(p + dot(p, float3(F3)));
    float3 x = p - s + dot(s, float3(G3));

    float3 e  = step(float3(0.0), x - x.yzx);
    float3 i1 = e * (1.0 - e.zxy);
    float3 i2 = 1.0 - e.zxy * (1.0 - e);

    float3 x1 = x - i1 + G3;
    float3 x2 = x - i2 + 2.0 * G3;
    float3 x3 = x - 1.0 + 3.0 * G3;

    float4 w;
    float4 d;

    w.x = dot(x,  x);
    w.y = dot(x1, x1);
    w.z = dot(x2, x2);
    w.w = dot(x3, x3);

    w = max(0.6 - w, 0.0);

    d.x = dot(electro_random3(s),       x);
    d.y = dot(electro_random3(s + i1),  x1);
    d.z = dot(electro_random3(s + i2),  x2);
    d.w = dot(electro_random3(s + 1.0), x3);

    w *= w;
    w *= w;
    d *= w;

    return dot(d, float4(52.0));
}

float electro_noise(float3 m) {
    return  0.5333333 * electro_simplex3d(m)
          + 0.2666667 * electro_simplex3d(2.0 * m)
          + 0.1333333 * electro_simplex3d(4.0 * m)
          + 0.0666667 * electro_simplex3d(8.0 * m);
}

fragment float4 electroFragment(VertexOut in [[stage_in]],
                                 constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv = fragCoord / resolution * 2.0 - 1.0;

    float2 p  = fragCoord / resolution.x;
    float3 p3 = float3(p, u.time * 0.4);

    float intensity = electro_noise(p3 * 12.0 + 12.0);

    float mouse_y    = 1.0 - 2.0 * u.mousePosition.y / u.resolution.y;
    float arc_center = mix(0.0, mouse_y, u.indicatorOpacity);

    float t = clamp(-uv.x * uv.x * 0.16 + 0.15, 0.0, 1.0);
    float y = abs(intensity * -t * 8.0 + uv.y - arc_center);
    y *= mix(1.0, 0.35, u.indicatorOpacity);

    float g = pow(y, 0.2);

    float3 bg  = float3(17.0 / 255.0); // #111111
    float3 col = float3(1.70, 1.48, 1.78);
    col = col * -g + col;
    col = col * col;
    col = col * col;
    col = max(col, bg);

    return float4(col, 1.0);
}

// MARK: - Starfield

float sf_hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 sf_hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.103, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float2x2 sf_rot(float a) {
    float s = sin(a), c = cos(a);
    return float2x2(float2(c, s), float2(-s, c));
}

float3 sf_getStarField(float2 uv, float zoom, float time, float seed) {
    float2 gv  = fract(uv * zoom) - 0.5;
    float2 id  = floor(uv * zoom);
    float3 col = float3(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 offs = float2(float(x), float(y));
            float2 n    = sf_hash22(id + offs + seed);
            float pTime = time * (0.3 + n.x * 0.7) + n.y * 6.28;
            float size  = (0.04 + 0.12 * sf_hash12(id + offs + seed + 121.3))
                        * (sin(pTime) * 0.5 + 0.5);
            float2 p    = offs + n - 0.5;
            float  d    = length(gv - p);
            float3 starCol = mix(float3(0.5, 0.7, 1.0),
                                 float3(1.0, 0.5, 0.3),
                                 sf_hash12(id + offs + seed + 45.1));
            starCol = mix(starCol, float3(1.0, 0.9, 0.7), n.x * n.y);
            float light  = (size * 0.015) / (d + 5e-4);
            float glow   = (size * 0.003) / (d * d + 8e-5);
            float2 r_uv  = (gv - p) * sf_rot(pTime * 0.5);
            float  rays  = pow(max(0.0, 1.0 - abs(r_uv.x * r_uv.y * 1e3)), 12.0)
                         * (size * 0.1 / (d + 0.01));
            rays += pow(max(0.0, 1.0 - abs(r_uv.x)), 50.0) * (size * 0.05 / (d + 0.01));
            col += (light + glow + rays) * starCol;
        }
    }
    return col;
}

fragment float4 starfieldFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    float2 resolution = u.resolution;
    float2 fragCoord  = float2(in.uv.x, 1.0 - in.uv.y) * resolution;

    float2 uv    = (fragCoord - 0.5 * resolution) / resolution.y;
    float  t = u.time * 0.15;

    float2 camPath = float2(sin(t * 0.5), cos(t * 0.3)) * 2.0;
    float  camRot  = sin(t * 0.2) * 0.4;

    float3 finalCol = float3(0.0);
    float  noise    = sf_hash12(fragCoord + u.time);

    for (float i = 0.0; i < 1.0; i += 1.0 / 8.0) {
        float  depth = fract(i - t * 0.5);
        float  zoom  = mix(15.0, 0.05, depth);
        float  fade  = smoothstep(0.0, 0.4, depth) * smoothstep(1.0, 0.8, depth);
        float2 p_uv  = uv;
        p_uv = p_uv * sf_rot(camRot * depth);
        p_uv += camPath * depth;
        finalCol += sf_getStarField(p_uv, zoom, u.time, i * 951.4) * fade;
    }

    finalCol *= mix(1.0, 2.8, u.indicatorOpacity);
    finalCol  = pow(finalCol, float3(0.8));
    finalCol *= 1.2;

    float vign = length(in.uv - 0.5);
    finalCol *= smoothstep(1.2, 0.3, vign);
    finalCol += (noise - 0.5) * 0.012;

    float3 bloom = finalCol * finalCol;
    finalCol += bloom * 0.3;
    finalCol = mix(finalCol,
                   float3(dot(finalCol, float3(0.299, 0.587, 0.114))),
                   -0.1);

    return float4(clamp(finalCol, 0.0, 1.0), 1.0);
}

// MARK: - Colors
// "V-Drop" by Del — 19/11/2019 (Shadertoy default CC BY-NC-SA 3.0)

float colors_vDrop(float2 uv, float t, float trailMax, float trailMin) {
    uv.x *= 128.0;
    float dx = fract(uv.x);
    uv.x = floor(uv.x);
    uv.y *= 0.05;
    float o     = sin(uv.x * 215.4);
    float s     = cos(uv.x * 33.1) * 0.3 + 0.7;
    float trail = mix(trailMax, trailMin, s);
    float yv    = fract(uv.y + t * s + o) * trail;
    yv = 1.0 / yv;
    yv = smoothstep(0.0, 1.0, yv * yv);
    yv = sin(yv * 3.14159265) * (s * 5.0);
    float d2 = sin(dx * 3.14159265);
    return yv * (d2 * d2);
}

fragment float4 colorsFragment(VertexOut in [[stage_in]],
                                constant Uniforms& u [[buffer(0)]]) {
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;
    float2 p = (fragCoord - 0.5 * u.resolution) / u.resolution.y;
    p.x *= 0.18;
    float  d = length(p) + 0.1;
    p = float2(atan2(p.x, p.y) / 3.14159265, 2.5 / d);

    float t        = u.time * 0.4;
    float trailMax = mix(60.0, 140.0, u.indicatorOpacity);
    float trailMin = mix(20.0,  60.0, u.indicatorOpacity);
    float3 col  = float3(1.55, 0.65, 0.225) * colors_vDrop(p, t,        trailMax, trailMin);
    col += float3(0.55, 0.75, 1.225) * colors_vDrop(p, t + 0.33, trailMax, trailMin);
    col += float3(0.45, 1.15, 0.425) * colors_vDrop(p, t + 0.66, trailMax, trailMin);

    float3 result = max(col * (d * d), float3(17.0 / 255.0));
    return float4(result, 1.0);
}

// MARK: - Topograph
// Topographic noise shader originally by poweredbypine.com

float3 tg_hash33(float3 p) {
    p = float3(dot(p, float3(127.1, 311.7,  74.7)),
               dot(p, float3(269.5, 183.3, 246.1)),
               dot(p, float3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float tg_tetraNoise(float2 o, float time) {
    float3 p = float3(o.x + 0.024 * time, o.y + 0.012 * time, 0.015 * time);
    float3 i = floor(p + dot(p, float3(0.33333)));
    p -= i - dot(i, float3(0.16666));
    float3 i1 = step(p.yzx, p);
    float3 i2 = max(i1, 1.0 - i1.zxy);
    i1 = min(i1, 1.0 - i1.zxy);
    float3 p1 = p - i1 + 0.16666;
    float3 p2 = p - i2 + 0.33333;
    float3 p3 = p - 0.5;
    float4 v = max(0.5 - float4(dot(p,p), dot(p1,p1), dot(p2,p2), dot(p3,p3)), 0.0);
    float4 d = float4(dot(p,  tg_hash33(i)),
                      dot(p1, tg_hash33(i + i1)),
                      dot(p2, tg_hash33(i + i2)),
                      dot(p3, tg_hash33(i + 1.0)));
    return clamp(dot(d, v*v*v*8.0) * 1.732 + 0.5, 0.0, 1.0);
}

float tg_topologize(float noise, float lineCount) {
    float smoothFloor = noise * lineCount;
    float2 fracU = float2(smoothFloor, fwidth(smoothFloor) * 1.3);
    fracU.x = fract(fracU.x);
    fracU += (1.0 - 2.0 * fracU) * step(fracU.y, fracU.x);
    smoothFloor = smoothFloor - clamp(1.0 - fracU.x / fracU.y, 0.0, 1.0);
    return noise * 0.25 + smoothFloor * 0.75 / (lineCount - 1.0);
}

fragment float4 topographFragment(VertexOut in [[stage_in]],
                                   constant Uniforms& u [[buffer(0)]]) {
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;
    float2 p = (fragCoord * 2.5 - u.resolution) / (u.resolution.y * 0.5 + u.resolution.x * 0.5);
    float2 e = float2(10.0 / (u.resolution.y + u.resolution.x), 0.0);

    float lineCount = mix(12.0, 28.0, u.indicatorOpacity);
    float fxl = tg_topologize(tg_tetraNoise(p + e.xy, u.time), lineCount);
    float fxr = tg_topologize(tg_tetraNoise(p - e.xy, u.time), lineCount);
    float fyu = tg_topologize(tg_tetraNoise(p + e.yx, u.time), lineCount);
    float fyd = tg_topologize(tg_tetraNoise(p - e.yx, u.time), lineCount);
    float weight = clamp((max(abs(fxl - fxr), abs(fyu - fyd)) - 0.01) * 12.0, 0.0, 1.0);

    float3 color = mix(float3(0.11), float3(0.18), weight);
    return float4(color, 1.0);
}

// MARK: - Snow

fragment float4 snowFragment(VertexOut in [[stage_in]],
                              constant Uniforms& u [[buffer(0)]]) {
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;

    float snow   = 0.0;
    float random = fract(sin(dot(fragCoord, float2(12.9898, 78.233))) * 43758.5453);

    for (int k = 0; k < 6; k++) {
        // i starts at 1 — i=0 causes div-by-zero (5.0/float(i)), producing NaN
        // which silently fails the omiVal < 0.08 check in GLSL; skip it explicitly.
        for (int i = 1; i < 12; i++) {
            float cellSize  = 2.0 + float(i) * 3.0;
            float downSpeed = 0.3 + (sin(u.time * 0.4 + float(k + i * 20)) + 1.0) * 0.00008;
            float2 uv = (fragCoord / u.resolution.x)
                      + float2(0.01 * sin((u.time + float(k * 6185)) * 0.6 + float(i)) * (5.0 / float(i)),
                               downSpeed * (u.time + float(k * 1352)) * (1.0 / float(i)));
            float2 uvStep = ceil(uv * cellSize - float2(0.5)) / cellSize;

            float x = fract(sin(dot(uvStep, float2(12.9898 + float(k) * 12.0,  78.233 + float(k) * 315.156))) * 43758.5453 + float(k) * 12.0) - 0.5;
            float y = fract(sin(dot(uvStep, float2(62.2364 + float(k) * 23.0,  94.674 + float(k) *  95.0)))   * 62159.8432 + float(k) * 12.0) - 0.5;

            float randomMagnitude1 = sin(u.time * 2.5) * 0.7 / cellSize;
            float randomMagnitude2 = cos(u.time * 2.5) * 0.7 / cellSize;

            float d = 5.0 * distance(uvStep + float2(x * sin(y), y) * randomMagnitude1
                                            + float2(y, x) * randomMagnitude2, uv);

            float omiVal  = fract(sin(dot(uvStep, float2(32.4691, 94.615))) * 31572.1684);
            float density = mix(0.08, 0.3, u.indicatorOpacity);
            if (omiVal < density) {
                float newd = (x + 1.0) * 0.4 * clamp(1.9 - d * (15.0 + x * 6.3) * (cellSize / 1.4), 0.0, 1.0);
                snow += newd;
            }
        }
    }

    float3 bg = float3(17.0 / 255.0);
    return float4(clamp(bg + float3(snow) + random * 0.01, 0.0, 1.0), 1.0);
}

// MARK: - Cellular

float2 cel_getCellPower(float2 coord, float2 pos, float2 size) {
    float2 power = (size * size) / dot(coord - pos, coord - pos);
    power *= power * sqrt(power); // inverse 5th-power falloff
    return power;
}

float3 cel_powerToColor(float2 power) {
    float3 bg    = float3(17.0 / 255.0); // #111111
    float3 outer = float3(0.13);
    float3 inner = float3(0.21);
    float  tMax  = pow(1.03, 2.2);
    float  tMin  = 1.0 / tMax;
    float3 col   = mix(bg,    outer, smoothstep(tMin, tMax, power.y));
    col           = mix(col,  inner, smoothstep(tMin, tMax, power.x));
    return col;
}

fragment float4 cellularFragment(VertexOut in [[stage_in]],
                                  constant Uniforms& u [[buffer(0)]]) {
    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * u.resolution;
    float2 cellSize  = float2(10.0, 14.0);
    float2 hRes      = u.resolution * 0.5;

    float  T        = u.time * 0.1;
    float  varBase  = 0.5;
    float  varRange = mix(0.1, 0.9, u.indicatorOpacity);
    float2 power    = float2(0.0);

    for (int xi = 1; xi <= 40; xi++) {
        float x = float(xi);
        float2 pos = hRes * float2(
            sin(T * fract(0.246  * x) + x * 3.6) * cos(T * fract(0.374  * x) - x * fract(0.6827 * x)) + 1.0,
            cos(T * fract(0.4523 * x) + x * 5.5) * sin(T * fract(0.128  * x) + x * fract(0.3856 * x)) + 1.0
        );
        power += cel_getCellPower(fragCoord, pos, cellSize * (varBase + fract(0.2834 * x) * varRange));
    }

    return float4(cel_powerToColor(power), 1.0);
}

// MARK: - Edge Highlight
// Optional post-process pass — adds a subtle white rim along the inside of
// the dock's rounded rect.

fragment float4 edgeHighlightFragment(VertexOut in [[stage_in]],
                                       constant Uniforms& u [[buffer(0)]],
                                       texture2d<float> channel0 [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 base = channel0.sample(s, in.uv);

    float2 pixelPos = in.uv * u.resolution;
    float  sdf      = roundedRectSDF(pixelPos, u.resolution, u.cornerRadius);
    float  edge     = smoothstep(-2.5, 0.0, sdf);

    float3 col = base.rgb + float3(edge * 0.18);
    return float4(col, base.a);
}

// MARK: - Corner Mask
// Final pass applied to every style. Clips rendered output to the dock's
// rounded rect so individual shaders don't need to manage their own alpha.

fragment float4 cornerMaskFragment(VertexOut in [[stage_in]],
                                    constant Uniforms& u [[buffer(0)]],
                                    texture2d<float> channel0 [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 col   = channel0.sample(s, in.uv);
    float  alpha = roundedRectAlpha(in.uv, u.resolution, u.cornerRadius);
    return float4(col.rgb, col.a * alpha);
}
