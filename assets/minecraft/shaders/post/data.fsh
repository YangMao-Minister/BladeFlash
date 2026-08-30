#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:constants.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:utils.glsl>

uniform sampler2D MainSampler;
uniform sampler2D PrevDataSampler;

flat layout(location = 0) in int frame;
flat layout(location = 1) in int vertexCount;

layout(location = 0) out vec4 fragColor;

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
        } else if(coord.x >= 4 && coord.x < 7) {
            fragColor = encodeFloat(CameraOffset[coord.x - 4]);
            return;
        } else {
            return;
        }
    }

    if(coord.x < 33 + VERTEX_PIXELS * vertexCount && coord.y == 0) {
        fragColor = texelFetch(MainSampler, ivec2(coord.x, 0), 0);
        return;
    }

    int pixelIndex = int(coord.x - 33 - VERTEX_PIXELS * vertexCount) % VERTEX_PIXELS;
    vec4 prevDataPixel = texelFetch(PrevDataSampler, ivec2(coord.x - VERTEX_PIXELS * vertexCount, coord.y), 0);

    // xyz : 2,3,4
    #ifdef TURE_WORLDSPACE
    if(pixelIndex >= 2 && pixelIndex <= 4) {
        float lastData = decodeFloat12000(prevDataPixel.rgb);
        float currentPosAxis = (CameraBlockPos - CameraOffset)[pixelIndex - 2];
        float prevPosAxis = float(decodeInt(texelFetch(PrevDataSampler, ivec2(pixelIndex - 1, 1), 0).rgb)) - decodeFloat(texelFetch(PrevDataSampler, ivec2(pixelIndex + 2, 1), 0).rgb);
        float offsetAxis = currentPosAxis - prevPosAxis;
        lastData -= offsetAxis;
        prevDataPixel = encodeFloat12000(lastData);
    }
    #endif

    fragColor = prevDataPixel;

}
