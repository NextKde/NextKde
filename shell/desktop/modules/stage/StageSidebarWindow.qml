import QtQuick
import Quickshell
import Quickshell.Wayland
import org.kde.taskmanager
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import "stage-geometry.mjs" as StageGeo
import "stage-groups.mjs" as StageGroups

// Stage Sidebar 面板本体：左侧常驻、保留屏幕空间（窗口自动让位）。
// 渐进堆叠卡片栏：同应用的窗口堆叠在同一张卡上（×N 角标）；放得下=
// 原尺寸宽松排开（居中），放不下=整列变牌堆（铺满全长）；或选 adaptive
// 模式等比缩小全部显示。悬停卡原位放大置顶、其余原位退避；玻璃质感
// 卡片 + 悬停辉光，背板完全透明。窗宽 = 常驻条 + 两侧溢出余量（辉光
// 不被窗缘硬切，余量区输入由 mask 穿透）。
//
// 分层：纯逻辑（分组/顺序表/矩形/模型对账）在 stage-groups.mjs 与
// stage-geometry.mjs（node 单测覆盖）；展示在 StageCard；本文件只留
// 编排——快照/发布/最小化的节拍控制。
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell-stagebar"
    WlrLayershell.layer: WlrLayer.Top
    exclusionMode: ExclusionMode.Normal
    // 保留区含两侧溢出余量：最大化的窗从余量之外开始，左侧不会被
    // 悬停辉光盖住（实测踩过"放大窗口左缘被卡片辉光覆盖"）
    exclusiveZone: StageGeo.PANEL_WIDTH // 实验：临时回 240

    property bool open: false

    visible: open
    color: "transparent"
    anchors { top: true; left: true; bottom: true }
    // 窗宽 = 常驻条 + 两侧溢出余量：悬停放大 + 辉光 + 倾斜投影超出卡面
    // 13~20px，窗缘硬切会显出"边界"（实测踩过）。exclusiveZone 仍只占
    // 常驻条宽；余量区的输入由文件尾的 mask 穿透到桌面。
    implicitWidth: StageGeo.PANEL_WIDTH + StageGeo.CARD_OVERFLOW_MARGIN * 2

    // ── 分组：当前桌面上除"活动应用整组"外的窗口，按应用堆叠 ──
    // （分组规则见 stage-groups.mjs：同 desktopId / rawAppId / 同 pid 归
    // 一张卡；代表窗口优先未最小化、其次已有缩略图的。）
    // macOS 语义：前台应用整体不打折为卡——只排除活动窗本身的话，主窗
    // 在前、同组子窗的卡还挂在栏里（用户实测踩过）。
    readonly property var sideGroups: {
        WindowService.revision
        WindowService.activeWindowId
        const activeRec = WindowService.windowById(WindowService.activeWindowId)
        return StageGroups.decorateGroups(
            StageGroups.groupRecords(WindowService.records || [], {
                desktopId: WindowService.currentDesktopId,
                skipWindowId: WindowService.activeWindowId,
                excludeKey: activeRec ? StageGroups.groupKeyOf(activeRec) : "",
                excludeKeepMinimized: true,
            }),
            id => WindowService.thumbnailUrl(id))
    }

    function _appOf(windowId) {
        const r = WindowService.windowById(windowId)
        return r?.identity?.desktopId ?? ""
    }

    function hasWindowId(id: string): bool {
        const records = WindowService.records || []
        for (let i = 0; i < records.length; i++)
            if (records[i].windowId === id)
                return true
        return false
    }

    // 退位应用的整组窗口 id（同组键、未最小化、当前桌面）——交换时整组
    // 同拍收编，而不是只收活动窗、兄弟窗等 applyAutoMinimize 补扫
    //（用户实测"多张卡一前一后回侧边"即此错拍）。
    function _demoteGroupIds(demotedId) {
        const rec = WindowService.windowById(demotedId)
        if (!rec)
            return []
        const key = StageGroups.groupKeyOf(rec)
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const ids = []
        for (let i = 0; i < records.length; i++) {
            const r = records[i]
            if (r.toplevel?.minimized)
                continue
            if (StageGroups.groupKeyOf(r) !== key)
                continue
            if (!StageGroups.isOnDesktop(r, currentId))
                continue
            ids.push(r.windowId)
        }
        return ids
    }

    property string _prevActiveId: ""

    // ── 收编公共尾板：先拍快照，再按通道节拍派发最小化 ──
    // ⚠️ 先拍快照、后收编：KWin 对最小化窗口截到的是黑帧，必须趁窗口还
    // 可见时完成捕获。矩形落盘（publishSimulatedLayout）也必须在最小化
    // 前进文件，否则特效按窗口 id 查不到起止点就回落全局矩形。
    //   delayed = true  → 300ms 快照等待 → 发布 → 30ms 派发
    //                     （自动收编路径：多窗连拍需要时间）
    //   delayed = false → 立即发布 → 30ms 派发
    //                     （交换路径：单窗即时拍）
    function captureAndDemote(ids, excludeKey, delayed) {
        for (let i = 0; i < ids.length; i++)
            WindowService.requestThumbnail(ids[i])
        root._pendingMinimize = ids
        if (delayed) {
            _captureThenMinTimer.restart()
        } else {
            publishSimulatedLayout(excludeKey)
            _minimizeDispatchTimer.restart()
        }
    }

    property var _pendingMinimize: []
    property Timer _minimizeDispatchTimer: Timer {
        interval: StageConfigService.demoteDispatchDelay
        onTriggered: {
            const t = root._pendingMinimize
            root._pendingMinimize = []
            for (let i = 0; i < t.length; i++)
                WindowService.minimizeWindow(t[i], true)
        }
    }
    property Timer _captureThenMinTimer: Timer {
        interval: StageConfigService.demoteCaptureDelay
        onTriggered: {
            root.publishSimulatedLayout("")
            root._minimizeDispatchTimer.restart()
        }
    }
    property Timer _autoMinTimer: Timer {
        interval: StageConfigService.autoMinDelay
        onTriggered: root.applyAutoMinimize()
    }

    // 过渡所有权交接：用户点了卡片/切换了窗口，在途的自动收编周期
    //（收集目标 → 300ms 快照窗 → 30ms 派发）作废——迟到的队列会把刚展
    // 开的应用又收回去（快照窗内点卡的竞态）。
    function _cancelPendingDemote() {
        root._pendingMinimize = []
        root._captureThenMinTimer.stop()
        root._minimizeDispatchTimer.stop()
    }

    // ── 自动收编：激活切换后，非同应用的非活动窗口全部最小化收进侧栏 ──
    // 同组窗口不动（对话框/同应用弹窗安全）。
    function applyAutoMinimize() {
        if (!StageModeService.enabled || !open
                || !StageConfigService.autoMinimize)
            return
        _cancelPendingDemote() // 作废在途批次（round35 NEW-6：属主归一）
        const activeId = WindowService.activeWindowId
        if (!activeId)
            return
        const activeRec = WindowService.windowById(activeId)
        const activeGroup = activeRec ? StageGroups.groupKeyOf(activeRec) : ""
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const targets = []
        for (let i = 0; i < records.length; i++) {
            const r = records[i]
            if (r.windowId === activeId || r.toplevel?.minimized)
                continue
            if (!StageGroups.isOnDesktop(r, currentId))
                continue
            // 同应用豁免双保险：同组，或同进程（XWayland 弹窗的身份解析
            // 常与主窗对不上，pid 不会骗人）
            if (StageGroups.groupKeyOf(r) === activeGroup)
                continue
            if (StageGroups.isSameProcess(r, activeRec))
                continue
            targets.push(r.windowId)
        }
        if (targets.length === 0)
            return
        captureAndDemote(targets, "", true)
    }

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            const current = WindowService.activeWindowId
            if (root._prevActiveId && root._prevActiveId !== current) {
                if (root.hasWindowId(root._prevActiveId))
                    WindowService.requestThumbnail(root._prevActiveId)
                // 活动窗变空有两种含义，必须区分：
                // ① KWin 真的无活动窗（kwinActiveId 也为空）= 点了桌面 → 收编
                // ② 焦点在未跟踪窗上（桥快照过滤掉的 transient 弹窗，如
                //    wemeet 扫码小窗；kwinActiveId 非空）→ 什么都不做
                if (current === "") {
                    if (WindowService.kwinActiveId === "")
                        root._desktopFocusTimer.restart()
                } else {
                    root._desktopFocusTimer.stop()
                    root.engageFromActivation()
                }
            }
            root._prevActiveId = current
            root._autoMinTimer.restart()
        }
        // 派发失败自愈（round35 NEW-2）：engage-swap 丢了（守护重启/桥缺席）
        // 时激活不会发生、被点组不离开侧栏、targetId 不变——engaging 的
        // opacity 0 会永久卡住（"卡片消失"的状态残留同型）。按票根外的
        // 最近派发键复位交棒中的卡，并清退位保护与同键在途队列。
        function onCommandFinished(action, ticket, found) {
            if (action !== "engage-swap" || found
                    || root._lastDispatchedKey === "")
                return
            for (let i = 0; i < cardRepeater.count; i++) {
                const slot = cardRepeater.itemAt(i)
                if (slot?.appKey === root._lastDispatchedKey
                        && slot.cardItem)
                    slot.cardItem.engaging = false
            }
            for (let q = root._engageQueue.length - 1; q >= 0; q--) {
                if (root._engageQueue[q].appKey === root._lastDispatchedKey)
                    root._engageQueue.splice(q, 1)
            }
            root._pendingSwaps = root._pendingSwaps.filter(
                swap => swap.clicked !== root._lastDispatchedKey)
            root._lastDispatchedKey = ""
            console.warn("[StageSidebar] engage-swap failed, card reset ("
                + "ticket=" + ticket + ")")
        }
    }

    // ── dock 点击的同拍收编：订阅 WindowService.activationRequested ──
    // 点击瞬间就锁退位窗（不等 KWin 事件经桥 120ms 防抖绕回来）。卡片点
    // 击路径（_dispatchNextEngage 内部激活）用 _engagingDispatch 防重入，
    // 维持自己的 engageDelay 卡片交棒时序。
    property bool _engagingDispatch: false

    function activateWithSwap(windowId) {
        if (_engagingDispatch)
            return
        if (!StageModeService.enabled || !open
                || !StageConfigService.autoMinimize)
            return
        const demotedId = WindowService.activeWindowId
        if (!demotedId || demotedId === windowId)
            return
        const rec = WindowService.windowById(demotedId)
        if (!rec || rec.toplevel?.minimized)
            return
        const activeRec = WindowService.windowById(windowId)
        // 同应用豁免双保险（同 applyAutoMinimize）
        if (StageGroups.isSameApp(rec, activeRec,
                _appOf(demotedId), _appOf(windowId)))
            return
        // 整组同拍收编：退位应用的全部窗口一起飞回组卡
        _cancelPendingDemote()
        captureAndDemote(_demoteGroupIds(demotedId),
            activeRec ? StageGroups.groupKeyOf(activeRec) : "", false)
    }

    Connections {
        target: WindowService
        function onActivationRequested(windowId) {
            root.activateWithSwap(windowId)
        }
    }

    // ── 激活切换（Alt-Tab 等 shell 外部路径）的同拍收编兜底 ──
    // 与 engageCard 同构：切换瞬间锁定退位窗、趁可见拍快照、发布预测卡位，
    // 与新活动窗的展开动画同一节拍最小化——而不是等 autoMinTimer。
    function engageFromActivation() {
        if (!StageModeService.enabled || !open
                || !StageConfigService.autoMinimize)
            return
        const activeId = WindowService.activeWindowId
        const demotedId = root._prevActiveId
        if (!activeId || !demotedId || demotedId === activeId)
            return
        if (!root.hasWindowId(demotedId))
            return
        const rec = WindowService.windowById(demotedId)
        if (rec?.toplevel?.minimized)
            return
        const activeRec = WindowService.windowById(activeId)
        // 同应用豁免双保险（对话框安全，与 applyAutoMinimize 同规则）
        if (StageGroups.isSameApp(rec, activeRec,
                _appOf(demotedId), _appOf(activeId)))
            return
        if (!StageGroups.isOnDesktop(rec, WindowService.currentDesktopId))
            return
        // 整组同拍收编（与 activateWithSwap 同规则）
        _cancelPendingDemote()
        captureAndDemote(_demoteGroupIds(demotedId),
            activeRec ? StageGroups.groupKeyOf(activeRec) : "", false)
    }

    // ── 桌面聚焦：全部应用窗收进侧栏（Stage Manager 语义） ──
    // KOS 桌面图标层不可激活，点空白处后 KWin 无 activated 记录。
    // ⚠️ "无活动窗"必须去抖 150ms 且核对 kwinActiveId：XWayland 焦点交接
    //（如 wemeet 扫码小窗）与未跟踪 transient 窗都会造成空活动窗快照。
    property Timer _desktopFocusTimer: Timer {
        interval: StageConfigService.desktopFocusDebounce
        onTriggered: {
            if (WindowService.activeWindowId === ""
                    && WindowService.kwinActiveId === "")
                root.collapseToStrip()
        }
    }

    function collapseToStrip() {
        if (!StageModeService.enabled || !open
                || !StageConfigService.autoMinimize)
            return
        _cancelPendingDemote() // 作废在途批次（round35 NEW-6：属主归一）
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const targets = []
        for (let i = 0; i < records.length; i++) {
            const r = records[i]
            if (r.toplevel?.minimized || !(r.pid > 0))
                continue // 无 pid 的 KWin 内部表面不碰
            if (StageGroups.isOnDesktop(r, currentId))
                targets.push(r)
        }
        if (targets.length === 0)
            return
        captureAndDemote(targets.map(r => r.windowId), "", false)
        console.info("[StageSidebar] collapse to strip: "
            + targets.length + " window(s)")
    }

    // ── 布局仿真发布：按"切换后的分组布局"给每个窗口发布它的组卡矩形 ──
    // stageanim 按 KWin internalId 读起止点；同组多窗共用一张卡，所以每个
    // 窗的 handleId 都映射到组卡矩形——任一窗最小化都飞进同一张卡。
    // excludeKey = 激活应用的组（它的卡将离开侧栏）；空 = 全量（桌面收编）。
    // orderOverride：点击换位的**预测顺序表**（派发前持久表还没转正，
    // 预测发布用它把退位组矩形放到被点槽位；缺省用持久表）
    // ⚠️ excludeKey 为空时自动排除活动组（与视图一致：活动应用没有卡）。
    // 活动组一旦被算进布局就是一张"幻影卡"——整列按 N+1 张重排、全体
    // 矩形上移，还原动画读到错位矩形（实测 3 卡场景偏 104px，卡越多偏
    // 得越多——"窗口缩到侧边栏上方、卡片再滑动"的根源）。组内已最小化
    // 的兄弟窗保留（与 sideGroups 的 excludeKeepMinimized 同语义）。
    // 交换路径传非空 excludeKey（被点组），退位组由 orderOverride 显式
    // 给槽位，不受自动排除影响。
    function publishSimulatedLayout(excludeKey, orderOverride) {
        if (!StageModeService.enabled)
            return
        const records = WindowService.records || []
        if (records.length === 0)
            return // 桥未就绪，保留既有缓存
        // keepActiveMin 只对自动排除的活动组生效：调用方显式传入的
        // excludeKey（交换路径的被点组）必须整组排除——被点窗的最小化
        // 兄弟正在还原，保留它们会把已排除的组当"最小化兄弟"捞回来，
        // 变成尾部的幻影卡（还原/收编双双飞错，实测）
        let keepActiveMin = false
        let activeRec = null
        if (!excludeKey) {
            activeRec = WindowService.windowById(
                WindowService.activeWindowId)
            if (activeRec) {
                excludeKey = StageGroups.groupKeyOf(activeRec)
                keepActiveMin = true
            }
        }
        const groups = StageGroups.sortByOrder(
            orderOverride || root._groupOrder,
            StageGroups.groupRecords(records,
                { requirePid: true, excludeKey: excludeKey,
                  excludeKeepMinimized: keepActiveMin }))
        // 基础布局发布，不掺悬停态：聚焦缩放是 TopLeft 原点（y 不动，
        // "从放大位长出"无损），而退避（±deckSidePeek）是鼠标扫过的瞬态
        // ——烤进矩形会让收编窗口落在比卡片落点高/低一个退避量的位置，
        // 鼠标离开后卡片回落 = "窗口飞得比卡高、卡片再从上面滑回来"
        //（实测：悬停另一张卡时点卡，收编矩形 base−28）。卡片落点以
        // 无指针时的基础槽位为准。
        let lay
        if (StageConfigService.layoutMode === "scroll") {
            lay = StageGeo.scrollLayout(cards.height, groups.length, {
                cardHeight: StageConfigService.cardHeight,
                spacing: StageConfigService.cardSpacing,
                scroll: root.scrollOffset,
            })
        } else {
            lay = _layout(groups.length)
        }
        root._lastCardRects = StageGeo.computeTargetRects(groups, lay,
            { columnY: cards.y, columnWidth: cards.width,
                columnX: cards.x,
                cardHeight: StageConfigService.cardHeight },
            records, root._lastCardRects)
        // round35 NEW-4：活动组"ghost 槽位"。活动组被排除在视图布局外
        //（round33 幻影卡修复的正确代价），但非 shell 发起的最小化（标题
        // 栏按钮/dock toggle，shell 无法预发布）在事件时刻读 targets 文件
        // ——若该组上次作为卡片的槽位已变（上方卡被关掉/换位重排），动画
        // 会飞向陈旧矩形。按"活动组假想插回布局"的槽位补写矩形：只进
        // targets 文件（_lastCardRects 仅被 _writeTargetsFile 消费，无
        // 视图回流路径），视图布局完全不变。
        if (keepActiveMin) {
            const allGroups = StageGroups.groupRecords(records,
                { requirePid: true })
            let ghostEntry = null
            for (let g = 0; g < allGroups.length; g++) {
                if (allGroups[g].key === excludeKey) {
                    ghostEntry = allGroups[g]
                    break
                }
            }
            if (ghostEntry) {
                // 按顺序表算 ghost 槽位序号（含自身）——其余视图组的
                // 相对次序与视图布局一致
                const order = root._groupOrder
                const gIdx = StageGroups.orderIndex(order, excludeKey)
                let pos = 0
                for (let g = 0; g < groups.length; g++)
                    if (StageGroups.orderIndex(order, groups[g].key) < gIdx)
                        pos++
                const ghostLay = StageConfigService.layoutMode === "scroll"
                    ? StageGeo.scrollLayout(cards.height,
                        groups.length + 1, {
                            cardHeight: StageConfigService.cardHeight,
                            spacing: StageConfigService.cardSpacing,
                            scroll: root.scrollOffset,
                        })
                    : _layout(groups.length + 1)
                root._lastCardRects = StageGeo.computeTargetRects(
                    [ghostEntry], ghostLay,
                    { columnY: cards.y, columnWidth: cards.width,
                        columnX: cards.x,
                        cardHeight: StageConfigService.cardHeight },
                    records, root._lastCardRects)
            }
        }
        _writeTargetsFile()
    }

    readonly property string _targetsPath: Quickshell.stateDir + "/fg-sched/stage-targets.json"
    property var _lastCardRects: ({})

    // ── 组顺序表：卡片点击 = 位置交换（退位组补到被点槽位），顺序由本表
    // 决定，而不是 records 顺序。维护点：滚轮翻动（直接重建）、engageCard
    // 的 applySwapOrder、syncCards 的 pruneOrder（实现都在 stage-groups.mjs）。
    property var _groupOrder: []

    // 设置页改动（倾斜角/间距/布局模式都会挪动卡片几何）→ 立即重排并重发布
    Connections {
        target: StageConfigService
        function onRevisionChanged() {
            root.layoutCards()
            root.publishSimulatedLayout("")
        }
    }

    function _writeTargetsFile() {
        const targets = []
        for (const k in root._lastCardRects)
            targets.push(root._lastCardRects[k])
        // suppress 恒空：伪实时（静默名单）已删除，动画全部照播；
        // 保留键位仅为 stageanim 的文件格式兼容（无需重建特效）
        JsonConfigStore.writePath(root._targetsPath, JSON.stringify(
            { targets: targets, suppress: [] }))
    }

    // ── engage 派发队列（round35 NEW-1）：点击只入队 + 卡片淡出交棒，
    // engageDelay 到点由窗口级单 Timer 逐个派发，**派发时刻**才重算退位
    // 组/预测顺序表（动画全部在派发后才起跑，预测挪晚无损，反而消灭
    // "点击时刻快照过期"整类问题）。旧实现把待办挂在五个无属主单槽上，
    // 极速连点（间隔 < engageDelay）时后一次点击顶掉前一次的全部待办
    // = 丢派发/飞错位/丢收编（round35 审计 NEW-1 实锤）。
    property var _engageQueue: []
    // 最近派发的被点组键（NEW-2 回执失败复位 engaging 用）
    property string _lastDispatchedKey: ""

    property Timer _engageDispatchTimer: Timer {
        interval: StageConfigService.engageDelay
        onTriggered: root._dispatchNextEngage()
    }

    function _dispatchNextEngage() {
        const entry = root._engageQueue.shift()
        if (!entry)
            return
        root._lastDispatchedKey = entry.appKey
        // 退位判定在派发时刻做（点击到派发之间没有任何激活派发，活动窗
        // 未变；豁免规则与旧点击时刻版一致：同组/同应用/已最小化豁免）
        const demotedId = WindowService.activeWindowId
        let skipDemote = true
        let demotedKey = ""
        let minimizeIds = []
        if (demotedId && demotedId !== entry.targetId) {
            const dRec = WindowService.windowById(demotedId)
            const aRec = WindowService.windowById(entry.targetId)
            const sameGroup = JSON.parse(entry.idsJson || "[]")
                .indexOf(demotedId) >= 0
            if (!dRec?.toplevel?.minimized && !sameGroup
                    && !StageGroups.isSameApp(dRec, aRec,
                        _appOf(demotedId), _appOf(entry.targetId))) {
                skipDemote = false
                demotedKey = dRec ? StageGroups.groupKeyOf(dRec) : ""
            }
        }
        if (!skipDemote) {
            // 整组快照此刻拍（窗口仍可见，不截黑帧）——比旧版（点击时刻
            // 拍）晚 engageDelay，仍在可见窗口内
            minimizeIds = _demoteGroupIds(demotedId)
            for (let g = 0; g < minimizeIds.length; g++)
                WindowService.requestThumbnail(minimizeIds[g])
        }
        // 换位两拍：预测顺序表只喂本次发布（退位组矩形=被点槽位，必须在
        // 最小化派发前进文件）；**顺序表本体不在此刻转正**——转正提前于
        // 记录翻转的话，间隙里的任何一次对账（派发时拍的缩略图事件恰好
        // 落在这个窗口）会按"被点组已走"重排旧记录：邻卡先顶进被点槽位
        // （N−1 布局）、真快照到达再弹回 = 换位抽动。转正由 syncCards 的
        // 提交门在退位组真正进场的那一次对账里完成（与模型变更同拍）。
        const predictedOrder = StageGroups.applySwapOrder(root._groupOrder,
            entry.appKey, skipDemote ? "" : demotedKey)
        if (!skipDemote && demotedKey) {
            const swaps = root._pendingSwaps.slice()
            swaps.push({ clicked: entry.appKey, demoted: demotedKey,
                at: Date.now() })
            root._pendingSwaps = swaps
        }
        publishSimulatedLayout(entry.appKey, predictedOrder)
        // 整组一起展开（macOS 语义）：原子 engage-swap——还原抬升、代表窗
        // 拿焦点、退位组同拍收编，一条命令一个 tick 处理完（分开会按桥
        // 50ms 轮询一拍一条，收编慢半拍）。activationRequested 只发一次
        //（代表窗），_engagingDispatch 挡掉回环。
        let ids = []
        try {
            ids = JSON.parse(entry.idsJson || "[]")
        } catch (e) {
            ids = []
        }
        if (ids.indexOf(entry.targetId) < 0)
            ids.push(entry.targetId)
        root._engagingDispatch = true
        WindowService.engageSwap(ids, entry.targetId, minimizeIds,
            "eng-" + Date.now())
        root._engagingDispatch = false
        // kwin 记录已随原子命令收编（NEW-7），仅 foreign 兜底逐条发
        for (let i = 0; i < minimizeIds.length; i++) {
            if (WindowService.windowById(minimizeIds[i])?.provider !== "kwin")
                WindowService.minimizeWindow(minimizeIds[i], true)
        }
        console.info("[StageSidebar] engage " + entry.appKey
            + " demote=" + (skipDemote ? "none" : demotedId))
        // 队列还有剩余：下一个 engageDelay 拍继续
        if (root._engageQueue.length > 0)
            root._engageDispatchTimer.restart()
    }

    // 换位提交门（派发→记录翻转的缓冲队列）：每项 {clicked, demoted, at}。
    // syncCards 开头检查——退位组键已出现在 sideGroups（记录已确认最小化）
    // 的那次对账，把 applySwapOrder 转正进顺序表，与 desired 计算同拍；
    // 2 秒未到场的换位作废（最小化被拦/窗口关闭）。急速连点各自独立入队，
    // 先到先转正——无单槽互踩。
    property var _pendingSwaps: []

    function engageCard(slot) {
        // 面板隐藏/模式关闭后不可从不可见卡片派发展开
        if (!StageModeService.enabled || !open)
            return
        const card = slot.cardItem
        if (card.engaging)
            return
        card.engaging = true
        _cancelPendingDemote()
        // 只入队；退位判定/快照/预测表全部挪到派发时刻（见队列注释）
        root._engageQueue.push({ appKey: slot.appKey,
            targetId: slot.targetId, idsJson: slot.idsJson })
        // 首条入队才启动计时（后续条目由派发尾链触发，保持每 engageDelay
        // 一拍的节奏）
        if (root._engageQueue.length === 1)
            root._engageDispatchTimer.restart()
    }

    // 无头验证钩子（同 dock-debug 惯例）：模拟点击第一张卡走完整同拍交换
    function debugEngageFirst(): string {
        const slot = cardRepeater.itemAt(0)
        if (!slot)
            return JSON.stringify({ error: "no cards" })
        const demoted = WindowService.activeWindowId
        engageCard(slot)
        return JSON.stringify({ engaged: slot.targetId, demoted: demoted })
    }

    // 无头点击任意卡（排障钩子；跨应用退位/停泊路径的确定性复现）
    function debugEngageIndex(index): string {
        const slot = cardRepeater.itemAt(index)
        if (!slot)
            return JSON.stringify({ error: "bad index", n: cardModel.count })
        const demoted = WindowService.activeWindowId
        engageCard(slot)
        return JSON.stringify({ engaged: slot.targetId,
            demoted: demoted, app: slot.appKey })
    }

    // ── round30 调研探针：zkde_screencast 活体流可行性 ──
    // Plasma 6 任务栏活体预览的官方路径 = ScreencastingRequest（zkde_screencast
    // Wayland 协议开单窗口 PipeWire 流）+ kpipewire 渲染。授权前提：quickshell
    // 进程关联的 .desktop 声明 X-KDE-Wayland-Interfaces=zkde_screencast_unstable_v1
    //（org.quickshell.desktop 已加）。探针成功（nodeId>0）= 可迁移真·活体缩略图。
    property ScreencastingRequest _streamProbe: ScreencastingRequest {
        onNodeIdChanged: console.info("[StageSidebar] stream probe nodeId="
            + nodeId + " uuid=" + uuid)
    }

    function debugStreamProbe(index): string {
        const slot = cardRepeater.itemAt(index)
        if (!slot)
            return JSON.stringify({ error: "bad index", n: cardModel.count })
        const rec = WindowService.windowById(slot.targetId)
        const uuid = rec ? rec.handleId : ""
        _streamProbe.uuid = uuid
        return JSON.stringify({ requested: uuid })
    }

    function closeGroup(idsJson) {
        let ids = []
        try {
            ids = JSON.parse(idsJson || "[]")
        } catch (e) {
            return
        }
        for (let i = 0; i < ids.length; i++)
            WindowService.closeWindow(ids[i])
    }

    // ── 标题 ──
    Text {
        id: header
        anchors {
            top: parent.top
            topMargin: 14
            horizontalCenter: parent.horizontalCenter
        }
        text: "Stage"
        color: Qt.rgba(1, 1, 1, 0.38)
        font { pixelSize: 11; weight: Font.DemiBold; letterSpacing: 1.5 }
    }

    // ── 卡片堆叠区 ──
    // 背景完全透明（用户要求）：无背板、无霜层，只留悬浮卡片本身。
    // 左右锚到"内容列"（窗宽减两侧溢出余量 = PANEL_WIDTH）；上下留出
    // 辉光余量（首/末卡的辉光外扩 ~19px 不出窗缘）。
    Item {
        id: cards
        anchors {
            top: header.bottom
            topMargin: 18
            left: parent.left
            leftMargin: StageGeo.CARD_OVERFLOW_MARGIN
            right: parent.right
            rightMargin: StageGeo.CARD_OVERFLOW_MARGIN
            bottom: parent.bottom
            bottomMargin: 18
        }

        // 指针监测：光标离开整个堆叠区（卡片之间的空隙/露边）时统一收悬停
        MouseArea {
            id: fanArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            z: -1
            onContainsMouseChanged: {
                if (!containsMouse && root.hoveredKey !== "")
                    root._cardHover(root.hoveredKey, false)
            }
        }

        // 滚轮滚动（无滚动条，底部提示条给出位置与总数）
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(wheel) {
                if (root._maxScroll <= 0)
                    return
                // 每格滚轮 ≈ 半个卡槽，方向与内容一致（上滚=往前翻）
                const step = root._lastPitch * 0.5
                const next = Math.max(0, Math.min(root._maxScroll,
                    root.scrollOffset
                        - wheel.angleDelta.y / 120 * step))
                if (next !== root.scrollOffset)
                    root.scrollOffset = next
            }
        }

        // 滚动视口：只裁**上下**（滚动方向），左右各放宽 GLOW_PAD——悬停
        // 辉光外扩 ~14px 超出卡面 inset，整条 clip 会把辉光侧边切掉
        //（窗口的 CARD_OVERFLOW_MARGIN 余量就是给辉光留的，别在内层先切）。
        // slot 坐标系 = 视口（slotX 已含 GLOW_PAD 补偿，视觉位置不变）。
        Item {
            id: cardsViewport
            x: -StageGeo.GLOW_PAD
            y: 0
            width: cards.width + StageGeo.GLOW_PAD * 2
            height: cards.height
            clip: true

            Repeater {
                id: cardRepeater
                model: cardModel

            delegate: Item {
                id: slot

                // 字段清单单一出处：stage-groups.mjs 的 CARD_FIELDS
                required property string appKey
                required property string targetId
                required property int pid
                required property string appName
                required property string title
                required property string iconSource
                required property int count
                required property string idsJson

                // 统一等比缩放：设计宽 = 列宽 − inset，slotX 按缩放居中
                //（聚焦/退位与 adaptive 缩小共用本机制）
                property real slotScale: 1
                property real slotX: StageGeo.CARD_X_INSET
                property alias cardItem: card
                property bool dimmed: false
                // 首拍落位守卫：delegate 诞生在 y=0（列顶），若首赋值也走
                // Behavior，新收编的卡会从列顶滑进槽位——窗口正向槽位飞、
                // 卡片却先出现在最上面再滑下来 = "收起时先到顶再突兀移动"
                // （首拍直接落位，后续重排照常动画）。
                property bool placed: false
                // 共享透视的地平线偏移：卡中心相对滚动视口中心的 y 距离
                //（全部属性可通知，绑定随滚动/布局动画逐帧刷新）
                readonly property real planeYOff:
                    (y + height / 2) - cardsViewport.height / 2
                // 视口边缘渐隐：滚动时跨上/下缘的卡淡出而不是被 clip 硬切
                //（侧栏透明背景下硬切边特别刺眼，实测）。绑定 slot.y =
                // 随滚动/布局动画逐帧跟随，无需手动刷新。
                readonly property real edgeFade: {
                    const h = StageConfigService.cardHeight
                    const fade = h * 0.45
                    const top = (slot.y + h) / fade
                    const bot = (cards.height - slot.y) / fade
                    return Math.max(0, Math.min(1, Math.min(top, bot)))
                }
                opacity: (dimmed && StageConfigService.focusDim ? 0.72 : 1)
                    * edgeFade
                width: cards.width - StageGeo.CARD_WIDTH_INSET
                height: StageConfigService.cardHeight
                x: slotX
                scale: slotScale
                transformOrigin: Item.TopLeft
                // 平滑过渡：牌堆重排/聚焦/退位/滚轮翻动全部带阻尼。
                // ⚠️ 全属性同一时长——聚焦时"退让缩小"与"主体放大"必须
                // 同拍起止，分两种时长会看出先缩后放的两段感（实测踩过）。
                // y 的 Behavior 只对已落位的卡生效（见 slot.placed）。
                Behavior on y { enabled: slot.placed; NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
                Behavior on x { NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
                visible: true

                StageCard {
                    id: card
                    anchors.verticalCenter: parent.verticalCenter
                    appKey: slot.appKey
                    targetId: slot.targetId
                    pid: slot.pid
                    appName: slot.appName
                    title: slot.title
                    iconSource: slot.iconSource
                    count: slot.count
                    idsJson: slot.idsJson
                    perspectiveYOff: slot.planeYOff
                    // 活体流判定源：窗口侧聚焦键（与布局同源，无头调试可触达）
                    focusKey: root.hoveredKey
                    onHovered: function(over) { root._cardHover(slot.appKey, over) }
                    // 对账就地换主（行移动/字段更新不重建 delegate）时，
                    // containsMouse 不变 → 没有 enter/leave 事件——悬停追踪
                    // 必须跟着新键重报，否则"辉光但不放大"
                    onAppKeyChanged: {
                        if (card.isHovered)
                            root._cardHover(slot.appKey, true)
                    }
                    onEngageClicked: root.engageCard(slot)
                    onCloseAllRequested: root.closeGroup(slot.idsJson)
                }
            }
        }
        }

        // 空态提示
        Text {
            visible: root.sideGroups.length === 0
            width: parent.width - 24
            x: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "没有其他窗口\n切换窗口后这里显示卡片"
            color: Qt.rgba(1, 1, 1, 0.30)
            font.pixelSize: 11
            topPadding: 18
        }

        // ── 底部提示条：位置点（当前视口内高亮）+ 总窗数（用户要求的
        // "小小缩略提示"）。不随滚动移动；点数封顶 12，更多以省略号收尾。
        // z 抬到所有卡之上（卡的 slot.z ≥ 1，默认 0 会被滚过来的卡盖住）。
        Rectangle {
            visible: cardModel.count > 0
            z: 1000
            anchors {
                bottom: parent.bottom
                bottomMargin: 2
                horizontalCenter: parent.horizontalCenter
            }
            width: indicatorRow.implicitWidth + 16
            height: 20
            radius: 10
            color: Qt.rgba(0.05, 0.07, 0.12, 0.55)
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.10)

            Row {
                id: indicatorRow
                anchors.centerIn: parent
                spacing: 5

                Repeater {
                    model: Math.min(cardModel.count, 12)

                    Rectangle {
                        required property int index
                        // Row 默认顶对齐——5px 圆点必须显式垂直居中才和
                        // 文字基线对齐（实测跑上去过）
                        anchors.verticalCenter: indicatorRow.verticalCenter
                        // 卡与视口的交集判定（slot.y 已含滚动偏移）
                        readonly property bool inView: {
                            const s = cardRepeater.count > index
                                ? cardRepeater.itemAt(index) : null
                            return s ? (s.y + s.height > root.scrollOffset - 2
                                && s.y < root.scrollOffset + cards.height + 2)
                                : false
                        }
                        width: 5
                        height: 5
                        radius: 3
                        color: inView
                            ? Qt.rgba(0.62, 0.80, 1.0, 0.95)
                            : Qt.rgba(1, 1, 1, 0.28)
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                    }
                }

                Text {
                    visible: cardModel.count > 12
                    anchors.verticalCenter: indicatorRow.verticalCenter
                    text: "…"
                    color: Qt.rgba(1, 1, 1, 0.40)
                    font.pixelSize: 10
                }

                Text {
                    text: root.totalWindows + " 窗"
                    color: Qt.rgba(1, 1, 1, 0.60)
                    font { pixelSize: 10; weight: Font.DemiBold }
                }
            }
        }

        onHeightChanged: {
            root.layoutCards()
            root._geometryRepublish.restart()
        }
    }

    // ── 布局排布 ──
    // 布局参数全部来自 StageConfigService（设置页可调）；矩形发布与视图
    // 自适应布局入口（adaptive 模式；deck 的渐进堆叠在 layoutCards /
    // publishSimulatedLayout 里直接调 StageGeo.scrollLayout）。⚠️ 两处 count
    // 语义不同：视图用模型行数（含前台最小化保卡的组），发布用
    // groups.length（整组排除），不能混。
    function _layout(count) {
        return StageGeo.adaptiveLayout(cards.height, count,
            StageConfigService.cardHeight, StageConfigService.cardSpacing,
            StageConfigService.centerCards)
    }

    // 悬停聚焦键（组 key）：悬停卡原位放大置顶，其余卡从原位向两侧退避
    property string hoveredKey: ""

    // ── 滚动状态（scroll 模式）：滚轮驱动，clamp 由 layoutCards 回填 ──
    property real scrollOffset: 0
    property real _lastPitch: 0     // 上一轮布局的槽距（滚轮步进用）
    property real _maxScroll: 0     // contentH − 视口高（0 = 不可滚）
    onScrollOffsetChanged: {
        layoutCards(true)
        _scrollRepublish.restart()
    }
    // 滚动停止后重发布目标矩形（去抖 120ms：滚动途中窗口不收编，
    // 矩形只在与屏幕卡面对齐时才有意义）
    property Timer _scrollRepublish: Timer {
        interval: 120
        onTriggered: root.publishSimulatedLayout("")
    }

    // 高度/屏幕变化后 targets 文件随动（round35 NEW-10）：onHeightChanged
    // 只重排视图不重发布，分辨率切换/open 瞬间首发布会拿到未定高度——
    // 去抖 120ms 等高度稳定后补一份新鲜矩形（与 _scrollRepublish 同款）
    property Timer _geometryRepublish: Timer {
        interval: 120
        onTriggered: root.publishSimulatedLayout("")
    }

    // ── 悬停驻留（hover intent）：滑动途中只亮卡不重排，停稳才聚焦 ──
    // 跳卡感的根源：指针一进卡，邻卡立刻退让 → 指针穿越被让出的空档、
    // 落在更远的卡上 = "跨过一张"。驻留期内布局不动（卡片全静止、指针
    // 平滑掠过每张卡、各自即时亮辉光），停稳 hoverDwellDelay 后才应用
    // 聚焦排布（macOS 的悬停意图模式）。0 = 立即聚焦（旧手感）。
    property string _dwellKey: ""
    property Timer _hoverDwellTimer: Timer {
        interval: Math.max(0, StageConfigService.hoverDwellDelay)
        onTriggered: {
            const key = root._dwellKey
            root._dwellKey = ""
            if (key === "" || root.hoveredKey === key)
                return
            for (let i = 0; i < cardRepeater.count; i++) {
                const s = cardRepeater.itemAt(i)
                if (!s || s.appKey !== key)
                    continue
                // 到点时指针必须仍停在这张卡上（中途划走 = 驻留作废）
                if (s.cardItem.isHovered) {
                    root.hoveredKey = key
                }
                return
            }
        }
    }

    // 悬停锚定 = 卡片**当前视觉位置**（防抖 + 防滑出指针）；松开悬停时
    // 整列回基础槽位（指针已不在卡上，安全）。⚠️ 不要做"停稳后归位"——
    // 端点卡的漂移位离基础槽位可达 300+px（对面端点聚焦时它被退到
    // y≈-41/10），归位滑动会把卡片从指针下方带走 → 悬停丢失 → 全部弹回
    //（"从外面放到第一/最后一张只高亮不退避"的 kill 实锤）。
    function _cardHover(key, over) {
        let m = ""
        for (let i = 0; i < cardRepeater.count; i++) {
            const s = cardRepeater.itemAt(i)
            if (s && s.cardItem.appKey === key) {
                m = " mouse=" + s.cardItem.mousePos
                break
            }
        }
        console.info("[StageSidebar] hover call key=" + key
            + " over=" + over + " cur=" + root.hoveredKey + m)
        if (over) {
            if (root.hoveredKey !== key) {
                root._dwellKey = key
                root._hoverDwellTimer.restart()
            }
        } else {
            if (root._dwellKey === key) {
                root._dwellKey = ""
                root._hoverDwellTimer.stop()
            }
            if (root.hoveredKey === key) {
                root.hoveredKey = ""
            }
        }
    }

    // 无头验证钩子：绕过驻留直接设/清悬停键（模拟"已停稳"）
    function debugHover(index, over): string {
        if (index < 0 || index >= cardModel.count)
            return JSON.stringify({ error: "bad index", n: cardModel.count })
        const key = cardModel.get(index).appKey
        root._dwellKey = ""
        root._hoverDwellTimer.stop()
        root.hoveredKey = over ? key : ""
        return JSON.stringify({ key: key, hovered: root.hoveredKey })
    }

    // 无头几何快照：窗口/堆叠区高度 + 每张卡的当前 y/scale/z（排障用）
    function debugGeom(): string {
        const slots = []
        for (let i = 0; i < cardRepeater.count; i++) {
            const s = cardRepeater.itemAt(i)
            if (!s)
                continue
            slots.push({ app: s.appKey, y: Math.round(s.y),
                scale: Math.round(s.slotScale * 100) / 100, z: s.z,
                x: Math.round(s.x) })
        }
        return JSON.stringify({ winH: Math.round(root.height),
            cardsH: Math.round(cards.height), hovered: root.hoveredKey,
            scroll: Math.round(root.scrollOffset),
            maxScroll: Math.round(root._maxScroll),
            totalWin: root.totalWindows, order: root._groupOrder,
            slots: slots })
    }

    onHoveredKeyChanged: layoutCards()

    // 高度纪元：窗口尺寸变化的那一轮布局禁用 hoverY 锚定——启动时首轮
    // 布局常在窗口未定尺寸时跑（cards.height 短），锚定会把垃圾位置
    // 冻结成"永远回不去"（后续每轮都以它为锚）。高度稳定后恢复锚定。
    property real _layoutHeight: -1

    // scrollPass = 滚动轮次：全员平移（悬停卡不冻结——卡片从指针下滑走、
    // 悬停自然消失，聚焦布局随即回落基础态；冻结反而会让悬停卡卡死在半路）
    function layoutCards(scrollPass) {
        const n = cardModel.count
        if (n === 0)
            return
        if (StageConfigService.layoutMode === "scroll") {
            let h = -1
            if (!scrollPass) {
                for (let i = 0; i < n; i++) {
                    if (cardModel.get(i).appKey === root.hoveredKey) {
                        h = i
                        break
                    }
                }
                // 悬停键不在模型里 = 该组已离开侧栏（被点开）但指针没动——
                // 卡片自身辉光（MouseArea 还悬着）而布局回基础态 = "辉光但
                // 不放大"。自愈：清掉追踪键；delegate 行字段就地换主时由
                // onAppKeyChanged 重报悬停
                if (root.hoveredKey !== "" && h < 0) {
                    console.warn("[StageSidebar] hovered key left sidebar: "
                        + root.hoveredKey)
                    root.hoveredKey = ""
                }
            }
            const heightEpochChanged = cards.height !== root._layoutHeight
            root._layoutHeight = cards.height
            if (!scrollPass && (h >= 0 || root.hoveredKey !== ""
                    || heightEpochChanged))
                console.info("[StageSidebar] layout n=" + n + " h=" + h
                    + " key=" + root.hoveredKey + " cardsH="
                    + Math.round(cards.height) + " yProp="
                    + (h >= 0 && cardRepeater.itemAt(h)
                        ? Math.round(cardRepeater.itemAt(h).y) : "-")
                    + " yVisual="
                    + (h >= 0 && cardRepeater.itemAt(h)
                        ? Math.round(cardRepeater.itemAt(h)
                            .mapToItem(cards, 0, 0).y) : "-"))
            const lay = StageGeo.scrollLayout(cards.height, n, {
                cardHeight: StageConfigService.cardHeight,
                spacing: StageConfigService.cardSpacing,
                scroll: root.scrollOffset,
                retreat: StageConfigService.deckSidePeek,
                hoveredIndex: h,
                // 锚定**视觉**位置（mapToItem 含在途动画），不是属性 y——
                // 飞行途中两者不一致，锚属性值会让卡片从指针下方滑走。
                // 聚焦矩形从视觉位置由 TopLeft 向外生长，悬停点必然仍在卡内。
                // 高度刚变的那轮除外（纪元守卫见 _layoutHeight 注释）
                hoverY: (!heightEpochChanged && h >= 0
                    && cardRepeater.itemAt(h))
                    ? cardRepeater.itemAt(h).mapToItem(cards, 0, 0).y
                    : undefined,
            })
            for (let i = 0; i < n; i++) {
                const slot = cardRepeater.itemAt(i)
                if (!slot)
                    continue
                // ⚠️ 悬停卡的 y 冻结（跳过赋值，scrollPass 除外）：聚焦
                // 期间任何 y 位移都会把卡从指针下方带走 = kill 循环（五轮
                // 排查的最终结论）。缩放/x 的变化是 TopLeft 外扩（区域只
                // 向外长，卡内指针数学上不可能被挤出）；y 是唯一危险的
                // 自由度，冻结到悬停解除。滚动轮次全员平移（见函数头）。
                if (i !== h) {
                    // 首拍落位：placed 尚为 false 时 Behavior 禁用，y 直接
                    // 跳到槽位（新卡不播"列顶→槽位"滑入）；写完置位，后续
                    // 重排照常动画。
                    slot.y = lay.positions[i] ?? 0
                    slot.placed = true
                }
                slot.slotScale = lay.scales[i] ?? 1
                // +GLOW_PAD：slot 在放宽的视口里，补偿视口 x 偏移保持视觉位置
                slot.slotX = (cards.width - slot.width * slot.slotScale) / 2
                    + StageGeo.GLOW_PAD
                slot.z = lay.zs[i] ?? 1
                // 压暗走 dimmed 属性（opacity 由 dimmed × edgeFade 绑定合成）
                slot.dimmed = lay.dims[i] ? true : false
                slot.visible = true
            }
            // 滚动状态回填：槽距（滚轮步进）+ 上限（clamp；卡数变化后
            // 收敛滚动位置，超限回落触发一轮再布局）
            root._lastPitch = lay.pitch
            root._maxScroll = lay.scrollMax
            if (root.scrollOffset > root._maxScroll)
                root.scrollOffset = root._maxScroll
            return
        }
        const lay = _layout(n)
        for (let i = 0; i < n; i++) {
            const slot = cardRepeater.itemAt(i)
            if (!slot)
                continue
            // 首拍落位（scroll 分支同款：placed 为 false 时 Behavior 禁用）
            slot.y = lay.positions[i] ?? 0
            slot.placed = true
            slot.slotScale = lay.scale
            slot.slotX = (cards.width - slot.width * lay.scale) / 2
                + StageGeo.GLOW_PAD
            slot.visible = true
            slot.z = n - i
            slot.dimmed = false
        }
    }
    onHeightChanged: {
        layoutCards()
        _geometryRepublish.restart()
    }

    // ── 缩略图请求节奏（照抄 Overview：80ms 一拍、每拍 ≤3 张） ──
    property var _thumbRequestQueue: []

    property Timer _thumbRequestPacer: Timer {
        interval: 80
        repeat: true
        onTriggered: {
            if (!root.open || root._thumbRequestQueue.length === 0) {
                stop()
                return
            }
            for (let i = 0; i < 3 && root._thumbRequestQueue.length > 0; i++)
                WindowService.requestThumbnail(root._thumbRequestQueue.shift())
        }
    }

    // 缩略图是"收编快照"语义（同 macOS）：只在卡片出现/切换主角时拍新图，
    // 不做周期刷新——周期换图正是侧栏周期闪烁的根源。每组只拍代表窗口。
    function _queueAllThumbnails() {
        const seen = ({})
        const queue = []
        const groups = root.sideGroups
        for (let i = 0; i < groups.length; i++) {
            // 最小化窗口截到黑帧：绝不请求，用既有快照或占位符
            const rep = WindowService.windowById(groups[i].targetId)
            if (rep?.toplevel?.minimized)
                continue
            const id = groups[i].targetId
            if (!seen[id]) {
                seen[id] = true
                queue.push(id)
            }
        }
        root._thumbRequestQueue = queue
        _thumbRequestPacer.restart()
    }

    onOpenChanged: {
        if (open) {
            _prevActiveId = WindowService.activeWindowId
            _queueAllThumbnails()
            publishSimulatedLayout("")
        } else {
            _thumbRequestPacer.stop()
            root._thumbRequestQueue = []
        }
    }

    onSideGroupsChanged: syncCards()

    // 初始求值不触发 changed 信号，挂载时先对账一次
    Component.onCompleted: syncCards()

    // ── 增量卡片模型（按应用分组） ──
    // sideGroups 是派生数组，任何窗口元数据变化都会生成新数组 → Repeater
    // 整表重建 → 所有卡片重播入场动画（周期"刷新"的根源）。syncCards 把它
    // 对账进 ListModel：字段就地 setProperty、只有新增/消失的组才创建/销毁
    // delegate，入场动画只在真新卡上播一次。对账计划由 stage-groups.mjs 的
    // planModelSync 纯函数算出，这里只执行（删除 → 更新 → 追加 → 移动）。
    ListModel { id: cardModel }

    // 总窗数（各组 ×N 之和）——底部提示条显示
    property int totalWindows: 0

    function syncCards() {
        // 换位提交门：预测顺序（派发时只喂了发布）在这里等记录确认——退位
        // 组键已进 sideGroups 的这一次对账，把 applySwapOrder 转正进顺序表，
        // 与下面的 desired 计算同拍（顺序表变更与模型变更原子落地，中间
        // 对账永远看到的都是自洽的 [旧序+旧记录] 或 [新序+新记录]）。
        if (root._pendingSwaps.length > 0) {
            const committed = StageGroups.commitDueSwaps(root._groupOrder,
                root._pendingSwaps,
                root.sideGroups.map(g => g.key), Date.now())
            root._groupOrder = committed.order
            root._pendingSwaps = committed.swaps
        }
        // desired 按顺序表排序——点击换位（applySwapOrder）由此落到可见
        // 模型上（历史 bug：排序只在发布路径，卡片从未真换过位，窗口飞向
        // 被点槽位而卡片留在 records 顺序位 = 用户看到的"飞错位置再滑动"）
        const desired = StageGroups.buildModelRows(
            StageGroups.sortByOrder(root._groupOrder, root.sideGroups))
        // 组顺序表对账：剪除已消失 + 补全新组（只 prune 会退化成空表，
        // 见 stage-groups.mjs 的 mergeOrder 注释）
        const liveKeys = desired.map(d => d.appKey)
        root._groupOrder = StageGroups.mergeOrder(root._groupOrder,
            liveKeys)
        const current = []
        for (let i = 0; i < cardModel.count; i++)
            current.push(cardModel.get(i))
        const plan = StageGroups.planModelSync(current, desired)
        for (let r = 0; r < plan.removes.length; r++)
            cardModel.remove(plan.removes[r])
        for (let u = 0; u < plan.updates.length; u++) {
            const upd = plan.updates[u]
            for (const field in upd.fields)
                cardModel.setProperty(upd.row, field, upd.fields[field])
        }
        for (let a = 0; a < plan.appends.length; a++)
            cardModel.append(plan.appends[a])
        for (let m = 0; m < plan.moves.length; m++)
            cardModel.move(plan.moves[m].from, plan.moves[m].to, 1)
        _queueAllThumbnails()
        let total = 0
        for (let i = 0; i < cardModel.count; i++)
            total += cardModel.get(i).count
        root.totalWindows = total
        layoutCards()
        publishSimulatedLayout("")
    }

    // 输入遮罩：只有常驻条区域可交互，两侧溢出余量（辉光渲染区）的
    // 点击穿透到桌面/窗口（BarWindow 同款手法）
    Item {
        id: stripHitRegion
        x: StageGeo.CARD_OVERFLOW_MARGIN
        y: 0
        width: StageGeo.PANEL_WIDTH
        height: root.height
        visible: false
    }
    mask: Region {
        Region { item: stripHitRegion }
    }
}
