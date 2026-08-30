#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:constants.glsl>

uniform sampler2D DataSampler;
uniform sampler2D PrevDataSampler;

layout(location = 0) out vec2 texCoord;
flat layout(location = 1) out mat4 mvpInverse;
flat layout(location = 5) out mat4 viewProjMat;
flat layout(location = 9) out mat4 projection;
flat layout(location = 13) out mat4 viewMat;
flat layout(location = 17) out int vertexCount;
flat layout(location = 18) out ivec3 prevCameraBlockPos;
flat layout(location = 19) out vec3 prevCameraOffset;

int decodeInt(vec3 ivec) {
    ivec *= 255.0;
    int s = ivec.b >= 128.0 ? -1 : 1;
    return s * (int(ivec.r) + int(ivec.g) * 256 + (int(ivec.b) - 64 + s * 64) * 256 * 256);
}

float decodeFloat(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 40000.0;
}

float decodeFloat12000(vec3 ivec) {
    int v = decodeInt(ivec);
    return float(v) / 12000.0;
}

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    vec4 pos = vec4(uv * vec2(2, 2) + vec2(-1, -1), 0, 1);

    gl_Position = pos;
    texCoord = uv;

    if(texelFetch(DataSampler, ivec2(0, 0), 0) != EXISTENCE)
        return;

    for(int i = 0; i < 16; i++) {
        vec4 color = texelFetch(DataSampler, ivec2(i + 1, 0), 0);
        projection[i / 4][i % 4] = decodeFloat(color.rgb);
    }

    for(int i = 0; i < 16; i++) {
        vec4 color = texelFetch(DataSampler, ivec2(i + 17, 0), 0);
        viewMat[i / 4][i % 4] = decodeFloat(color.rgb);
    }

    viewProjMat = projection * viewMat;
    mvpInverse = inverse(viewProjMat);

    vertexCount = 0;
    for(int i = 0; i < 255 && texelFetch(DataSampler, ivec2(33 + i * VERTEX_PIXELS, 0), 0) == EXISTENCE; i++) {
        vertexCount++;
    }

    prevCameraBlockPos.x = decodeInt(texelFetch(PrevDataSampler, ivec2(1, 1), 0).rgb);
    prevCameraBlockPos.y = decodeInt(texelFetch(PrevDataSampler, ivec2(2, 1), 0).rgb);
    prevCameraBlockPos.z = decodeInt(texelFetch(PrevDataSampler, ivec2(3, 1), 0).rgb);
    prevCameraOffset.x = decodeFloat(texelFetch(PrevDataSampler, ivec2(4, 1), 0).rgb);
    prevCameraOffset.y = decodeFloat(texelFetch(PrevDataSampler, ivec2(5, 1), 0).rgb);
    prevCameraOffset.z = decodeFloat(texelFetch(PrevDataSampler, ivec2(6, 1), 0).rgb);
}