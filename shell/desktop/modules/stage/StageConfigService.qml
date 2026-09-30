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
        // 布局（scroll = 完整滚动：卡片完整显示不重叠，固定间距自然排列、
        // 放不下滚轮滚动；adaptive = 等比缩小全显）
        "layoutMode":   { type: "enum", values: ["scroll", "adaptive"],
                          def: "scroll" },
        // 常驻侧：left = 屏幕左缘（默认）；right = 屏幕右缘（macOS
        // Stage Manager 的位置设置同款）。切换会翻窗口锚点/卡片镜像/
        // 特效回退矩形，三处联动见各自文件
        "side":         { type: "enum", values: ["left", "right"],
                          def: "left" },
        // 自由合并卡视觉：扇叠背板间距（px）/ 左下角图标排的图标大小 /
        // 图标排并列上限（实际还按卡宽动态封顶，超出进 "+N"）
        "fanSpacing":   { type: "int", min: 2, max: 24, def: 8 },
        "stripIconSize": { type: "int", min: 16, max: 40, def: 24 },
        "maxIconSlots": { type: "int", min: 3, max: 8, def: 5 },
        // 合并手势驻留：被拖卡压在目标卡上停此时长才"武装"并组意图
        //（用户实测调过 320→550→450，入 schema 供设置页可调）
        "mergeDwellMs": { type: "int", min: 200, max: 1200, def: 450 },
        // 卡片顶部名称：可关（沉浸缩略图——整卡就是窗口内容）
        "showCardTitle": { type: "bool", def: true },
        "cardHeight":   { type: "int", min: 100, max: 220, def: 148 },
        "cardSpacing":  { type: "int", min: 4, max: 48, def: 16 },
        "centerCards":  { type: "bool", def: true },
        "deckSidePeek": { type: "int", min: 4, max: 60, def: 20 },
        "focusDim":     { type: "bool", def: false },
        // ⚠️ 倾角上限 40 = 特效 stageanim 的 std::clamp 钳位（>40° 时
        // depth>focal 顶点镜像炸裂）——schema 越过它就是"设置页可选但
        // 静默被砍"，两处必须同步
        "deckRestTilt": { type: "real", min: 0, max: 40, def: 10 },
        "tiltAngle":    { type: "real", min: 0, max: 40, def: 22 },
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
        // 保留整条侧栏条（exclusiveZone）：关=卡片纯悬浮，最大化/普通窗
        // 可铺满全宽、滑到卡片下方（卡片浮在窗上、输入只挡卡面）
        "reserveStrip": { type: "bool", def: true },
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
        // 诊断遥测开关（[DragTrace] 拖拽跟手日志）：默认关；排障时
        // `stage-config set debugTrace true` 打开。设置页不暴露（非用户参数）
        "debugTrace":   { type: "bool", def: false },
    })

    // 运行时属性（_load 用持久值覆盖默认；分组与 schema 一一对应）
    // 卡片布局：scroll = 完整滚动（卡片完整显示永不重叠，固定间距自然
    // 排列，超出滚轮滚动，底部位置点+窗数提示）；adaptive = 自适应缩小
    //（全部完整显示，等比缩小到恰好放下）
    property string layoutMode: "scroll"
    property string side: "left"
    property int fanSpacing: 8
    property int stripIconSize: 24
    property int maxIconSlots: 5
    // ⚠️ 属性默认值 = 无 config.json 时的真实默认（_load 不回填 schema def，
    // 两处默认必须同步改——2026-09-30 审计抓过 550/450 漂移）
    property int mergeDwellMs: 450
    property bool debugTrace: false   // 诊断遥测（[DragTrace]），见 schema 注释
    property bool showCardTitle: true
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
    property bool reserveStrip: true
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
    //（bool 也一样：只有真/假布尔字面量合法）
    function _coerce(s, value) {
        if (s.type === "int" || s.type === "real") {
            // 前置拒收布尔/空串/空白串/数组/null：Number("")===0、
            // Number(" ")===0、Number(true)===1、Number(null)===0、
            // Number([5])===5 都会静默钳到 min 且 set 报 ok（IPC 手误
            // 不报错——与 bool 路径的"非法报错"契约对称，2026-09-30 审计）
            if (typeof value === "boolean" || value === null
                    || value === undefined || Array.isArray(value)
                    || String(value).trim() === "")
                return null
            let v = Number(value)
            if (isNaN(v))
                return null
            v = Math.max(s.min, Math.min(s.max, v))
            return s.type === "int" ? Math.round(v) : v
        }
        if (s.type === "bool") {
            // 收严到枚举式判定：true/"true"/1/"1" → true，false/"false"/
            // 0/"0" → false，其余 null 走 error 路径——与 int/real/enum 的
            // "非法返回 null"契约一致（原实现任意垃圾值静默转 false 且
            // set 报 ok，IPC 手误不报错直接翻转开关）
            if (value === true || value === "true" || value === 1
                    || value === "1")
                return true
            if (value === false || value === "false" || value === 0
                    || value === "0")
                return false
            return null
        }
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
    // ⚠️ 本队列是全 shell 唯一的 kwinrc 写通道（StageModeService 的
    // 开关/对齐链也走 enqueueBashChain 入这里）：kwriteconfig6 是整文件
    // 读改写、无跨进程写锁，两条队列并发时后完成者会抹掉先完成者刚写的
    // 键（审计 P1：启动对齐窗口期 Target*/特效参数互相丢失即此）。
    property var _writerQueue: []

    function _enqueueWriter(argv) {
        _writerQueue.push(argv)
        if (!_writer.running)
            _startNextWriter()
    }

    // 跨服务入口：StageModeService 的特效装卸/对齐链经此串行化
    function enqueueBashChain(argv) {
        _enqueueWriter(argv)
    }

    function _startNextWriter() {
        if (_writerQueue.length === 0)
            return
        _writer.command = _writerQueue.shift()
        _writer.running = true
    }

    // 写完读回校验（历史事故：两个 --key 挤进一条 kwriteconfig6 把值写
    // 串——GlassOpacity 被写成 25）。失配只告警不回滚：链本身成功说明
    // 写入完成，失配意味着键被别的写手覆盖或拼错，打出来给人看。
    function _verifyKeyCmd(key, expected): string {
        // 失配信息走 stderr（stdout 无人看）；写手对任何 stderr 输出都会
        // 告警，见 _procFactory 的 onExited
        return " && v=$(kreadconfig6 --file kwinrc --group Effect-stageanim"
            + " --key " + key + "); if [ \"$v\" != \"" + expected
            + "\" ]; then echo '[StageConfig] kwinrc verify " + key
            + " expected " + expected + " got'\"$v\" >&2; fi"
    }

    function _pushEffectConfig() {
        if (!_writer)
            return
        const tilt = layoutMode === "scroll" ? deckRestTilt : tiltAngle
        _enqueueWriter(["bash", "-c",
            "kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key AnimationDuration " + animDuration
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key EasingCurve " + animEasing
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key TiltAngle " + tilt
            + " && kwriteconfig6 --file kwinrc --group Effect-stageanim"
            + " --key GlassOpacity " + glassOpacity
            + " && qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects"
            + ".reconfigureEffect " + StageModeService.effectId
            + _verifyKeyCmd("TiltAngle", tilt)
            + _verifyKeyCmd("GlassOpacity", glassOpacity)])
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
    //（同 WindowService / StageModeService 写法）。stderr 接出来 + 退出码
    // 检查：bash 链任一步失败（qdbus 拒连/kwriteconfig 出错）原本无声
    // 无息——半装卸态 + 零日志是排障黑洞（审计 P1）
    property Component _procFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: function(exitCode) {
                // 退出码非零 = 链断裂；stderr 有内容 = 链走完但有告警
                //（kwinrc 验值失配等）——两种都要落 journal
                const err = stderr.text.trim()
                if (exitCode !== 0)
                    console.warn("[StageConfig] kwinrc writer chain failed"
                        + " exit=" + exitCode + " stderr: " + err)
                else if (err !== "")
                    console.warn("[StageConfig] kwinrc writer warning: "
                        + err)
                svc._startNextWriter()
            }
        }
    }

    property var _writer: null

    Component.onCompleted: {
        _writer = _procFactory.createObject(svc)
        _load()
    }
}
