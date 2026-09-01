float perspectiveInterpolate(vec4 cA, vec4 cB, float a, float b, float k) {
    float invWA = 1.0 / cA.w;
    float invWB = 1.0 / cB.w;
    float invW = mix(invWA, invWB, k);
    return mix(a * invWA, b * invWB, k) / invW;
}

vec3 perspectiveInterpolate(vec4 cA, vec4 cB, vec3 a, vec3 b, float k) {
    float invWA = 1.0 / cA.w;
    float invWB = 1.0 / cB.w;
    float invW = mix(invWA, invWB, k);
    return mix(a * invWA, b * invWB, k) / invW;
}

vec4 perspectiveInterpolate(vec4 cA, vec4 cB, vec4 a, vec4 b, float k) {
    float invWA = 1.0 / cA.w;
    float invWB = 1.0 / cB.w;
    float invW = mix(invWA, invWB, k);
    return mix(a * invWA, b * invWB, k) / invW;
}

vec2 interpolateAttribute(
    vec2 attrA,
    vec2 attrB,
    vec2 attrC,
    float invWA,
    float invWB,
    float invWC,
    vec3 bary
) {
    // 透视校正：先除以 w，插值，再除以结果
    vec2 attrInterp = bary.x * attrA * invWA +
        bary.y * attrB * invWB +
        bary.z * attrC * invWC;
    float invW = bary.x * invWA + bary.y * invWB + bary.z * invWC;
    return attrInterp / invW;
}

vec3 interpolateAttribute(
    vec3 attrA,
    vec3 attrB,
    vec3 attrC,
    float invWA,
    float invWB,
    float invWC,
    vec3 bary
) {
    // 透视校正：先除以 w，插值，再除以结果
    vec3 attrInterp = bary.x * attrA * invWA +
        bary.y * attrB * invWB +
        bary.z * attrC * invWC;
    float invW = bary.x * invWA + bary.y * invWB + bary.z * invWC;
    return attrInterp / invW;
}

vec4 interpolateAttribute(
    vec4 attrA,
    vec4 attrB,
    vec4 attrC,
    float invWA,
    float invWB,
    float invWC,
    vec3 bary
) {
    // 透视校正：先除以 w，插值，再除以结果
    vec4 attrInterp = bary.x * attrA * invWA +
        bary.y * attrB * invWB +
        bary.z * attrC * invWC;
    float invW = bary.x * invWA + bary.y * invWB + bary.z * invWC;
    return attrInterp / invW;
}

float interpolateAttribute(
    float attrA,
    float attrB,
    float attrC,
    float invWA,
    float invWB,
    float invWC,
    vec3 bary
) {
    // 透视校正：先除以 w，插值，再除以结果
    float attrInterp = bary.x * attrA * invWA +
        bary.y * attrB * invWB +
        bary.z * attrC * invWC;
    float invW = bary.x * invWA + bary.y * invWB + bary.z * invWC;
    return attrInterp / invW;
}

vec4 encodeInt(int i) {
    int s = int(i < 0) * 128;
    i = abs(i);
    int r = i % 256;
    i = i / 256;
    int g = i % 256;
    i = i / 256;
    int b = i % 256;
    return vec4(float(r) / 255.0, float(g) / 255.0, float(b + s) / 255.0, 1.0);
}

vec4 encodeFloat12000(float v) {
    v *= 12000.0;
    v = floor(v);
    return encodeInt(int(v));
}

vec4 encodeFloat(float v) {
    v *= 40000.0;
    v = floor(v);
    return encodeInt(int(v));
}

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

float decodeFloat12000(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 12000.0;
}

float decodeFloat(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 40000.0;
}