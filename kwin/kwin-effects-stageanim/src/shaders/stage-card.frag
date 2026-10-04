#version 100
precision mediump float;

// stage-card.frag — 卡面整体（玻璃背板 + 渐变 + 内容 + 边框 + 圆角）合成器直绘
//
// 方案"卡进特效"的核心：卡片 chrome 不再由 QML 条带窗渲染（那层与内容
// 分属两个进程，动画只能靠文件追赶＝悬停脱节的根因），改由本特效在
// paintScreen 后置通道一次过画完整卡面——同一管线、同一时钟，像素级同步。
//
// 数学与 stage-live.frag / QML stage_tilt.frag 同源（针孔逆投影到卡面局部
// 坐标 u,v），在此之上叠加：
//   - 圆角矩形 SDF 裁形（stage_round 孪生）
//   - 背板 tint（悬停提亮 / 扇叠副本减淡——由 C++ 传色）
//   - 顶光渐变（topLight，顶部白）/ 深度渐变（depthG，屏缘侧压暗）
//   - 内容纹理满铺（FBO 活体画面；无内容时纯背板=占位形态）
//   - 边框环（borderWidth 内缘；dropHover/dwellHint 时 C++ 传蓝色）
// 输出预乘 alpha（blend ONE, ONE_MINUS_SRC_ALPHA）。
// fanOff：扇叠副本的卡面局部中心偏移（主卡 = 0）；fanOnly：只画背板色。

uniform sampler2D texUnit;
uniform float angleRad;
uniform float focal;
uniform float yOff;
uniform vec2 camRel;    // 相机在 item 坐标系：x = item 中心（= 卡中心竖轴），y = 地平线
uniform vec2 itemSize;  // 本覆盖矩形设备像素尺寸
uniform vec2 cardSize;  // 卡面设备像素尺寸（主卡 plate）
uniform float crad;     // 圆角半径（设备像素）
uniform vec2 fanOff;    // 本张副本卡面局部偏移（扇叠）
uniform float fanOnly;  // 1 = 扇叠背板（纯 tint）
uniform vec4 tint;      // 背板色（直 alpha）
uniform vec4 borderColor;
uniform float borderWidth;
uniform float depthG;
uniform float topLight;
uniform float hasContent;
uniform float hoverBlend;
uniform float sideRight;
uniform float alpha;    // 整卡透明度（engaging 淡出）

varying vec2 uv;


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

    vec2 lc = vec2(u, v) - fanOff;
    vec2 q = abs(lc) - (cardSize * 0.5 - vec2(crad));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - crad;
    float a = (1.0 - smoothstep(-1.0, 1.0, d)) * alpha;
    if (a <= 0.003)
        discard;

    if (fanOnly > 0.5) {
        gl_FragColor = vec4(tint.rgb * tint.a * a, tint.a * a);
        return;
    }

    // 归一化卡面坐标（0..1，原点左上）
    vec2 n = lc / cardSize + 0.5;
    if (n.x < -0.002 || n.x > 1.002 || n.y < -0.002 || n.y > 1.002)
        discard;

    vec3 rgb;
    float al;
    if (hasContent > 0.5) {
        // FBO 纹理是 GL 朝向（行 0 = 窗口底）——采样时 Y 镜像
        vec4 ct = texture2D(texUnit, vec2(n.x, 1.0 - n.y));
        rgb = ct.rgb + tint.rgb * tint.a * (1.0 - ct.a);
        al = ct.a + tint.a * (1.0 - ct.a);
    } else {
        rgb = tint.rgb * tint.a;
        al = tint.a;
    }

    // 深度渐变（屏缘侧压暗；sideRight=1 时压右缘——右条镜像）。C++ 侧已
    // 按 hoverBlend 衰减 depthG/topLight（悬停淡出），shader 只管方向
    float nx = mix(n.x, 1.0 - n.x, sideRight);
    float depth = depthG * (1.0 - smoothstep(0.0, 0.75, nx));
    rgb *= (1.0 - depth * 0.85);
    al *= (1.0 - depth * 0.45);
    // 顶光（顶部一条白，模拟玻璃高光）+ 底部黑 0.10 stop（老 Gradient 尾）
    float tl = topLight * (1.0 - smoothstep(0.0, 0.35, n.y));
    rgb += vec3(tl);
    rgb *= (1.0 - 0.10 * smoothstep(0.35, 1.0, n.y));

    // 边框环（-borderWidth < d < 0）
    float ring = smoothstep(-borderWidth - 1.0, -borderWidth + 1.0, d);
    float ba = borderColor.a * ring;
    rgb = mix(rgb, borderColor.rgb * borderColor.a, ba);
    al = mix(al, max(al, ba), ba);

    gl_FragColor = vec4(rgb * a, al * a);
}
