#version 100
// ES 变体（KWin GLES 上下文；核心配置读 _core 版）：软件光标补绘——本特效 paintScreen 后置通道画在整场景之上，
// 会盖住场景内绘的软件光标（容器无硬件光标平面）；卡画完后在光标位
// 置重绘光标精灵（QImage 已预乘，走 ONE/ONE_MINUS_SRC_ALPHA）。
precision mediump float;
uniform sampler2D texUnit;
uniform float alpha;
varying vec2 uv;
void main(void)
{
    gl_FragColor = texture2D(texUnit, uv) * alpha;
}
