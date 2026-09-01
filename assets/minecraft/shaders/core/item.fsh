#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <minecraft:fog.glsl>
#include <minecraft:dynamictransforms.glsl>
#include <minecraft:oit.glsl>
#include <minecraft:constants.glsl>
#include <minecraft:utils.glsl>

#ifndef OIT
layout(std140) uniform Projection {
    mat4 ProjMat;
};
#endif

uniform sampler2D Sampler0;

#ifdef GLINT
uniform sampler2D GlintSampler;
#endif

#ifndef OIT_ALPHA_ONLY
layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
#endif
layout(location = 2) in vec4 vertexColor;
#ifndef OIT_ALPHA_ONLY
layout(location = 3) in vec4 lightMapColor;
layout(location = 4) in vec4 overlayColor;
#endif
layout(location = 5) in vec2 texCoord0;

#ifdef GLINT
layout(location = 6) in vec2 texCoordGlint;
flat layout(location = 8) in float isMarker;
layout(location = 9) in vec4 position0;
layout(location = 10) in vec4 position1;
layout(location = 11) in vec4 position2;
layout(location = 12) in vec4 position3;
layout(location = 13) in vec2 normalizedUV;
layout(location = 14) in vec4 cornerUV01;
layout(location = 15) in vec4 cornerUV23;
#else
flat layout(location = 6) in float isMarker;
layout(location = 7) in vec4 position0;
layout(location = 8) in vec4 position1;
layout(location = 9) in vec4 position2;
layout(location = 10) in vec4 position3;
layout(location = 11) in vec2 normalizedUV;
layout(location = 12) in vec4 cornerUV01;
layout(location = 13) in vec4 cornerUV23;
#endif

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

#ifndef OIT_ALPHA_ONLY
vec4 calculateFinalColor(vec4 color) {
    color.rgb = mix(overlayColor.rgb, color.rgb, overlayColor.a);
    color *= lightMapColor;

    #ifdef GLINT
    vec4 glintColor = GlintAlpha * texture(GlintSampler, texCoordGlint);// Glint color modulator?
    // Matches BlendFuntion.GLINT
    color.rgb += glintColor.rgb * glintColor.rgb;
    #endif

    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif

    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}
#endif

void main() {
    vec4 color = texture(Sampler0, texCoord0);

    vec3 pInterp = position0.xyz + position1.xyz + position2.xyz + position3.xyz;
    vec3 dpdx = dFdx(pInterp);
    vec3 dpdy = dFdy(pInterp);
    vec2 dtdx = dFdx(texCoord0);
    vec2 dtdy = dFdy(texCoord0);

    #ifndef OIT_ALPHA_ONLY
    if(isMarker > 0.0 && ProjMat[2][3] != 0.0) {
        vec2 pixel = floor(gl_FragCoord.xy);

        if(pixel.x == 0) {
            fragColor = EXISTENCE;
        } else if(pixel.x < 17) {
            mat4 proj = ProjMat;
            int index = int(pixel.x) - 1;
            float value = proj[index / 4][index % 4];
            fragColor = encodeFloat(value);
        } else if(pixel.x < 33) {
            int index = int(pixel.x) - 17;
            float value = ModelViewMat[index / 4][index % 4];
            fragColor = encodeFloat(value);
        } else if(pixel.x >= 33) {
            int index = int(pixel.x - 33) % VERTEX_PIXELS;

            vec2 atlasSize = textureSize(Sampler0, 0);
            int texel = int(pixel.x - 33) / VERTEX_PIXELS + 1;

            if(texel < 0 || texel >= 15) {
                discard;
            }

            bool has0 = position0.w > 0.0;
            bool has1 = position1.w > 0.0;
            bool has2 = position2.w > 0.0;
            bool has3 = position3.w > 0.0;

            vec2 u0 = has0 ? cornerUV01.xy / position0.w : vec2(0.0);
            vec2 u1 = has1 ? cornerUV01.zw / position1.w : vec2(0.0);
            vec2 u2 = has2 ? cornerUV23.xy / position2.w : vec2(0.0);
            vec2 u3 = has3 ? cornerUV23.zw / position3.w : vec2(0.0);
            vec3 pos0 = has0 ? position0.xyz / position0.w : vec3(0.0);
            vec3 pos1 = has1 ? position1.xyz / position1.w : vec3(0.0);
            vec3 pos2 = has2 ? position2.xyz / position2.w : vec3(0.0);
            vec3 pos3 = has3 ? position3.xyz / position3.w : vec3(0.0);

            if(!has0 && has1 && has2 && has3) {
                pos0 = pos1 + pos3 - pos2;
                u0 = u1 + u3 - u2;
            } else if(!has1 && has0 && has2 && has3) {
                pos1 = pos0 + pos2 - pos3;
                u1 = u0 + u2 - u3;
            } else if(!has2 && has0 && has1 && has3) {
                pos2 = pos1 + pos3 - pos0;
                u2 = u1 + u3 - u0;
            } else if(!has3 && has0 && has1 && has2) {
                pos3 = pos0 + pos2 - pos1;
                u3 = u0 + u2 - u1;
            }

            vec2 start = min(min(u0, u1), min(u2, u3));
            vec2 sampleCoord = start + (vec2(texel, 0) + 0.5) / atlasSize;
            vec2 targetUV = texture(Sampler0, sampleCoord, 0).rg * 255.0;
            vec2 imgSize = texture(Sampler0, start + vec2(0.0, 1.5) / atlasSize, 0).rg * 255.0;
            if(targetUV == vec2(0.0) || targetUV.x > imgSize.x || targetUV.y > imgSize.y) {
                discard;
            }

            if(index == 0) {
                fragColor = EXISTENCE;
                return;
            }

            // 26.3 烘焙出的 south 面角点顺序（模型坐标 -> 图像 UV）：
            //   p0(0,16,8)@(0,0)  p1(0,0,8)@(0,1)
            //   p2(16,0,8)@(1,1)  p3(16,16,8)@(1,0)
            // 图像 v 与模型 y 反向：v=0 的边是 p0->p3，v=1 的边是 p1->p2。
            // 取 texel 中心 (target + 0.5)，与上面取颜色用的采样点一致。
            vec2 uv = (targetUV + 0.5) / imgSize;
            vec3 posTop = mix(pos0, pos3, uv.x);
            vec3 posBottom = mix(pos1, pos2, uv.x);
            vec3 fallbackPos = mix(posTop, posBottom, uv.y);

            // 用 atlas UV 本身作为基方向
            vec2 targetAtlas = start + (targetUV + vec2(1.0, 0.0)) / atlasSize;
            vec2 deltaT = targetAtlas - texCoord0;
            float detT = dtdx.x * dtdy.y - dtdx.y * dtdy.x;
            vec3 pos = fallbackPos;
            if(abs(detT) > 1e-12) {
                vec3 dPdU = (dpdx * dtdy.y - dpdy * dtdx.y) / detT;
                vec3 dPdV = (dpdy * dtdx.x - dpdx * dtdy.x) / detT;
                pos = pInterp + dPdU * deltaT.x + dPdV * deltaT.y;
            }

            if(index == 1) {
                fragColor = texture(Sampler0, sampleCoord + vec2(0.0, 1.0) / atlasSize, 0);
                return;
            }
            fragColor = encodeFloat12000(pos[index - 2]);
        }
        return;
    }

    // 末地传送门渲染
    if(color == END_PORTAL_FX) {
        if(ProjMat[2][3] != 0.0) {
            fragColor = vec4((END_PORTAL_FX).rgb, 1.0);
            return;
        }
        // 在gui里画个假的
        vec3 guiColor = vec3(0.08, 0.01, 0.12);
        // vec2 uv = gl_FragCoord.xy / ScreenSize;
        // for(int i = 0; i < 4; i++) {
        //     vec2 layerUV = pow(fract(uv * 32.0), 4.0);
        //     guiColor += vec3(layerUV, 0.0);
        // }
        fragColor = vec4(guiColor, 1.0);
        return;
    }

    #endif

    #ifdef ALPHA_CUTOUT
    if(color.a < ALPHA_CUTOUT) {
        discard;
    }
    #endif

    color *= vertexColor * ColorModulator;

    #ifdef GLINT
    color.a = max(color.a, GlintAlpha);
    #endif

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}
