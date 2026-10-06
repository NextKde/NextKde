#version 140

// stage-live.frag — 活体卡逐像素投影 + 圆角（合成器直绘）
//
// QML 侧 stage_tilt.frag（真透视逆投影）+ stage_round.frag（圆角 SDF）
// 的合成器孪生：对目标像素逆投影回卡面坐标 (u,v)，采样窗口小 FBO
// 纹理，卡面圆角外的片元丢弃——侧栏 chrome（背板色调/深度渐变/标题）
// 在条带窗里画在本绘制之上，视觉与静态快照完全同层。
//
// 单位约定：所有量均为设备像素（逻辑量在 C++ 侧 ×dpr 后传入；均匀
// 缩放与针孔数学可交换——k = f/(f+u·s) 在 f,u 同乘 dpr 时不变）。

uniform sampler2D texUnit;
uniform float angleRad;
uniform float focal;
uniform float yOff;
uniform vec2 camRel;    // 相机在 item 坐标系：x = item 中心（= 卡中心竖轴），y = 地平线
uniform vec2 itemSize;  // 本覆盖矩形设备像素尺寸
uniform vec2 cardSize;  // 卡面设备像素尺寸
uniform float crad;
uniform float alpha;     // 整卡透明度

in vec2 uv;
out vec4 fragColor;

void main(void)
{
    vec2 p = uv * itemSize;
    float c = cos(angleRad);
    float s = sin(angleRad);
    float A = p.x - camRel.x;
    float denom = c * focal - A * s;
    if (abs(denom) < 1.0)
        discard;
    float u = A * focal / denom;
    float k = focal / (focal + u * s);
    float v = (p.y - camRel.y) / k - yOff;

    // FBO 纹理是 GL 朝向（行 0=窗口底）——采样时 Y 镜像（官方
    // screencast 源码 setContentTransform(FlipY) 的着色器版等价物）
    vec2 tuv = vec2(u / cardSize.x + 0.5, 0.5 - v / cardSize.y);
    if (tuv.x < 0.0 || tuv.x > 1.0 || tuv.y < 0.0 || tuv.y > 1.0)
        discard;

    // 圆角矩形 SDF（stage_round 孪生）：d<0 在卡面内，±1px smoothstep 抗锯齿
    vec2 q = abs(vec2(u, v)) - (cardSize * 0.5 - vec2(crad));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - crad;
    float a = 1.0 - smoothstep(-1.0, 1.0, d);
    if (a <= 0.003)
        discard;
    // FBO 内容是预乘 alpha，整体乘 a 后仍是合法的预乘输出
    fragColor = texture(texUnit, tuv) * a * alpha;
}
