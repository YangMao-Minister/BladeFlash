#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <minecraft:constants.glsl>
#include <minecraft:utils.glsl>

uniform sampler2D MainSampler;
uniform sampler2D DataSampler;
uniform sampler2D DepthSampler;
uniform sampler2D NoiseSampler;

layout(location = 0) in vec2 texCoord;
flat layout(location = 1) in mat4 mvpInverse;
flat layout(location = 5) in mat4 viewProjMat;
flat layout(location = 9) in mat4 projection;
flat layout(location = 13) in mat4 viewMat;
flat layout(location = 17) in int vertexCount;
flat layout(location = 18) in ivec3 prevCameraBlockPos;
flat layout(location = 19) in vec3 prevCameraOffset;

layout(location = 0) out vec4 fragColor;

vec3 reconstructPosition(in vec2 uv, in float z) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, z, 1.0);
    vec4 position_v = mvpInverse * ndc;
    return position_v.xyz / position_v.w;
}

uint hash(uint x) {
    x += (x << 10u);
    x ^= (x >> 6u);
    x += (x << 3u);
    x ^= (x >> 11u);
    x += (x << 15u);
    return x;
}

uint hash(uvec3 v) {
    return hash(v.x ^ hash(v.y) ^ hash(v.z));
}

float floatConstruct(uint m) {
    const uint ieeeMantissa = 0x007FFFFFu;
    const uint ieeeOne = 0x3F800000u;

    m &= ieeeMantissa;
    m |= ieeeOne;

    float f = uintBitsToFloat(m);
    return f - 1.0;
}

float random(inout vec3 v) {
    return floatConstruct(hash(floatBitsToUint(v += 1.0)));
}

float random2D(vec2 p) {
    return floatConstruct(hash(floatBitsToUint(p.x) ^ hash(floatBitsToUint(p.y))));
}

vec4 samplerNoise(vec2 uv) {
    return texture(NoiseSampler, fract(uv));
}

float sdfSegment(in vec2 p, vec2 a, vec2 b, float d) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - d;
}

struct TailVertex {
    vec3 pos;
    vec3 color;
};

TailVertex decodeNode(int index) {
    int base = index * 5 + 33;
    TailVertex n;
    n.color = texelFetch(DataSampler, ivec2(base + 1, 0), 0).rgb;
    n.pos.x = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 2, 0), 0).rgb);
    n.pos.y = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 3, 0), 0).rgb);
    n.pos.z = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 4, 0), 0).rgb);
    return n;
}

struct Triangle {
    vec3 posA, posB, posC;
    vec3 colorA, colorB, colorC;
    int indexA, indexB, indexC;
};

// 裁剪用的视图空间顶点（位置/颜色/索引都是视图空间或原始数据）
struct ClipVertex {
    vec3 pos;    // 视图空间
    vec3 color;
    float index; // 用于渐变的索引
};

// 在近平面 z = -nearPlane 处插值两个视图空间顶点
ClipVertex intersectNear(in ClipVertex a, in ClipVertex b, in float nearPlane) {
    float t = (-nearPlane - a.pos.z) / (b.pos.z - a.pos.z);
    ClipVertex r;
    r.pos = mix(a.pos, b.pos, t);
    r.color = mix(a.color, b.color, t);
    r.index = mix(a.index, b.index, t);
    return r;
}

// 用叉积判断点 p 是否在三角形 (a,b,c) 内
bool isInsideTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    float w0 = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    float w1 = (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x);
    float w2 = (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x);

    // 所有 w 同号 = 在内部
    return (w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0) ||
        (w0 <= 0.0 && w1 <= 0.0 && w2 <= 0.0);
}

vec3 barycentric(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 v0 = b - a, v1 = c - a, v2 = p - a;
    float d00 = dot(v0, v0);
    float d01 = dot(v0, v1);
    float d11 = dot(v1, v1);
    float d20 = dot(v2, v0);
    float d21 = dot(v2, v1);
    float denom = d00 * d11 - d01 * d01;
    float v = (d11 * d20 - d01 * d21) / denom;
    float w = (d00 * d21 - d01 * d20) / denom;
    return vec3(1.0 - v - w, v, w);
}

// 视图空间近平面裁剪：输入三角形，输出最多 4 个顶点（凸多边形）。
// 返回裁剪后的顶点数（0 表示完全在近平面之外，丢弃）。
// 近平面在视图空间是 z = -nearPlane；保留 z <= -nearPlane 的一侧。
int clipTriangleNear(
    in vec3 v0,
    in vec3 v1,
    in vec3 v2,
    in vec3 c0,
    in vec3 c1,
    in vec3 c2,
    in float i0,
    in float i1,
    in float i2,
    in float nearPlane,
    out ClipVertex outVerts[4]
) {
    ClipVertex inVerts[4];
    ClipVertex tmpVerts[4];
    int outCount = 0;

    inVerts[0].pos = v0;
    inVerts[0].color = c0;
    inVerts[0].index = i0;
    inVerts[1].pos = v1;
    inVerts[1].color = c1;
    inVerts[1].index = i1;
    inVerts[2].pos = v2;
    inVerts[2].color = c2;
    inVerts[2].index = i2;

    // Sutherland-Hodgman：对每条边，按近平面裁剪（固定 3 条边）
    for(int i = 0; i < 3; i++) {
        ClipVertex cur = inVerts[i];
        ClipVertex nxt = inVerts[(i + 1) % 3];
        bool curIn = cur.pos.z <= -nearPlane;
        bool nxtIn = nxt.pos.z <= -nearPlane;

        if(curIn) {
            tmpVerts[outCount++] = cur;
        }
        if(curIn != nxtIn) {
            tmpVerts[outCount++] = intersectNear(cur, nxt, nearPlane);
        }
    }

    // 完全被裁剪掉
    if(outCount == 0)
        return 0;

    // 把结果复制到输出（out 参数数组不能直接逐元素赋值给 in 数组）
    for(int i = 0; i < 4; i++) {
        if(i < outCount) {
            outVerts[i] = tmpVerts[i];
        }
    }
    return outCount;
}

struct ShadeResult {
    vec3 color;
    vec2 disort;
};

// 光栅化一个裁剪后的三角形（3 个视图空间顶点 + 颜色 + 索引）
ShadeResult shadeClippedTriangle(
    in ClipVertex a,
    in ClipVertex b,
    in ClipVertex c,
    in vec3 fragPos,
    in float fragDepth
) {
    ShadeResult result;
    result.color = vec3(0.0);
    result.disort = vec2(0.0);

    vec4 cA = projection * vec4(a.pos, 1.0);
    vec4 cB = projection * vec4(b.pos, 1.0);
    vec4 cC = projection * vec4(c.pos, 1.0);

    vec2 sA = (cA.xy / cA.w * 0.5 + 0.5) * ScreenSize;
    vec2 sB = (cB.xy / cB.w * 0.5 + 0.5) * ScreenSize;
    vec2 sC = (cC.xy / cC.w * 0.5 + 0.5) * ScreenSize;

    vec2 pixelPos = gl_FragCoord.xy;
    if(!isInsideTriangle(pixelPos, sA, sB, sC))
        return result;

    vec3 bary = barycentric(pixelPos, sA, sB, sC);

    float invWA = 1.0 / cA.w;
    float invWB = 1.0 / cB.w;
    float invWC = 1.0 / cC.w;
    float invW = bary.x * invWA + bary.y * invWB + bary.z * invWC;

    // 深度测试：统一到视图空间 z 比较（反转深度下更稳）
    vec3 sceneView = (viewMat * vec4(fragPos, 1.0)).xyz;
    float bladeViewZ = (bary.x * a.pos.z * invWA + bary.y * b.pos.z * invWB + bary.z * c.pos.z * invWC) / invW;
    if(sceneView.z > bladeViewZ) {
        return result;
    }

    vec3 fColor = interpolateAttribute(a.color, b.color, c.color, invWA, invWB, invWC, bary);
    float smoothIndex = interpolateAttribute(a.index, b.index, c.index, invWA, invWB, invWC, bary);
    float x = smoothIndex / float(MAX_FRAMES - 1);
    result.color = fColor * (1.0 - x);

    // 扭曲方向：用刀光三角形自身的屏幕方向（最长边法线）。
    // 相邻三角形共享边，方向在接缝处连续，避免 dFdx/dFdy 的导数跳变。
    // vec2 edge = sB - sA;
    // vec2 nrm = vec2(-edge.y, edge.x);
    // vec2 dir = nrm / max(length(nrm), 1e-5);
    vec2 dir = normalize(vec2(dFdx(smoothIndex), dFdy(smoothIndex)));
    result.disort = dir * 50.0 * (1.0 - x);

    return result;
}

Triangle decodeTriangle(int index) {
    int base = 33 + index * VERTEX_PIXELS; // 每个三角形3个顶点 × 5像素
    Triangle t;
    // 读取顶点A
    t.colorA = texelFetch(DataSampler, ivec2(base + 1, 0), 0).rgb;
    t.posA.x = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 2, 0), 0).rgb);
    t.posA.y = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 3, 0), 0).rgb);
    t.posA.z = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 4, 0), 0).rgb);
    t.indexA = index;
    // 顶点B...
    base += 5;
    t.colorB = texelFetch(DataSampler, ivec2(base + 1, 0), 0).rgb;
    t.posB.x = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 2, 0), 0).rgb);
    t.posB.y = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 3, 0), 0).rgb);
    t.posB.z = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 4, 0), 0).rgb);
    t.indexB = index + 1;
    // 顶点C...
    base += 5;
    t.colorC = texelFetch(DataSampler, ivec2(base + 1, 0), 0).rgb;
    t.posC.x = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 2, 0), 0).rgb);
    t.posC.y = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 3, 0), 0).rgb);
    t.posC.z = decodeFloat12000(texelFetch(DataSampler, ivec2(base + 4, 0), 0).rgb);
    t.indexC = index + 2;
    return t;
}

const float nearPlane = 0.05;

bool clipNearView(vec3 a, vec3 b, out vec3 va, out vec3 vb) {
    vec3 av = (viewMat * vec4(a, 1.0)).xyz;
    vec3 bv = (viewMat * vec4(b, 1.0)).xyz;

    bool aBad = av.z > -nearPlane;
    bool bBad = bv.z > -nearPlane;
    if(aBad && bBad)
        return false;

    if(!aBad && !bBad) {
        va = av;
        vb = bv;
        return true;
    }

    float t = (-nearPlane - av.z) / (bv.z - av.z);
    vec3 inter = mix(av, bv, clamp(t, 0.0, 1.0));

    if(aBad) {
        va = inter;
        vb = bv;
    } else {
        va = av;
        vb = inter;
    }
    return true;
}

ShadeResult sampleTailSegment(int index, vec3 fragPos, float fragDepth) {
    TailVertex vertexA = decodeNode(index);
    TailVertex vertexB = decodeNode(index + 1);

    ShadeResult result;
    result.color = vec3(0.0);
    result.disort = vec2(0.0);
    vec2 pixelPos = gl_FragCoord.xy;

    vec3 posA = vertexA.pos;
    vec3 posB = vertexB.pos;

    vec3 va, vb;
    if(!clipNearView(posA, posB, va, vb))
        return result;

    vec3 sceneView = (viewMat * vec4(fragPos, 1.0)).xyz;
    vec4 cA = projection * vec4(va, 1.0);
    vec4 cB = projection * vec4(vb, 1.0);
    vec2 sA = (cA.xy / cA.w * 0.5 + 0.5) * ScreenSize;
    vec2 sB = (cB.xy / cB.w * 0.5 + 0.5) * ScreenSize;

    float t = GameTime * 1200.0;

    // vec2 seed;
    // seed.x = GameTime * 12000.0 * 0.34;
    // seed.y = samplerNoise(0.8 * texCoord).r;
    // vec4 originalNoise = samplerNoise(seed);

    vec2 ba = sB - sA;
    vec2 normal = normalize(vec2(-ba.y, ba.x));

    vec2 pa = pixelPos - sA;
    float linearMixer = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);

    float invWA = 1.0 / cA.w;
    float invWB = 1.0 / cB.w;
    float invW = mix(invWA, invWB, linearMixer);
    float lineViewZ = mix(va.z * invWA, vb.z * invWB, linearMixer) / invW;
    if(sceneView.z > lineViewZ)
        return result;

    result.color = mix(vertexA.color * invWA, vertexB.color * invWB, linearMixer) / invW;
    float x = float(index) / float(MAX_FRAMES - 1);
    float lineWidth = 10.0 * smoothstep(1.0, 0.0, x);
    float d = length(pa - ba * linearMixer) - lineWidth;
    result.color *= 1.0 - smoothstep(0.0, 3.0, d);

    return result;
}

ShadeResult sampleTailTriangle(int index, vec3 fragPos, float fragDepth) {
    Triangle tri = decodeTriangle(index);
    ShadeResult result;
    result.color = vec3(0.0);
    result.disort = vec2(0.0);

    // 1. 变换到视图空间
    vec3 vA = (viewMat * vec4(tri.posA, 1.0)).xyz;
    vec3 vB = (viewMat * vec4(tri.posB, 1.0)).xyz;
    vec3 vC = (viewMat * vec4(tri.posC, 1.0)).xyz;

    // 2. 近平面裁剪（Sutherland-Hodgman），输出最多 4 个顶点
    ClipVertex clipped[4];
    int count = clipTriangleNear(vA, vB, vC, tri.colorA, tri.colorB, tri.colorC, float(tri.indexA), float(tri.indexB), float(tri.indexC), nearPlane, clipped);
    if(count < 3)
        return result;

    // 3. 凸多边形扇形三角化并累加
    // 最多两个扇形三角形；用固定边界避免动态循环
    for(int i = 1; i < 3; i++) {
        if(i < count - 1) {
            ShadeResult r = shadeClippedTriangle(clipped[0], clipped[i], clipped[i + 1], fragPos, fragDepth);
            result.color += r.color;
            // 取最强而非累加：避免接缝处两个三角形偏移叠加
            if(length(r.disort) > length(result.disort)) {
                result.disort = r.disort;
            }
        }
    }
    return result;
}

vec3 shade(vec3 fragPos, float depth) {
    ShadeResult result;
    result.color = vec3(0.0);
    result.disort = vec2(0.0);
    int segments = MAX_FRAMES - 1;
    for(int i = 0; i < segments; i++) {
        ShadeResult r = vertexCount > 1 ? sampleTailTriangle(i, fragPos, depth) : sampleTailSegment(i, fragPos, depth);
        result.color += r.color;
        result.disort += r.disort;
        
        if(length(result.color) > 0.01) {
            break;
        }
    }

    vec3 c = texture(MainSampler, texCoord + result.disort / ScreenSize).rgb;
    c += result.color;
    return c;
}

void main() {
    float fragDepth = texture(DepthSampler, texCoord).r;

    if(texelFetch(DataSampler, ivec2(0, 0), 0) != EXISTENCE) {
        fragColor = vec4(0.0);
        return;
    }

    // 26.2+ 反转 Z：ProjMat 已把近平面映射到 NDC z=1（远=0），
    // 深度纹理值 fragDepth 本身就是 NDC z，直接用于反投影重建。
    vec3 fragPosition = reconstructPosition(texCoord, fragDepth);
    vec3 color = shade(fragPosition, fragDepth);
    // vec4 mainColor = texelFetch(DataSampler, ivec2(0, 1), 0);
    fragColor = vec4(color, 1.0);
}
