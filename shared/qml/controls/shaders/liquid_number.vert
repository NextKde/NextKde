#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 uv;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec2 sampleOrigin;
    vec2 sampleAxisX;
    vec2 sampleAxisY;
    float thickness;
    float refractionStrength;
    float blurRadius;
    float tintStrength;
    vec4 tintColor;
    float reflectionStrength;
    float shadowOpacity;
};

void main() {
    uv = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
