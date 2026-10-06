#version 140

// stage-cursor.frag 的核心版（GLSL 140）：软件光标补绘。
// 本特效 paintScreen 后置通道画在整场景之上，会盖住场景内绘的软件
// 光标（容器无硬件光标平面）；卡画完后在光标位置重绘光标精灵。

uniform sampler2D texUnit;
uniform float alpha;
in vec2 uv;
out vec4 fragColor;

void main(void)
{
    fragColor = texture(texUnit, uv) * alpha;
}
