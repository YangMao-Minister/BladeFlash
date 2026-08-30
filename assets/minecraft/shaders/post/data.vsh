#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:constants.glsl>

uniform sampler2D MainSampler;
uniform sampler2D PrevDataSampler;

flat layout(location = 0) out int frame;
flat layout(location = 1) out int vertexCount;

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    vec4 pos = vec4(uv * vec2(2, 2) + vec2(-1, -1), 0, 1);

    gl_Position = pos;

    frame = int(texelFetch(PrevDataSampler, ivec2(0, 1), 0).r * 255.0);

    vertexCount = 0;
    for(int i = 0; i < 255 && texelFetch(MainSampler, ivec2(33 + i * VERTEX_PIXELS, 0), 0) == EXISTENCE; i++) {
        vertexCount++;
    }
}