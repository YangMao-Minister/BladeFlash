#version 330

#moj_import <minecraft:light.glsl>
#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:sample_lightmap.glsl>
#moj_import <minecraft:constants.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV1;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler0;
uniform sampler2D Sampler1;
uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;
out vec4 lightMapColor;
out vec4 overlayColor;

out vec2 texCoord0;
flat out float isMarker;
out vec4 position0;
out vec4 position1;
out vec4 position2;
out vec4 position3;
out vec2 normalizedUV;
out vec4 cornerUV01;
out vec4 cornerUV23;

void main() {

    isMarker = texture(Sampler0, UV0) == MARKER ? 1.0 : 0.0;

    // 选用4~9顶点，对应overlay层
    if(isMarker > 0.0) {
        switch(gl_VertexID % 4) {
            case 0:
                gl_Position = vec4(-1.0, 0.0, 1.0, 1.0);
                normalizedUV = vec2(0.0, 0.0);
                break;
            case 1:
                gl_Position = vec4(-1.0, -1.0, 1.0, 1.0);
                normalizedUV = vec2(0.0, 1.0);
                break;
            case 2:
                gl_Position = vec4(1.0, -1.0, 1.0, 1.0);
                normalizedUV = vec2(1.0, 1.0);
                break;
            case 3:
                gl_Position = vec4(1.0, 0.0, 1.0, 1.0);
                normalizedUV = vec2(1.0, 0.0);
                break;
            default:
                gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
        }

    } else {
        gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
    }
    // gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    sphericalVertexDistance = fog_spherical_distance(Position);
    cylindricalVertexDistance = fog_cylindrical_distance(Position);

    vertexColor = minecraft_mix_light(Light0_Direction, Light1_Direction, Normal, Color);
    lightMapColor = sample_lightmap(Sampler2, UV2);
    overlayColor = texelFetch(Sampler1, UV1, 0);

    texCoord0 = UV0;

    position0 = position1 = position2 = position3 = vec4(0.0);
    vec3 pos = Position;

    switch(gl_VertexID % 4) {
        case 0:
            position0 = vec4(pos, 1.0);
            break;
        case 1:
            position1 = vec4(pos, 1.0);
            break;
        case 2:
            position2 = vec4(pos, 1.0);
            break;
        case 3:
            position3 = vec4(pos, 1.0);
            break;
    }

    // 四个角点的 UV0（xy/zw 各装两个），供片元恢复图像在 atlas 中的起点
    cornerUV01 = cornerUV23 = vec4(0.0);
    switch(gl_VertexID % 4) {
        case 0:
            cornerUV01 = vec4(UV0, 0.0, 0.0);
            break;
        case 1:
            cornerUV01 = vec4(0.0, 0.0, UV0);
            break;
        case 2:
            cornerUV23 = vec4(UV0, 0.0, 0.0);
            break;
        case 3:
            cornerUV23 = vec4(0.0, 0.0, UV0);
            break;
    }
}
