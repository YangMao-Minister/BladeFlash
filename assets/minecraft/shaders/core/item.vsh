#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:light.glsl>
#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:sample_lightmap.glsl>
#include <minecraft:constants.glsl>
#include <minecraft:utils.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;
layout(location = 2) in vec2 UV0;
layout(location = 3) in ivec2 UV1;
layout(location = 4) in ivec2 UV2;
#ifdef GLINT_SPECIAL
layout(location = 5) in vec2 UV3;
#endif
layout(location = 6) in vec3 Normal;

uniform sampler2D Sampler0;
#ifndef OIT_ALPHA_ONLY
uniform sampler2D Sampler1;
uniform sampler2D Sampler2;

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
#endif
layout(location = 2) out vec4 vertexColor;
#ifndef OIT_ALPHA_ONLY
layout(location = 3) out vec4 lightMapColor;
layout(location = 4) out vec4 overlayColor;
#endif

layout(location = 5) out vec2 texCoord0;

#ifdef GLINT
layout(location = 6) out vec2 texCoordGlint;
flat layout(location = 8) out float isMarker;
layout(location = 9) out vec4 position0;
layout(location = 10) out vec4 position1;
layout(location = 11) out vec4 position2;
layout(location = 12) out vec4 position3;
layout(location = 13) out vec2 normalizedUV;
layout(location = 14) out vec4 cornerUV01;
layout(location = 15) out vec4 cornerUV23;
#else
flat layout(location = 6) out float isMarker;
layout(location = 7) out vec4 position0;
layout(location = 8) out vec4 position1;
layout(location = 9) out vec4 position2;
layout(location = 10) out vec4 position3;
layout(location = 11) out vec2 normalizedUV;
layout(location = 12) out vec4 cornerUV01;
layout(location = 13) out vec4 cornerUV23;
#endif

void main() {
    isMarker = texture(Sampler0, UV0).a == MARKER ? 1.0 : 0.0;

    position0 = position1 = position2 = position3 = vec4(0.0);
    cornerUV01 = cornerUV23 = vec4(0.0);
    normalizedUV = vec2(0.0);

    if(isMarker > 0.0) {
        switch(gl_VertexIndex % 4) {
            case 0:
                gl_Position = vec4(-2.0, 0.0, 1.0, 1.0);
                normalizedUV = vec2(0.0, 0.0);
                break;
            case 1:
                gl_Position = vec4(-2.0, -2.0, 1.0, 1.0);
                normalizedUV = vec2(0.0, 1.0);
                break;
            case 2:
                gl_Position = vec4(1.0, -2.0, 1.0, 1.0);
                normalizedUV = vec2(1.0, 1.0);
                break;
            case 3:
                gl_Position = vec4(1.0, 0.0, 1.0, 1.0);
                normalizedUV = vec2(1.0, 0.0);
                break;
            default:
                gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
        }

        position0 = position1 = position2 = position3 = vec4(0.0);
        cornerUV01 = cornerUV23 = vec4(0.0);
        vec3 pos = Position;
        switch(gl_VertexIndex % 4) {
            case 0:
                position0 = vec4(pos, 1.0);
                cornerUV01 = vec4(UV0, 0.0, 0.0);
                break;
            case 1:
                position1 = vec4(pos, 1.0);
                cornerUV01 = vec4(0.0, 0.0, UV0);
                break;
            case 2:
                position2 = vec4(pos, 1.0);
                cornerUV23 = vec4(UV0, 0.0, 0.0);
                break;
            case 3:
                position3 = vec4(pos, 1.0);
                cornerUV23 = vec4(0.0, 0.0, UV0);
                break;
        }

    } else {
        gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
    }

    // gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);


    #ifndef OIT_ALPHA_ONLY
    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);
    #endif
    vertexColor = minecraft_mix_light(Light0_Direction, Light1_Direction, Normal, Color);
    #ifndef OIT_ALPHA_ONLY
    lightMapColor = sample_lightmap(Sampler2, UV2);
    overlayColor = texelFetch(Sampler1, UV1, 0);
    #endif

    texCoord0 = UV0;
    #ifdef GLINT
    #ifdef GLINT_SPECIAL
    texCoordGlint = (TextureMat * vec4(UV3, 0.0, 1.0)).xy;
    #else
    texCoordGlint = (TextureMat * vec4(UV0, 0.0, 1.0)).xy;
    #endif
    #endif
}
