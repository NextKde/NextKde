#version 440

// stage_plate.frag — 卡片背板（圆角矩形 SDF 绘制）
//
// 背板原来是 QQuickShape。Shape 的曲线抗锯齿依赖多重采样的渲染目标，而
// 背板所在的 plane 是离屏 layer（layer.samples 默认 0）——硬边直接成为
// 暗色缩略图卡的可见轮廓，圆角读作 1px 台阶（2026-10-18 实测左缘
// 99→31 一步跳变）。这里改用与缩略图遮罩同一条 SDF：近/远缘各一组半径、
// 逐像素抗锯齿，使轮廓在哪张卡上都由软边定义。
//
// 本项在透视重采样之前，坐标是逻辑 px；"±2 覆盖带"与 stage_round.frag
// 保持一致，让背板边与缩略图遮罩边合成出同一条曲线。

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float rNear;        // 近缘（贴屏缘一侧）半径
    float rFar;         // 远缘半径
    float nearLeft;     // 1 = 近缘在左（右条镜像）
    float borderWidth;  // 内侧描边宽度（逻辑 px，0 = 无）
    vec2 isz;           // 本项像素尺寸（逻辑坐标）
    vec4 fillColor;     // 直通 alpha（非预乘）
    vec4 borderColor;
} ubuf;

void main() {
    vec2 h = ubuf.isz * 0.5;
    vec2 p = qt_TexCoord0 * ubuf.isz;
    // 同侧两角同半径：按 p.x 的侧别取即可，跨中线无 SDF 断裂
    float r = ((p.x < h.x) == (ubuf.nearLeft > 0.5))
        ? ubuf.rNear : ubuf.rFar;
    vec2 q = abs(p - h) - (h - vec2(r));
    float d = length(max(q, vec2(0.0)))
        + min(max(q.x, q.y), 0.0) - r;

    // 抗锯齿带宽取屏幕空间导数：±2 逻辑 px 在 dpr=2 下是 8 片元宽的
    // 灰度带，边缘读作一圈灰色描边。导数带宽 ≈1 设备 px 才是真 AA。
    float aa = max(fwidth(d), 0.25);

    float cov = 1.0 - smoothstep(-aa, aa, d);

    // 描边画在内侧：d + bw > 0 处已在描边内侧，smoothstep 给出过渡
    vec4 col = ubuf.fillColor;
    if (ubuf.borderWidth > 0.0) {
        float inner = smoothstep(-aa, aa, d + ubuf.borderWidth);
        col = mix(ubuf.borderColor, ubuf.fillColor, inner);
    }

    // Qt Quick layer 合成按预乘 alpha
    fragColor = vec4(col.rgb * col.a, col.a) * cov * ubuf.qt_Opacity;
}
