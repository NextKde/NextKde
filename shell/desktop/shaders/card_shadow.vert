#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float shadowWidth;
    float shadowHeight;
    float cardWidth;
    float cardHeight;
    float cornerRadius;
    float cornerExponent;
    float offsetX;
    float offsetY;
    float softness;
    float spread;
    float falloff;
    vec4 shadowColor;
};

layout(location = 0) out vec2 shadowCoord;

void main()
{
    // Normalised position inside this item, derived from the vertex position
    // instead of qt_MultiTexCoord0: a ShaderEffect with no source item is not
    // guaranteed to be handed texture coordinates, but it always has vertices.
    // With qt_TexCoord0 the whole item can end up evaluating one constant point,
    // which paints a flat block rather than a shaped shadow.
    shadowCoord = qt_Vertex.xy
        / vec2(max(shadowWidth, 1.0), max(shadowHeight, 1.0));

    // Same uniform block as the fragment stage, so qt_Matrix is available here.
    gl_Position = qt_Matrix * qt_Vertex;
}
