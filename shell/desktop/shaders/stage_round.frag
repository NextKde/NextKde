#version 440

// stage_round.frag — 缩略图圆角遮罩（圆角矩形 SDF 抠 alpha）
//
// 沉浸缩略图填满整卡，直角内容会盖住背板的圆角（"卡片变矩形"）。
// Rectangle.clip 是矩形裁切给不了圆角；Qt5Compat OpacityMask 是
// layer.effect（带特效的嵌套层），在本机 freedreno 栈上于 plane 离屏层
// 内静默失效（实测：直角照旧，且疑似连带杀掉整卡渲染）。这里改用与
// plane → stage_tilt 完全相同的已验证形态：visible:false + 裸 layer 出
// 纹理，本着色器对纹理做圆角矩形 SDF（signed distance field）逐像素
// 抠 alpha，圆角外的片元透出下方的背板（背板自带 radius）。
//
// SDF：q = |p − 中心| − (半尺寸 − r)；d = len(max(q,0)) + min(max(q.x,
// q.y), 0) − r。d<0 在圆角矩形内。±1px smoothstep 抗锯齿。纹理是
// premultiplied alpha，整体乘 a 后仍是合法的预乘输出。

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float crad;      // 远缘圆角半径（px，逻辑坐标）
    float cradNear;  // 近缘圆角半径（贴屏缘一侧的两角更大）
    float nearLeft;  // 1 = 近缘在左，0 = 近缘在右（右条镜像）
    vec2 isz;        // 本项像素尺寸（逻辑坐标）
} ubuf;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec2 h = ubuf.isz * 0.5;
    vec2 p = qt_TexCoord0 * ubuf.isz;
    // 近/远缘两侧各自一组半径：左两角同半径、右两角同半径，故按
    // p.x 的侧别取即可；同一侧上下两角一致，纵向跨中线无 SDF 断裂。
    float r = ((p.x < h.x) == (ubuf.nearLeft > 0.5)) ? ubuf.cradNear : ubuf.crad;
    vec2 q = abs(p - h) - (h - vec2(r));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
    // 抗锯齿带宽取屏幕空间导数（每设备像素的 d 变化量），而不是固定
    // ±2 逻辑 px：本机 dpr=2，±2 逻辑 = 8 个片元宽的灰度过渡，白窗卡
    // 四周直接读成一圈灰色边框（2026-10-18 用户"灰色边框/锯齿"反馈）。
    // 导数带宽在近缘约 1 设备 px，远缘被透视缩小后也仍是 1 设备 px。
    float aa = max(fwidth(d), 0.25);
    float a = 1.0 - smoothstep(-aa, aa, d);
    fragColor = c * a * ubuf.qt_Opacity;
}
