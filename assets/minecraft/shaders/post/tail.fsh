#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <minecraft:constants.glsl>

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

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

float decodeFloat1024(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 12000.0;
}

float decodeFloat(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 40000.0;
}

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
    n.pos.x = decodeFloat1024(texelFetch(DataSampler, ivec2(base + 2, 0), 0).rgb);
    n.pos.y = decodeFloat1024(texelFetch(DataSampler, ivec2(base + 3, 0), 0).rgb);
    n.pos.z = decodeFloat1024(texelFetch(DataSampler, ivec2(base + 4, 0), 0).rgb);

    vec3 prevCameraPos = vec3(prevCameraBlockPos) + prevCameraOffset;
    vec3 cameraPos = vec3(CameraBlockPos) + CameraOffset;
    vec3 offset = cameraPos - prevCameraPos;
    // n.pos += offset;
    return n;
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

vec3 sampleTailSegment(int index, vec3 fragPos, float fragDepth) {
    TailVertex vertexA = decodeNode(index);
    TailVertex vertexB = decodeNode(index + 1);

    vec3 color = vec3(0.0);
    vec2 pixelPos = gl_FragCoord.xy;

    vec3 posA = vertexA.pos;
    vec3 posB = vertexB.pos;

    vec3 va, vb;
    if(!clipNearView(posA, posB, va, vb))
        return color;

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
    vec4 lineClipPos = mix(cA * invWA, cB * invWB, linearMixer) / invW;
    color = mix(vertexA.color * invWA, vertexB.color * invWB, linearMixer) / invW;
    float lineDepth = lineClipPos.z / lineClipPos.w;

    float x = float(index) / float(MAX_FRAMES - 1);
    float lineWidth = 10.0 * smoothstep(1.0, 0.0, x);
    float d = length(pa - ba * linearMixer) - lineWidth;
    color *= 1.0 - smoothstep(0.0, 3.0, d);

    return fragDepth < lineDepth ? color : vec3(0.0);
}

vec3 shade(vec3 fragPos, float depth) {
    vec3 color = vec3(0.0);
    int segments = MAX_FRAMES - 1;
    for(int i = 0; i < segments; i++) {
        vec3 b = sampleTailSegment(i, fragPos, depth);
        color += b;
    }

    return color;
}

void main() {
    float fragDepth = texture(DepthSampler, texCoord).r;

    if(texelFetch(DataSampler, ivec2(0, 0), 0) != EXISTENCE) {
        fragColor = vec4(0.0);
        return;
    }

    vec3 fragPosition = reconstructPosition(texCoord, fragDepth);
    vec3 color = shade(fragPosition, fragDepth);
    // vec4 mainColor = texelFetch(DataSampler, ivec2(0, 1), 0);
    fragColor = vec4(color, 1.0);
}
