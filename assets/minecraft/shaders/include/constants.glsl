#define TARGET 254.0/255.0
#define MARKER vec4(114.0, 51.0, 4.0, 255.0) / 255.0
#define EXISTENCE vec4(67, 78, 91, 255) / 255.0
#define MAX_VERTEX 128
#define MAX_FRAMES 16

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
