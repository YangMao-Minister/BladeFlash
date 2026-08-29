#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:constants.glsl>
#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(location = 0) out vec4 fragColor;

void main() {
    if(texture(InSampler, vec2(0.0)) != EXISTENCE) {
        discard;
    }

    ivec2 coord = ivec2(gl_FragCoord);
    fragColor = texelFetch(InSampler, ivec2(coord.x, 0), 0);
}