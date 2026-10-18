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
// 1100）：2026-10-18 按参考反推——参考列是共享相机的广角透视（横边
// 斜率随卡位线性变化、上下卡反向、竖边严格垂直），静置偏航 30° 下
// f≈1100 才复现得出每像素斜率 ~5e-4；更大的焦距会把整列压成平面。
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
    vec2 cardHalf;    // 卡面（plate）在卡坐标系里的半尺寸（不含 shadows 余量）
    float cornerRadius; // 卡面四角圆角半径（px，卡坐标系）
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
    // ── 卡面圆角裁切（2026-10-18）──
    // plane 是 visible:false 的 layer 子树，其内部 ShaderEffect 的自定义
    // 属性绑定在本机栈上不生效（thumbRound 的半径恒为 0 = 卡片直角；
    // 实测改成字面量立刻出圆角、绑配置值永不更新）。透视层在可见树里、
    // 绑定可靠，故圆角在这里做：用逆映射已算出的卡面坐标 (u,v) 取
    // 圆角矩形 SDF。**只在卡面包围盒内抠角**——投影/辉光/扇叠背板都画在
    // 卡面之外，不能一起被裁。
    float r = min(cornerRadius, min(cardHalf.x, cardHalf.y));
    vec2 ah = abs(vec2(u, v)) - (cardHalf - vec2(r));
    float dist = length(max(ah, vec2(0.0))) + min(max(ah.x, ah.y), 0.0) - r;
    float aa = max(fwidth(dist), 0.25);
    float a = 1.0 - smoothstep(-aa, aa, dist);
    if (abs(u) <= cardHalf.x && abs(v) <= cardHalf.y)
        col *= a;
    fragColor = col * qt_Opacity;
}
