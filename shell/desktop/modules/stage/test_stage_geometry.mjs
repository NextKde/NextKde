// test_stage_geometry.mjs — stage-geometry 纯函数回归门（布局/目标矩形/倾斜）
// 运行：node shell/desktop/modules/stage/test_stage_geometry.mjs
// 数值锚点来自 2026-09-26/27 的实测（发布矩形 y、倾斜余量、布局槽位）。
import assert from "node:assert/strict";
import {
    PANEL_WIDTH, CARD_WIDTH_INSET, CARD_HEIGHT, CARD_X_INSET, PANEL_ORIGIN_Y,
    SCROLL_RETREAT as RETREAT_DEFAULT, TILT_FOCAL,
    tiltProject, tiltUnproject,
    adaptiveLayout, scrollLayout, computeTargetRects, tiltHeadroom,
} from "./stage-geometry.mjs";

const cases = [];
function check(name, actual, expected) {
    assert.deepEqual(actual, expected, name);
    cases.push(name);
}

// ── 常量契约 ──
check("PANEL_WIDTH", PANEL_WIDTH, 240);
check("CARD_WIDTH_INSET", CARD_WIDTH_INSET, 24);
check("CARD_HEIGHT", CARD_HEIGHT, 148);
check("CARD_X_INSET", CARD_X_INSET, 12);
check("PANEL_ORIGIN_Y", PANEL_ORIGIN_Y, 35);
check("SCROLL_RETREAT default", RETREAT_DEFAULT, 20);

check("computeTargetRects: dims.cardHeight scales rect height",
    computeTargetRects(
        [{ key: "a", wins: [win("w1", "h1", 10)] }],
        { positions: [0], scale: 1 },
        { columnY: 0, columnWidth: 240, cardHeight: 180 },
        [win("w1", "h1", 10)], {}).h1.height, 180);

// ── adaptiveLayout：自适应缩小（全部完整显示，等比缩小到恰好放下）──
// 4 张放进 560 高 → scale = (560-3*12)/(4*148) = 0.8818…
let lay = adaptiveLayout(560, 4);
assert.ok(Math.abs(lay.scale - (560 - 36) / 592) < 1e-9, "adaptive scale");
// 两侧同取整：actual 是未取整浮点（二进制下 524/592*148 不保证精确等于
// 目标整数），单侧 round 的锚点靠整除运气，换参数就会假红
check("adaptive: pos1 = s*148+12", Math.round(lay.positions[1]),
    Math.round((560 - 36) / 592 * 148 + 12));
check("adaptive clamp min 0.3", adaptiveLayout(100, 4).scale, 0.3);
// 放得下（scale=1）+ center=true：整列下移居中，间距不变
lay = adaptiveLayout(1200, 2, CARD_HEIGHT, 12, true);
check("adaptive center: shifted",
    lay.positions[0], Math.round((1200 - (160 + 148)) / 2));
check("adaptive center: gap preserved",
    lay.positions[1] - lay.positions[0], 160);
// center=false（默认）：顶部锚定
check("adaptive center off: top anchored",
    adaptiveLayout(1200, 2).positions, [0, 160]);

// ── scrollLayout：完整滚动（固定间距自然排列 + 放不下滚动）──
// ① 固定间距：pitch = 卡高 + spacing（avail 1000, ch 148, sp 16 → 164）；
// 放得下整块居中：4 张 content = 3·164+148 = 640，top0 = 180
lay = scrollLayout(1000, 4, { spacing: 16 });
check("scroll: fixed pitch = card + spacing", lay.pitch, 164);
check("scroll: block centered when fits",
    lay.positions.map(p => Math.round(p)), [180, 344, 508, 672]);
check("scroll: fits means no scroll", lay.scrollMax, 0);
check("scroll: full size", lay.scales, [1, 1, 1, 1]);
check("scroll: first card on top", lay.zs, [4, 3, 2, 1]);
// 卡少时不再被拉扯：2 张卡仍是自然间距 164、居中
lay = scrollLayout(1000, 2, { spacing: 16 });
check("scroll: few cards keep natural spacing",
    Math.round(lay.positions[1] - lay.positions[0]), 164);
check("scroll: two cards centered as block",
    lay.positions.map(p => Math.round(p)), [344, 508]);
// ② 溢出：顶锚 + 滚动上限（8 张 content = 7·164+148 = 1296 > 1000）
lay = scrollLayout(1000, 8, { spacing: 16 });
check("scroll: overflow top anchored", lay.positions[0], 0);
check("scroll: scrollMax = content + glowPad - avail",
    lay.scrollMax, 7 * 164 + 148 + 22 - 1000);
const atMax = scrollLayout(1000, 8,
    { spacing: 16, scroll: lay.scrollMax });
check("scroll: at max scroll last card bottom = avail - glowPad",
    Math.round(atMax.positions[7] + 148), 1000 - 22);
// 滚动偏移：positions 整体 −scroll
lay = scrollLayout(1000, 8, { spacing: 16, scroll: 300 });
check("scroll: offset applied", lay.positions[0], -300);
check("scroll: offset uniform", Math.round(lay.positions[7]),
    7 * 164 - 300);
// ③ 聚焦原位退避（avail 1000, n=5, sp 16 → pitch 164，content 804，
// top0=98，基础 [98,262,426,590,754]，retreat 默认 20）
lay = scrollLayout(1000, 5, { spacing: 16, hoveredIndex: 2 });
const baseScroll = scrollLayout(1000, 5, { spacing: 16 });
check("scroll focus: hovered stays in place",
    Math.round(lay.positions[2] - baseScroll.positions[2]), 0);
check("scroll focus: focused scale", lay.scales[2], 1.0);
check("scroll focus: focused top z", lay.zs[2], 7);
check("scroll focus: others keep full size",
    lay.scales.filter((s, i) => i !== 2), [1, 1, 1, 1]);
check("scroll focus: others dimmed", lay.dims.filter(d => d).length, 4);
check("scroll focus: retreat from slots",
    lay.positions.map(p => Math.round(p)), [78, 242, 426, 610, 774]);
// 滚动态聚焦：retreat 基于滚动后的槽位（scroll 200 → 基础
// [−102,62,226,390,554]，悬停 i=3：上组再 −20、下组 +20，无下限）
lay = scrollLayout(1000, 5,
    { spacing: 16, scroll: 200, hoveredIndex: 3, retreat: 20 });
check("scroll focus: scrolled slots retreat, no floor",
    lay.positions.map(p => Math.round(p)), [-122, 42, 206, 390, 574]);
// 聚焦锚定当前视觉位置（hoverY）：原样采用（卡不动 = 指针安全）
lay = scrollLayout(1000, 5, { spacing: 16, hoveredIndex: 4, hoverY: 700 });
check("scroll focus: anchored at hoverY verbatim",
    Math.round(lay.positions[4]), 700);
// 聚焦缩放 ≥ 基础缩放（外扩不变量）：基础恒 1.0，低于 1.0 的聚焦值被
// 抬到 1.0（内缩会把指针从卡缘挤出 → 悬停丢失慢振荡）
check("scroll focus: focus clamped up to base scale",
    scrollLayout(1000, 5, { spacing: 16, hoveredIndex: 2,
        focusScale: 0.95 }).scales[2], 1.0);
// 越界悬停索引 = 基础态
check("scroll focus: invalid index falls back to base",
    scrollLayout(1000, 3, { hoveredIndex: 9 }).dims,
    [false, false, false]);

// computeTargetRects：每组独立缩放（牌堆），x 居中宽随缩放
const scaled = computeTargetRects(
    [{ key: "a", wins: [win("w1", "h1", 10)] },
     { key: "b", wins: [win("w3", "h3", 20)] }],
    { positions: [100, 300], scales: [0.82, 1.0], scale: 1 },
    { columnY: 0, columnWidth: 240, cardHeight: 148 },
    [win("w1", "h1", 10), win("w3", "h3", 20)], {});
check("rects: scaled width", scaled.h1.width, Math.round(216 * 0.82));
check("rects: scaled x centered", scaled.h1.x,
    Math.round((240 - Math.round(216 * 0.82)) / 2));
check("rects: full-scale card keeps 12/216",
    [scaled.h3.x, scaled.h3.width], [12, 216]);

// ── computeTargetRects：特效起止点发布 ──
// 夹具：两组，每组两窗（同组多窗共用一张组卡矩形）
function win(id, handleId, pid) {
    return { windowId: id, handleId, pid };
}
const groups = [
    { key: "a", wins: [win("w1", "h1", 10), win("w2", "h2", 10)] },
    { key: "b", wins: [win("w3", "h3", 20)] },
];
const rectLay = { positions: [0, 160], scale: 1 };
const dims = { columnY: 41, columnWidth: 240 };
const rects = computeTargetRects(groups, rectLay, dims,
    [groups[0].wins[0], groups[0].wins[1], groups[1].wins[0]], {});

// 面板原点 35 + 列 y 41 + 槽位 y；组内每窗的 handleId 都映射到同一张组卡
check("targets: y = origin + column + slot", rects.h1.y, 35 + 41 + 0);
check("targets: second slot", rects.h3.y, 35 + 41 + 160);
check("targets: group windows share card rect",
    [rects.h1.y, rects.h2.y, rects.h2.id], [rects.h1.y, rects.h1.y, "h2"]);
check("targets: x/width from column", [rects.h1.x, rects.h1.width], [12, 216]);
// columnX（面板窗带溢出余量时内容列的窗内偏移）叠加到屏幕 x
check("targets: columnX offsets screen x",
    computeTargetRects(groups, rectLay,
        { columnY: 41, columnWidth: 240, columnX: 28 },
        groups.flatMap(g => g.wins), {}).h1.x, 28 + 12);
check("targets: height scaled", computeTargetRects(groups,
    { positions: [0, 100], scale: 0.5 },
    dims, groups.flatMap(g => g.wins), {}).h1.height, 74);

// 与 prevRects 合并：窗口仍存活但组本次缺席时，旧矩形兜底保留；
// 已死亡的键（窗口关闭）剪除
const merged = computeTargetRects([groups[1]], rectLay, dims,
    groups.flatMap(g => g.wins),
    { h1: { id: "h1", y: 76 }, hold1: { id: "hold1", y: 1 } });
check("targets: live prev retained (group momentarily absent)", merged.h1.y, 76);
check("targets: dead prev pruned", merged.hold1, undefined);

// 存活剪除：本轮 records 查无的键全部删除
const pruned = computeTargetRects([groups[1]], rectLay, dims,
    [win("w3", "h3", 20), win("w9", "h9", 30)], merged);
check("targets: stale keys pruned",
    pruned.h1 === undefined && pruned.hold1 === undefined, true);
check("targets: only live remain", Object.keys(pruned), ["h3"]);
// 无 handleId 时回退 windowId
const noHandle = computeTargetRects(
    [{ key: "c", wins: [win("wN", "", 7)] }], rectLay, dims,
    [win("wN", "", 7)], {});
check("targets: windowId fallback", noHandle.wN.id, "wN");

// ── tiltHeadroom：余量随倾斜角单调（特效倾斜展开的裁剪契约参考）──
check("headroom 0°", tiltHeadroom(0, 240), 6);
check("headroom 24°", tiltHeadroom(24, 240), 10);
check("headroom 42°", tiltHeadroom(42, 240), 13);
check("headroom 60° (上限)", tiltHeadroom(60, 240), 15);
check("headroom monotonic", tiltHeadroom(30, 240) <= tiltHeadroom(45, 240), true);

// ── tiltProject/tiltUnproject：真透视孪生（与 shaders/stage_tilt.frag 同式）──
// 角度 0 = 恒等
lay = tiltUnproject(tiltProject(37, -52, 0, TILT_FOCAL, 300).x,
    tiltProject(37, -52, 0, TILT_FOCAL, 300).y, 0, TILT_FOCAL, 300)
check("tilt: angle 0 identity", [Math.round(lay.u), Math.round(lay.v)], [37, -52])
// 往返一致（10° 与 45°、地平线上下的卡）
for (const [deg, yOff] of [[10, 0], [10, 400], [45, -300], [8.8, 250]]) {
    const rad = deg * Math.PI / 180
    const pr = tiltProject(-80, 60, rad, TILT_FOCAL, yOff)
    const inv = tiltUnproject(pr.x, pr.y, rad, TILT_FOCAL, yOff)
    assert.ok(Math.abs(inv.u + 80) < 1e-6 && Math.abs(inv.v - 60) < 1e-6,
        "tilt roundtrip " + deg + "° yOff " + yOff)
    cases.push("tilt roundtrip " + deg + "° yOff " + yOff)
}
// 近缘高远缘矮（真透视）：同一卡，近侧（u<0，正角左近）投影高度 > 远侧
const hNear = Math.abs(tiltProject(-108, 88, 10 * Math.PI / 180, TILT_FOCAL, 0).y
    - tiltProject(-108, -88, 10 * Math.PI / 180, TILT_FOCAL, 0).y)
const hFar = Math.abs(tiltProject(108, 88, 10 * Math.PI / 180, TILT_FOCAL, 0).y
    - tiltProject(108, -88, 10 * Math.PI / 180, TILT_FOCAL, 0).y)
check("tilt: near edge taller than far (true perspective)", hNear > hFar, true)
// 共享灭点：远离地平线的卡，近/远缘的竖直位置随 k 分离（共享透视的
// 正确现象——整列卡读作一面同向微转的 3D 墙）
const nearMid = tiltProject(-108, 0, 10 * Math.PI / 180, TILT_FOCAL, 400).y
const farMid = tiltProject(108, 0, 10 * Math.PI / 180, TILT_FOCAL, 400).y
check("tilt: near/far edges split vertically off-horizon",
    Math.abs(nearMid - farMid) > 5, true)

// ── originX（右侧常驻的窗口原点偏移）──
{
    const groups = [{ key: "a", wins: [win("w9", "h9", 10)] }];
    const dimsBase = { columnY: 41, columnWidth: 240, columnX: 20,
        cardHeight: 148 };
    const left = computeTargetRects(groups, { positions: [0], scale: 1 },
        dimsBase, [win("w9", "h9", 10)], {});
    const right = computeTargetRects(groups, { positions: [0], scale: 1 },
        Object.assign({}, dimsBase, { originX: 1920 - 280 }),
        [win("w9", "h9", 10)], {});
    check("originX default = window-relative", left["h9"].x,
        Math.round(20 + (240 - Math.round(216)) / 2));
    check("originX shifts rect to screen coords", right["h9"].x,
        left["h9"].x + 1920 - 280);
}

console.log(`stage-geometry: ${cases.length} checks passed`);
