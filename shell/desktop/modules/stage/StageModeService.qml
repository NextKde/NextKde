pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "stage-geometry.mjs" as StageGeo
import "stage-effects.mjs" as StageEffects

// Stage is opt-in: only a persisted "1" enables automatic window collection.
// The flag stores the requested mode; enabled reflects a successful effect
// transition. All effect/config writes share StageConfigService's queue.
QtObject {
    id: svc

    property bool enabled: false
    property bool _requestedEnabled: false
    property int _modeRevision: 0

    readonly property string flagDir: (Quickshell.env("XDG_CONFIG_HOME")
        || Quickshell.env("HOME") + "/.config") + "/fg-sched"
    readonly property string flagPath: flagDir + "/stage-mode"

    // Plugin id matches the installed CMake target and metadata.
    readonly property string effectId: "stageanim13"

    // 显示桌面开关：DeskCenter 空区左键 → 台前侧栏收编/放出来回切换。
    // 走单例信号：DeskCenter 与侧栏分属两个模块，这是它们之间唯一的
    // 控制通道。
    signal deskRevealToggleRequested()

    // 侧栏条矩形（屏幕逻辑坐标：顶栏之下、常驻条；几何常量同源
    // stage-geometry.mjs。X = 面板窗原点 + 溢出余量：左侧=余量本身；
    // 右侧=屏宽−窗宽+余量（面板窗锚右缘，窗宽 = 常驻条 + 两侧余量）。
    // 高度从屏幕高推导（顶栏之下到屏底）；screens[0] 是多屏下的已知近似
    // ——此矩形仅作特效第三级回落，不随面板几何变化）
    readonly property int _screenW: Quickshell.screens.length > 0
        ? Quickshell.screens[0].width : 1920
    readonly property int _screenH: Quickshell.screens.length > 0
        ? Quickshell.screens[0].height : 1080
    // kwinrc 三级回退矩形：targets 文件未命中时的粗略"顶栏之下的条带"
    // 近似（非卡位精度——精确矩形走 stage-targets.json 每窗发布，
    // 那条链路已按全屏浮层原点 (0,0) 修正，勿按卡位精度校准这里）
    readonly property string targetRectCmd: ""
        + "kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetX "
        + (StageConfigService.side === "right"
            ? String(_screenW - StageGeo.PANEL_WIDTH
                - StageGeo.CARD_OVERFLOW_MARGIN)
            : String(StageGeo.CARD_OVERFLOW_MARGIN))
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetY " + StageGeo.PANEL_ORIGIN_Y
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetWidth " + StageGeo.PANEL_WIDTH
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetHeight " + (_screenH - StageGeo.PANEL_ORIGIN_Y)
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetMirror "
        + (StageConfigService.side === "right" ? "true" : "false")

    readonly property string clearTargetRectCmd: ""
        + "kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetX --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetY --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetWidth --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetHeight --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetMirror --delete"

    function _applyMode(v, persist) {
        _requestedEnabled = v
        const revision = ++_modeRevision
        const commit = persist
            ? "mkdir -p " + StageEffects.shellQuote(flagDir)
              + " && printf '%s' '" + (v ? "1" : "0") + "' > "
              + StageEffects.shellQuote(flagPath + ".tmp")
              + " && mv " + StageEffects.shellQuote(flagPath + ".tmp")
              + " " + StageEffects.shellQuote(flagPath)
            : ":"
        const cmd = (v ? targetRectCmd : clearTargetRectCmd)
            + " && bash -c " + StageEffects.shellQuote(
                StageEffects.effectSwitchCommand(v, effectId, commit))
        StageConfigService.enqueueBashChain(["bash", "-c", cmd], function(ok) {
            if (ok) {
                svc.enabled = v
                console.info("[StageMode] enabled=" + v)
            } else {
                if (revision === svc._modeRevision)
                    svc._requestedEnabled = svc.enabled
                console.warn("[StageMode] effect transition failed; previous mode retained")
            }
        })
    }

    function setEnabled(v) {
        if (v !== _requestedEnabled)
            _applyMode(v, true)
    }

    function toggle() { setEnabled(!_requestedEnabled) }

    // 侧栏位置切换：只重投影全局回退矩形（每窗矩形由 shell 窗口侧的
    // originX 现算，不落 kwinrc），reconfigure 让特效重读。
    // ⚠️ 不能写 Connections 子对象——QtObject 没有默认属性容纳子项
    //（同 Process 直挂的坑，crash-loop 实测），Component.onCompleted
    // 里手动 connect
    function _onSideChanged() {
        StageConfigService.enqueueBashChain(["bash", "-c",
            (enabled ? targetRectCmd : clearTargetRectCmd)
            + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects"
            + ".reconfigureEffect " + effectId])
        console.info("[StageMode] side=" + StageConfigService.side)
    }

    // QtObject 没有默认属性，Process 不能直接作子对象——用 Component 工厂
    // 实例化（kwinrc 写手已收敛到 StageConfigService，这里只剩旗标读取器）。
    property Component _procFactory: Component {
        Process {
            stdout: StdioCollector {}
        }
    }

    Component.onCompleted: {
        StageConfigService.sideChanged.connect(svc._onSideChanged)
        const reader = _procFactory.createObject(svc,
            { command: ["cat", svc.flagPath] })
        reader.exited.connect(function() {
            const t = (reader.stdout?.text ?? "").trim()
            // With no saved preference, keep the desktop's existing effects.
            if (svc._modeRevision === 0 && (t === "1" || t === "0"))
                svc._applyMode(t === "1", false)
            reader.destroy()
        })
        reader.running = true
    }
}
