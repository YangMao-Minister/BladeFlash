#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:constants.glsl>
#moj_import <minecraft:projection.glsl>

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec4 vertexColor;
in vec4 lightMapColor;
in vec4 overlayColor;
in vec2 texCoord0;
flat in float isMarker;
in vec2 normalizedUV;
in vec4 position0;
in vec4 position1;
in vec4 position2;
in vec4 position3;
in vec4 cornerUV01;
in vec4 cornerUV23;

out vec4 fragColor;

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
    vec4 textureColor = texture(Sampler0, texCoord0);

    if(isMarker > 0.0 && ProjMat[2][3] != 0.0) {
        // if(abs(textureColor.a - 254.0 / 255.0) > 0.0001) {
        //     discard;
        // }

        vec2 pixel = floor(gl_FragCoord.xy);
        // if(pixel.y >= 1.0) {
        //     discard;
        // }

        // Data
        // 0 - marker
        // 1-16 - projection matrix
        // 17-32 - view matrix
        // 32+ - vertex positions
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
            int index = int(pixel.x - 33) % 4;

            // 精确采样纹理
            vec2 imgSize = vec2(16.0);
            vec2 atlasSize = textureSize(Sampler0, 0);
            vec2 scale = imgSize / atlasSize;
            int texel = int(pixel.x - 33) / 4 + 1;

            // 从四个角点 UV 恢复图像在 atlas 中的左上角起点（与烘焙顶点顺序无关）
            vec2 uv0 = cornerUV01.xy / position0.w;
            vec2 uv1 = cornerUV01.zw / position1.w;
            vec2 uv2 = cornerUV23.xy / position2.w;
            vec2 uv3 = cornerUV23.zw / position3.w;
            vec2 start = min(min(uv0, uv1), min(uv2, uv3));

            // 采样纹素中心，避免线性过滤时采到纹素边界
            vec2 sampleCoord = start + (vec2(texel, 0) + 0.5) / imgSize * scale;
            // vec2 sampleCoord = start + ((vec2(texel, 0) + 0.5) / imgSize - normalizedUV) * scale;

            vec2 data = texture(Sampler0, sampleCoord, 0).rg * 255.0;

            if(data == vec2(0.0) || data.x > imgSize.x || data.y > imgSize.y) {
                discard;
            }

            if(index == 0) {
                fragColor = EXISTENCE;
                return;
            }

            // 双线性透视矫正插值获取像素pos
            vec3 pos0 = position0.xyz / position0.w;
            vec3 pos1 = position1.xyz / position1.w;
            vec3 pos2 = position2.xyz / position2.w;
            vec3 pos3 = position3.xyz / position3.w;

            // data 是纹素坐标(0~15)，归一化到 [0,1)
            vec2 uv = data / imgSize;
            // 各角点在图像内的位置(0..1)，据此计算与顶点顺序无关的权重
            vec2 iuv0 = (uv0 - start) / scale;
            vec2 iuv1 = (uv1 - start) / scale;
            vec2 iuv2 = (uv2 - start) / scale;
            vec2 iuv3 = (uv3 - start) / scale;
            float w0 = (1.0 - abs(uv.x - iuv0.x)) * (1.0 - abs(uv.y - iuv0.y));
            float w1 = (1.0 - abs(uv.x - iuv1.x)) * (1.0 - abs(uv.y - iuv1.y));
            float w2 = (1.0 - abs(uv.x - iuv2.x)) * (1.0 - abs(uv.y - iuv2.y));
            float w3 = (1.0 - abs(uv.x - iuv3.x)) * (1.0 - abs(uv.y - iuv3.y));

            vec3 pos = (w0 * pos0 + w1 * pos1 + w2 * pos2 + w3 * pos3) / (w0 + w1 + w2 + w3);

            // fragColor = vec4(uv, 0.0, 1.0);
            // fragColor = vec4(texture(Sampler0, sampleCoord).rg, 0.0, 1.0);

            fragColor = encodeFloat12000(pos[index - 1]);
        }

        return;

        fragColor = textureColor;
        return;
    }

    // if(textureColor.a == MARKER) {
    //     fragColor = vec4(1.0);
    //     return;
    // }

#ifdef ALPHA_CUTOUT
    if(textureColor.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

    textureColor *= vertexColor * ColorModulator;
    textureColor.rgb = mix(overlayColor.rgb, textureColor.rgb, overlayColor.a);
    textureColor *= lightMapColor;

    fragColor = apply_fog(textureColor, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
