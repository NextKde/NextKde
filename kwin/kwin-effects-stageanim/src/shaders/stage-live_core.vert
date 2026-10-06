#version 140

// 活体卡顶点着色器：全屏覆盖矩形（设备像素坐标），uv 直接透传。
// 属性名与 KWin GLVertexBuffer 绑定约定一致（position/texcoord），
// MVP uniform 名与 blur 等内置特效同款。

uniform mat4 modelViewProjectionMatrix;

in vec2 position;
in vec2 texcoord;

out vec2 uv;

void main(void)
{
    gl_Position = modelViewProjectionMatrix * vec4(position, 0.0, 1.0);
    uv = texcoord;
}
