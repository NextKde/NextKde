pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// StageConfigService — 台前调度（Stage 侧栏）全部可调参数的唯一事实来源。
// 持久化 <stateDir>/stage/config.json（JsonConfigStore 原子写）；kwinrc
// [Effect-stageanim] 的 AnimationDuration/EasingCurve 是它的副作用投影，
// 改动经 reconfigureEffect 即时生效、启动时对齐一次。
// 设置应用走 stage-config IPC 的 set/snapshot（返回整份快照 JSON）。
// 本地 CLI（~/.local/bin/stage-anim）直接写 kwinrc 的值会在下次 shell
// 启动对齐或设置页改动时被这里的持久值覆盖——CLI 是临时调参通道。
QtObject {
    id: svc

    property int revision: 0

    // ── schema：唯一事实来源（新增参数 = 加一行 schema + 一个属性）──
    // 分组：布局 / 玻璃质感 / 动效节拍 / 实时预览 / 窗口动画特效投影
    readonly property var _schema: ({
        // 布局（scroll = 完整滚动：卡片完整显示不重叠，固定可见数 + 滚轮翻页）
        "layoutMode":   { type: "enum", values: ["scroll", "adaptive"],
                          def: "scroll" },
        "cardHeight":   { type: "int", min: 100, max: 220, def: 148 },
        "cardSpacing":  { type: "int", min: 4, max: 48, def: 16 },
        "centerCards":  { type: "bool", def: true },
        "deckSidePeek": { type: "int", min: 4, max: 60, def: 20 },
        "focusDim":     { type: "bool", def: false },
        "deckRestTilt": { type: "real", min: 0, max: 45, def: 10 },
        "tiltAngle":    { type: "real", min: 0, max: 60, def: 22 },
        // 玻璃质感（StageCard 卡面：背板/受光/描边/辉光/纵深）
        "cardRadius":   { type: "int", min: 0, max: 24, def: 14 },
        "cardTint":     { type: "real", min: 0.2, max: 0.95, def: 0.55 },
        "cardTopLight": { type: "real", min: 0, max: 0.3, def: 0.07 },
        "cardBorder":   { type: "real", min: 0, max: 0.4, def: 0.13 },
        "cardGlow":     { type: "real", min: 0, max: 0.4, def: 0.13 },
        "cardDepth":    { type: "real", min: 0, max: 0.6, def: 0.38 },
        "thumbSize":    { type: "int", min: 160, max: 640, def: 320 },
        // 动效与节拍
        "hoverScale":   { type: "real", min: 1.0, max: 1.20, def: 1.05 },
        "hoverDwellDelay": { type: "int", min: 0, max: 800, def: 200 },
        "cardEnterDuration": { type: "int", min: 100, max: 800, def: 240 },
        "tiltAnimDuration": { type: "int", min: 100, max: 800, def: 250 },
        "engageDelay":  { type: "int", min: 60, max: 500, def: 170 },
        "autoMinimize": { type: "bool", def: true },
        "autoMinDelay": { type: "int", min: 200, max: 3000, def: 650 },
        "demoteCaptureDelay": { type: "int", min: 100, max: 1500, def: 300 },
        "demoteDispatchDelay": { type: "int", min: 10, max: 200, def: 30 },
        "desktopFocusDebounce": { type: "int", min: 50, max: 1000, def: 150 },
        // 活体流（zkde_screencast PipeWire 实时画面）：⚠️ 默认禁用——
        // 本容器（安卓宿主）GPU 预算极紧。round36 起带占空比节流
        //（连接抓帧→断开渲染，见 StageCard），实测可控后可开。
        "thumbLiveStream": { type: "bool", def: false },
        "streamCycleOnMs": { type: "int", min: 80, max: 1000, def: 250 },
        "streamCycleOffMs": { type: "int", min: 200, max: 5000, def: 750 },
        // 窗口动画特效（stageanim）的 kwinrc 投影
        "animDuration": { type: "int", min: 120, max: 2000, def: 420 },
        "glassOpacity": { type: "real", min: 0.3, max: 1.0, def: 0.65 },
        "animEasing":   { type: "enum",
            values: ["OutCubic", "InOutCubic", "OutBack", "OutQuad",
                     "InOutQuad", "Linear"],
            def: "OutCubic" },
    })

    // 运行时属性（_load 用持久值覆盖默认；分组与 schema 一一对应）
    // 卡片布局：scroll = 完整滚动（卡片完整显示永不重叠，固定可见卡数
    // 等分视口，超出滚轮翻页无滚动条，底部位置点+窗数提示）；adaptive =
    // 自适应缩小（全部完整显示，等比缩小到恰好放下）
    property string layoutMode: "scroll"
    property int cardHeight: 148
    property int cardSpacing: 16
    // adaptive 模式：放得下时整列垂直居中；贴满时顶部锚定
    property bool centerCards: true
    // 聚焦退避距离：悬停聚焦时其余卡片从原位向两侧平移的像素
    property int deckSidePeek: 20
    // 聚焦时压暗退避卡片（用户觉得不必要，默认关）
    property bool focusDim: false
    // 静置倾斜：scroll 模式静止时卡片带统一倾角，悬停聚焦放平，交棒保持
    //（kwinrc TiltAngle 同源投影）；tiltAngle = adaptive 模式的悬停倾角。
    //（悬停放大只有一个旋钮 hoverScale——原 deckFocusScale 与其相乘控
    // 同一效果，冲突已删）
    property real deckRestTilt: 10
    property real tiltAngle: 22
    // 卡面玻璃质感：背板浓度（悬停自动 ×1.3 提亮）/ 顶部受光 / 静置描边
    // 亮度 / 聚焦辉光强度 / 纵深压暗
    property int cardRadius: 14
    property real cardTint: 0.55
    property real cardTopLight: 0.07
    property real cardBorder: 0.13
    property real cardGlow: 0.13
    property real cardDepth: 0.38
    // 缩略图解码尺寸（宽，高等比 0.7）：越大越清晰、内存与重拍开销越大
    property int thumbSize: 320
    property real hoverScale: 1.05
    // 悬停驻留：指针停稳多久才应用聚焦排布（滑动途中只亮卡不重排 =
    // 不跳卡）。0 = 立即聚焦（旧手感）
    property int hoverDwellDelay: 200
    property int cardEnterDuration: 240
    property int tiltAnimDuration: 250
    property int engageDelay: 170
    property bool autoMinimize: true
    property int autoMinDelay: 650
    // 收编节拍：先拍快照（capture 等待多窗连拍完成）→ 矩形落盘 →
    // dispatch 后派发最小化（特效起跑延迟，与展开动画对拍）
    property int demoteCaptureDelay: 300
    property int demoteDispatchDelay: 30
    property int desktopFocusDebounce: 150
    // 活体流门控（默认关：容器 GPU 预算红线，悬停建流即被宿主杀桌面）。
    // 伪实时（thumbLive：keepBelow 后台重拍 + 静默最小化悬停预备）已整体
    // 删除——只留静态快照与活体流两态（2026-09-28 用户定案）
    property bool thumbLiveStream: false
    // 占空比节流（round36）：on=连接消费抓帧时长，off=断开（KWin 停止
    // 离屏渲染）时长；平均负载 ≈ on/(on+off) × 单流全速
    property int streamCycleOnMs: 250
    property int streamCycleOffMs: 750
    property int animDuration: 420
    // 飞行玻璃透明度：窗口在卡片↔桌面途中半透明透见桌面，落地凝实；
    // 1.0 = 关闭玻璃感（全程不透明，纯淡出）
    property real glassOpacity: 0.65
    property string animEasing: "OutCubic"

    readonly property string configPath: Quickshell.stateDir + "/stage/config.json"

    function snapshotJson(): string {
        const out = { revision: revision }
        for (const k in _schema)
            out[k] = svc[k]
        return JSON.stringify(out)
    }

    // schema 类型转换 + 钳位（set 与 _load 共用）；非法值返回 null
    // （bool 永远合法，false 是有效值不是失败）
    function _coerce(s, value) {
        if (s.type === "int" || s.type === "real") {
            let v = Number(value)
            if (isNaN(v))
                return null
            v = Math.max(s.min, Math.min(s.max, v))
            return s.type === "int" ? Math.round(v) : v
        }
        if (s.type === "bool")
            return (value === true || value === "true" || value === 1
                    || value === "1")
        if (s.type === "enum") {
            const v = String(value)
            return s.values.indexOf(v) >= 0 ? v : null
        }
        return null
    }

    // 唯一变更入口：强制转换 → 钳位 → 应用 → 副作用 → 持久化。
    // 返回整份快照，设置应用的 IPC 应答直接可用。
    function set(key, value): string {
        const s = _schema[key]
        if (!s)
            return JSON.stringify({ ok: false, error: "unknown key: " + key })
        const v = _coerce(s, value)
        if (v === null)
            return JSON.stringify({ ok: false, error: "invalid value for " + key })
        svc[key] = v
        revision++
        if (key === "animDuration" || key === "animEasing"
                || key === "tiltAngle" || key === "glassOpacity"
                || key === "deckRestTilt" || key === "layoutMode")
            _pushEffectConfig()
        _save()
        return snapshotJson()
    }

    // kwinrc 投影 + 即时 reconfigure（不重启 KWin / shell）。
    // 写手命令队列（round35 NEW-3）：滑杆连续 commit 时 Quickshell 的
    // Process 在运行中重设 command 是彻底 no-op（命令静默丢弃、特效拿旧
    // 值）——一律入队，exited 回调串行取下一条。勿改用 exec()（会 SIGTERM
    // 杀在跑的链，留下部分写入）。
    property var _writerQueue: []

    function _enqueueWriter(argv) {
        _writerQueue.push(argv)
        if (!_writer.running)
            _startNextWriter()
    }

    function _startNextWriter() {
        if (_writerQueue.length === 0)
            return
        _writer.command = _writerQueue.shift()
        _writer.running = true
    }

    function _pushEffectConfig() {
        if (!_writer)
            return
        _enqueueWriter(["bash", "-c",
            "kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key AnimationDuration " + animDuration
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key EasingCurve " + animEasing
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
                    + " --key TiltAngle " + (layoutMode === "scroll"
                        ? deckRestTilt : tiltAngle)
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key GlassOpacity " + glassOpacity
            + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects"
            + ".reconfigureEffect " + StageModeService.effectId])
    }

    function _save() {
        const out = { version: 1 }
        for (const k in _schema)
            out[k] = svc[k]
        JsonConfigStore.writePath(configPath, JSON.stringify(out))
    }

    function _load() {
        JsonConfigStore.readPath(configPath, function(data, exists) {
            if (!exists)
                return
            try {
                const obj = JSON.parse(data)
                for (const k in _schema) {
                    if (obj[k] === undefined)
                        continue
                    const v = _coerce(_schema[k], obj[k])
                    if (v === null)
                        continue
                    svc[k] = v
                }
            } catch (e) {
                console.warn("[StageConfig] bad config, keep defaults: " + e)
                return
            }
            // 启动对齐：把持久值投影到 kwinrc（覆盖 CLI 的临时试验值）
            _pushEffectConfig()
            console.info("[StageConfig] loaded revision=" + revision)
        })
    }

    // QtObject 没有默认属性，Process 经 Component 工厂实例化
    // （同 WindowService / StageModeService 写法）
    property Component _procFactory: Component {
        Process {
            stdout: StdioCollector {}
            onExited: svc._startNextWriter()
        }
    }

    property var _writer: null

    Component.onCompleted: {
        _writer = _procFactory.createObject(svc)
        _load()
    }
}
