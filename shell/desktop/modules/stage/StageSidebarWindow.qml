import QtQuick
import Quickshell
import Quickshell.Wayland
// ⚠️ ScreencastingRequest 是本模块的类型（活体缩略图流开单窗口用）——
// 曾被"未使用"审计误删导致 shell crash-loop（is not a type），勿再删
import org.kde.taskmanager
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import qs.desktop.modules.applauncher
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
    // 全屏透明浮层（2026-09-30 用户定稿"完完全全不用侧边栏，卡片就是
    // 卡片"）：无保留区、无边框——悬停放大/倾斜投影/扇叠背板/拖拽越界
    // 全都不会再被窗缘裁掉（旧 280px 窗实测裁掉扇叠）。输入只挡卡面
    //（mask 只罩卡片实际范围，文件尾），其余区域点击穿透到桌面。
    // ⚠️ reserveStrip 键废弃（全屏浮层天然无保留区），仅为配置兼容保留。
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    property bool open: false

    // 启动台打开时整窗隐藏：全屏浮层若留在原位会盖在启动台内容上
    //（旧窄条不重叠所以无所谓，全屏必须躲）
    visible: open && !AppLauncherService.open
    color: "transparent"
    // 常驻侧（stage-config side）：right 时卡片列锚屏幕右缘（内容层
    // 各自镜像：StageCard/深度渐变/图标排）；窗体本身恒全屏
    readonly property bool rightSide: StageConfigService.side === "right"
    anchors { top: true; bottom: true; left: true; right: true }

    // ── 舞台视角的活动窗 ──
    // 桥的活动窗在 shell 覆盖层（启动台）拿走焦点时会变空——但桌面上的
    // 应用一个都没动。此刻冻结"最后一个真实活动应用"：活动组照样不出
    // 卡（否则窗口还在桌面、卡却先冒出来＝幽灵卡），交换/收编路径也不
    // 跑。覆盖层关掉后焦点回到哪个应用就正常跟随哪个。
    readonly property bool shellOverlayActive: AppLauncherService.open
    property string stageActiveId: ""
    // 桌面聚焦期间的"扣卡"：true 时 stageActiveId 保持冻结（活动组的卡
    // 不先冒出来），收编派发最小化的同一拍（或 600ms 兜底）释放
    property bool _deskHoldActive: false

    // ── 分组：当前桌面上除"活动应用整组"外的窗口，按应用堆叠 ──
    // （分组规则见 stage-groups.mjs：同 desktopId / rawAppId / 同 pid 归
    // 一张卡；代表窗口优先未最小化、其次已有缩略图的。）
    // macOS 语义：前台应用整体不打折为卡——只排除活动窗本身的话，主窗
    // 在前、同组子窗的卡还挂在栏里（用户实测踩过）。
    // ── 自由组合层 ──
    // overrides: { handleId: groupKey }——用户把不同应用的窗口拖进同一
    // 张卡。键用 KWin internalId（窗口生命周期内稳定，shell 重启不丢）；
    // 落盘 stage/merges.json，syncCards 尾部剪枝死窗口项。
    readonly property string _mergesPath: Quickshell.stateDir + "/stage/merges.json"
    property var _mergeOverrides: ({})
    // 拖拽合并手势的当前候选（被拖卡压在谁上面）；"" = 无（走换位）
    property string _dropMergeKey: ""

    function _effKey(rec) {
        // 空守卫在此单点收口：调用点常拿 windowById 的瞬时结果（窗口刚
        // 关 = undefined），groupKeyOf 解引用 r.handleId 会抛 TypeError
        return rec ? StageGroups.groupKeyOf(rec, root._mergeOverrides) : ""
    }

    function _saveMerges() {
        JsonConfigStore.writePath(root._mergesPath, JSON.stringify(
            { version: 1, merges: root._mergeOverrides }))
    }

    // 拖 A 卡放到 B 卡上 = 合并（B 的组键收养 A 的全部窗口）
    // 返回是否真并了组（no-op = from 组已无 record）——调用方据此复位
    // 被吞卡的 engaging（否则它停在淡出态永久隐身，热区还活着）
    function mergeGroups(fromKey, toKey): bool {
        const next = StageGroups.applyMerge(root._mergeOverrides,
            WindowService.records || [], fromKey, toKey)
        if (next === root._mergeOverrides)
            return false
        root._mergeOverrides = next
        root._saveMerges()
        syncCards()   // 顺序表里消失的键由 mergeOrder 剪掉
        console.info("[StageSidebar] merge " + fromKey + " -> " + toKey)
        return true
    }

    // 右键合并卡 = 拆散回各自的应用卡。拆出的新卡做"迸开"入场：
    // 错峰（每张错 70ms）从窗口侧滑入——同时冒出来是死板感（用户：
    // "拆分动画没有灵动的感觉"）
    function splitGroupByKey(key) {
        const beforeKeys = ({})
        for (let i = 0; i < cardModel.count; i++)
            beforeKeys[cardModel.get(i).appKey] = true
        const next = StageGroups.splitGroup(root._mergeOverrides,
            WindowService.records || [], key)
        if (next === root._mergeOverrides)
            return
        root._mergeOverrides = next
        root._saveMerges()
        syncCards()
        _burstNewCards(beforeKeys)
        console.info("[StageSidebar] split " + key)
    }

    property var _burstQueue: []   // [{ card: StageCard, at: ms }]
    property Timer _burstTimer: Timer {
        interval: 45
        repeat: true
        onTriggered: {
            const now = Date.now()
            const remaining = []
            for (let i = 0; i < root._burstQueue.length; i++) {
                const item = root._burstQueue[i]
                if (!item.card)
                    continue   // delegate 动画窗口内被销毁（组又变了）
                if (now >= item.at)
                    item.card.shown = true
                else
                    remaining.push(item)
            }
            root._burstQueue = remaining
            if (remaining.length === 0)
                stop()
        }
    }

    function _burstNewCards(beforeKeys) {
        let k = 0
        for (let i = 0; i < cardRepeater.count; i++) {
            const s = cardRepeater.itemAt(i)
            if (!s || beforeKeys[s.appKey])
                continue
            const c = s.cardItem
            if (!c)
                continue
            c.shown = false   // 压回入场起点（Component.onCompleted 已置 true）
            root._burstQueue.push({ card: c, at: Date.now() + k * 70 })
            k++
        }
        if (k > 0)
            root._burstTimer.restart()
    }

    readonly property var sideGroups: {
        WindowService.revision
        root.stageActiveId
        root._deskHoldActive
        const activeRec = WindowService.windowById(root.stageActiveId)
        return StageGroups.decorateGroups(
            StageGroups.groupRecords(WindowService.records || [], {
                overrides: root._mergeOverrides,
                desktopId: WindowService.currentDesktopId,
                // requirePid 与发布侧对齐：无 pid 但有 caption 的表面
                //（桥 includeWindow 放行）能进 records，视图成卡会把它
                // 计入 count、发布侧却无矩形无槽位——两侧 count 差 1，
                // auto 路径布局整体错位
                requirePid: true,
                skipWindowId: root.stageActiveId,
                excludeKey: activeRec ? root._effKey(activeRec) : "",
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
        const key = root._effKey(rec)
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const ids = []
        for (let i = 0; i < records.length; i++) {
            const r = records[i]
            if (r.toplevel?.minimized)
                continue
            if (root._effKey(r) !== key)
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
    function captureAndDemote(ids, excludeKey, delayed, captureDelayMs) {
        for (let i = 0; i < ids.length; i++)
            WindowService.requestThumbnail(ids[i])
        root._pendingMinimize = ids
        root._pendingPublishExcludeKey = excludeKey
        if (delayed) {
            _captureThenMinTimer.interval = captureDelayMs > 0
                ? captureDelayMs : StageConfigService.demoteCaptureDelay
            _captureThenMinTimer.restart()
        } else {
            publishSimulatedLayout(excludeKey)
            _minimizeDispatchTimer.restart()
        }
    }

    // 延迟路径的发布排除键（captureAndDemote 落下，计时器拍使用）。
    // 旧实现硬编码 ""＝自动排除活动组——桌面收编时被扣卡冻结的活动组
    // 正是要收编的对象，它的矩形被排除后不更新，特效读到上一轮的陈旧
    // 矩形：窗口飞向旧槽位、卡出现在新槽位（实测"飞到第一张卡位置，
    // 第三张卡才突然出现"）。
    property string _pendingPublishExcludeKey: ""

    property var _pendingMinimize: []
    property Timer _minimizeDispatchTimer: Timer {
        interval: StageConfigService.demoteDispatchDelay
        onTriggered: {
        const t = root._pendingMinimize
        root._pendingMinimize = []
        // 原子整组最小化：N 窗一条命令一个桥轮询拍内落地（逐窗排队会把
        // 收编管线拖到 N*50ms，比 toggle 防抖还长——快速第二击插进管线
        // 中途的"卡出现、程序没收回去"即此，实测复现过）
        WindowService.minimizeGroup(t, true)
        // 最小化已派发＝窗口开始飞进卡：此刻放出被扣住的卡（同拍）
        if (root._deskHoldActive) {
            root._deskHoldActive = false
            root._deskHoldReleaseTimer.stop()
            root.stageActiveId = WindowService.activeWindowId
        }
        }
    }

    // 桌面聚焦的"扣卡"兜底释放：没有收编走（自动收编关/无目标）时，
    // 别把活动组排除一直扣着
    property Timer _deskHoldReleaseTimer: Timer {
        interval: 600
        onTriggered: {
            if (root._deskHoldActive) {
                root._deskHoldActive = false
                root.stageActiveId = WindowService.activeWindowId
            }
        }
    }
    property Timer _captureThenMinTimer: Timer {
        interval: StageConfigService.demoteCaptureDelay
        onTriggered: {
            root.publishSimulatedLayout(root._pendingPublishExcludeKey)
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
        const activeId = WindowService.activeWindowId
        if (!activeId)
            // 空活动窗＝桌面聚焦：此刻在途的往往是桌面收编批次
            //（focus 路径 150ms 起拍、330ms 才派发），取消它＝最小化
            // 永远不落地（"卡出现了程序没收回去"的根因，实测竞态差
            // ~10ms）。真正的属主取消留给有新活动窗的分支。
            return
        // 显示桌面开关属主判定：活动窗在开关集里＝桌面收编管线正在收
        // 它（toggle 连活动窗一起收），autoMin 的"保护活动应用"语义会把
        // 批次打散、留下 armed-but-out 残局（collected 挂着但窗没收，
        // 实测复现）——让位。
        if (root.deskCollectedIds.indexOf(activeId) >= 0)
            return
        const activeRec = WindowService.windowById(activeId)
        const activeGroup = activeRec ? root._effKey(activeRec) : ""
        // 外科手术式作废：只从在途批次剔除"现在成了活动应用"的窗口
        //（round35 的病＝刚展开的应用被迟到批次收走），其余保留——
        // 桌面收编/整组退位批次不该被一次无关的激活周期整批清掉。
        if (root._pendingMinimize.length > 0 && activeGroup !== "") {
            root._pendingMinimize = root._pendingMinimize.filter(id => {
                const r = WindowService.windowById(id)
                return !(r && root._effKey(r) === activeGroup)
            })
            if (root._pendingMinimize.length === 0) {
                root._captureThenMinTimer.stop()
                root._minimizeDispatchTimer.stop()
            }
        }
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
            if (root._effKey(r) === activeGroup)
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
            // 覆盖层（启动台）拿走焦点：活动窗变空但桌面应用没动——
            // 冻结舞台活动窗、不走任何切换/收编路径。
            if (current === "" && root.shellOverlayActive) {
                root._desktopFocusTimer.stop()
                return
            }
            if (current === "" && (WindowService.kwinActiveId === ""
                    || WindowService.kwinActiveDesktop)) {
                // 桌面聚焦：保持活动组排除（卡不先冒出来），等收编派发
                // 最小化的同一拍再放出卡（动画和谐：窗口起飞=卡出现）；
                // 若最终没有收编走（自动收编关/无目标），短延迟后照常放出
                root._deskHoldActive = true
                root._deskHoldReleaseTimer.restart()
            } else {
                root._deskHoldActive = false
                root._deskHoldReleaseTimer.stop()
                root.stageActiveId = current
                // 真实窗口被激活而桌面开关态还挂着（用户直接点了桌面上的
                // 窗，没走卡片）：交互意图＝退出显示桌面（macOS 同语义），
                // 否则下次点桌面会"惊喜"整组放出来。开关集内的窗聚焦
                //（收编中的焦点漂移）不算——它们正是要收的对象。
                if (root.deskCollectedIds.length > 0
                        && root.deskCollectedIds.indexOf(current) < 0) {
                    const cr = WindowService.windowById(current)
                    if (cr && !cr.toplevel?.minimized) {
                        root._exitDeskReveal()
                        root._cancelPendingDemote()
                        console.info("[StageSidebar] desk reveal: exit on"
                            + " direct window activation")
                    }
                }
            }
            if (root._prevActiveId && root._prevActiveId !== current) {
                if (root.hasWindowId(root._prevActiveId))
                    WindowService.requestThumbnail(root._prevActiveId)
                // 活动窗变空有三种含义，必须区分：
                // ① 焦点在桌面上（kwinActiveId 为空＝真无活动窗，或
                //    kwinActiveDesktop＝活动窗是我们自己的全屏桌面表面，
                //    点桌面后正是这种）→ 收编
                // ② 覆盖层拿走焦点（启动台）→ 上面已经 return，走不到这
                // ③ 焦点在未跟踪窗上（transient 弹窗；kwinActiveId 非空
                //    且非桌面表面）→ 什么都不做
                if (current === "") {
                    if (WindowService.kwinActiveId === ""
                            || WindowService.kwinActiveDesktop)
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
        // 同卡豁免：目标窗与退位窗已在同一张卡（同应用，或用户合并的
        // 自由组）＝整卡一起向前，无退位可言
        if (_effKey(rec) === _effKey(activeRec))
            return
        // 同应用豁免双保险（同 applyAutoMinimize）
        if (StageGroups.isSameApp(rec, activeRec,
                _appOf(demotedId), _appOf(windowId)))
            return
        // 整组同拍收编：退位应用的全部窗口一起飞回组卡
        _cancelPendingDemote()
        captureAndDemote(_demoteGroupIds(demotedId),
            root._effKey(activeRec), false)
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
        // 同卡豁免（合并组同卡＝无退位；同 activateWithSwap）
        if (_effKey(rec) === _effKey(activeRec))
            return
        // 同应用豁免双保险（对话框安全，与 applyAutoMinimize 同规则）
        if (StageGroups.isSameApp(rec, activeRec,
                _appOf(demotedId), _appOf(activeId)))
            return
        if (!StageGroups.isOnDesktop(rec, WindowService.currentDesktopId))
            return
        // 整组同拍收编（与 activateWithSwap 同规则）
        _cancelPendingDemote()
        captureAndDemote(_demoteGroupIds(demotedId),
            root._effKey(activeRec), false)
    }

    // ── 桌面聚焦 / 显示桌面开关（Stage Manager 语义的"收进去/放出来"）──
    // KOS 桌面图标层不可激活，点空白处后 KWin 无 activated 记录。
    // ⚠️ "无活动窗"必须去抖 150ms 且核对 kwinActiveId：XWayland 焦点交接
    //（如 wemeet 扫码小窗）与未跟踪 transient 窗都会造成空活动窗快照。
    property Timer _desktopFocusTimer: Timer {
        interval: StageConfigService.desktopFocusDebounce
        onTriggered: {
            // 点击自带 toggle 路径（DeskCenter onClicked）——同一次点击的
            // 焦点变化不该再触发第二次收编（实测：两路互相 cancel 在途
            // 批次，快速点击时状态翻车）。只兜不经过点击的聚焦转移。
            if (Date.now() - root._lastDeskToggleAt < _deskFocusYieldMs)
                return
            if (WindowService.activeWindowId === ""
                    && (WindowService.kwinActiveId === ""
                        || WindowService.kwinActiveDesktop)
                    && StageConfigService.autoMinimize)
                root._collectDesktopToStrip(true)
        }
    }

    // 缩略图失败重试：截图授权空档（kosctl install→start 间隙、守护重启）
    // 里失败的请求不会自愈，卡会永远停在图标占位符。开着侧栏时周期补拍
    // 没图的代表窗（成功即停——decorateGroups 每轮重选代表）。
    property Timer _thumbRetryTimer: Timer {
        interval: 1500
        running: root.open
        repeat: true
        onTriggered: {
            const groups = root.sideGroups
            for (let i = 0; i < groups.length; i++) {
                const g = groups[i]
                if (!g.targetId)
                    continue
                // 最小化代表窗截到黑帧（_queueAllThumbnails 同款守卫）：
                // 对它重试会把黑帧灌进缩略图缓存，占位符恶化成永久黑块
                const rep = WindowService.windowById(g.targetId)
                if (rep?.toplevel?.minimized)
                    continue
                if (!WindowService.thumbnailUrl(g.targetId))
                    WindowService.requestThumbnail(g.targetId)
            }
        }
    }

    // 显示桌面开关：DeskCenter 空区左键（经 StageModeService 信号转发）
    // 触发。第一次＝全部应用窗带动画收进卡；再点一次＝整组放出来、
    // 最后激活先前的活动窗。点击某张卡＝退出开关态（选了那个应用）。
    property var deskCollectedIds: []
    property string deskCollectedFocusId: ""
    // 最近一次 toggle 的时刻：①双击防抖——第一次的收编管线 330ms 才
    // 落地，紧接的第二击会在"窗口还没进卡"时反向恢复（用户看到的就是
    // "卡出现了、程序没收回去"）；②焦点定时器的收编在 toggle 后让路
    // 1.2s——同一次点击不该走两条收编路（互相 cancelPendingDemote 打架）。
    property real _lastDeskToggleAt: 0
    // ── 桌面开关时序链（顺序不变式：防抖 < 管线 < 撤销看门狗 < 焦点让
    // 路 < heal 静默窗——任何一项调到前一项之下都会制造新的竞态窗口）──
    readonly property int _deskToggleDebounceMs: 400  // 双击防抖
    readonly property int _deskUndoWatchMs: 900       // 撤销后迟到落地兜底
    readonly property int _deskFocusYieldMs: 1200      // toggle 后焦点定时器让路
    readonly property int _deskHealSilenceMs: 1600     // toggle 后 heal 静默窗

    // 桌面窗 id 集合（按最小化状态过滤；pid>0 且在当前桌面）——收编目标
    // 与死态复活共用同一口径。无 pid 的 KWin 内部表面不碰。
    function _desktopWindowIds(wantMinimized) {
        const currentId = WindowService.currentDesktopId
        const records = WindowService.records || []
        const out = []
        for (let i = 0; i < records.length; i++) {
            const r = records[i]
            if (!(r.pid > 0))
                continue
            if (r.toplevel?.minimized !== !!wantMinimized)
                continue
            if (StageGroups.isOnDesktop(r, currentId))
                out.push(r.windowId)
        }
        return out
    }

    // 集合里是否已有最小化落地的窗（toggle 撤销/恢复分流与 heal 判残共用）
    function _anyMinimized(ids) {
        for (let i = 0; i < ids.length; i++) {
            const r = WindowService.windowById(ids[i])
            if (r && r.toplevel?.minimized)
                return true
        }
        return false
    }

    function toggleDeskReveal() {
        if (!StageModeService.enabled || !open)
            return
        const now = Date.now()
        if (now - root._lastDeskToggleAt < _deskToggleDebounceMs)
            return
        root._lastDeskToggleAt = now
        if (deskCollectedIds.length > 0) {
            const ids = deskCollectedIds
            const focusId = deskCollectedFocusId
            // 抗打断：第二击先问窗口的真实状态再决定语义——一条都没
            // 最小化＝收编管线还没落地，这是"撤销"（窗口从未离开桌面，
            // 反向恢复只会白放一遍再收回去）；有最小化的＝正常恢复。
            // 撤销取消不掉已入桥队列的原子命令（FIFO），迟到落地由
            // _deskUndoWatchTimer 兜住。
            const anyMin = _anyMinimized(ids)
            _exitDeskReveal()
            // 杀掉在途最小化批次：迟到的派发会把刚放出来的窗口又收走
            _cancelPendingDemote()
            if (!anyMin) {
                root._deskUndoWatch = { ids: ids, focusId: focusId }
                root._deskUndoWatchTimer.restart()
                console.info("[StageSidebar] desk reveal: undo"
                    + " (pipeline in flight, " + ids.length + " window(s))")
                return
            }
            WindowService.activateGroup(ids, focusId)
            console.info("[StageSidebar] desk reveal: restore "
                + ids.length + " window(s)")
            return
        }
        if (!_collectDesktopToStrip(true)) {
            // 死角兜底（审计 🔴）：一条都没得收、开关态也没武装，但桌面
            // 语义上"已经全在卡里"（undo 看门狗窗口外迟到落地/被击杀后
            // 的遗孤最小化集）——把这次点击读作 toggle 的另一半"放出
            // 来"，否则无 targets 的点击永久无效。武装开关集：再点一次
            // 回到正常开关语义。
            const revived = _desktopWindowIds(true)
            if (revived.length > 0) {
                deskCollectedIds = revived
                deskCollectedFocusId = root.stageActiveId || revived[0]
                WindowService.activateGroup(revived,
                    deskCollectedFocusId)
                console.warn("[StageSidebar] desk reveal: revived orphaned"
                    + " minimized set (" + revived.length + " window(s))")
            }
        }
    }

    // 撤销看门狗：undo 时原子最小化命令可能已在桥队列里（取消不了），
    // 迟到落地会把窗口收进卡而开关态已清——放回来。恢复方式按焦点归属
    // 分流：用户已聚焦集外窗口时只原子还原不动焦点（activateGroup 会抢
    // 焦点，且 activationRequested 会把用户正在用的窗整组收编——审计 🟡）。
    property var _deskUndoWatch: null
    property Timer _deskUndoWatchTimer: Timer {
        interval: root._deskUndoWatchMs
        onTriggered: {
            const w = root._deskUndoWatch
            root._deskUndoWatch = null
            if (!w)
                return
            const cur = WindowService.activeWindowId
            if (cur !== "" && w.ids.indexOf(cur) < 0) {
                WindowService.minimizeGroup(w.ids, false)
                console.warn("[StageSidebar] desk undo: late minimize"
                    + " landed, restored without focus steal")
                return
            }
            const focusId = w.ids.indexOf(w.focusId) >= 0
                ? w.focusId : (cur !== "" ? cur : w.ids[0])
            WindowService.activateGroup(w.ids, focusId)
            console.warn("[StageSidebar] desk undo: late minimize landed ("
                + w.ids.length + "), restored")
        }
    }

    function _exitDeskReveal() {
        deskCollectedIds = []
        deskCollectedFocusId = ""
    }

    function _collectDesktopToStrip(recordSet) {
        if (!StageModeService.enabled || !open)
            return false
        _cancelPendingDemote() // 作废在途批次（round35 NEW-6：属主归一）
        const ids = _desktopWindowIds(false)
        // ⚠️ 撤销看门狗只在真收编时退役（移到 targets 判空之后）：无目标
        // 的空跑（undo 后迟到落地前的再点击等）先把看门狗杀了，就没人兜
        // 迟到的最小化——"全部最小化+开关未武装"的死态即此（审计 🔴）
        if (ids.length === 0)
            return false
        root._deskUndoWatch = null
        root._deskUndoWatchTimer.stop()
        if (recordSet) {
            deskCollectedIds = ids
            deskCollectedFocusId = root.stageActiveId || ids[0]
        }
        // 哨兵键：桌面收编要让**每个组**的矩形都发布（含被扣卡冻结的
        // 活动组）——publishSimulatedLayout 的空键=自动排除活动组，会把
        // 刚要收编的组排除掉，特效回落陈旧矩形。快照等待取 min(设置值,
        // 120)：桌面收编通常 1-3 扇且点击后的手感优先，120 封顶防手滑
        // 调慢；用户调低「收编快照等待」时这里跟随（不再被绕过）
        captureAndDemote(ids, "__desk-collect-no-exclude__", true,
            Math.min(StageConfigService.demoteCaptureDelay, 120))
        console.info("[StageSidebar] collapse to strip: "
            + ids.length + " window(s)")
        return true
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
                root.stageActiveId)
            if (activeRec) {
                // ⚠️ 必须是有效键（含合并 overrides）：活动窗属于用户合并
                // 组时自然键 ≠ 有效键 → 活动组不被排除 → 发布布局多一张
                // 幻影卡、全列矩形错一槽（合并组作为前台期间每次发布都
                // 错，2026-09-30 审计 🔴）
                excludeKey = root._effKey(activeRec)
                keepActiveMin = true
            }
        }
        const groups = StageGroups.sortByOrder(
            orderOverride || root._groupOrder,
            StageGroups.groupRecords(records,
                { requirePid: true, overrides: root._mergeOverrides,
                  excludeKey: excludeKey,
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
                { requirePid: true, overrides: root._mergeOverrides })
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
                // computeTargetRects 按数组下标取 lay.positions[g]——直接
                // 传 [ghostEntry] 下标恒 0，pos 算完即丢，ghost 矩形永远
                // 落最顶槽（审计 P0）。单槽位布局对象让下标 0 = ghost 槽位；
                // 只写 ghost 组的矩形，其余组保持首段发布的可见卡槽位。
                const ghostAt = Object.assign({}, ghostLay, {
                    positions: [ghostLay.positions[pos] ?? 0],
                })
                if (ghostLay.scales)
                    ghostAt.scales = [ghostLay.scales[pos]]
                root._lastCardRects = StageGeo.computeTargetRects(
                    [ghostEntry], ghostAt,
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
    // 的 applySwapOrder、syncCards 的 mergeOrder（实现都在 stage-groups.mjs）。
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

    // 把一组窗口的动画起点矩形改写为指定屏幕矩形（中心合并：被拖卡
    // 停在哪，窗口就从哪"长大"）。写进 _lastCardRects 再落盘——后续
    // 常规发布会经 prevRects 兜底把这些键保留住（活动组缺席时 hold）
    function _publishOverrideRects(windowIds, x, y, w, h) {
        let n = 0
        for (let i = 0; i < windowIds.length; i++) {
            const hid = WindowService.handleIdOf(windowIds[i])
            if (hid === "")
                continue
            root._lastCardRects[hid] = { id: hid,
                x: Math.round(x), y: Math.round(y),
                width: Math.round(w), height: Math.round(h) }
            n++
        }
        if (n > 0)
            root._writeTargetsFile()
        return n
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
            let entryIds = []
            try {
                entryIds = JSON.parse(entry.idsJson || "[]")
            } catch (e) {
                entryIds = []
            }
            const sameGroup = entryIds.indexOf(demotedId) >= 0
            if (!dRec?.toplevel?.minimized && !sameGroup
                    && !StageGroups.isSameApp(dRec, aRec,
                        _appOf(demotedId), _appOf(entry.targetId))) {
                skipDemote = false
                demotedKey = dRec ? root._effKey(dRec) : ""
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

    // ── 拖拽排序：按下位移超阈值（StageCard 内 12px）进入。被拖卡 y 直接
    // 跟手（其槽位 Behavior 在拖拽中禁用），其余卡按"预览顺序"实时让位
    //（Behavior 保持=平滑移位）；松手转正顺序表 + syncCards + 矩形重发布。
    property string dragKey: ""
    property int dragFromIndex: -1   // 被拖卡当前模型行（=可见槽序）
    property int dragToIndex: -1     // 悬停目标槽
    property real dragY: 0           // 被拖卡视觉 y（列坐标）
    property real dragGrabOffset: 0  // 抓取偏移（指针列坐标 − 卡 y）
    property real dragGrabOffsetX: 0 // 抓取偏移 x（指针列坐标 − 卡 x）
    property real dragPointerX: 0    // 指针列坐标 x（合并候选/中心区判定源）
    property real dragPointerY: 0    // 指针列坐标 y（同上——跟指针不跟卡心）

    // ── 中心合并区（拖卡向屏幕中心 = 与前台程序并组）──
    // 判定源 = 指针越过卡片列 + 缓冲；目标是当前活动窗口的有效组键
    //（活动组没有卡——它就是前台窗口本身）。armed = 有合法目标且指针
    // 在区内；被拖卡自身高亮（selfMergeHint）示意"松手即并入前台"。
    property bool _centerMergeArmed: false
    property string _centerMergeTarget: ""

    // ── 合并手势的驻留门控（拖拽 vs 并组"打架"的修法）──
    // 换位拖拽必然连续掠过别的卡（卡列里被拖卡中心几乎总落在某张卡的
    // 卡面内），即时判合并会和换位让位互相翻转布局：中心进卡→合并冻结
    // 让位→卡回到指针下→又出卡→又让位 = 无限抖动；且密列里松手十有
    // 八九压在卡上 = 误并组。规则改为：候选翻转只重启计时器、**不动
    // 布局**；中心在同一张卡上停稳 DRAG_MERGE_DWELL_MS 才"武装"
    // （高亮 + 冻结让位 + 松手即并组），武装后中心离开卡面+滞回边距
    // 才解除（恢复换位预览）。快拖永远只是换位，并组=明确停顿。
    property string _mergeCandidate: ""
    // 驻留时长走 stage-config（mergeDwellMs，设置页「合并驻留时长」可调）；
    // 滞回边距是防卡缘抖动的竞态防线，刻意不入 schema（调它只会制造抖动）
    readonly property real _mergeExitRatio: 0.2
    property Timer _mergeDwellTimer: Timer {
        interval: StageConfigService.mergeDwellMs
        onTriggered: root._mergeDwellFire()
    }

    // 驻留到点：此刻中心仍压在候选卡面上才武装（中途划走=作废）。
    // 独立成函数 = 无头钩子（debugMergeGesture）可直接触发，不走真实时钟
    function _mergeDwellFire() {
        // 三分支全打点（低频高值诊断：本轮靠它实锤"预览挤走候选卡"真因）
        if (root.dragKey === "" || root._mergeCandidate === ""
                || root._mergeCandidate === root.dragKey) {
            console.info("[StageSidebar] dwell fired-guard drag="
                + root.dragKey + " cand=" + root._mergeCandidate)
            return
        }
        const ch = StageConfigService.cardHeight
        // 复核跟指针（与候选检测同源）+ 基础槽位（恒定坐标系）
        const py = root.dragPointerY
        const lay = root._dragBaseLayout(cardRepeater.count)
        for (let i = 0; i < cardRepeater.count; i++) {
            const s = cardRepeater.itemAt(i)
            if (s && s.appKey === root._mergeCandidate) {
                const top = lay.positions[i] ?? 0
                if (py >= top && py <= top + ch) {
                    root._dropMergeKey = root._mergeCandidate
                    root._mergeCandidate = ""
                    console.info("[StageSidebar] merge armed on "
                        + root._dropMergeKey)
                    layoutCards()   // 冻结让位 + 目标高亮
                } else {
                    console.info("[StageSidebar] dwell fired-offcard pY="
                        + Math.round(py) + " rect=" + Math.round(top)
                        + ".." + Math.round(top + ch))
                }
                return
            }
        }
        console.info("[StageSidebar] dwell fired-noslot cand="
            + root._mergeCandidate)
    }

    function _beginCardDrag(slot, index, sceneX, sceneY) {
        if (root.dragKey !== "" || slot.cardItem.engaging)
            return
        // 驻留定时器一并作废：按下后 12px 内进拖拽时驻留可能还在跑，
        // 到点仍会设 hoveredKey → 拖拽结束该卡命中 y 冻结分支不归位
        root._dwellKey = ""
        root._hoverDwellTimer.stop()
        root.hoveredKey = ""
        root._dropMergeKey = ""
        root._mergeCandidate = ""
        root._mergeDwellTimer.stop()
        root._centerMergeArmed = false
        root._centerMergeTarget = ""
        root.dragKey = slot.appKey
        root.dragFromIndex = index
        root.dragToIndex = index
        // 抓取偏移 = 指针列坐标 − 卡当前 x/y（保持指尖抓在按下的位置）
        const p = cards.mapFromItem(null, sceneX, sceneY)
        root.dragGrabOffset = p.y - slot.y
        root.dragGrabOffsetX = p.x - slot.x
        root.dragPointerX = p.x
        root.dragPointerY = p.y
        root.dragY = slot.y
        layoutCards()
    }

    // 拖拽期间的基础槽位布局（无悬停/无拖拽的自然排列）——候选检测、
    // 驻留复核、插入目标都用**基础槽位**而不是实时 y：实时位置随预览
    // 让位而动，拿它做检测会构成反馈回路（中心进卡→预览把卡挤走→检测
    // 翻空→预览又回来 = 抽搐循环的根源）。基础槽位恒定，检测确定性。
    function _dragBaseLayout(n) {
        return StageConfigService.layoutMode === "scroll"
            ? StageGeo.scrollLayout(cards.height, n, {
                cardHeight: StageConfigService.cardHeight,
                spacing: StageConfigService.cardSpacing,
                scroll: root.scrollOffset,
                hoveredIndex: -1,
            })
            : _layout(n)
    }

    function _updateCardDrag(slot, index, sceneX, sceneY) {
        if (root.dragKey !== slot.appKey)
            return
        root.dragFromIndex = index   // 对账就地换主后行号可能变
        const p = cards.mapFromItem(null, sceneX, sceneY)
        root.dragPointerX = p.x
        root.dragPointerY = p.y
        const want = p.y - root.dragGrabOffset
        const edge = StageConfigService.cardHeight * StageGeo.DRAG_EDGE_RATIO
        root.dragY = Math.max(-edge,
            Math.min(cards.height - edge, want))
        // 逐帧跟手：被拖卡的 y/x 直接赋值（其 Behavior 已在拖拽中禁用；
        // x 跟指针走 = 中心合并手势的实体感，且**必须**在此直接赋值——
        // layoutCards 只在目标槽变化时跑，横移不触发，靠它更新 x = 卡
        // 不跟手 + 偶发布局才跳一下 = "没反馈 + 掉帧"的实测根源）。
        // 只在目标槽变化时才 layoutCards——让其余卡重排，否则每帧全量
        // 布局会拖累跟手帧率
        slot.y = root.dragY
        slot.slotX = Math.max(8 - cards.x,
            Math.min(root.width - slot.width - 8 - cards.x,
                p.x - root.dragGrabOffsetX))
        const n = cardModel.count
        const ch = StageConfigService.cardHeight
        const lay = _dragBaseLayout(n)
        // ── 中心合并区：指针越过卡片列 + 缓冲 = 与前台程序并组手势 ──
        // 判定跟指针（拖出去的是卡，瞄的是手）；活动窗口 = 正在运行的
        // 程序（其组此刻没有卡——它在前台）。离开卡列时清掉列内候选。
        const inCenterZone = StageConfigService.side === "right"
            ? p.x < -48 : p.x > cards.width + 48
        if (inCenterZone) {
            if (root._dropMergeKey !== "") {
                root._dropMergeKey = ""
                layoutCards()
            }
            if (root._mergeCandidate !== "") {
                root._mergeCandidate = ""
                root._mergeDwellTimer.stop()
            }
            const activeRec = WindowService.windowById(
                WindowService.activeWindowId)
            const target = root._effKey(activeRec)
            const valid = target !== "" && target !== root.dragKey
            const newArmed = valid
            const newTarget = valid ? target : ""
            if (newArmed !== root._centerMergeArmed
                    || newTarget !== root._centerMergeTarget) {
                root._centerMergeArmed = newArmed
                root._centerMergeTarget = newTarget
            }
            return   // 区内不更新插入目标（松手=并入前台或弹回）
        }
        if (root._centerMergeArmed || root._centerMergeTarget !== "") {
            root._centerMergeArmed = false
            root._centerMergeTarget = ""
        }
        // ── 统一插入预览（2026-09-30 三轮手感回归后的终版）──
        // 插入目标 = 基础槽位里离被拖卡最近的——始终如此：压在卡面上
        // 松手（未武装）= 插到那张卡的槽位，拖到缝隙 = 插进缝里。合并
        // 候选卡在 layoutCards 里钉在基础槽位（不被插入预览挤走）。
        // ⚠️ 候选/驻留/滞回全部跟**指针**（dragPointerY）且用基础槽位：
        // 用户瞄的是指针——用被拖卡中心会"抓卡偏一点就等错目标"
        //（"合并十分困难"的根源之一）；用实时 y 则构成检测-布局反馈回路。
        if (root._dropMergeKey !== "") {
            // 武装态滞回：指针离开目标基础槽位 ± DRAG_MERGE_EXIT_RATIO×
            // 卡高才解除；解除即恢复统一插入预览
            let armed = false
            for (let i = 0; i < n; i++) {
                const s = cardRepeater.itemAt(i)
                if (s && s.appKey === root._dropMergeKey) {
                    const top = lay.positions[i] ?? 0
                    const m = ch * root._mergeExitRatio
                    armed = root.dragPointerY >= top - m
                        && root.dragPointerY <= top + ch + m
                    break
                }
            }
            if (armed)
                return   // 武装中：不更新插入目标（松手即合并）
            root._dropMergeKey = ""
            root._mergeCandidate = ""
            root._mergeDwellTimer.stop()
            console.info("[StageSidebar] merge disarmed (left target)")
            layoutCards()   // 恢复插入预览
        } else {
            // 候选检测（指针 + 基础槽位 + 边界滞回：进卡面收紧 6px、
            // 出卡面放宽 0.15×卡高——手在 550ms 驻留里的自然漂移不应
            // 清候选，否则计时不断归零 = "停了也不亮"）
            let mergeKey = ""
            const enter = 6
            const stay = ch * 0.15
            for (let i = 0; i < n; i++) {
                if (i === root.dragFromIndex)
                    continue
                const s = cardRepeater.itemAt(i)
                if (!s)
                    continue
                const top = lay.positions[i] ?? 0
                if (s.appKey === root._mergeCandidate) {
                    if (root.dragPointerY >= top - stay
                            && root.dragPointerY <= top + ch + stay) {
                        mergeKey = s.appKey
                        break
                    }
                } else if (root.dragPointerY >= top + enter
                            && root.dragPointerY <= top + ch - enter) {
                    mergeKey = s.appKey
                    break
                }
            }
            if (mergeKey !== root._mergeCandidate) {
                root._mergeCandidate = mergeKey
                if (mergeKey === "")
                    root._mergeDwellTimer.stop()
                else
                    root._mergeDwellTimer.restart()
            }
        }
        // 插入目标 = 最近基础槽位（按被拖卡位置算——卡是插进列的东西）
        let best = index, bestDist = Infinity
        for (let i = 0; i < n; i++) {
            const d = Math.abs((lay.positions[i] ?? 0) - root.dragY)
            if (d < bestDist) { bestDist = d; best = i }
        }
        if (best !== root.dragToIndex) {
            root.dragToIndex = best
            layoutCards()
        }
    }

    // 合并动画收尾：动画播完才改模型。槽位中途没了（被关/对账重建）
    // 就跳过动画直接合并——不能丢用户的合并意图
    property var _mergeAnimPending: null
    property Timer _mergeAnimTimer: Timer {
        interval: 260
        onTriggered: {
            const p = root._mergeAnimPending
            root._mergeAnimPending = null
            if (!p)
                return
            if (!root.mergeGroups(p.from, p.to)) {
                // no-op（260ms 窗口内 from 组已无 record）：交还被吞卡
                // 姿态，否则停在 engaging=true 的隐形态（热区还挡输入）
                for (let i = 0; i < cardRepeater.count; i++) {
                    const s = cardRepeater.itemAt(i)
                    if (s && s.appKey === p.from && s.cardItem)
                        s.cardItem.engaging = false
                }
            }
        }
    }

    // 无头合并/拆分钩子（按槽位下标；自由组合链路验证用）
    function debugMerge(fromIndex, toIndex): string {
        const a = cardRepeater.itemAt(fromIndex)
        const b = cardRepeater.itemAt(toIndex)
        if (!a || !b)
            return "no slot"
        root.mergeGroups(a.appKey, b.appKey)
        return JSON.stringify({ order: root._groupOrder })
    }

    function debugSplit(index): string {
        const a = cardRepeater.itemAt(index)
        if (!a)
            return "no slot"
        root.splitGroupByKey(a.appKey)
        return JSON.stringify({ order: root._groupOrder })
    }

    // 无头合并手势模拟（驻留门控链路验证，不走真实时钟）：
    //   begin → 中心压到目标卡 →（cand 应入表、armed 应空）→ 驻留到点
    //   （直接调 _mergeDwellFire）→ armed 应=目标 →
    //   mode="merge"  : 松手 = 应并组（动画 260ms 后 order 少一键）
    //   mode="moveaway": 再拖离目标（超滞回边距）→ armed 应清空 → 松手 =
    //                    只换位不并组（order 键数不变）
    function debugMergeGesture(fromIndex, toIndex, mode): string {
        const slot = cardRepeater.itemAt(fromIndex)
        const target = cardRepeater.itemAt(toIndex)
        if (!slot || !target || fromIndex === toIndex)
            return JSON.stringify({ error: "no slot" })
        const log = []
        const o = cards.mapToItem(null, 0, 0)
        const ch = StageConfigService.cardHeight
        // 列内指针 x（列中线上）与中心区指针 x（越过卡列 + 300）
        const colX = o.x + cards.width / 2
        const centerX = o.x + (StageConfigService.side === "right"
            ? -300 : cards.width + 300)
        _beginCardDrag(slot, fromIndex, colX,
            o.y + slot.y + ch / 2)
        if (mode === "center") {
            // 拖向屏幕中心松手：应与前台程序（活动组）并组
            _updateCardDrag(slot, fromIndex, centerX,
                o.y + slot.y + ch / 2)
            log.push({ step: "center", armed: root._centerMergeArmed,
                target: root._centerMergeTarget })
            _endCardDrag(slot)
            log.push({ step: "end", pending: root._mergeAnimPending !== null })
            return JSON.stringify(log)
        }
        // 指针压到目标卡基础槽位中心（检测跟指针）
        _updateCardDrag(slot, fromIndex, colX,
            o.y + (target.y + ch / 2))
        log.push({ step: "over", cand: root._mergeCandidate,
            armed: root._dropMergeKey })
        if (mode === "pass") {
            // 压在卡面上直接松手（未驻留）：应换位到目标槽位而非弹回
            _endCardDrag(slot)
            log.push({ step: "end", pending: root._mergeAnimPending !== null,
                to: "slot of target" })
            return JSON.stringify(log)
        }
        if (mode === "timer") {
            // 真实时钟验证：拖拽保持打开直接返回（dwell 定时器自然在跑），
            // sleep 后查 journal 的 "merge armed" 行，再用 debugDrag <from>
            // 收尾松手（begin 因 dragKey 已设而跳过，直接走 _endCardDrag）
            log.push({ step: "open", note: "drag left open, timer live" })
            return JSON.stringify(log)
        }
        _mergeDwellFire()
        log.push({ step: "dwell", armed: root._dropMergeKey })
        if (mode === "moveaway") {
            // 拖回列顶：指针远离目标基础槽位 ≥ 滞回边距 → 应解除武装
            _updateCardDrag(slot, fromIndex, colX, o.y)
            log.push({ step: "moveaway", armed: root._dropMergeKey,
                cand: root._mergeCandidate })
        }
        _endCardDrag(slot)
        log.push({ step: "end", pending: root._mergeAnimPending !== null })
        return JSON.stringify(log)
    }

    // 无头拖拽模拟：跳过阈值/跟手（纯视觉），走完 begin→目标槽→end 的
    // 提交链路（顺序表转正 + syncCards + 矩形重发布）
    function debugDrag(fromIndex, toIndex) {
        const slot = cardRepeater.itemAt(fromIndex)
        if (!slot)
            return "no slot at " + fromIndex
        const scene0 = slot.mapToItem(null, 0, 0).y
        _beginCardDrag(slot, fromIndex, scene0)
        root.dragToIndex = Math.max(0, Math.min(cardModel.count - 1, toIndex))
        layoutCards()
        _endCardDrag(slot)
        return JSON.stringify({ order: root._groupOrder })
    }

    function _endCardDrag(slot) {
        if (root.dragKey !== slot.appKey)
            return
        const key = root.dragKey
        const mergeKey = root._dropMergeKey   // 仅武装态非空：驻留未到点
        const centerKey = root._centerMergeArmed
            ? root._centerMergeTarget : ""    // 中心区松手 = 并入前台程序
        const to = root.dragToIndex           // ⚠️ 先取再清态：清了再读=恒
        // -1，换位提交链路整个变死代码（拖拽松手弹回、只剩误并组——
        // "拖拽和合并打架"的另一半根源，合并动画重构时引入的回归）
        root._dropMergeKey = ""               // 松手 = 只是换位（意图明确）
        root._mergeCandidate = ""
        root._mergeDwellTimer.stop()
        root._centerMergeArmed = false
        root._centerMergeTarget = ""
        root.dragKey = ""
        root.dragFromIndex = -1
        root.dragToIndex = -1
        // 中心合并落点（用户定稿语义）：拖到屏幕中心的卡 = **在原地放
        // 大成应用置顶桌面**，并与之前的前台程序（"下面的"那个）结成
        // 卡组。顺序 = 先并组后激活：同卡豁免（_effKey）让退位/收编管
        // 线不碰刚让位的前台窗——两个应用一起留在桌面，切走时一起收
        // 进一张卡。被拖卡的最后屏幕矩形发布为动画起点（stageanim 读
        // targets），窗口从卡片位置"长大"。
        if (centerKey !== "" && centerKey !== key) {
            let ids = []
            try {
                ids = JSON.parse(slot.idsJson || "[]")
            } catch (e) {
                ids = []
            }
            const focusId = ids.indexOf(slot.targetId) >= 0
                ? slot.targetId
                : (ids.length > 0 ? ids[0] : slot.targetId)
            const vis = slot.mapToItem(null, 0, 0)
            const rw = slot.width * StageGeo.DRAG_SCALE
            const rh = slot.height * StageGeo.DRAG_SCALE
            root.mergeGroups(key, centerKey)   // 直接落模型（卡片行即消失）
            root._publishOverrideRects(ids, vis.x, vis.y, rw, rh)
            WindowService.activateGroup(ids, focusId)
            console.info("[StageSidebar] center engage+merge " + key
                + " -> " + centerKey)
            return
        }
        // 合并落点：压在别的卡上松手 = 先播合并动画（被吞卡滑向目标 +
        // 交棒淡出，槽位 Behavior 在 dragKey 清掉后已恢复），到位再真正
        // 并组——模型瞬变没有过程感（用户："合并水灵灵的动画呢"）
        if (mergeKey !== "" && mergeKey !== key) {
            let targetSlot = null
            for (let i = 0; i < cardRepeater.count; i++) {
                const s2 = cardRepeater.itemAt(i)
                if (s2 && s2.appKey === mergeKey) { targetSlot = s2; break }
            }
            if (targetSlot) {
                const absorbed = slot
                absorbed.cardItem.engaging = true   // 180ms 淡出（同点卡交棒）
                absorbed.y = targetSlot.y           // 240ms 滑向目标槽
                // 上一单动画还在窗口内：先冲刷（立即落模型）再排新单，
                // 否则单槽覆盖会把上一张被吞卡永久留在隐形态
                if (root._mergeAnimPending)
                    root.mergeGroups(root._mergeAnimPending.from,
                        root._mergeAnimPending.to)
                root._mergeAnimPending = { from: key, to: mergeKey }
                root._mergeAnimTimer.restart()
                return
            }
            root.mergeGroups(key, mergeKey)
            return
        }
        if (to >= 0) {
            const next = StageGroups.moveOrderKey(root._groupOrder, key, to)
            if (next !== root._groupOrder) {
                root._groupOrder = next
                console.info("[StageSidebar] drag reorder key=" + key
                    + " -> slot " + to)
            }
        }
        syncCards()   // 模型移动 + layoutCards 动画收敛 + 矩形重发布（自动
        // 排除活动组——活动组没有卡，烤进布局就是 N+1 幻影卡，整列矩形
        // 错一个槽；哨兵键只属于桌面收编路径，那里全员即将最小化）
    }

    function engageCard(slot) {
        engageCardWindow(slot, slot.targetId)
    }

    // 点卡 / 点左下角窗口图标共用的入列口：iconWindowId 传图标命中的那扇
    // 窗时焦点钉它（macOS Stage Manager：图标排是逐窗直达），点卡面用
    // 代表窗。整组还原语义不变，只有 focus 目标不同。
    function engageCardWindow(slot, iconWindowId) {
        // 面板隐藏/模式关闭后不可从不可见卡片派发展开
        if (!StageModeService.enabled || !open)
            return
        const card = slot.cardItem
        if (card.engaging)
            return
        card.engaging = true
        // 点卡＝主动选了某个应用，退出"显示桌面"开关态（其余最小化窗
        // 保留为普通卡，下次点桌面不再整组放出来）
        _exitDeskReveal()
        _cancelPendingDemote()
        // 点卡意图接管：撤销看门狗退役（迟到恢复会跟 engage 抢焦点）
        root._deskUndoWatch = null
        root._deskUndoWatchTimer.stop()
        // 只入队；退位判定/快照/预测表全部挪到派发时刻（见队列注释）
        let ids = []
        try {
            ids = JSON.parse(slot.idsJson || "[]")
        } catch (e) {
            ids = []
        }
        // 图标窗必须还在组里（窗口可能刚关，idsJson 是上一轮快照）
        const focusId = iconWindowId !== slot.targetId
                && ids.indexOf(iconWindowId) >= 0
            ? iconWindowId : slot.targetId
        root._engageQueue.push({ appKey: slot.appKey,
            targetId: focusId, idsJson: slot.idsJson })
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
            console.warn("[StageSidebar] closeGroup parse failed: " + e)
            return
        }
        for (let i = 0; i < ids.length; i++)
            WindowService.closeWindow(ids[i])
    }

    // ── 卡片堆叠区 ──
    // 背景完全透明（用户要求）：无背板、无霜层，只留悬浮卡片本身。
    // 左右锚到"内容列"（窗宽减两侧溢出余量 = PANEL_WIDTH）；上下留出
    // 辉光余量（首/末卡的辉光外扩 ~19px 不出窗缘）。
    Item {
        id: cards
        // 卡片列：固定条宽、贴常驻侧（全屏浮层下 cards.x 即屏幕绝对 x，
        // 特效矩形/hit 区域都从它推）
        anchors {
            top: parent.top
            topMargin: 46
            left: root.rightSide ? undefined : parent.left
            leftMargin: root.rightSide ? 0 : StageGeo.CARD_OVERFLOW_MARGIN
            right: root.rightSide ? parent.right : undefined
            rightMargin: root.rightSide ? StageGeo.CARD_OVERFLOW_MARGIN : 0
            bottom: parent.bottom
            bottomMargin: 18
        }
        width: StageGeo.PANEL_WIDTH

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
        // ⚠️ 拖拽中解裁：被拖卡要跟指针拖出卡列（中心合并手势），clip
        // 会在视口缘把它硬切（实测"拖过某处就被截断"）
        Item {
            id: cardsViewport
            x: -StageGeo.GLOW_PAD
            y: 0
            width: cards.width + StageGeo.GLOW_PAD * 2
            height: cards.height
            clip: root.dragKey === ""

            Repeater {
                id: cardRepeater
                model: cardModel

            delegate: Item {
                id: slot

                // 字段清单单一出处：stage-groups.mjs 的 CARD_FIELDS
                required property int index
                required property string appKey
                required property string targetId
                required property int pid
                required property string appName
                required property string title
                required property string iconSource
                required property int count
                required property string idsJson
                required property string iconsJson
                required property bool merged

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
                Behavior on y {
                    // 拖拽中的被拖卡必须逐帧跟手（Behavior=橡皮筋延迟）；
                    // 其余卡的 Behavior 保持——让位/回弹平滑
                    enabled: slot.placed && root.dragKey !== slot.appKey
                    NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic }
                }
                Behavior on x {
                    // 被拖卡 x 逐帧跟手（同 y 的拖拽守卫；Behavior=橡皮筋）
                    enabled: root.dragKey !== slot.appKey
                    NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic }
                }
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
                    iconsJson: slot.iconsJson
                    merged: slot.merged
                    dropHovered: root._dropMergeKey === slot.appKey
                    // 驻留预示 = 指针在候选上计时中；中心合并预示 =
                    // 被拖卡自身进了屏幕中心区且前台可并组
                    dwellHint: root.dragKey !== ""
                        && root._mergeCandidate === slot.appKey
                    selfMergeHint: root._centerMergeArmed
                        && slot.appKey === root.dragKey
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
                    onDragStarted: function(sceneX, sceneY) {
                        root._beginCardDrag(slot, slot.index, sceneX, sceneY)
                    }
                    onDragMoved: function(sceneX, sceneY) {
                        root._updateCardDrag(slot, slot.index, sceneX, sceneY)
                    }
                    onDragReleased: root._endCardDrag(slot)
                    onCloseAllRequested: root.closeGroup(slot.idsJson)
                    onUngroupRequested: root.splitGroupByKey(slot.appKey)
                    onIconActivated: function(windowId) {
                        root.engageCardWindow(slot, windowId)
                    }
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
        // 拖拽期间指针必然在被拖卡上——悬停聚焦布局会让其余卡退避，和
        // 拖拽让位打架；拖拽布局自己管
        if (root.dragKey !== "")
            return
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
        return JSON.stringify({ open: root.open, visible: root.visible,
            launcherOpen: AppLauncherService.open,
            winW: Math.round(root.width),
            winH: Math.round(root.height),
            cardsH: Math.round(cards.height), hovered: root.hoveredKey,
            scroll: Math.round(root.scrollOffset),
            maxScroll: Math.round(root._maxScroll),
            totalWin: root.totalWindows, order: root._groupOrder,
            hitRegion: [stripHitRegion.y, stripHitRegion.height],
            slots: slots })
    }

    // 显示桌面开关状态机快照（抗打断排障）：集合/在途批次/定时器/焦点
    // 各维度一眼对齐，"卡住了"时直接对照哪一环悬空
    function deskState(): string {
        const minPending = root._pendingMinimize.map(id => {
            const r = WindowService.windowById(id)
            return { id: id, min: r ? !!r.toplevel?.minimized : null }
        })
        const collected = root.deskCollectedIds.map(id => {
            const r = WindowService.windowById(id)
            return { id: id, min: r ? !!r.toplevel?.minimized : null }
        })
        return JSON.stringify({
            collected: collected,
            focusId: root.deskCollectedFocusId,
            pendingMinimize: minPending,
            timers: { capture: root._captureThenMinTimer.running,
                dispatch: root._minimizeDispatchTimer.running,
                hold: root._deskHoldReleaseTimer.running,
                autoMin: root._autoMinTimer.running,
                deskFocus: root._desktopFocusTimer.running },
            hold: root._deskHoldActive,
            undoWatch: root._deskUndoWatch !== null,
            stageActiveId: root.stageActiveId,
            activeId: WindowService.activeWindowId,
            kwinActiveId: WindowService.kwinActiveId,
            kwinDesktop: WindowService.kwinActiveDesktop,
            lastToggleAt: Math.round(Date.now() - root._lastDeskToggleAt),
            engageQ: root._engageQueue.length })
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
        if (n === 0) {
            // 空态也要归零输入遮罩：早退会让 stripHitRegion 保持上一轮的
            // 非零 extent，最后一张卡消失后旧卡区域继续吞点击（输入黑洞）
            _updateHitRegionExtent()
            return
        }
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
            const lay = StageGeo.scrollLayout(cards.height, n, {
                cardHeight: StageConfigService.cardHeight,
                spacing: StageConfigService.cardSpacing,
                scroll: root.scrollOffset,
                retreat: StageConfigService.deckSidePeek,
                hoveredIndex: root.dragKey !== "" ? -1 : h,
                // 锚定**视觉**位置（mapToItem 含在途动画），不是属性 y——
                // 飞行途中两者不一致，锚属性值会让卡片从指针下方滑走。
                // 聚焦矩形从视觉位置由 TopLeft 向外生长，悬停点必然仍在卡内。
                // 高度刚变的那轮除外（纪元守卫见 _layoutHeight 注释）
                hoverY: (!heightEpochChanged && h >= 0
                    && cardRepeater.itemAt(h))
                    ? cardRepeater.itemAt(h).mapToItem(cards, 0, 0).y
                    : undefined,
            })
            // 拖拽排序：被拖卡跟手（y=dragY），其余按"抽出再插回目标槽"
            // 的预览顺序落基础槽位（让位实时可见）；槽位 z 抬满、微放大
            const dragging = root.dragKey !== ""
            for (let i = 0; i < n; i++) {
                const slot = cardRepeater.itemAt(i)
                if (!slot)
                    continue
                if (dragging) {
                    slot.placed = true
                    if (i === root.dragFromIndex) {
                        slot.y = root.dragY
                        slot.slotScale = StageGeo.DRAG_SCALE
                        // x 跟手：纵向拖拽停在列内（抓取偏移钳制），拖向
                        // 屏幕中心时卡随指针横移（中心合并手势的实体感）。
                        // 钳位 = 屏幕边界 8px（cards 视口坐标系换算）
                        slot.slotX = Math.max(8 - cards.x,
                            Math.min(root.width - slot.width - 8 - cards.x,
                                root.dragPointerX - root.dragGrabOffsetX))
                        slot.z = StageGeo.DRAG_Z
                        slot.dimmed = false
                        continue
                    }
                    // 合并悬停中：其余卡钉在各自基础槽位（目标卡不能从
                    // 指针下移走），只高亮目标（dropHovered 走 delegate 绑定）
                    if (root._dropMergeKey !== "") {
                        slot.y = lay.positions[i] ?? 0
                        slot.slotScale = 1
                        slot.slotX = (cards.width - slot.width) / 2
                            + StageGeo.GLOW_PAD
                        slot.z = n - i
                        slot.dimmed = false
                        continue
                    }
                    // 合并候选钉位：候选卡不被插入预览挤走（钉在自己的
                    // 基础槽位，被拖卡悬停在它上方 = "叠上去"的合并隐喻）；
                    // 其余卡照常让位——预览全程单状态，无"过卡归位/过缝
                    // 让位"的来回翻转（实测抽搐+掉帧的根源）
                    if (root._mergeCandidate !== ""
                            && slot.appKey === root._mergeCandidate) {
                        slot.y = lay.positions[i] ?? 0
                        slot.slotScale = lay.scales[i] ?? 1
                        slot.slotX = (cards.width
                            - slot.width * slot.slotScale) / 2
                            + StageGeo.GLOW_PAD
                        slot.z = n - i
                        slot.dimmed = false
                        continue
                    }
                    let pi = i < root.dragFromIndex ? i : i - 1
                    if (pi >= root.dragToIndex)
                        pi += 1
                    slot.y = lay.positions[pi] ?? 0
                    slot.slotScale = lay.scales[pi] ?? 1
                    slot.slotX = (cards.width - slot.width * slot.slotScale) / 2
                        + StageGeo.GLOW_PAD
                    slot.z = n - pi
                    slot.dimmed = false
                    continue
                }
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
            }
            // 滚动状态回填：槽距（滚轮步进）+ 上限（clamp；卡数变化后
            // 收敛滚动位置，超限回落触发一轮再布局）
            root._lastPitch = lay.pitch
            root._maxScroll = lay.scrollMax
            if (root.scrollOffset > root._maxScroll)
                root.scrollOffset = root._maxScroll
            _updateHitRegionExtent()
            return
        }
        const lay = _layout(n)
        const dragging = root.dragKey !== ""
        for (let i = 0; i < n; i++) {
            const slot = cardRepeater.itemAt(i)
            if (!slot)
                continue
            if (dragging) {
                slot.placed = true
                if (i === root.dragFromIndex) {
                    slot.y = root.dragY
                    slot.slotScale = StageGeo.DRAG_SCALE
                    // x 跟手（adaptive 分支同款，见 scroll 分支注释）
                    slot.slotX = Math.max(8 - cards.x,
                        Math.min(root.width - slot.width - 8 - cards.x,
                            root.dragPointerX - root.dragGrabOffsetX))
                    slot.z = StageGeo.DRAG_Z
                    slot.dimmed = false
                    continue
                }
                if (root._dropMergeKey !== "") {
                    slot.y = lay.positions[i] ?? 0
                    slot.slotScale = lay.scale
                    slot.slotX = (cards.width - slot.width * lay.scale) / 2
                        + StageGeo.GLOW_PAD
                    slot.z = n - i
                    slot.dimmed = false
                    continue
                }
                // 合并候选钉位（scroll 分支同款，见该处注释）
                if (root._mergeCandidate !== ""
                        && slot.appKey === root._mergeCandidate) {
                    slot.y = lay.positions[i] ?? 0
                    slot.slotScale = lay.scales?.[i] ?? lay.scale ?? 1
                    slot.slotX = (cards.width
                        - slot.width * slot.slotScale) / 2
                        + StageGeo.GLOW_PAD
                    slot.z = n - i
                    slot.dimmed = false
                    continue
                }
                let pi = i < root.dragFromIndex ? i : i - 1
                if (pi >= root.dragToIndex)
                    pi += 1
                slot.y = lay.positions[pi] ?? 0
                slot.slotScale = lay.scale
                slot.slotX = (cards.width - slot.width * lay.scale) / 2
                    + StageGeo.GLOW_PAD
                slot.z = n - pi
                slot.dimmed = false
                continue
            }
            // 首拍落位（scroll 分支同款：placed 为 false 时 Behavior 禁用）
            slot.y = lay.positions[i] ?? 0
            slot.placed = true
            slot.slotScale = lay.scale
            slot.slotX = (cards.width - slot.width * lay.scale) / 2
                + StageGeo.GLOW_PAD
            slot.z = n - i
            slot.dimmed = false
        }
        _updateHitRegionExtent()
    }
    // 根窗口 onHeightChanged 不另设：cards 锚满窗体（上下留辉光余量），
    // 窗高变化必然带动 cards 高度 → cards.onHeightChanged 已覆盖，同帧
    // 两轮 layoutCards + 两轮 geometryRepublish 是纯浪费

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

    // 窗口隐藏（启动台打开/面板关闭）时 release 不再送达——拖拽必须
    // 就地中断，否则 dragKey 永久卡死（拒新拖拽 + 杀死悬停聚焦）
    onVisibleChanged: if (!visible) _abortDrag()

    onSideGroupsChanged: syncCards()

    // 初始求值不触发 changed 信号，挂载时先对账一次
    Connections {
        target: StageModeService
        // DeskCenter 空区左键 → 显示桌面开关（DeskCenter 与本窗分属两个
        // 模块，StageModeService 单例是唯一控制通道）
        function onDeskRevealToggleRequested() { root.toggleDeskReveal() }
    }

    Connections {
        target: AppLauncherService
        // 覆盖层关在桌面上（点外部关闭/启动应用后又回桌面）：此刻活动窗
        // 已是空且不会再变——手动补一次桌面聚焦判定
        function onOpenChanged() {
            if (!AppLauncherService.open
                    && WindowService.activeWindowId === ""
                    && root._prevActiveId !== "")
                root._desktopFocusTimer.restart()
        }
    }

    Component.onCompleted: {
        stageActiveId = WindowService.activeWindowId
        // 自由组合落盘加载：读到的覆盖表就位后再对账一次（首帧先按自然
        // 组显示，不阻塞启动）
        JsonConfigStore.readPath(root._mergesPath, function(data, exists) {
            if (exists) {
                try {
                    const obj = JSON.parse(data)
                    if (obj && obj.merges && typeof obj.merges === "object") {
                        root._mergeOverrides = obj.merges
                        syncCards()
                    }
                } catch (e) {
                    console.warn("[StageSidebar] bad merges.json: " + e)
                }
            }
        })
        syncCards()
    }

    // 启动一致性：shell 重启后焦点可能无处安放（无活动窗）而桌面还有
    // 可见窗——这正是"卡出现了、程序却还在桌面"的幽灵态。按桌面聚焦
    // 语义收编并记入开关集（下次点桌面＝整组放出来）。
    property Timer _bootConsistencyTimer: Timer {
        interval: 1500
        repeat: false
        running: root.open
        onTriggered: {
            if (WindowService.activeWindowId === ""
                    && (WindowService.kwinActiveId === ""
                        || WindowService.kwinActiveDesktop)
                    && StageConfigService.autoMinimize)
                root._collectDesktopToStrip(true)
        }
    }

    // ── 收敛看门狗（抗打断兜底）：焦点在桌面、有桌面窗没收、且没有任何
    // 管线/定时器在途、也无刚发生的人机交互 → 任何被打断的收编管线最终
    // 都会落进这个态（取消者清了状态、被取消者半途而废、恢复焦点失败等
    // 未知交错），统一自动补一次收编拉回"显示桌面"一致态。语义与
    // _desktopFocusTimer 的桌面聚焦收编一致（同一判定条件），只是带重试。
    property Timer _deskHealTimer: Timer {
        interval: 1500
        repeat: true
        running: root.open && StageModeService.enabled
        onTriggered: {
            if (!StageModeService.enabled || !root.open
                    || root.shellOverlayActive)
                return
            // 残局清理：开关态挂着但集内一条都没最小化、管线也已停摆＝
            // 被打断的收编只剩个空壳（armed-but-out，实测复现：autoMin
            // 的激活周期把桌面批次拦在派发前）——清壳前武装落地铁底看
            // 门狗（"停摆"判定看不见已在桥队列里的命令，>1600ms 积压时
            // 清完才落地就没人兜了），再清让状态与现实一致。armed 且有
            // 最小化的＝正常开关态，不碰。
            if (root.deskCollectedIds.length > 0) {
                if (root._pendingMinimize.length > 0
                        || root._captureThenMinTimer.running
                        || root._minimizeDispatchTimer.running
                        || Date.now() - root._lastDeskToggleAt < _deskHealSilenceMs)
                    return
                if (!root._anyMinimized(root.deskCollectedIds)) {
                    root._deskUndoWatch = {
                        ids: root.deskCollectedIds.slice(),
                        focusId: root.deskCollectedFocusId }
                    root._deskUndoWatchTimer.restart()
                    console.warn("[StageSidebar] desk heal: stale armed"
                        + " set cleared (nothing minimized)")
                    root._exitDeskReveal()
                }
                return
            }
            // 有属主在管状态（管线在途/看门狗在飞/交互进行中）＝不是孤儿态
            //（开关态必为空——上面 armed 分支全路径 return，此处不再查）
            if (root._pendingMinimize.length > 0
                    || root._deskUndoWatch !== null
                    || root.dragKey !== ""
                    || root._engageQueue.length > 0)
                return
            if (root._captureThenMinTimer.running
                    || root._minimizeDispatchTimer.running
                    || root._deskHoldReleaseTimer.running
                    || root._desktopFocusTimer.running
                    || root._autoMinTimer.running)
                return
            // 刚 toggle 过（含撤销/恢复）让路：正常管线最长 ~600ms + 动画
            if (Date.now() - root._lastDeskToggleAt < _deskHealSilenceMs)
                return
            if (!StageConfigService.autoMinimize)
                return
            const activeId = WindowService.activeWindowId
            if (activeId !== "")
                return
            if (!(WindowService.kwinActiveId === ""
                    || WindowService.kwinActiveDesktop))
                return
            if (root._collectDesktopToStrip(true))
                console.warn("[StageSidebar] desk heal: re-collected"
                    + " (interrupted pipeline residue)")
        }
    }

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
        // 覆盖表剪枝：窗口销毁后它的合并项随之作废（handleId 不在存活集）
        const records = WindowService.records || []
        if (records.length > 0) {
            const liveHandles = ({})
            for (let i = 0; i < records.length; i++)
                liveHandles[records[i].handleId] = true
            const pruned = StageGroups.pruneOverrides(
                root._mergeOverrides, liveHandles)
            if (pruned !== root._mergeOverrides) {
                root._mergeOverrides = pruned
                root._saveMerges()
            }
        }
        layoutCards()
        publishSimulatedLayout("")
        // 拖拽存活性对账：被拖组行消失（窗口全关/被并走/成为活动组）时
        // release 永远不会来——dragKey 卡死会拒新拖拽、杀死悬停聚焦、
        // 把无辜的新行钉在 dragY/DRAG_Z。就地校正行号消除模型变更后
        // 的短暂陈旧行号
        if (root.dragKey !== "") {
            let dragIdx = -1
            for (let i = 0; i < cardModel.count; i++) {
                if (cardModel.get(i).appKey === root.dragKey) {
                    dragIdx = i
                    break
                }
            }
            if (dragIdx < 0)
                _abortDrag()
            else
                root.dragFromIndex = dragIdx
        }
    }

    // 拖拽中断的统一出口（被拖卡消失 / 窗口隐藏后 release 不再送达）
    function _abortDrag() {
        if (root.dragKey === "" && root._dropMergeKey === ""
                && root._mergeCandidate === "")
            return
        console.info("[StageSidebar] drag aborted key=" + root.dragKey)
        root._dropMergeKey = ""
        root._mergeCandidate = ""
        root._mergeDwellTimer.stop()
        root._centerMergeArmed = false
        root._centerMergeTarget = ""
        root.dragKey = ""
        root.dragFromIndex = -1
        root.dragToIndex = -1
        layoutCards()
    }

    // 输入遮罩：只罩住**卡片实际占据的纵向范围**——整条全高遮罩会把
    // 首卡上方/末卡下方的大片透明区也变成输入黑洞，滑进侧栏下的窗口
    // 那部分就点不到（实测"程序有一部分在侧边栏那边点不到"）。排布/
    // 滚动/拖拽变化时由 layoutCards 尾部刷新；无卡=零高全穿透。
    Item {
        id: stripHitRegion
        x: StageGeo.CARD_OVERFLOW_MARGIN   // layoutCards 尾部由 _updateHitRegionExtent 按侧校正
        y: 0
        width: StageGeo.PANEL_WIDTH
        height: 0
        visible: false
    }
    // 拖拽期全窗输入区：mask 只罩卡条是给点击穿透用的；拖拽中指针必须
    // 能拖出卡条（中心合并手势）——指针离开 mask = 事件不再送达本窗 =
    // 拖拽就地冻结 + release 丢失 + dragKey 卡死（"拉到中间没反应/不
    // 合并"的根源，也是此前"莫名拖不动"的嫌疑）。松手即回落条形 mask。
    Rectangle {
        id: dragInputMask
        visible: false
        anchors.fill: parent
    }
    mask: Region {
        Region { item: root.dragKey !== "" ? dragInputMask
            : stripHitRegion }
    }

    function _updateHitRegionExtent() {
        let top = Infinity, bottom = -Infinity
        for (let i = 0; i < cardRepeater.count; i++) {
            const s = cardRepeater.itemAt(i)
            if (!s || !s.visible)
                continue
            const wy = cards.y + s.y
            const wh = s.height * (s.slotScale || 1)
            if (wy < top)
                top = wy
            if (wy + wh > bottom)
                bottom = wy + wh
        }
        if (top === Infinity) {
            stripHitRegion.y = 0
            stripHitRegion.height = 0
            return
        }
        stripHitRegion.x = cards.x
        stripHitRegion.y = Math.max(0, Math.floor(top) - StageGeo.GLOW_PAD)
        stripHitRegion.height = Math.ceil(bottom - stripHitRegion.y)
            + StageGeo.GLOW_PAD
    }
}
