pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "stage-geometry.mjs" as StageGeo

// StageModeService — 前台调度（Stage 侧栏）总开关。
// 状态落盘 ~/.config/fg-sched/stage-mode（"1"/"0"），同一文件被 fg-schedd
// 的 sweep 读取作冻结门控。
// 最小化动画方向由自研 KWin 特效 stageanim（vendor/kwin-effects-stageanim，
// magiclamp 魔改）承担。目标矩形按窗口解析：
//   ① shell 发布的每窗卡片矩形（stage-targets.json，按 KWin internalId）
//   ② 全局侧栏矩形（kwinrc [Effect-stageanim] Target*，开=写入/关=清空）
//   ③ 都没有 → magiclamp 原版回落（光标/面板方向 ≈ dock）
// magiclamp 永久停用（stageanim 两模式全包）。改配置后 reconfigure 即生效。
QtObject {
    id: svc

    // 启动时由读取进程用落盘态覆盖；文件缺失/为空 = 默认开
    property bool enabled: true
    property int revision: 0

    readonly property string flagDir: Quickshell.env("HOME") + "/.config/fg-sched"
    readonly property string flagPath: flagDir + "/stage-mode"

    // KWin 特效代号——换代时只改这一处（vendor CMakeLists/metadata 与
    // ~/.local/bin/stage-anim 脚本头部需手动同步，旧代卸载流程见 AGENTS.md）
    readonly property string effectId: "stageanim13"

    // 显示桌面开关：DeskCenter 空区左键 → 台前侧栏收编/放出来回切换。
    // 走单例信号：DeskCenter 与侧栏分属两个模块，这是它们之间唯一的
    // 控制通道。
    signal deskRevealToggleRequested()

    // 侧栏条矩形（屏幕逻辑坐标：顶栏之下、左侧常驻条；几何常量同源
    // stage-geometry.mjs。X 带溢出余量偏移（面板窗比常驻条宽，内容列
    // 居中）。TargetHeight 1059 是历史全局回退矩形的实测值，仅作特效
    // 第三级回落，不随面板几何变化）
    readonly property string targetRectCmd: ""
        + "kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetX " + StageGeo.CARD_OVERFLOW_MARGIN
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetY " + StageGeo.PANEL_ORIGIN_Y
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetWidth " + StageGeo.PANEL_WIDTH
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetHeight 1059"

    readonly property string clearTargetRectCmd: ""
        + "kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetX --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetY --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetWidth --delete"
        + " && kwriteconfig6 --file kwinrc --group Effect-stageanim --key TargetHeight --delete"

    // 最小化动画特效二选一（避免两个特效抢动画）：
    //   开 = effectId（目标=卡片矩形）独占，KOS dock 精灵卸载
    //   关 = kos_dock_window_animation（KOS dock 精灵）独占，effectId 卸载
    function swapEffectsCmd(v): string { return (v ? ""
        + "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect kos_dock_window_animation"
        + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect " + effectId
        + " && kwriteconfig6 --file kwinrc --group Plugins --key " + effectId + "Enabled true"
        + " && kwriteconfig6 --file kwinrc --group Plugins --key kos_dock_window_animationEnabled false"
        : ""
        + "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect " + effectId
        + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect kos_dock_window_animation"
        + " && kwriteconfig6 --file kwinrc --group Plugins --key " + effectId + "Enabled false"
        + " && kwriteconfig6 --file kwinrc --group Plugins --key kos_dock_window_animationEnabled true")
    }

    // 写手命令队列（round35 NEW-3）：Quickshell 的 Process 在运行中重设
    // command+running=true 是彻底 no-op（命令静默丢弃）。bash 链实测
    // 200-500ms，快速 toggle/启动对齐撞车就会丢命令——一律入队，exited
    // 回调串行取下一条。勿改用 Quickshell 的 exec() 便捷方法（它会
    // SIGTERM 杀掉在跑的链，kwriteconfig 半途而死留下部分写入）。
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

    function setEnabled(v) {
        if (!_writer || v === svc.enabled)
            return
        enabled = v
        revision++
        _enqueueWriter(["bash", "-c",
            "mkdir -p " + flagDir
            + " && printf '%s' '" + (v ? "1" : "0") + "' > " + flagPath
            + " && " + (v ? targetRectCmd : clearTargetRectCmd)
            + " && " + swapEffectsCmd(v)
            + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect " + effectId])
        console.info("[StageMode] enabled=" + v)
    }

    function toggle() { setEnabled(!enabled) }

    // 首启对齐：目标矩形 + 两特效加载态二选一。必须等读取进程带回落盘态后
    // 再执行，否则会拿默认值对齐（落盘是"关"、默认是"开"的场景会开错方向）。
    function _alignWithPersistedMode() {
        _enqueueWriter(["bash", "-c",
            (enabled ? targetRectCmd : clearTargetRectCmd)
            + " && " + swapEffectsCmd(enabled)
            + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect " + effectId])
        console.info("[StageMode] startup align enabled=" + enabled)
    }

    // QtObject 没有默认属性，Process 不能直接作子对象——用 Component 工厂
    // 实例化（同 WindowService 的 probe factory 写法）。
    property Component _procFactory: Component {
        Process {
            stdout: StdioCollector {}
            onExited: svc._startNextWriter()
        }
    }

    property var _writer: null

    Component.onCompleted: {
        _writer = _procFactory.createObject(svc)
        const reader = _procFactory.createObject(svc,
            { command: ["cat", svc.flagPath] })
        reader.exited.connect(function() {
            const t = (reader.stdout?.text ?? "").trim()
            if (t.length > 0)
                svc.enabled = (t === "1")
            svc._alignWithPersistedMode()
            reader.destroy()
        })
        reader.running = true
    }
}
