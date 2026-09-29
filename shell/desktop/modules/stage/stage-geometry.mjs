// stage-geometry.mjs — 台前调度侧栏的纯几何计算，QML 与 node 单测共用
// （pragma library 先例：modules/common/VisibilityPolicy.mjs）。
// 布局常量集中于此；PERSPECTIVE_FOCAL 与 vendor/kwin-effects-stageanim
// 的透视焦距必须保持一致——改一处必须同步另一处。

// 面板窗宽 = 常驻左侧条宽（窗口 implicitWidth / exclusiveZone /
// StageModeService 的 TargetWidth 三处同源）
export const PANEL_WIDTH = 240
// 悬停放大 + 辉光 + 倾斜的横向溢出余量：面板窗比常驻条两侧各宽这么多
//（内容列仍居中 PANEL_WIDTH），避免放大后的卡/辉光被窗缘硬切（输入用
// mask 限制回内容列，余量区点击穿透到桌面）。取值按"辉光外扩 13px ×
// 悬停放大 1.05 + 倾斜投影 ~6px"（≈19）再留 1px——exclusiveZone 会把它
// 一并保留（窗口不被辉光盖到），改辉光层数/悬停放大时同步核此值。
export const CARD_OVERFLOW_MARGIN = 20
// 卡宽 = 列宽 − 24（左右各 12 内边距）
export const CARD_WIDTH_INSET = 24
export const CARD_HEIGHT = 148
export const CARD_X_INSET = 12          // 卡片 x（列左内边距）
export const PANEL_ORIGIN_Y = 35        // 面板窗口原点 = 顶栏(35px)之下
export const HOVER_SCALE = 1.05
export const PERSPECTIVE_FOCAL = 900    // ⚠️ 特效 stageanim 同名常量必须同步

export const SCROLL_RETREAT = 20        // 聚焦退避：其余卡从原位向两侧平移的像素
// ── 拖拽排序（StageCard 与 StageSidebarWindow 共用；阈值/视觉同源）──
export const DRAG_PICK_THRESHOLD = 12   // 按下位移超过此值才算拖拽（否则是点击）
export const DRAG_SCALE = 1.06          // 被拖卡微放大（与悬停 HOVER_SCALE 同量级）
export const DRAG_Z = 999               // 被拖卡置顶 z（盖过全部槽位 z = n-i）
export const DRAG_EDGE_RATIO = 0.5      // 拖拽 y 的上下钳位（半个卡高出界余量）
// 辉光裁剪放宽：滚动视口只裁上下（滚动方向），左右各放宽这么多——
// 悬停辉光外扩 13px×放大 1.05 + 倾斜投影后 ≈19px 超出卡面 inset，
// 整条 clip 会把辉光侧边切掉（要与 CARD_OVERFLOW_MARGIN 同步核算）
export const GLOW_PAD = 22

// ── 卡面真透视（与 shaders/stage_tilt.frag 互为孪生，改一处同步另一处）──
// 卡片倾斜的针孔焦距：比特效（PERSPECTIVE_FOCAL=900）温和——整列卡片共享
// 透视时大焦距避免远离地平线的卡被广角式放大（45° 倾角下 k 偏差仍 <4%）
export const TILT_FOCAL = 2200

// 前向投影：卡面 (u,v)（相对卡中心/相机竖轴）→ **相机系**屏幕偏移。
// depth = −u·sinR（正角 = 左缘近大，与 stageanim 特效约定一致）；
// yOff = 卡中心相对共享地平线的偏移（正 = 卡在地平线下方）。
export function tiltProject(u, v, angleRad, focal, yOff) {
    const s = Math.sin(angleRad), c = Math.cos(angleRad)
    const k = focal / (focal + u * s)
    return { x: u * c * k, y: (v + yOff) * k }
}

// 逆投影：相机系屏幕偏移 → 卡面 (u,v)（着色器逐像素用同一式子）
export function tiltUnproject(px, py, angleRad, focal, yOff) {
    const s = Math.sin(angleRad), c = Math.cos(angleRad)
    const denom = c * focal - px * s
    if (Math.abs(denom) < 1)
        return null
    const u = px * focal / denom
    const k = focal / (focal + u * s)
    return { u: u, v: py / k - yOff }
}

// ── 自适应布局（adaptive）：全部完整显示，整体等比缩小到恰好放下 ──
// center：放得下时（scale=1 且有富余）整列垂直居中；贴满自动退回顶部锚定。
// 返回 { positions[], scale }。
// NaN 防线：availH 在"高度纪元未定"窗口期可能还不是有限值（面板尺寸未
// 稳定），NaN 会顺着 scale/positions 一路污染到特效矩形——回退为"放得下"。
function _finiteAvailH(availH, count, cardHeight, spacing) {
    return Number.isFinite(availH)
        ? availH : Math.max(count, 1) * (cardHeight + spacing)
}
export function adaptiveLayout(availH, count, cardHeight = CARD_HEIGHT,
                                spacing = 12, center = false) {
    const positions = []
    if (!(count > 0))
        return { positions, scale: 1 }
    availH = _finiteAvailH(availH, count, cardHeight, spacing)
    const scale = Math.max(0.3, Math.min(1,
        (availH - (count - 1) * spacing) / (count * cardHeight)))
    for (let i = 0; i < count; i++)
        positions.push(i * (cardHeight * scale + spacing))
    if (center)
        _centerPositions(positions, availH,
            positions[positions.length - 1] + cardHeight * scale)
    return { positions, scale }
}

// 整列下移使内容垂直居中；内容高度 ≥ 可用高度（贴满/溢出）时不动。
function _centerPositions(positions, availH, contentBottom) {
    const offset = Math.round((availH - contentBottom) / 2)
    if (offset <= 0)
        return
    for (let i = 0; i < positions.length; i++)
        positions[i] += offset
}

// ── 滚动布局（scroll）：固定间距自然排列，放不下滚动 ──
// 基础态（2026-09-28 用户定案，弃"可见数等分槽"——2 张卡时被 4 槽拉开
// 得离谱）：
//   ① 槽距 = 卡高 + spacing（固定自然间距，间距是唯一布局旋钮）；
//   ② 放得下：整块垂直居中；放不下：顶锚 + 滚动（scroll 偏移，
//      clamp 到 scrollMax，滚到底末卡完整露出 + 辉光余量）；
//   ③ 卡面永不缩小、无隐藏卡。
// 聚焦态（hoveredIndex 命中且 count>1，"原位退避"）：悬停卡**原位微放大
// + 置顶**（TopLeft 外扩只向右下长，卡内指针不可能被挤出）；其余卡
// **保持基础槽位与原尺寸**，只从悬停卡向两侧平移 retreat px 并压暗
//（focusDim 可关）。
// 返回 { positions[], scales[], zs[], dims[], scale, pitch, scrollMax }——
// positions 已含 scroll 偏移；pitch 供滚轮步进、scrollMax 供滚动上限；
// scale 为基础缩放兜底值。
export function scrollLayout(availH, count, opts = {}) {
    const ch = opts.cardHeight ?? CARD_HEIGHT
    const spacing = opts.spacing ?? 12
    const scroll = Number.isFinite(opts.scroll) ? Math.max(0, opts.scroll) : 0
    const h = (opts.hoveredIndex >= 0 && opts.hoveredIndex < count)
        ? opts.hoveredIndex : -1
    const positions = []
    const scales = []
    const zs = []
    const dims = []
    if (!(count > 0))
        return { positions, scales, zs, dims, scale: 1,
            pitch: ch + spacing, scrollMax: 0 }
    availH = _finiteAvailH(availH, count, ch, spacing)
    // 基础槽位（未滚动）：固定间距；放得下整块居中，放不下顶锚
    const pitch = ch + spacing
    const contentH = (count - 1) * pitch + ch
    const fits = contentH <= availH
    const top0 = fits ? (availH - contentH) / 2 : 0
    const baseY = i => top0 + i * pitch
    // 滚动上限：滚到底末卡完整露出（+GLOW_PAD 辉光余量）
    const scrollMax = fits ? 0
        : Math.max(0, contentH + GLOW_PAD - availH)
    if (h < 0 || count === 1) {
        for (let i = 0; i < count; i++) {
            positions.push(baseY(i) - scroll)
            scales.push(1)
            zs.push(count - i)
            dims.push(false)
        }
        return { positions, scales, zs, dims, scale: 1, pitch, scrollMax }
    }
    // 聚焦缩放 ≥ 基础缩放（基础恒 1，TopLeft 外扩不变量）：聚焦比基础小
    // 会让悬停卡向内收缩、把指针从卡缘挤出（悬停丢失→回弹→驻留→再聚焦
    // 的慢振荡）。聚焦只许放大或等大。
    const focusScale = Math.max(opts.focusScale ?? 1.0, 1)
    const retreat = opts.retreat ?? SCROLL_RETREAT
    // 悬停卡锚定当前视觉位置（hoverY）；缺省回退滚动后的基础槽位
    const hy = Number.isFinite(opts.hoverY)
        ? opts.hoverY : baseY(h) - scroll
    for (let i = 0; i < count; i++) {
        if (i === h) {
            positions.push(hy)
            scales.push(focusScale)
            zs.push(count + 2)
            dims.push(false)
            continue
        }
        // 上组退避不设下限：滚动布局里卡在视口上方属正常（clip 裁掉）
        positions.push(i < h
            ? baseY(i) - scroll - retreat
            : baseY(i) - scroll + retreat)
        scales.push(1)
        zs.push(count - i)
        dims.push(true)
    }
    return { positions, scales, zs, dims, scale: 1, pitch, scrollMax }
}

// ── 特效目标矩形（stage-targets.json 的内容）──
// stageanim 按 KWin internalId（handleId）读动画起止点；同组多窗共用一张
// 卡，所以组内每个窗的 handleId 都映射到同一张组卡矩形——任一窗最小化都
// 飞进同一张卡。分组/排除在 stage-groups.mjs；这里只做：布局 → 矩形 →
// 与 prevRects 合并 → 剪除已消失窗口（handleId/windowId 都查无即删，防
// 会话缓存无限增长）。groups 须已按组顺序表排序；lay = scrollLayout /
// adaptiveLayout 输出；
// dims = { columnY, columnWidth, columnX?, cardHeight? }（缺省用常量
// CARD_HEIGHT；columnX = 内容列在面板窗内的 x 偏移——窗口带溢出余量时
// 矩形 x 必须加上它才是屏幕坐标，缺省 0 兼容旧调用）；
// records 用于存活剪除（矩形发布跨桌面，调用方不筛桌面）。发布时机约定：
// 坐标必须在最小化派发前进文件，否则特效查不到就回落全局矩形。
export function computeTargetRects(groups, lay, dims, records, prevRects) {
    const cardHeight = dims.cardHeight ?? CARD_HEIGHT
    const merged = ({})
    for (const k in prevRects)
        merged[k] = prevRects[k]
    for (let g = 0; g < groups.length; g++) {
        // 每组可有独立缩放（牌堆/聚焦态）；缺省用统一 scale（stack/adaptive）。
        // 缩放卡的 x 居中（与视图 slotX 同式），宽随缩放——矩形=可见卡面
        const s = (lay.scales && lay.scales[g] !== undefined)
            ? lay.scales[g] : (lay.scale ?? 1)
        const y = Math.round(PANEL_ORIGIN_Y + dims.columnY
            + (lay.positions[g] ?? 0))
        const h = Math.round(cardHeight * s)
        const w = Math.round((dims.columnWidth - CARD_WIDTH_INSET) * s)
        // originX = 面板窗在屏幕上的原点 x：左侧常驻=0；右侧常驻时窗口
        // 锚在屏幕右缘，矩形必须加窗口原点才是特效要的屏幕坐标（缺省 0
        // 兼容旧调用与既有测试锚点）
        const x = Math.round((dims.originX ?? 0) + (dims.columnX ?? 0)
            + (dims.columnWidth - w) / 2)
        const wins = groups[g].wins
        for (let wI = 0; wI < wins.length; wI++) {
            const r = wins[wI]
            merged[r.handleId || r.windowId] = {
                id: r.handleId || r.windowId,
                pid: r.pid,
                x: x,
                y: y,
                width: w,
                height: h,
            }
        }
    }
    const liveIds = ({})
    for (let i = 0; i < records.length; i++) {
        if (records[i].handleId)
            liveIds[records[i].handleId] = true
        else if (records[i].windowId)
            liveIds[records[i].windowId] = true
    }
    for (const k in merged) {
        if (!liveIds[k])
            delete merged[k]
    }
    return merged
}

// 倾斜余量：倾斜（近缘透视放大）+ hover 缩放会超出卡片矩形，首张的顶部/
// 末张的底部需要留白——按倾斜角算出余量。轴心 = 卡片中心垂直轴（与
// StageCard/特效一致）：近缘距轴心半卡宽。侧栏堆叠区的上下留白按本公式
// 上限（tiltAngle 默认 22°）校准；改动效参数前先跑这里的锚点测试。
export function tiltHeadroom(tiltAngle, columnWidth) {
    const cardWidth = columnWidth - CARD_WIDTH_INSET
    const rad = tiltAngle * Math.PI / 180
    const k = PERSPECTIVE_FOCAL
        / (PERSPECTIVE_FOCAL - (cardWidth / 2) * Math.sin(rad))
    return Math.ceil((CARD_HEIGHT / 2) * (k * HOVER_SCALE - 1)) + 2
}
