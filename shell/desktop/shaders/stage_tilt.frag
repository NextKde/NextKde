#version 440

// stage_tilt.frag — 台前侧栏卡片的真透视倾斜（共享灭点）
//
// 背景：QML Rotation 是仿射变换——绕竖轴旋转只会把卡面横向压扁，近缘
// 不会变大、远缘不会变小，没有灭点，每张卡各是各的"假 3D"。本着色器用
// 针孔模型把卡面纹理按透视重投影：近缘放大、远缘缩小，且**所有卡片共
// 享同一台相机**（竖轴 = 内容列中心线，地平线 = 滚动视口垂直中心）——
// 整列卡片读作一面朝同一方向微转的 3D 墙，灭点唯一。
//
// 正交约定与 kwin/kwin-effects-stageanim 一致：depth = −u·sinR（正角
// = 左缘近大，Qt Y 轴朝下）。焦距用 TILT_FOCAL（stage-geometry.mjs，
// 2200）：比特效的 900 温和——侧栏整列共享透视时，大焦距避免远离地平
// 线的卡被广角式放大/缩小（45° 倾角下 k 偏差仍 <4%）。
//
// 逆映射（片元 → 源纹理坐标）：
//   前向：sx = camX + u·cosR·f/(f+u·sinR)；sy = camY + (v+yOff)·k
//   逆：  u = A·f/(cosR·f − A·s)（A = p.x − camX）
//         k = f/(f+u·s)；v = (p.y − camY)/k − yOff
// 纯函数孪生在 stage-geometry.mjs 的 tiltProject/tiltUnproject（node
// 单测断言往返一致），改这里必须同步改那里。

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float angleRad;   // 倾角（弧度）
    float focal;      // 针孔焦距（px）
    vec2 cardSize;    // 未旋转卡面尺寸（px，含辉光余量的 plane 尺寸）
    vec2 camRel;      // 共享相机在本项坐标系：x = 项中心（竖轴），y = 地平线
    float yOff;       // 卡中心 y − 地平线 y（px，正 = 卡在地平线下方）
    vec2 itemSize;    // 本 ShaderEffect 的像素尺寸
};

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float c = cos(angleRad);
    float s = sin(angleRad);
    float A = p.x - camRel.x;
    // 分母过零（极端角度/超广角）时弃片，避免除零噪声
    float denom = c * focal - A * s;
    if (abs(denom) < 1.0)
        discard;
    float u = A * focal / denom;
    float k = focal / (focal + u * s);
    float v = (p.y - camRel.y) / k - yOff;
    vec2 tuv = vec2(u / cardSize.x + 0.5, v / cardSize.y + 0.5);
    if (tuv.x < 0.0 || tuv.x > 1.0 || tuv.y < 0.0 || tuv.y > 1.0)
        discard;
    vec4 col = texture(source, tuv);
    fragColor = col * qt_Opacity;
}
