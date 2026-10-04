#version 100
// ES 变体（KWin GLES 上下文自动回退到本文件；核心配置读 _core 版）。
attribute vec2 position;
attribute vec2 texcoord;
uniform mat4 modelViewProjectionMatrix;
varying vec2 uv;
void main(void)
{
    gl_Position = modelViewProjectionMatrix * vec4(position, 0.0, 1.0);
    uv = texcoord;
}
