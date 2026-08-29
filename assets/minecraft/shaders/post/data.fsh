#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:constants.glsl>
#include <minecraft:globals.glsl>

uniform sampler2D MainSampler;
uniform sampler2D PrevDataSampler;

flat layout(location = 0) in int frame;
flat layout(location = 1) in int vertexCount;

layout(location = 0) out vec4 fragColor;

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

void main() {
    if(texelFetch(MainSampler, ivec2(0, 0), 0) != EXISTENCE) {
        fragColor = vec4(0.0);
        return;
    }

    ivec2 coord = ivec2(gl_FragCoord);

    if(coord.y == 1) {
        if(coord.x == 0) {
            int nextFrame = (frame + 1) % 256;
            fragColor = vec4(float(nextFrame) / 255.0, 0.0, 0.0, 1.0);
            return;
        } else if(coord.x >= 1 && coord.x < 4) {
            fragColor = encodeInt(CameraBlockPos[coord.x - 1]);
            return;
        } else if(coord.x >= 5 && coord.x < 8) {
            fragColor = encodeFloat(CameraOffset[coord.x - 5]);
        } else {
            return;
        }
    }

    if(coord.x < 33 + 5 * vertexCount && coord.y == 0) {
        fragColor = texelFetch(MainSampler, ivec2(coord.x, 0), 0);
        return;
    }

    fragColor = texelFetch(PrevDataSampler, ivec2(coord.x - 5 * vertexCount, coord.y), 0);
}