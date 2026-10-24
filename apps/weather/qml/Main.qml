pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Particles
import Kos.Ui

KosApplicationWindow {
    id: root

    modernDesign: true
    visible: true
    title: qsTr("Weather")

    readonly property string temperatureUnit: backend.units === "imperial" ? "°F" : "°C"
    readonly property string speedUnit: backend.units === "imperial" ? qsTr("mph") : qsTr("km/h")
    readonly property string distanceUnit: backend.units === "imperial" ? qsTr("mi") : qsTr("km")
    readonly property int weatherSidebarWidth: Math.round(307 * AppTheme.densityScale) // ref-main 干净行（y=47 无卡无胶囊）Pillow 实测侧栏→主区过渡 x≈211.5@814 ×1.4501≈307；旧 x205 实为卡片右缘（卡右缘与侧栏缘间有 ~6px 侧栏底色带，y=440 带色 (60,91,128) ≈ 侧栏底），2026-10-18 勘误；AppTheme.sidebarWidth(224) 系 shared 值（music 引用）不动
    readonly property var upcomingHours: upcomingForecast()
    // §3 control.compact：窄窗（root.compact <940，KosApplicationWindow）工具盘圆形钮收为 compact lg=30；
    // 默认窗宽取 AppTheme.controlHeight（34），窄窗外逐字节等价
    readonly property int trayControlHeight: root.compact
        ? Math.round(30 * AppTheme.densityScale)
        : AppTheme.controlHeight
    property string pendingLocationId: ""
    readonly property int currentWeatherCode: number(backend.current, "weatherCode", -1)
    readonly property bool currentIsDay: Boolean(value(backend.current, "isDay", true))
    // 批 1｜天空系统（用户 2026-10-24）：2 态 → dawn/day/dusk/night 四时段，按本地日出日落判定；
    // 时段切换 12s 平滑插值，天气条件切换 1.2s crossfade（禁止瞬时换色）。颜色值见 skyStopsFor。
    readonly property string skyPeriod: skyPeriodFor(
        String(value(backend.current, "time", "")),
        backend.daily && backend.daily.length > 0
            ? String(value(backend.daily[0], "sunrise", "")) : "",
        backend.daily && backend.daily.length > 0
            ? String(value(backend.daily[0], "sunset", "")) : "",
        root.currentIsDay)
    property color skyTop: "#0c1a33"
    property color skyMid: "#12294d"
    property color skyBottom: "#274d79"
    property int skyTransitionMs: 12000
    property bool skyReady: false
    property string _lastSkyPeriod: ""
    property int _lastSkyCode: -2
    readonly property var skyStops: [skyTop, skyMid, skyBottom]
    Behavior on skyTop {
        enabled: root.skyReady && !AppTheme.reduceMotion
        ColorAnimation { duration: root.skyTransitionMs; easing.type: Easing.InOutSine }
    }
    Behavior on skyMid {
        enabled: root.skyReady && !AppTheme.reduceMotion
        ColorAnimation { duration: root.skyTransitionMs; easing.type: Easing.InOutSine }
    }
    Behavior on skyBottom {
        enabled: root.skyReady && !AppTheme.reduceMotion
        ColorAnimation { duration: root.skyTransitionMs; easing.type: Easing.InOutSine }
    }
    // 首次数据到达前保持瞬时赋值；1.2s 后开启动画，避免启动阶段从占位色缓慢爬升。
    Timer {
        interval: 1200
        running: true
        onTriggered: root.skyReady = true
    }
    // R113（CPU 轮）：环境动画统一节拍。此前云漂移(50ms) / hero 呼吸(66ms) / 日晕呼吸(100ms) /
    // 水珠滑落(40ms) 各自独立 Timer，事件并集 ≈45–60 次/秒 → 全窗口每秒被合成 45–60 次。
    // R108 单独降每条的频率无效（其并集仍是几十次/秒），故合并为单一 66ms(15fps) 时钟：
    // 所有消费者同一事件循环内响应，一帧只合成一次。端点/周期逐值不变（cos 曲线按 ambientSec 求值）。
    // R115（CPU 轮）：66ms(15fps) → 100ms(10fps)。R114 逐帧实测稳态帧率被本时钟钉在 15fps，
    // 单帧 GUI+RT ≈11.4ms → 帧数直接线性决定 CPU。
    // R116（CPU 轮）：本档曾试降到 133ms(7.5fps)，同会话 A/B 实测 17.7→16.0 / 16.9→17.2
    // （两对均值 17.3→16.6，落在 loadavg 噪声内）→ **帧率已不是 10fps 以下的瓶颈，试值已回退**，
    // 保持 100ms(10fps)；本轮真实改动见 sidebarBackdrop.hideSource。
    property double ambientSec: 0
    Timer {
        id: ambientTick
        interval: 100; repeat: true
        running: !AppTheme.reduceMotion
        onRunningChanged: if (!running) root.ambientSec = 0
        onTriggered: root.ambientSec = root.ambientSec + 0.100
    }
    onSkyPeriodChanged: root.refreshSkyStops()
    // live:false 的采样源：天空色每帧变化（12s 过渡）时补一次捕获；静止时不捕获。
    onSkyTopChanged: sidebarBackdrop.refresh()
    onSkyMidChanged: sidebarBackdrop.refresh()
    onSkyBottomChanged: sidebarBackdrop.refresh()
    onWidthChanged: sidebarBackdrop.refresh()
    onHeightChanged: sidebarBackdrop.refresh()
    onCurrentWeatherCodeChanged: root.refreshSkyStops()
    Component.onCompleted: root.refreshSkyStops()
    readonly property color skyText: "#ffffff"
    readonly property color skyTextMuted: Qt.rgba(1, 1, 1, 0.66)
    // tile-cards 原生分辨率实测：卡头小 caps 与卡头 glyph 同浅蓝墨（SUNSET/UV 峰值 (146,205,255)/(147,206,255)；
    // 白@α 反解三通道矛盾 R 0.33/B 0.91，证独立蓝墨非白@α），与 glyph 色 #90cbff 同源
    readonly property color cardHeaderText: "#90cbff"

    // 用户裁定 2026-10-23：卡片改**中性白玻璃**，禁止蓝色 tint 压在蓝色天空上（旧值
    // α0.30 的 (0,96,210) 深蓝玻璃在模糊蓝底上糊成一片）。白底 α0.14（夜景 0.16 不变），
    // 层级仍按 §1：L0 内容不用玻璃，白 α 属标准材质；对比度以 §2.10 正文 ≥4.5:1 复核。
    readonly property color cardGlassRgb: Qt.rgba(1, 1, 1, 1.0)
    readonly property real cardGlassAlpha: root.currentIsDay ? 0.14 : 0.16
    readonly property real cardGlassAlphaHot: root.cardGlassAlpha + 0.02 // §4 卡片（L0）hover 只 +2% 亮度（原 0.36/0.21 系 +0.06 超标）
    readonly property int tileRadius: 16 // ref-main UV 瓦角部拟合 r≈10.5@814 × 1.46 窗比 ≈ 15.3，LEDGER WIND 瓦 r≈11±1 同证；AppTheme.smallRadius(12) 是 shared 基础件不动，weather 内显式覆盖

    // Liquid Glass circular button background (stage 3, style A) for the
    // sky top bar. `selected` shows the tinted glass disc, unselected stays
    // transparent until hover; `subtle` is the always-on action-button glass
    // (same family as KosSidebarToggle: fill white@0.14 + border white@0.22).
    // hover/press 按 §4.1 叠 hoverFill/pressFill（dark 变体白 .08/.12：
    // 位于天空媒体之上、glyph 恒白，§2.6 随背景翻转与 ref-main 白色控件冲突处按 §9 以参考图为准）。
    // subtle 底 0.14 与 selected 0.27 系 ref-main 拟合值（§9 参考图优先），不随本轮改。
    component GlassCircleBg: Rectangle {
        property bool selected: false
        property bool pressed: false
        property bool hovered: false
        property bool subtle: false
        // §5 Focus：失焦或禁用即移除外环（绑定方以 activeFocus && enabled 驱动）
        property bool focused: false
        readonly property bool filled: selected || pressed || hovered || subtle
        radius: width / 2
        color: subtle ? Qt.rgba(1, 1, 1, 0.14)
            : (selected ? Qt.rgba(1, 1, 1, 0.27)
               : (pressed ? Qt.rgba(1, 1, 1, 0.12)
                  : (hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")))
        // 用户裁决 2026-10-23（R80 0.5）：内容区白描边一律去掉——盘钮填充层即材质，
        // 不再叠 1px 白边（spec §2.7 亮边由顶部 specular 高光承担）。
        Rectangle {
            // specular top sheen, clipped to the circle
            visible: parent.filled
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        Rectangle {
            // §5 Focus：2px accent 外环，偏移 2（margins −4 扣描边 2 留白恰 2px，外环计入描边宽度）；
            // 色走 LiquidStyle.focusColor（accent 无彩/明度越界回退 #3478f6，§3 color.focusFallback）
            visible: parent.focused
            anchors.fill: parent
            anchors.margins: -4
            radius: parent.radius + 2
            border.width: 2
            border.color: LiquidStyle.focusColor(AppTheme.accent)
            color: "transparent"
        }
    }
    readonly property bool nightClearSky:
        !Boolean(value(backend.current, "isDay", true))
        && (root.currentWeatherCode === 0 || root.currentWeatherCode === 1)
    readonly property bool dayClearSky:
        root.currentIsDay
        && (root.currentWeatherCode === 0 || root.currentWeatherCode === 1)
    readonly property bool rainySky: {
        const c = root.currentWeatherCode
        return (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95
    }
    readonly property bool snowySky: {
        const c = root.currentWeatherCode
        return (c >= 71 && c <= 77) || c === 85 || c === 86
    }
    readonly property bool cloudySky: {
        const c = root.currentWeatherCode
        return c === 2 || c === 3 || c === 45 || c === 48
    }
    readonly property bool thunderSky: root.currentWeatherCode >= 95
    readonly property var dailyRange: {
        let lo = Number.POSITIVE_INFINITY
        let hi = Number.NEGATIVE_INFINITY
        const rows = backend.daily ?? []
        for (let index = 0; index < rows.length; index++) {
            lo = Math.min(lo, number(rows[index], "temperatureMinimum", 0))
            hi = Math.max(hi, number(rows[index], "temperatureMaximum", 0))
        }
        return hi > lo ? { minimum: lo, maximum: hi } : { minimum: 0, maximum: 1 }
    }

    function clamp(value, minimum, maximum) {
        return Math.min(Math.max(value, minimum), maximum)
    }

    function mulberry32(seed) {
        let state = seed >>> 0
        return function() {
            state = (state + 0x6D2B79F5) >>> 0
            let t = state
            t = Math.imul(t ^ (t >>> 15), t | 1)
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    // Star positions come from a fixed-seed PRNG so the layout is identical
    // on every launch; the twinkle phase (below) intentionally uses
    // Math.random() so each run animates from a different point.
    readonly property var starField: {
        const random = mulberry32(20261016)
        const stars = []
        for (let index = 0; index < 48; index++) {
            stars.push({
                xRatio: random(),
                yRatio: Math.pow(random(), 1.3) * 0.75,
                diameter: 1.2 + random() * 1.6,
                baseOpacity: 0.35 + random() * 0.6,
                twinkleMs: 2400 + random() * 4800
            })
        }
        // R115（CPU 轮）：闪烁相位与间歇用**独立** PRNG 生成，绝不扰动上面的位置/尺寸序列
        // （同一条 random 流继续取数会让后续星位变化）。相位仍每次启动随机。
        for (let index = 0; index < stars.length; index++) {
            stars[index].twinklePauseMs = Math.random() * stars[index].twinkleMs
        }
        return stars
    }

    // 批 3｜粒子与闪电（用户 2026-10-24）：雨/雪由 64/56 个 QML delegate
    // 改为 Canvas 粒子池（雨 420 / 雪 320，均 ≥300），粒子数接降水强度、
    // 下落带风向偏移（windDirection）、雨/雪形态区分（雨=斜线，雪=圆点+摆动）。
    // backend WeatherCurrent 无降水强度字段（services/data-service/weather.go:68），
    // 按 weatherCode 映射为 0..1（映射表见 LEDGER 外推待确认）。
    readonly property real precipitationIntensity: {
        const code = root.currentWeatherCode
        if (code >= 51 && code <= 55) return 0.35   // drizzle
        if (code === 56 || code === 57) return 0.50 // freezing drizzle
        if (code >= 61 && code <= 63) return 0.65   // rain
        if (code >= 64 && code <= 67) return 0.90   // heavy/freezing rain
        if (code >= 71 && code <= 73) return 0.45   // snow
        if (code >= 74 && code <= 77) return 0.85   // heavy snow
        if (code === 80) return 0.55
        if (code === 81) return 0.75
        if (code === 82) return 0.95
        if (code === 85) return 0.65
        if (code === 86) return 0.90
        if (code >= 95) return 0.95                 // thunderstorm
        return 0
    }
    readonly property real windDirectionDeg: root.number(backend.current, "windDirection", 0)
    readonly property real windSpeedValue: Math.max(0, root.number(backend.current, "windSpeed", 0))
    // 风向为气象「来向」，粒子运动方向 = 来向 +180°；风偏移映射
    // windFactor = clamp(windSpeed/40, 0, 1)（40 km/h 及以上按满速），
    // 雨滴水平速度 = sin(rad(dir+180)) × 260 × windFactor px/s。
    readonly property real windDriftX: {
        const rad = (root.windDirectionDeg + 180) * Math.PI / 180
        return Math.sin(rad) * Math.min(root.windSpeedValue / 40, 1) * 260
    }
    // 批 7｜Qt AngleDirection：angle 以 +x 轴为 0°、顺时针（y 向下）。
    // 水平分量沿用既有 windDriftX（windDirection+180 的来向取反），垂直分量取该层标称下落速度；
    // ±3° 抖动由 AngleDirection.angleVariation 提供。无风时退化为正下方 90°。
    function rainAngleFor(vy) {
        const vx = root.windDriftX
        if (Math.abs(vx) < 0.001) return 90
        return Math.atan2(vy, vx) * 180 / Math.PI
    }
    function rainMagFor(vy) {
        return Math.sqrt(root.windDriftX * root.windDriftX + vy * vy)
    }
    // 批 11｜雨粒子层已删除（雨＝静止水痕），雨密度池/计数属性随之移除。
    readonly property int snowParticlePool: 320
    readonly property int snowParticleCount:
        Math.round(root.snowParticlePool * root.precipitationIntensity)

    // 批 2｜云层分层与参数化（用户 2026-10-24）：单层 → 前/中/后三层，
    // 速度比 前:中:后 = 1 : 0.55 : 0.3（前最快），透明度随深度递减（后层更淡）。
    // 云朵数量与不透明度接 cloudCover（0% 无云、100% 满覆盖），不再写死随机数。
    // backend WeatherCurrent 无 cloudCover 字段（services/data-service/weather.go:68），
    // 故按 weatherCode 映射为百分比（映射表见 LEDGER 外推待确认）。
    readonly property real cloudCover: {
        const code = root.currentWeatherCode
        if (code < 0) return 0
        if (code === 0) return 0.05          // clear
        if (code === 1) return 0.22          // mainly clear
        if (code === 2) return 0.55          // partly cloudy
        if (code === 3) return 0.95          // overcast
        if (code === 45 || code === 48) return 0.85   // fog
        if (code >= 51 && code <= 57) return 0.80     // drizzle
        if (code >= 61 && code <= 67) return 0.90     // rain
        if (code >= 71 && code <= 77) return 0.92     // snow
        if (code >= 80 && code <= 82) return 0.75     // showers
        if (code >= 95) return 0.95          // thunderstorm
        return 0.60
    }
    readonly property real cloudCoverOpacity: 0.25 + 0.75 * root.cloudCover

    // 批 4｜大气洗层（用户 2026-10-24）：雾/霾/沙尘半透 wash，按 weatherCode 开关，
    // opacity 0.12–0.30（裁决区间）。Open-Meteo 无霾/沙尘码，WMO 30–35 按沙尘处理；
    // 45/48 为雾/雾凇。静态层，无动画（reduceMotion 天然满足）。
    readonly property var atmosphereWash: {
        const code = root.currentWeatherCode
        if (code === 45) return { color: "#d8dee6", alpha: 0.30 }       // fog
        if (code === 48) return { color: "#c9d6e2", alpha: 0.26 }       // depositing rime fog
        if (code >= 30 && code <= 35) return { color: "#c4a678", alpha: 0.24 } // dust / sand
        return { color: "#d8dee6", alpha: 0 }
    }
    readonly property real atmosphereWashAlpha: root.atmosphereWash.alpha
    readonly property color atmosphereWashColor: root.atmosphereWash.color

    // 批 4｜夜空月亮：按 moonPhase 相位绘制，位置随时间（月相决定月中天时刻——
    // 新月≈12:00、满月≈00:00，故 transit = 12:00 + 24h×phase）。天顶/地平弧与
    // ±6h 可见窗口为天文近似推导值（无星历表，记 LEDGER 外推）。
    readonly property real moonPhaseNorm: {
        const v = root.number(backend.current, "moonPhase", Number.NaN)
        return Number.isFinite(v) ? ((v % 1) + 1) % 1 : 0.5
    }
    readonly property int moonClockMinute: {
        const t = root.clockMinutes(root.value(backend.current, "time", ""))
        return Number.isNaN(t) ? 720 : t
    }
    readonly property int moonTransitMinute: (720 + Math.round(1440 * root.moonPhaseNorm)) % 1440
    readonly property real moonDeltaMinute: {
        let d = root.moonClockMinute - root.moonTransitMinute
        while (d > 720) d -= 1440
        while (d < -720) d += 1440
        return d
    }
    readonly property bool moonVisible: !root.currentIsDay
        && Math.abs(root.moonDeltaMinute) < 360
        && root.cloudCover < 0.9
    readonly property real moonXRatio: 0.5 + (root.moonDeltaMinute / 720) * 0.72
    readonly property real moonYRatio:
        0.09 + 0.40 * (1 - Math.cos(Math.min(Math.abs(root.moonDeltaMinute) / 360, 1) * Math.PI / 2))

    // 三层云参数。driftMs = 基准 9000ms / 速度比 → 前 9000 / 中 16364 / 后 30000。
    // maxCount 为 100% 覆盖时的满额朵数，实际朵数 = round(maxCount × cloudCover)。
    readonly property var cloudLayers: [
        { name: "back",  speed: 0.30, driftMs: 30000, depthOpacity: 0.55,
          maxCount: 5, wMin: 260, wRange: 200, hRatio: 0.24, yMax: 0.20, alphaBase: 0.16, alphaRange: 0.10 },
        { name: "mid",   speed: 0.55, driftMs: 16364, depthOpacity: 0.78,
          maxCount: 5, wMin: 220, wRange: 160, hRatio: 0.30, yMax: 0.34, alphaBase: 0.22, alphaRange: 0.12 },
        { name: "front", speed: 1.00, driftMs: 9000,  depthOpacity: 1.00,
          maxCount: 4, wMin: 150, wRange: 170, hRatio: 0.38, yMax: 0.46, alphaBase: 0.30, alphaRange: 0.18 }
    ]

    // Cloud puffs: fixed-seed PRNG so the layout is identical on every
    // launch; each cloud drifts across the full screen. ref-main 观感拟合（用户第二批背景轮）：
    // 云deck集中在顶部 ~50%（ref 云带在 top 8-45%），三层——后层大而淡的云堤、
    // 中层过渡、前层较实的结构云（paint 时分层出阴影底/受光顶，光源左上 §2.7）。
    readonly property var cloudField: {
        const random = mulberry32(20261019)
        const clouds = []
        for (let layerIndex = 0; layerIndex < root.cloudLayers.length; layerIndex++) {
            const spec = root.cloudLayers[layerIndex]
            const count = Math.round(spec.maxCount * root.cloudCover)
            for (let index = 0; index < count; index++) {
                const cloudWidth = spec.wMin + random() * spec.wRange
                const puffs = []
                // 结构云细化（ref-main 观感）：旧版每朵只有 5 个大半径径向渐变团，
                // 上屏读成散景光斑；改为沿云体横向等距铺 14 个小绒团 + 随机抖动，
                // 形成连续云 deck 的细部。云朵数量/透明度/速度比不变（批 2 裁决）。
                for (let puff = 0; puff < 14; puff++) {
                    puffs.push({
                        cxRatio: 0.04 + (puff / 13) * 0.92 + (random() - 0.5) * 0.07,
                        cyRatio: 0.32 + random() * 0.36,
                        rRatio: 0.15 + random() * 0.18,
                        alphaMul: 0.55 + random() * 0.45
                    })
                }
                puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
                clouds.push({
                    layer: spec.name,
                    xRatio: random(),
                    yRatio: random() * spec.yMax,
                    cloudWidth: cloudWidth,
                    cloudHeight: cloudWidth * spec.hRatio,
                    opacity: (spec.alphaBase + random() * spec.alphaRange)
                             * spec.depthOpacity * root.cloudCoverOpacity,
                    driftMs: spec.driftMs,
                    phaseMs: random() * spec.driftMs,
                    puffs: puffs
                })
            }
        }
        return clouds
    }
    readonly property var cloudFieldBack: root.cloudField.filter(function(c) { return c.layer === "back" })
    readonly property var cloudFieldMid: root.cloudField.filter(function(c) { return c.layer === "mid" })
    readonly property var cloudFieldFront: root.cloudField.filter(function(c) { return c.layer === "front" })

    // Static high cloud band for the clear day sky: a fixed-seed PRNG lays
    // out 5 soft white streaks hugging the top of the window. Streak form
    // per ref-main measurement: clouds are concentrated in the top 8-15% of
    // the window height and rendered as long, horizontally feathered bands
    // (aspect ratio ~7:1) rather than discrete round puffs. Purely
    // decorative, never animated.
    readonly property var clearSkyClouds: {
        const random = mulberry32(20261020)
        const clouds = []
        for (let index = 0; index < 5; index++) {
            const cloudWidth = 300 + random() * 160
            const puffs = []
            for (let puff = 0; puff < 8; puff++) {
                puffs.push({
                    // Streak form per ref-main measurement: puffs are laid out
                    // at even horizontal spacing so neighbours overlap into a
                    // single feathered horizontal band (top 8-15% of window).
                    cxRatio: 0.12 + puff * 0.105 + (random() - 0.5) * 0.05,
                    cyRatio: 0.5 + (random() - 0.5) * 0.3,
                    rRatio: 0.55 + random() * 0.25,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: index * 0.035 + random() * 0.025,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.14,
                opacity: 0.40 - index * 0.075 + random() * 0.05,
                puffs: puffs
            })
        }
        return clouds
    }

    // Static faint cloud band for the clear night sky, added per user ruling
    // 2026-10-18. No night reference image exists (refs are day-only), so
    // geometry/opacity is a programmatic approximation: 4 flatter wisps
    // (height = width * 0.24) at much lower opacity than the day band, since
    // the night sky is dark and the clouds must stay subtle. Purely
    // decorative, static texture, never animated (reduce-motion safe by
    // construction, no frame-diff obligation).
    readonly property var nightClearClouds: {
        const random = mulberry32(20261021)
        const clouds = []
        for (let index = 0; index < 4; index++) {
            const cloudWidth = 340 + random() * 180
            const puffs = []
            for (let puff = 0; puff < 5; puff++) {
                puffs.push({
                    cxRatio: 0.1 + random() * 0.8,
                    cyRatio: 0.3 + random() * 0.4,
                    rRatio: 0.28 + random() * 0.22,
                    alphaMul: 0.6 + random() * 0.4
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: index * 0.085 + random() * 0.04,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.24,
                opacity: 0.16 - index * 0.035 + random() * 0.02,
                puffs: puffs
            })
        }
        return clouds
    }

    // Static per-card cloud texture for sidebar city cards: the reference
    // sidebar (tile-sidebar) shows every city card carrying weather-
    // appropriate sky texture (white puffs on day cards, faint wisps on the
    // night card). Fixed-seed PRNG per card index so each card differs but
    // stays identical across launches. Purely decorative, never animated.
    // Shown on every card: the reference shows sky texture on all five
    // visible cards (day and night alike); the clear-day card form is an
    // extrapolation from the main-window clear-day band precedent.
    function sidebarCardClouds(cardIndex, isDay) {
        const random = mulberry32(20261022 + cardIndex * 97)
        const clouds = []
        for (let i = 0; i < 3; i++) {
            const cloudWidth = 70 + random() * 60
            const puffs = []
            // 与主天空同一细化口径：小绒团铺满云体，避免侧栏卡上读成模糊白斑。
            for (let puff = 0; puff < 10; puff++) {
                puffs.push({
                    cxRatio: 0.06 + (puff / 9) * 0.88 + (random() - 0.5) * 0.08,
                    cyRatio: 0.34 + random() * 0.32,
                    rRatio: 0.18 + random() * 0.16,
                    alphaMul: 0.5 + random() * 0.5
                })
            }
            puffs.sort(function(a, b) { return a.cxRatio - b.cxRatio })
            clouds.push({
                xRatio: random(),
                yRatio: i * 0.28 + random() * 0.18,
                cloudWidth: cloudWidth,
                cloudHeight: cloudWidth * 0.3,
                opacity: (isDay ? 0.32 : 0.13) - i * 0.07 + random() * 0.03,
                puffs: puffs
            })
        }
        return clouds
    }

    // 时刻（本地 ISO 无时区后缀）→ 分钟数；无法解析返回 NaN
    function clockMinutes(isoTime) {
        const match = String(isoTime ?? "").match(/T(\d{2}):(\d{2})/)
        if (!match) return Number.NaN
        return Number(match[1]) * 60 + Number(match[2])
    }

    // 4 时段判定（用户 2026-10-24 批 1）：以本地日出/日落为锚点。
    // dawn = 日出前 50min – 日出后 60min；dusk = 日落前 60min – 日落后 50min；
    // 其余按日升/日落分 day/night。窗口宽度 spec/参考图均未给，记 LEDGER 外推。
    function skyPeriodFor(currentTime, sunrise, sunset, isDay) {
        const now = clockMinutes(currentTime)
        const rise = clockMinutes(sunrise)
        const set = clockMinutes(sunset)
        if (!Number.isNaN(now) && !Number.isNaN(rise) && !Number.isNaN(set)) {
            if (now >= rise - 50 && now < rise + 60) return "dawn"
            if (now >= set - 60 && now < set + 50) return "dusk"
            if (now >= rise + 60 && now < set - 60) return "day"
            return "night"
        }
        return Boolean(isDay) ? "day" : "night"
    }

    // 天空目标色刷新：时段切换走 12s 插值，天气条件切换走 1.2s crossfade。
    function refreshSkyStops() {
        const next = skyStopsFor(root.currentWeatherCode, root.skyPeriod)
        const periodChanged = root._lastSkyPeriod !== ""
            && root._lastSkyPeriod !== root.skyPeriod
        const codeChanged = root._lastSkyCode !== -2
            && root._lastSkyCode !== root.currentWeatherCode
        root.skyTransitionMs = (codeChanged || !periodChanged) ? 1200 : 12000
        root.skyTop = next[0]
        root.skyMid = next[1]
        root.skyBottom = next[2]
        root._lastSkyPeriod = root.skyPeriod
        root._lastSkyCode = root.currentWeatherCode
    }

    // 4 时段调色板（day/night 沿用既有 ref-main 拟合值；dawn/dusk 按 iOS 天气晨昏观感拟合，
    // spec §3 无天空色 token，记 LEDGER 外推）。第二参数兼容旧布尔调用（侧栏城市卡：day/night）。
    function skyStopsFor(code, periodOrIsDay) {
        const c = Number(code)
        const period = typeof periodOrIsDay === "string"
            ? periodOrIsDay
            : (Boolean(periodOrIsDay) ? "day" : "night")
        if (period === "dawn") {
            if (c >= 95) return ["#2a2f47", "#5b4a5c", "#8a6f74"]
            if (c === 0 || c === 1) return ["#37456e", "#c97a5c", "#f0b184"]
            if (c === 2) return ["#3f4a6d", "#b8795f", "#dfa886"]
            if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82))
                return ["#4c5369", "#7d6f74", "#a08c8c"]
            if ((c >= 71 && c <= 77) || c === 85 || c === 86)
                return ["#5f6a82", "#a98a92", "#d3b4b4"]
            return ["#48506a", "#9c7a6d", "#c39f8b"]
        }
        if (period === "dusk") {
            if (c >= 95) return ["#262a42", "#6a4a58", "#95687a"]
            if (c === 0 || c === 1) return ["#2f3a62", "#c9644a", "#ee8f60"]
            if (c === 2) return ["#394468", "#ad5f4e", "#d08064"]
            if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82))
                return ["#474d63", "#7a6368", "#997f7e"]
            if ((c >= 71 && c <= 77) || c === 85 || c === 86)
                return ["#59637b", "#a78591", "#cba6ac"]
            return ["#444a5f", "#96685f", "#bd8875"]
        }
        if (period === "night") {
            if (c >= 95) return ["#141a2c", "#1d2740", "#33415f"]
            if (c === 0 || c === 1) return ["#0c1a33", "#12294d", "#274d79"]
            if (c === 2) return ["#101f38", "#1a3355", "#31507a"]
            return ["#0f1826", "#1b2637", "#2e3c52"]
        }
        if (c >= 95) return ["#2a3752", "#3c4c6e", "#5a6b8c"]
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82))
            return ["#9ab5c4", "#92aebe", "#b9c5ce"]   // ref-main Chicago 白天卡实测：top(154,181,196)/mid(146,174,190)/bottom(185,197,206)——旧值 ["#3d5a7d","#2a4a70","#5f83a8"] 过暗（实测 (61,90,125)，ref 白天卡均 >150 亮度）
        if ((c >= 71 && c <= 77) || c === 85 || c === 86)
            return ["#7b90a6", "#5d7690", "#a9bccd"]
        // ref-main 观感拟合（用户 2026-10-23 第二批判据：以 ref-main 观感为准）：云隙蓝天梯度，
        // 顶部灰蓝由云deck覆盖，中段 y0.45 实测 ≈#1560b2，底部深蓝 ≈#0c5aa8。原灰调
        // ["#6a7b90","#4a5d75","#8ba0b5"] 是"粗糙感"来源之一（ref 顶部云隙间仍为饱和蓝）。
        if (c === 3 || c === 45 || c === 48) return ["#6288b5", "#1560b2", "#0c5aa8"]
        return ["#4a74ab", "#1469bc", "#5a90c9"]   // clear / mainly clear / partly cloudy day
    }

    function tempColor(temperature) {
        const u = clamp((temperature - dailyRange.minimum)
                        / (dailyRange.maximum - dailyRange.minimum), 0, 1)
        const cold = Qt.rgba(0.671, 0.827, 0.627, 1)   // #abd3a0 — tile-10day 原生条带实测低端绿（ref-main Thu 行 u=0 起点 #a8d4a4 同族）
        const mid  = Qt.rgba(0.812, 0.820, 0.482, 1)   // #cfd17b — tile-10day 原生条带实测中段黄绿
        const hot  = Qt.rgba(1, 0.839, 0.039, 1)       // #ffd60a — 原生条带实测高端金 #ffd603/#ffd000 家族（原值在族内，保留）
        const first = u < 0.5
        const amount = first ? u * 2 : (u - 0.5) * 2
        const a = first ? cold : mid
        const b = first ? mid : hot
        return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount,
                       a.b + (b.b - a.b) * amount, 1)
    }

    function activationOption(activationArgs, name) {
        const prefix = name + "="
        for (let index = 0; index < activationArgs.length; index++) {
            const argument = String(activationArgs[index])
            if (argument === name && index + 1 < activationArgs.length)
                return String(activationArgs[index + 1])
            if (argument.startsWith(prefix))
                return argument.slice(prefix.length)
        }
        return ""
    }

    function selectPendingLocation() {
        if (!pendingLocationId)
            return
        const source = backend.locations ?? []
        for (let index = 0; index < source.length; index++) {
            if (String(value(source[index], "id", "")) === pendingLocationId) {
                backend.selectLocation(source[index])
                pendingLocationId = ""
                return
            }
        }
    }

    function handleActivation(activationArgs, workingDirectory) {
        pendingLocationId = activationOption(activationArgs, "--location")
        selectPendingLocation()
    }

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === null || result === undefined ? fallback : result
    }

    function number(record, key, fallback) {
        const result = Number(value(record, key, fallback))
        return Number.isFinite(result) ? result : fallback
    }

    function locationName(location) {
        return String(value(location, "name", qsTr("Unknown location")))
    }

    function locationDetail(location) {
        const region = String(value(location, "admin1", ""))
        const country = String(value(location, "country", ""))
        if (region.length > 0 && country.length > 0 && region !== country)
            return region + ", " + country
        return region.length > 0 ? region : country
    }

    function conditionText(code) {
        const weatherCode = Number(code)
        if (weatherCode === 0) return qsTr("Clear sky")
        if (weatherCode === 1) return qsTr("Mainly clear")
        if (weatherCode === 2) return qsTr("Partly cloudy")
        if (weatherCode === 3) return qsTr("Overcast")
        if (weatherCode === 45 || weatherCode === 48) return qsTr("Fog")
        if (weatherCode >= 51 && weatherCode <= 57) return qsTr("Drizzle")
        if (weatherCode >= 61 && weatherCode <= 67) return qsTr("Rain")
        if (weatherCode >= 71 && weatherCode <= 77) return qsTr("Snow")
        if (weatherCode >= 80 && weatherCode <= 82) return qsTr("Rain showers")
        if (weatherCode >= 85 && weatherCode <= 86) return qsTr("Snow showers")
        if (weatherCode >= 95) return qsTr("Thunderstorm")
        return qsTr("Unknown conditions")
    }

    function localTime(isoTime) {
        const match = String(isoTime ?? "").match(/T(\d{2}:\d{2})/)
        return match ? match[1] : "--:--"
    }

    function cardTimeText(isoTime) {
        try {
            const parsed = new Date(String(isoTime))
            if (!Number.isNaN(parsed.getTime()))
                return Qt.formatTime(parsed, "h:mmAP")
        } catch (error) {
        }
        return String(isoTime ?? "").slice(11, 16)
    }

    function dayLabel(isoDate, index) {
        if (index === 0)
            return qsTr("Today")
        if (index === 1)
            return qsTr("Tomorrow")
        const parsed = new Date(String(isoDate) + "T12:00:00")
        return Number.isNaN(parsed.getTime())
            ? String(isoDate) : AppTheme.formatDate(parsed, "dddd")
    }

    function upcomingForecast() {
        const result = []
        const points = backend.hourly ?? []
        const currentTime = String(value(backend.current, "time", ""))
        let start = 0
        if (currentTime.length > 0) {
            while (start < points.length
                   && String(value(points[start], "time", "")) < currentTime)
                start++
        }
        for (let index = start; index < Math.min(points.length, start + 10); index++)
            result.push(points[index])
        return result
    }

    component WeatherMetric: Rectangle {
        id: metric

        required property string symbol
        required property string labelText
        required property string valueText

        implicitHeight: 66
        radius: root.tileRadius
        // 中性白玻璃（用户裁定 2026-10-23）：填充走 cardGlassRgb/cardGlassAlpha（白 α0.14/0.16），
        // 禁蓝色 tint；白天卡比天空亮、夜里更亮。白描边已按用户裁决 2026-10-23（R80 0.5）去除。
        property bool hot: metricHover.hovered
        // unified with full-width cards (AQ/10-day): fill 0.16; ref-main shows one shared card material
        property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
        Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
        color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)
        Accessible.role: Accessible.StaticText
        Accessible.name: metric.labelText + ": " + metric.valueText

        HoverHandler { id: metricHover }
        ToolTip.visible: metricHover.hovered
        ToolTip.text: metric.labelText

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9

            // ref-main SUNSET/UV 卡 glyph 直接放卡面上无盒子（4x 实测），白方块底系旧发明，TASK 阶段三 A 禁"半透明白方块"
            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Label {
                    anchors.centerIn: parent
                    text: metric.symbol
                    color: root.skyTextMuted
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Label {
                    Layout.fillWidth: true
                    // 参考设计头部为全大写+字距（同 :1458 AQ 卡头）
                    text: metric.labelText.toLocaleUpperCase(Qt.locale())
                    color: root.skyTextMuted
                    font.pixelSize: 10
                    font.letterSpacing: 1.4
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                Label {
                    Layout.fillWidth: true
                    text: metric.valueText
                    color: root.skyText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }
            }
        }
    }

    WeatherClient {
        id: backend
        onSnapshotChanged: root.selectPendingLocation()
    }

    Timer {
        id: searchDebounce
        interval: 450
        onTriggered: backend.searchLocations(locationField.text)
    }

    KosSettingsDialog {
        id: settingsDialog
        settings: root.applicationSettings
        applicationName: qsTr("Weather")
    }

    Shortcut {
        sequences: [StandardKey.Refresh]
        onActivated: backend.refresh()
    }

    // 液态玻璃采样源（§2.2：玻璃采样 L0 内容、拒绝自捕获）。声明在不透明天空矩形
    // 之前 → 被 sky 全覆盖、屏上不可见，仅供 LiquidBackdrop 捕获。内容 = 胶囊背后
    // 的真实合成（天空副本 + 半透明侧栏面 sidebarSurface@α，侧栏本体系 α0.32/0.36
    // 玻璃面，星空/云可透）；不含任何玻璃消费方。
    Rectangle {
        id: sidebarGlassUnderlay
        width: sidebar.width
        height: root.height
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.skyTop }
            GradientStop { position: 0.45; color: root.skyMid }
            GradientStop { position: 1.0; color: root.skyBottom }
        }
        Rectangle { anchors.fill: parent; color: AppTheme.sidebarSurface }
    }
    // CPU 轮（批 9 后续）：静采源只在天空色/尺寸变化时重捕获，不再 live:true 每帧
    // 强制重绘（§1 L0 采样源、不参与玻璃预算）。12s 天空过渡期间 onSky*Changed 每帧
    // 触发 refresh()，观感与 live 等价；静止时 0 次捕获。
    LiquidBackdrop {
        id: sidebarBackdrop
        sourceItem: sidebarGlassUnderlay
        live: false
        // R116（CPU 轮）：采样源在场景里被后面的不透明天空矩形整块覆盖，本就不上屏；
        // 但 ShaderEffectSource 默认 hideSource:false 会让它每帧仍参与合成（整窗高渐变 +
        // 侧栏面填充，纯过绘制）。置 true 后只留 1 次按需捕获，稳态每帧少两层全窗/全高绘制。
        hideSource: true
        onAvailableChanged: refresh()
        Component.onCompleted: refresh()
    }

    // 批 12｜天空折射源容器：所有天空层（渐变 / 云 / 日晕 / 星空 / 月亮 / 洗层）
    // 通过 `parent: skyComposite` 收进来，作为 ShaderEffectSource 的唯一采样源。
    // 属于 L0 天空材质，不入玻璃预算（§1/§2.2）。
    Item {
        id: skyComposite
        anchors.fill: parent
    }

    ShaderEffectSource {
        id: skyRefractionSource
        anchors.fill: parent
        sourceItem: skyComposite
        // 雨天：源不直接上屏，只经水图折射后由下方 ShaderEffect 输出；
        // 非雨天完全旁路（hideSource=false、live=false），成本为零。
        hideSource: root.rainySky
        live: root.rainySky
        recursive: false
        wrapMode: ShaderEffectSource.ClampToEdge
    }

    // 批 12｜雨＝折射（不是画白点）：waterMap 的 RG 是偏移图，A 是覆盖率；
    // uv' = uv + (RG−0.5)·strength·A → 一次纹理查表完成透镜折射；
    // 再把偏移向量当法线做单点镜面高光（光源左上 §2.7）+ 极淡雾。
    ShaderEffect {
        id: rainRefraction
        anchors.fill: parent
        visible: root.rainySky
        vertexShader: Qt.resolvedUrl("shaders/rain_refract.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/rain_refract.frag.qsb")
        property var source: skyRefractionSource
        property var waterMap: waterMapSource
        property vector2d surfaceSize: Qt.vector2d(Math.max(1, width), Math.max(1, height))
        property vector2d mapRepeat: Qt.vector2d(width / 512.0, height / 512.0)
        property real strength: 0.12
        property real specular: 0.28
        property real fog: 0.05
    }

    // 批 12｜水图 512×512（运行时 Canvas 绘制一次，静止时不重绘）：
    // 网格 40px + ±40% 抖动 + 按列错位；主层 ~160 颗、远层 ~90 颗、冷凝小点 ~200 颗。
    // 每颗用 drop-offset.png（R=y 偏移 / G=x 偏移 / B=深度 / A=覆盖率）盖图。
    Canvas {
        id: waterMapCanvas
        width: 512
        height: 512
        property var offsetSprite: null
        Accessible.ignored: true
        Component.onCompleted: offsetSprite = loadImage("particles/drop-offset.png")
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!offsetSprite)
                return
            let seed = 20261024
            function rnd() {
                seed |= 0
                seed = (seed + 0x6D2B79F5) | 0
                let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
                t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
                return ((t ^ (t >>> 14)) >>> 0) / 4294967296
            }
            function stamp(x, y, size, alpha) {
                ctx.globalAlpha = alpha
                ctx.drawImage(offsetSprite, x - size / 2, y - size / 2, size, size)
            }
            const cell = 40
            const cols = Math.ceil(width / cell)
            const rows = Math.ceil(height / cell)
            // 主层 ~160 颗（12–20px）：格内抖动 ±40%，每列独立错位破坏整齐感。
            let placed = 0
            for (let row = 0; row < rows && placed < 160; row++) {
                for (let col = 0; col < cols && placed < 160; col++) {
                    if (rnd() < 0.05)
                        continue
                    const jx = (rnd() - 0.5) * cell * 0.8
                    const jy = (rnd() - 0.5) * cell * 0.8
                    const colShift = ((col * 7) % 5 - 2) * 7
                    stamp(col * cell + cell / 2 + jx + colShift,
                          row * cell + cell / 2 + jy,
                          16 + rnd() * 10, 1.0)
                    placed++
                }
            }
            // 远层 ~90 颗（6–10px，UV×1.85 → 视觉上更小更淡）。
            for (let i = 0; i < 90; i++) {
                stamp(rnd() * width, rnd() * height,
                      9 + rnd() * 4, 0.55)
            }
            // 冷凝小点 ~200 颗（1–3px，α 极低）。
            for (let i = 0; i < 200; i++) {
                stamp(rnd() * width, rnd() * height,
                      1 + rnd() * 2, 0.18)
            }
            ctx.globalAlpha = 1
            waterMapSource.scheduleUpdate()
        }
    }

    ShaderEffectSource {
        id: waterMapSource
        width: 512
        height: 512
        sourceItem: waterMapCanvas
        hideSource: true
        live: false
        wrapMode: ShaderEffectSource.Repeat
        textureSize: Qt.size(512, 512)
    }

    Rectangle {
        id: skyGradientRect
        parent: skyComposite
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.skyTop }
            GradientStop { position: 0.45; color: root.skyMid }
            GradientStop { position: 1.0; color: root.skyBottom }
        }
        // R119（CPU 轮）：整窗渐变是每帧重绘面积最大的一层（1180×727）。衬成层纹理后
        // 稳态每帧只做一次不透明 blit，渐变求值只在天空色/尺寸真正变化时发生
        // （12s 天空过渡期间逐帧重建，与原来等价；静止时 0 次）。
        // 视觉零改动：覆盖整窗的不透明 L0 天空（§1 L0，非玻璃，§2.2 预算未变）。
        layer.enabled: true
    }

    // Static procedural cirrus band for the clear day sky (see
    // clearSkyClouds). Painted once per canvas resize, never animated.
    // Clouds are kept to the right of the (opaque) sidebar so none of the
    // band is wasted behind it.
    Item {
        id: clearSkyCloudLayer
        parent: skyComposite
        anchors.fill: parent
        visible: root.dayClearSky
        clip: true
        readonly property real cloudLeft:
            root.compact ? AppTheme.compactSidebarWidth : root.weatherSidebarWidth

        Repeater {
            model: root.clearSkyClouds

            delegate: Item {
                id: clearSkyCloud
                required property var modelData

                x: clearSkyCloudLayer.cloudLeft
                   + (clearSkyCloudLayer.width - clearSkyCloudLayer.cloudLeft - width)
                     * modelData.xRatio
                y: (clearSkyCloudLayer.height - height) * modelData.yRatio
                width: modelData.cloudWidth
                height: modelData.cloudHeight
                opacity: modelData.opacity
                Accessible.ignored: true

                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < modelData.puffs.length; i++) {
                            const p = modelData.puffs[i]
                            const cx = p.cxRatio * width
                            const cy = p.cyRatio * height
                            // Keep the gradient inside the canvas: alpha must
                            // reach 0 before any clipped edge, otherwise puffs
                            // show hard rectangular borders.
                            const r = Math.max(Math.min(p.rRatio * height * 1.2,
                                                        cy, height - cy,
                                                        cx, width - cx), 8)
                            // Horizontal-ellipse gradient (streak form, per
                            // ref-main top 8-15% height feathered band
                            // measurement): scale the circular gradient wider
                            // than tall; radii stay clamped to the canvas so
                            // alpha still reaches 0 before any clip.
                            const rx = Math.min(r * 2.6, cx, width - cx)
                            const ry = Math.min(r, cy, height - cy)
                            ctx.save()
                            ctx.translate(cx, cy)
                            ctx.scale(rx / r, ry / r)
                            const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, r)
                            grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                            grad.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.fillStyle = grad
                            ctx.beginPath()
                            ctx.arc(0, 0, r, 0, Math.PI * 2)
                            ctx.fill()
                            ctx.restore()
                        }
                    }
                }
            }
        }
    }

    Item {
        id: sunGlowLayer
        parent: skyComposite
        anchors.fill: parent
        visible: root.dayClearSky
        clip: true
        // CPU 轮（批 8）：原 SequentialAnimation 以 60Hz 推进 opacity（晴空场景的全窗口
        // 重绘驱动源之一）。改为定时器驱动同一余弦呼吸曲线，端点 0.10↔0.24、
        // 周期 7s 不变；reduceMotion 时钉在 0.17（原实现 reduceMotion 下停在动画初值）。
        // R108：33ms(30fps)→100ms(10fps)；R113：改由根级统一节拍驱动（不再单独占一条 Timer，
        // 7s 周期/0.10↔0.24 端点逐值不变，按 root.ambientSec 求同一余弦曲线）。
        opacity: AppTheme.reduceMotion ? 0.17
                 : 0.10 + 0.14 * (0.5 + 0.5 * Math.cos(2 * Math.PI * root.ambientSec / 7.0))

        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width * 0.65
                const cy = height * 0.14
                const r = Math.max(width * 0.55, height * 0.8)
                const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                g.addColorStop(0, "rgba(255, 240, 200, 0.85)")
                g.addColorStop(0.4, "rgba(255, 240, 200, 0.35)")
                g.addColorStop(1, "rgba(255, 240, 200, 0)")
                ctx.fillStyle = g
                ctx.fillRect(0, 0, width, height)
            }
        }

    }

    Item {
        id: starFieldLayer
        parent: skyComposite
        anchors.fill: parent
        visible: root.nightClearSky
        clip: true

        Repeater {
            model: root.starField

            delegate: Rectangle {
                required property var modelData

                x: (starFieldLayer.width - width) * modelData.xRatio
                y: (starFieldLayer.height - height) * modelData.yRatio
                width: modelData.diameter
                height: width
                radius: width / 2
                color: "white"
                Accessible.ignored: true

                // R115（CPU 轮）：原为每颗星一条 `SequentialAnimation on opacity`
                // （PauseAnimation + 两个 InOutSine NumberAnimation，循环）——动画在**显示
                // 刷新率**（60Hz）推进，48 颗星 = 夜晴场景的全窗口 60Hz 重绘驱动源。
                // 改为按根级节拍（root.ambientSec）求同一条余弦曲线：同一端点
                // baseOpacity ↔ baseOpacity×0.35、同一周期（twinklePauseMs + twinkleMs）、
                // cos 与 InOutSine 在两端导数为 0 的缓动等价；reduceMotion / 非夜晴钉在 baseOpacity
                // （与原 `running` 门控停在初值等价，§2.12）。
                property real twinklePeriodSec: (modelData.twinklePauseMs + modelData.twinkleMs) / 1000.0
                opacity: (AppTheme.reduceMotion || !root.nightClearSky)
                         ? modelData.baseOpacity
                         : modelData.baseOpacity * (0.675 + 0.325 * Math.cos(
                             2 * Math.PI * (((root.ambientSec * 1000.0 + modelData.twinklePauseMs)
                                             / 1000.0) % twinklePeriodSec) / twinklePeriodSec))
            }
        }
    }

    // 批 4｜夜空月亮（用户 2026-10-24）：相位取自 backend.moonPhase（与月相卡同源），
    // 位置由「当前时刻距月中天的小时角」决定——横向扫过 0.14–0.86，纵向沿余弦弧
    // 从 0.09（中天）落到 0.49（地平）。声明在星空之后、夜云/云层之前 → 云能从前方遮挡。
    // 静态几何（仅随数据时间变化），reduceMotion 下无任何动画。
    Item {
        id: skyMoonLayer
        parent: skyComposite
        visible: root.moonVisible
        clip: true
        Accessible.ignored: true
        readonly property int diameter: Math.max(24, Math.round(64 * AppTheme.densityScale))
        x: (parent.width - diameter) * root.moonXRatio
        y: parent.height * root.moonYRatio
        width: diameter
        height: diameter

        Canvas {
            id: skyMoonCanvas
            anchors.fill: parent
            property real phase: root.moonPhaseNorm
            antialiasing: true
            contextType: "2d"
            onPhaseChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const r = width / 2
                const c = r
                // 外晕：夜间月亮的柔光（静态渐变）
                const glow = ctx.createRadialGradient(c, c, r * 0.85, c, c, r * 1.9)
                glow.addColorStop(0, "rgba(196,216,248,0.30)")
                glow.addColorStop(1, "rgba(196,216,248,0)")
                ctx.fillStyle = glow
                ctx.beginPath()
                ctx.arc(c, c, r * 1.9, 0, Math.PI * 2)
                ctx.fill()
                // 暗面：深蓝灰实影（与月相卡同族）
                ctx.beginPath()
                ctx.arc(c, c, r * 0.78, 0, Math.PI * 2)
                ctx.fillStyle = "rgba(30,48,82,0.55)"
                ctx.fill()
                // 亮面：相位剪影（盈月亮在右、亏月亮在左；带符号 cosT 区分蛾眉/凸月）
                const p = phase
                const cosT = Math.cos(2 * Math.PI * p)
                const waxing = p < 0.5
                const rr = r * 0.78
                ctx.save()
                ctx.beginPath()
                ctx.arc(c, c, rr, 0, Math.PI * 2)
                ctx.clip()
                ctx.beginPath()
                if (waxing)
                    ctx.arc(c, c, rr, -Math.PI / 2, Math.PI / 2, false)
                else
                    ctx.arc(c, c, rr, -Math.PI / 2, Math.PI / 2, true)
                const steps = 32
                for (let i = 0; i <= steps; i++) {
                    const a = Math.PI / 2 - (Math.PI * i / steps)
                    const ex = waxing ? cosT * rr * Math.cos(a) : -cosT * rr * Math.cos(a)
                    ctx.lineTo(c + ex, c + rr * Math.sin(a))
                }
                ctx.closePath()
                ctx.fillStyle = "#dbe8fb"
                ctx.fill()
                // 确定性环形山（无随机，保证帧差稳定）
                const craters = [
                    { x: 0.42, y: 0.40, r: 0.10 },
                    { x: 0.60, y: 0.52, r: 0.07 },
                    { x: 0.50, y: 0.64, r: 0.05 },
                    { x: 0.36, y: 0.58, r: 0.045 },
                    { x: 0.58, y: 0.32, r: 0.04 }
                ]
                ctx.fillStyle = "rgba(150,175,208,0.28)"
                for (let i = 0; i < craters.length; i++) {
                    const k = craters[i]
                    ctx.beginPath()
                    ctx.arc(c + (k.x - 0.5) * rr * 2, c + (k.y - 0.5) * rr * 2,
                            k.r * rr, 0, Math.PI * 2)
                    ctx.fill()
                }
                ctx.restore()
            }
        }
    }

    // Static procedural faint cloud band for the clear night sky (see
    // nightClearClouds), added per user ruling 2026-10-18. No night reference
    // image exists (refs are day-only), so geometry/opacity is a programmatic
    // approximation. Deliberately placed after starFieldLayer so the clouds
    // occlude the twinkling stars (real-world ordering). Static texture,
    // never animated (reduce-motion safe by construction, no frame-diff
    // obligation).
    Item {
        id: nightClearCloudLayer
        parent: skyComposite
        anchors.fill: parent
        visible: root.nightClearSky
        clip: true
        readonly property real cloudLeft:
            root.compact ? AppTheme.compactSidebarWidth : root.weatherSidebarWidth

        Repeater {
            model: root.nightClearClouds

            delegate: Item {
                id: nightClearCloud
                required property var modelData

                x: nightClearCloudLayer.cloudLeft
                   + (nightClearCloudLayer.width - nightClearCloudLayer.cloudLeft - width)
                     * modelData.xRatio
                y: (nightClearCloudLayer.height - height) * modelData.yRatio
                width: modelData.cloudWidth
                height: modelData.cloudHeight
                opacity: modelData.opacity
                Accessible.ignored: true

                Canvas {
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        for (let i = 0; i < modelData.puffs.length; i++) {
                            const p = modelData.puffs[i]
                            const cx = p.cxRatio * width
                            const cy = p.cyRatio * height
                            // Keep the gradient inside the canvas: alpha must
                            // reach 0 before any clipped edge, otherwise puffs
                            // show hard rectangular borders.
                            const r = Math.max(Math.min(p.rRatio * height * 1.2,
                                                        cy, height - cy,
                                                        cx, width - cx), 8)
                            const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                            grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                            grad.addColorStop(1, "rgba(255,255,255,0)")
                            ctx.fillStyle = grad
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                }
            }
        }
    }

    // 批 7｜雨/雪迁移到 Qt Quick Particles；闪电仍留 Canvas（瞬态、开销可忽略）。
    // 原 PrecipitationLayer 的雨/雪绘制路径与 33ms 循环 Timer 已整段删除（不留两套并存）。
    component LightningLayer: Canvas {
        id: lightning
        anchors.fill: parent
        clip: true
        // R119（CPU 轮）：非闪光时不再把这块「全窗透明 Canvas」留在场景里。
        // 原先 visible 只绑 thunderSky，雷暴场景下即使 flashAlpha=0（绝大多数时间）仍会
        // 每帧参与一次 1180×727 的 alpha 合成（透明但照样全窗光栅化）。改为仅在闪光期间可见。
        visible: root.thunderSky && lightning.flashAlpha > 0
        Accessible.ignored: true

        property real flashAlpha: 0
        property var bolt: []
        property var fork: []
        property real strikeXRatio: 0.5

        // 可见性打开时补一次重绘（flashAlpha 与 visible 同一拍变化，信号顺序不保证）；
        // flashAlpha 回 0 时元素立即隐藏，无需再清空。
        onFlashAlphaChanged: if (lightning.flashAlpha > 0) lightning.requestPaint()
        onVisibleChanged: if (visible) lightning.requestPaint()

        function drawPolyline(ctx, points, widthPx, color) {
            if (!points || points.length < 2) return
            ctx.strokeStyle = color
            ctx.lineWidth = widthPx
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(points[0].x, points[0].y)
            for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y)
            ctx.stroke()
        }

        function buildBolt() {
            lightning.strikeXRatio = 0.12 + Math.random() * 0.76
            const segments = 9 + Math.floor(Math.random() * 4)
            // 落雷限制在云层带内（顶缘 3% → 62% 高度）
            const boltTop = height * 0.03
            const boltHeight = height * 0.59
            const stepY = boltHeight / segments
            const points = []
            let x = width * lightning.strikeXRatio
            let y = boltTop
            for (let i = 0; i <= segments; i++) {
                points.push({ x: x, y: y })
                x += (Math.random() - 0.5) * 46
                y += stepY * (0.8 + Math.random() * 0.4)
            }
            lightning.bolt = points
            const anchor = points[Math.floor(segments / 2)]
            const dir = Math.random() < 0.5 ? -1 : 1
            const forkPoints = [{ x: anchor.x, y: anchor.y }]
            let fx = anchor.x
            let fy = anchor.y
            for (let i = 0; i < 4; i++) {
                fx += dir * (14 + Math.random() * 26)
                fy += stepY * (0.5 + Math.random() * 0.4)
                forkPoints.push({ x: fx, y: fy })
            }
            lightning.fork = forkPoints
        }

        function triggerStrike() {
            lightning.buildBolt()
            strikeOn.duration = 50 + Math.random() * 60
            strikeOff.duration = 70 + Math.random() * 80
            strikeHold.duration = 90 + Math.random() * 120
            afterOn.duration = 50 + Math.random() * 70
            afterOff.duration = 120 + Math.random() * 120
            flashSeq.restart()
        }

        Timer {
            id: lightningTimer
            interval: 900 + Math.random() * 600
            repeat: true
            running: lightning.visible && !AppTheme.reduceMotion
            onTriggered: {
                lightningTimer.interval = 3500 + Math.random() * 5000
                lightning.triggerStrike()
            }
        }
        SequentialAnimation {
            id: flashSeq
            NumberAnimation { id: strikeOn; target: lightning; property: "flashAlpha"; to: 0.95 }
            NumberAnimation { id: strikeOff; target: lightning; property: "flashAlpha"; to: 0.12 }
            PauseAnimation { id: strikeHold }
            NumberAnimation { id: afterOn; target: lightning; property: "flashAlpha"; to: 0.45 }
            NumberAnimation { id: afterOff; target: lightning; property: "flashAlpha"; to: 0 }
        }

        function paintLightning(ctx) {
            if (!lightning.visible || lightning.flashAlpha <= 0) return
            if (!lightning.bolt || lightning.bolt.length < 2) return
            ctx.globalAlpha = lightning.flashAlpha
            ctx.fillStyle = "rgba(255,255,255,0.06)"
            ctx.fillRect(0, 0, width, height)
            const mid = lightning.bolt[Math.floor(lightning.bolt.length / 2)]
            const glowR = Math.min(width, height) * 0.55
            const glow = ctx.createRadialGradient(mid.x, mid.y, 0, mid.x, mid.y, glowR)
            glow.addColorStop(0, "rgba(226,240,255,0.42)")
            glow.addColorStop(0.35, "rgba(200,225,255,0.16)")
            glow.addColorStop(1, "rgba(200,225,255,0)")
            ctx.fillStyle = glow
            ctx.fillRect(0, 0, width, height)
            lightning.drawPolyline(ctx, lightning.bolt, 11, "rgba(190,220,255,0.18)")
            lightning.drawPolyline(ctx, lightning.bolt, 4.5, "rgba(235,245,255,0.55)")
            lightning.drawPolyline(ctx, lightning.bolt, 1.8, "rgba(255,255,255,0.95)")
            lightning.drawPolyline(ctx, lightning.fork, 4, "rgba(220,235,255,0.35)")
            lightning.drawPolyline(ctx, lightning.fork, 1.4, "rgba(255,255,255,0.8)")
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.globalAlpha = 1
            if (width <= 0 || height <= 0) return
            lightning.paintLightning(ctx)
        }
    }

    LightningLayer {
        id: lightningLayer
    }

    // 批 11｜雨＝静止水痕：删除下落雨粒子层（原三层共 30 颗，批 9 定值）。
    // 裁决：雨点贴在玻璃上不动，只允许 8–15 颗沿纯垂直方向缓慢下滑（见 slidingDrops），
    // 天上下落的雨丝不再作为视觉主体，全部关闭。雪与闪电保留（雪不是雨）。
    // 批 7｜雪 = ParticleSystem + Emitter + Wander + ImageParticle（8×8 柔边圆 sprite）。
    ParticleSystem {
        id: snowSystem
        anchors.fill: parent
        visible: root.snowySky
        running: root.snowySky && !AppTheme.reduceMotion

        Emitter {
            system: snowSystem
            anchors.fill: parent
            emitRate: root.snowParticleCount / 2
            lifeSpan: 2000
            lifeSpanVariation: 0
            size: 3.5
            sizeVariation: 1.5
            velocity: AngleDirection {
                angle: root.rainAngleFor(99)
                angleVariation: 3
                magnitude: root.rainMagFor(99) * 0.5
            }
        }
        Wander {
            system: snowSystem
            anchors.fill: parent
            xVariance: 22
            yVariance: 0
            pace: 0.6
        }
        ImageParticle {
            system: snowSystem
            source: "particles/snow.png"
            color: root.currentIsDay ? "#ffffff" : "#cfe0ff"
            alpha: root.currentIsDay ? 0.6 : 0.42
            alphaVariation: 0.25
            smooth: true
            entryEffect: ImageParticle.None
        }
    }

    // 批 2｜云层三层（后/中/前，z 序由声明顺序决定：先声明者在下）。
    // 批 5｜预烘焙改法：每层把所有云**一次**画进单张 2×宽 Canvas 纹理（左右各一份，
    // 周期 = 窗口宽，循环无缝），之后只平移纹理 x，禁止每帧重绘。烘焙只在
    // 尺寸 / clouds（cloudCover / weatherCode）变化时发生，计数见 [cloud-bake] 日志。
    // 速度比仍为 1 : 0.55 : 0.3（批 2 裁决，driftMs 由 cloudLayers 下发）。
    component CloudLayer: Item {
        id: cloudLayer
        property var clouds: []
        property int driftMs: 30000
        anchors.left: parent.left
        anchors.right: parent.right
        // 烘焙纹理只覆盖云带（yMax 0.46 + 云高；ref-main 云 deck 覆盖窗口上部
        // ~50%，旧的 0.46 视口高度只留出顶部窄条 → 上移到 0.62 容纳三层云带），
        // 下方大片天空无云 → 不再合成空白透明区（CPU 轮，观感零变化）。
        height: parent.height * 0.62
        visible: root.cloudySky
        clip: true

        Canvas {
            id: cloudTexture
            width: cloudLayer.width * 2
            height: cloudLayer.height
            // 夜间压暗：夜空无参考图（refs 日间 only），白云在暗天上调低存在感。
            opacity: root.currentIsDay ? 1 : 0.55
            Accessible.ignored: true
            // 烘焙计数：初始化 1 次，尺寸/天气变化各 1 次；稳定运行期间不再增长。
            property int bakeCount: 0
            // 纹理平移量（px）：由下方 33ms Timer 推进，x 绑定到它。
            property real panX: 0
            x: -panX

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            // 纹理平移驱动：Timer 只改 panX（合成器搬运已烘焙纹理），
            // 不触发 requestPaint / Canvas JS。reduceMotion 下停走（§2.12）。
            // R108：33ms(30fps)→50ms(20fps)。R113：不再单独占一条 Timer，改由根级统一节拍
            // （66ms）驱动；位移仍按真实 elapsed 计算，driftMs 9000/16364/30000 逐值不变。
            property double lastPanMs: 0
            Connections {
                target: root
                function onAmbientSecChanged() {
                    if (!root.cloudySky || AppTheme.reduceMotion) {
                        cloudTexture.lastPanMs = 0
                        return
                    }
                    const now = Date.now()
                    if (cloudTexture.lastPanMs > 0) {
                        cloudTexture.panX += (now - cloudTexture.lastPanMs)
                                             * cloudLayer.width / cloudLayer.driftMs
                        if (cloudTexture.panX >= cloudLayer.width)
                            cloudTexture.panX -= cloudLayer.width
                    }
                    cloudTexture.lastPanMs = now
                }
            }
            onPaint: {
                bakeCount += 1
                console.log("[cloud-bake]", (cloudLayer.clouds.length > 0
                                             ? cloudLayer.clouds[0].layer : "empty"),
                            "n=" + cloudLayer.clouds.length,
                            "bake#" + bakeCount, "w=" + width, "h=" + height,
                            "t=" + Date.now())
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                // Structured cloud per ref-main 观感（用户第二批背景轮）：三遍
                // 叠加出明暗结构——阴影底（右下偏移，深蓝 rgba(24,67,127) 系
                // ref 云影实测）、白色云体、受光顶（左上偏移，纯白高光，光源
                // 左上 §2.7）。偏移量按云体尺寸缩放，clamp 同步平移。
                const passes = [
                    { dxR: 0.06, dyR: 0.20, rgb: "24,67,127", mul: 0.85 },
                    { dxR: 0.0,  dyR: 0.0,  rgb: "255,255,255", mul: 0.85 },
                    { dxR: -0.03, dyR: -0.12, rgb: "255,255,255", mul: 1.0 }
                ]
                const periodW = width / 2
                for (let rep = 0; rep < 2; rep++) {
                    for (let c = 0; c < cloudLayer.clouds.length; c++) {
                        const cloud = cloudLayer.clouds[c]
                        const cw = Math.min(cloud.cloudWidth, periodW * 0.45)
                        const ch = cw * (cloud.cloudHeight / cloud.cloudWidth)
                        const ox = rep * periodW
                                   + cloud.xRatio * Math.max(periodW - cw, 0)
                        // 用窗口高度而非画布高度定位：画布收窄到云带后云的绝对位置不变。
                        const oy = (root.height - ch) * cloud.yRatio
                        for (let pass = 0; pass < passes.length; pass++) {
                            const ps = passes[pass]
                            const dx = ps.dxR * cw
                            const dy = ps.dyR * ch
                            for (let i = 0; i < cloud.puffs.length; i++) {
                                const p = cloud.puffs[i]
                                const cx = ox + p.cxRatio * cw + dx
                                const cy = oy + p.cyRatio * ch + dy
                                // Keep the gradient inside the canvas: alpha must
                                // reach 0 before any clipped edge, otherwise puffs
                                // show hard rectangular borders.
                                const r = Math.max(Math.min(p.rRatio * ch * 1.2,
                                                            cy, height - cy,
                                                            cx, width - cx), 8)
                                const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                                grad.addColorStop(0, "rgba(" + ps.rgb + ","
                                                  + (cloud.opacity * p.alphaMul * ps.mul).toFixed(3) + ")")
                                grad.addColorStop(1, "rgba(" + ps.rgb + ",0)")
                                ctx.fillStyle = grad
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                ctx.fill()
                            }
                        }
                    }
                }
            }
        }

        // clouds 绑定在 cloudCover / weatherCode 变化后重算 → 唯一的重烘焙触发点。
        onCloudsChanged: cloudTexture.requestPaint()
    }

    CloudLayer { id: cloudBackLayer; parent: skyComposite; clouds: root.cloudFieldBack; driftMs: root.cloudLayers[0].driftMs }
    CloudLayer { id: cloudMidLayer; parent: skyComposite; clouds: root.cloudFieldMid; driftMs: root.cloudLayers[1].driftMs }
    CloudLayer { id: cloudFrontLayer; parent: skyComposite; clouds: root.cloudFieldFront; driftMs: root.cloudLayers[2].driftMs }

    // 批 4｜大气洗层（雾/雾凇/沙尘）：位于云层之上、闪电之下，蒙住整个天空。
    // 纯静态半透填充，无动画。
    Rectangle {
        id: atmosphereWashLayer
        parent: skyComposite
        anchors.fill: parent
        visible: root.atmosphereWashAlpha > 0
        color: root.atmosphereWashColor
        opacity: root.atmosphereWashAlpha
        Accessible.ignored: true
    }

    // 批 12｜旧「白点贴图」水珠层（water-drops.png + Image.Tile）已删除：
    // 水珠不再画高光白点，而是由天空折射 ShaderEffect（见上方 rainRefraction +
    // waterMapCanvas / drop-offset.png）按偏移图采样背景生成。不留两套并存。

    // 批 11｜少数水珠缓慢滑落（唯一动态）：12 颗固定种子水珠，**纯垂直** 8–15 px/s，
    // 每滑 40–60px 留一颗 2–4px 小水珠；头部最多 1px 渐隐，**无长尾迹**
    // （原 18px 渐变拖尾是"流星雨"观感来源，已删）。
    // 只重绘 256×256 局部 Canvas（禁止全屏 clearRect / 全屏重绘 / 每帧重建贴图）；
    // reduceMotion 时 Timer 停走 → 水珠静止。
    Item {
        id: slidingDrops
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 6
        width: 256
        height: 256
        visible: root.rainySky
        Accessible.ignored: true
        property real clock: 0
        readonly property var drops: {
            const random = root.mulberry32(20261024)
            const rows = []
            for (let index = 0; index < 12; index++) {
                rows.push({
                    x: 12 + random() * (256 - 24),
                    y0: random() * 256,
                    speed: 8 + random() * 7,          // 8–15 px/s（批 11）
                    spacing: 40 + random() * 20,      // 每 40–60px 留一颗
                    bead: 2 + random() * 2            // 2–4px
                })
            }
            return rows
        }
        // R113：滑落水珠不再独占 40ms Timer，由根级统一节拍（66ms）驱动；clock 按真实
        // elapsed 推进，速度 8–15 px/s 逐值不变。仅重绘本 256×256 局部 Canvas。
        // R114（CPU 轮）：水珠只以 8–15 px/s 缓慢下滑，无需跟随环境节拍重绘局部
        // Canvas——每 3 个节拍重绘一次（≈5fps，单步位移 1.6–3.0px），姿态/速度/轨迹由
        // 真实 elapsed 累计，逐值不变；GUI 线程上的 Canvas 光栅与 JS 调用降至 1/3。
        // R115：根级节拍 66→100ms 后，为保持同一 ≈5fps 与同一步长，divisor 3 → 2。
        // R116：133ms(7.5fps) 试值同会话 A/B 无可测收益（见 ambientTick 注释）已回退，故本项
        // divisor 仍 2 → ≈5fps、单步 1.6–3.0px，逐值不变。
        property double lastClockMs: 0
        property int repaintPhase: 0
        Connections {
            target: root
            function onAmbientSecChanged() {
                if (!root.rainySky || AppTheme.reduceMotion) {
                    slidingDrops.lastClockMs = 0
                    slidingDrops.repaintPhase = 0
                    return
                }
                slidingDrops.repaintPhase = (slidingDrops.repaintPhase + 1) % 2
                if (slidingDrops.repaintPhase !== 0)
                    return
                const now = Date.now()
                if (slidingDrops.lastClockMs > 0)
                    slidingDrops.clock += (now - slidingDrops.lastClockMs) / 1000
                slidingDrops.lastClockMs = now
                slidingCanvas.requestPaint()
            }
        }
        Canvas {
            id: slidingCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (!slidingDrops.visible || width <= 0)
                    return
                const rows = slidingDrops.drops
                for (let index = 0; index < rows.length; index++) {
                    const drop = rows[index]
                    const headY = (drop.y0 + drop.speed * slidingDrops.clock) % (height + 20)
                    // 批 11：无长尾迹，最多 1px 渐隐（原 18px 拖尾已删）
                    ctx.fillStyle = "rgba(219,233,255,0.35)"
                    ctx.fillRect(drop.x - 0.5, headY - 1, 1, 1)
                    // 已滑过路径上每 40–60px 留下的静态小水珠
                    const travelled = drop.speed * slidingDrops.clock + drop.spacing
                    const beads = Math.min(10, Math.floor(travelled / drop.spacing))
                    for (let bead = 1; bead <= beads; bead++) {
                        const beadY = headY - bead * drop.spacing
                        if (beadY < -4)
                            break
                        ctx.beginPath()
                        ctx.fillStyle = "rgba(235,245,255,0.34)"
                        ctx.arc(drop.x, beadY, drop.bead * 0.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                    // 头部水珠：亮面 + 下缘暗边
                    ctx.beginPath()
                    ctx.fillStyle = "rgba(255,255,255,0.72)"
                    ctx.arc(drop.x, headY, 2, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.fillStyle = "rgba(10,30,72,0.32)"
                    ctx.arc(drop.x + 0.4, headY + 1.2, 1.6, 0, Math.PI)
                    ctx.fill()
                }
            }
        }
    }

    // 批 5｜闪电已并入降水 Canvas（见 PrecipitationLayer.paintLightning）；
    // 原独立 lightningLayer Canvas（批 3）整段移除：不再有第二个 33ms Timer/
    // 第二次全屏 clearRect/第二次纹理上传。

    RowLayout {
        anchors.fill: parent
        anchors.margins: 0
        // 侧栏与内容列之间不加缝，内容左缝由内容列 Layout.margins: 20 统一提供（否则左缝 8+20=28 违反四周 20px 硬约定；参考 LEDGER 0g）。
        spacing: 0

        KosSidebar {
            id: sidebar
            objectName: "applicationSidebar"
            expanded: root.sidebarExpanded
            expandedWidth: root.compact ? AppTheme.compactSidebarWidth : root.weatherSidebarWidth
            floating: false
            // CPU 轮（R118）：侧栏子树（玻璃胶囊 + 4 张城市卡的天空缩略 Canvas/文字/软影）
            // 全是静态内容，只有展开/收起宽度动画与搜索框输字会变；但环境节拍
            // （云漂移 / hero 呼吸，100ms）每帧触发整窗重合成 → 侧栏被逐帧重新光栅化。
            // layer.enabled 缓存为纹理后稳态每帧只 blit；内容/尺寸/主题变化时才重建。
            layer.enabled: true

            ColumnLayout {
                anchors.fill: parent
                // ref-main Pillow 实测：卡左缘 x10、卡右缘 x205.5、侧栏右缘 x211.5@814 → 内缩左 14.5 / 右 9.4@1180（×1.4501），胶囊右缘与卡右缘同线（同用右内缩）；旧对称 18 系未校准值
                anchors.leftMargin: 15
                anchors.rightMargin: 9
                spacing: 10

                Item {
                    Layout.topMargin: 36
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: 30

                    LiquidTextField {
                        id: locationField
                        anchors.fill: parent
                        leftPadding: 34
                        cornerRadius: 15
                        // 用户裁决 2026-10-23（R80 #0）：直用 shared 新液态玻璃组件
                        // LiquidTextField（不再经 KosTextField 包装），darkAppearance 走
                        // 组件默认绑定 AppTheme.dark（§2.6 小控件随主题翻转，dark 探针取证）。
                        // 真采样：backdrop 指向侧栏背板注册的 LiquidBackdrop，LiquidSurface
                        // 走 shader（折射/放大/反射渐变/rim）而非 fallback 平涂。
                        // 填充/描边沿用 ref-main 实测拟合值：填充白@0.15、rim 白@0.30。
                        backdrop: sidebarBackdrop
                        liquidFinish: true
                        liquidStrength: 0.2
                        glassColor: Qt.rgba(1, 1, 1, 0.15)
                        outlineColor: Qt.rgba(1, 1, 1, 0.30)
                        textColor: "#ffffff"
                        mutedTextColor: Qt.rgba(1, 1, 1, 0.66)
                        placeholderText: qsTr("Search")
                        Accessible.name: qsTr("Location search")
                        onAccepted: backend.searchLocations(text)
                        onTextChanged: {
                            if (text.trim().length >= 2)
                                searchDebounce.restart()
                            else {
                                searchDebounce.stop()
                                backend.clearSearch()
                            }
                        }
                    }

                    // 搜索放大镜：手绘确定性渲染，替代字体 ⌕ glyph（该字形
                    // 在当前字体里 bbox 仅 6px 且贴基线，视觉过小）。
                    // 手绘放大镜（参考图搜索胶囊左侧 magnifier；两笔确定性渲染，无字体依赖）
                    Item {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13
                        height: 13
                        Accessible.ignored: true
                        Rectangle { // 镜片圆环
                            width: 10
                            height: 10
                            radius: 5
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.72)
                            border.width: 1.4
                        }
                        Rectangle { // 手柄，45° 朝右下
                            x: 8.4
                            y: 8.4
                            width: 1.4
                            height: 5.2
                            radius: 0.7
                            color: Qt.rgba(1, 1, 1, 0.72)
                            rotation: -45
                            transformOrigin: Item.TopLeft
                        }
                    }
                }

                BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    running: backend.searching
                    visible: running
                }

                ListView {
                    id: searchResults
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    Layout.preferredHeight: visible ? Math.min(contentHeight, 220) : 0
                    visible: backend.searchResults.length > 0
                    clip: true
                    spacing: 3
                    model: backend.searchResults

                    delegate: KosItemDelegate {
                        id: searchResult

                        required property var modelData
                        width: searchResults.width
                        implicitHeight: 52
                        Accessible.name: root.locationName(modelData)
                        onClicked: {
                            backend.selectLocation(modelData)
                            locationField.clear()
                        }

                        contentItem: Column {
                            spacing: 2

                            Label {
                                width: parent.width
                                text: root.locationName(searchResult.modelData)
                                color: AppTheme.text
                                elide: Text.ElideRight
                            }

                            Label {
                                width: parent.width
                                text: root.locationDetail(searchResult.modelData)
                                color: AppTheme.mutedText
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                    KosKineticScroll { flickable: searchResults }
                }

                Item {
                    id: savedLocationsWrapper
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    Layout.fillHeight: true

                    ListView {
                        id: savedLocations
                        anchors.fill: parent
                        clip: true
                        spacing: 9 // ref-main 卡缝 ~6@814 × 1.4503 ≈ 9
                        model: backend.locations

                        delegate: KosItemDelegate {
                            id: savedLocation

                            required property var modelData
                            required property int index
                            readonly property var summary: root.value(modelData, "summary", null)
                            readonly property var cardStops: root.skyStopsFor(
                                savedLocation.summary ? savedLocation.summary.weatherCode : 2,
                                savedLocation.summary ? savedLocation.summary.isDay : true)
                            readonly property var cardClouds: root.sidebarCardClouds(
                                index,
                                savedLocation.summary ? savedLocation.summary.isDay : true)
                            readonly property real summaryHigh: root.number(
                                savedLocation.summary, "tempHigh", Number.NaN)
                            readonly property real summaryLow: root.number(
                                savedLocation.summary, "tempLow", Number.NaN)

                            width: savedLocations.width
                            // ref-main 直测卡高 ~75@814 × 1.4503 ≈ 109；取 106 与卡缝 9 保持 pitch ~115（旧 74 系 tile-sidebar ÷2.1 旧口径，侧栏校准 297 后未跟改）
                            implicitHeight: 106
                            topPadding: 5
                            bottomPadding: 5
                            highlighted: String(root.value(modelData, "id", ""))
                                === String(root.value(backend.location, "id", ""))
                            Accessible.name: savedLocation.summary
                                ? root.locationName(modelData) + ", "
                                  + root.conditionText(savedLocation.summary.weatherCode)
                                : root.locationName(modelData)
                            onClicked: backend.selectLocation(modelData)

                            background: Rectangle {
                                // ref-main 卡 3 角剖面实测 r≈7-8@814 ×1.4503 ≈ 10-12@1180，12 在误差带内；勿改为 16（旧 tile 换算链已勘误，见 LEDGER 0f）
                                radius: 12
                                // ref-main sidebar cards have no stroke (selected or not) — sampled Mumbai/Chicago/Cupertino edges
                                border.width: 0
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0; color: savedLocation.cardStops[0]
                                    }
                                    GradientStop {
                                        position: 0.45; color: savedLocation.cardStops[1]
                                    }
                                    GradientStop {
                                        position: 1.0; color: savedLocation.cardStops[2]
                                    }
                                }
                                Item {
                                    id: cardSkyTexture
                                    anchors.fill: parent
                                    clip: true
                                    Accessible.ignored: true

                                    Repeater {
                                        model: savedLocation.cardClouds

                                        delegate: Item {
                                            required property var modelData

                                            x: (cardSkyTexture.width - width)
                                               * modelData.xRatio
                                            y: (cardSkyTexture.height - height)
                                               * modelData.yRatio
                                            width: modelData.cloudWidth
                                            height: modelData.cloudHeight
                                            opacity: modelData.opacity

                                            Canvas {
                                                anchors.fill: parent
                                                onWidthChanged: requestPaint()
                                                onHeightChanged: requestPaint()
                                                onPaint: {
                                                    const ctx = getContext("2d")
                                                    ctx.clearRect(0, 0, width, height)
                                                    for (let i = 0; i < modelData.puffs.length; i++) {
                                                        const p = modelData.puffs[i]
                                                        const cx = p.cxRatio * width
                                                        const cy = p.cyRatio * height
                                                        const r = Math.max(Math.min(
                                                            p.rRatio * height * 1.2,
                                                            cy, height - cy, cx, width - cx), 4)
                                                        const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                                                        grad.addColorStop(0, "rgba(255,255,255," + p.alphaMul.toFixed(3) + ")")
                                                        grad.addColorStop(1, "rgba(255,255,255,0)")
                                                        ctx.fillStyle = grad
                                                        ctx.beginPath()
                                                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                                                        ctx.fill()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            contentItem: Item {
                                id: cardContent

                                RowLayout {
                                    id: cardTop
                                    height: 30
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.locationName(savedLocation.modelData)
                                        color: "#ffffff"
                                        font.pixelSize: 17
                                        font.weight: Font.DemiBold
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        elide: Text.ElideRight
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }

                                    Label {
                                        text: savedLocation.summary
                                            ? Math.round(savedLocation.summary.temperature) + "°" : "—"
                                        color: "#ffffff"
                                        font.pixelSize: 30
                                        font.weight: Font.Light
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                }

                                Label {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: cardTop.bottom
                                        topMargin: 0
                                    }
                                    text: savedLocation.highlighted
                                        ? qsTr("My Location")
                                        : savedLocation.summary
                                          && String(savedLocation.summary.time ?? "").length > 0
                                        ? root.cardTimeText(savedLocation.summary.time)
                                        : root.locationDetail(savedLocation.modelData)
                                    color: Qt.rgba(1, 1, 1, 0.72)
                                    font.pixelSize: 12
                                    lineHeight: 0.85
                                    lineHeightMode: Text.ProportionalHeight
                                    elide: Text.ElideRight
                                    visible: text.length > 0 && savedLocation.summary
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.22)
                                }

                                RowLayout {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    spacing: 8

                                    Label {
                                        Layout.fillWidth: true
                                        text: savedLocation.summary
                                            ? root.conditionText(savedLocation.summary.weatherCode)
                                            : root.locationDetail(savedLocation.modelData)
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }

                                    Label {
                                        text: "H:" + Math.round(savedLocation.summaryHigh) + "° L:"
                                              + Math.round(savedLocation.summaryLow) + "°"
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        font.pixelSize: 12
                                        lineHeight: 0.85
                                        lineHeightMode: Text.ProportionalHeight
                                        visible: Number.isFinite(savedLocation.summaryHigh)
                                            && Number.isFinite(savedLocation.summaryLow)
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.22)
                                    }
                                }
                            }
                        }
                        KosKineticScroll { flickable: savedLocations }
                    }

                    // 阶段三功能层 Liquid Glass：滚动边缘效果（HIG Materials——内容滚到侧栏下方时模糊并降不透明度）。
                    Item {
                        id: scrollEdgeTop
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 26
                        visible: savedLocations.contentY > 0.5
                        clip: true

                        MultiEffect {
                            width: savedLocations.width
                            height: savedLocations.height
                            source: savedLocations
                            blurEnabled: true
                            blurMax: 32
                            blur: 1.0
                            saturation: 0.2
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(AppTheme.sidebar.r, AppTheme.sidebar.g, AppTheme.sidebar.b, 0.9)
                                }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                    }

                    // 底边滚动边缘效果：与 scrollEdgeTop 镜像对称（HIG Materials——列表下方还有未滚入内容时模糊并降不透明度）。
                    Item {
                        id: scrollEdgeBottom
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 26
                        visible: savedLocations.contentY + savedLocations.height < savedLocations.contentHeight - 0.5
                        clip: true

                        MultiEffect {
                            width: savedLocations.width
                            height: savedLocations.height
                            source: savedLocations
                            blurEnabled: true
                            blurMax: 32
                            blur: 1.0
                            saturation: 0.2
                        }

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop {
                                    position: 1.0
                                    color: Qt.rgba(AppTheme.sidebar.r, AppTheme.sidebar.g, AppTheme.sidebar.b, 0.9)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Accessible.name: qsTr("Units")

                    ButtonGroup { id: unitsGroup }

                    KosToolButton {
                        id: settingsButton
                        text: "⚙"
                        font.pixelSize: 16
                        Layout.preferredWidth: root.trayControlHeight
                        Layout.preferredHeight: root.trayControlHeight // §3 control.compact.lg=30（窄窗）
                        Layout.alignment: Qt.AlignVCenter
                        background: GlassCircleBg {
                            subtle: true
                            focused: settingsButton.activeFocus && settingsButton.enabled
                        }
                        contentItem: Label {
                            text: settingsButton.text
                            font: settingsButton.font
                            color: settingsButton.enabled
                                ? "white" : Qt.rgba(1, 1, 1, 0.38)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        Accessible.name: qsTr("Weather settings")
                        ToolTip.visible: hovered
                        ToolTip.text: Accessible.name
                        onClicked: settingsDialog.open()
                    }

                    KosToolButton {
                        id: refreshButton
                        text: "↻"
                        font.pixelSize: 18
                        Layout.preferredWidth: root.trayControlHeight
                        Layout.preferredHeight: root.trayControlHeight // §3 control.compact.lg=30（窄窗）
                        enabled: backend.connected && !backend.loading
                        background: GlassCircleBg {
                            subtle: true
                            focused: refreshButton.activeFocus && refreshButton.enabled
                        }
                        contentItem: Label {
                            id: refreshGlyph
                            text: refreshButton.text
                            font: refreshButton.font
                            color: refreshButton.enabled
                                ? "white" : Qt.rgba(1, 1, 1, 0.38)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            RotationAnimation on rotation {
                                running: backend.loading && !AppTheme.reduceMotion
                                loops: Animation.Infinite
                                duration: 1000
                                from: 0
                                to: 360
                                onRunningChanged: if (!running) refreshGlyph.rotation = 0
                            }
                        }
                        Accessible.name: qsTr("Refresh weather forecast")
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Refresh weather forecast")
                        onClicked: backend.refresh()
                    }

                    BusyIndicator {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        // 批 4｜Reduce Motion 逐层覆盖：加载指示器也不许旋转（§2.12）
                        running: backend.loading && !AppTheme.reduceMotion
                        visible: backend.loading
                    }

                    Item { Layout.fillWidth: true }

                    KosButton {
                        id: metricButton
                        text: "°C"
                        checkable: true
                        leftPadding: 0
                        rightPadding: 0
                        Layout.preferredWidth: root.trayControlHeight
                        Layout.preferredHeight: root.trayControlHeight // §3 control.compact.lg=30（窄窗）
                        background: GlassCircleBg {
                            focused: metricButton.activeFocus && metricButton.enabled
                            selected: metricButton.checked
                            pressed: metricButton.down
                            hovered: metricButton.hovered
                        }
                        contentItem: Label {
                            text: metricButton.text
                            font: metricButton.font
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        ButtonGroup.group: unitsGroup
                        checked: backend.units === "metric"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: checked
                        Accessible.name: qsTr("Use metric units")
                        onClicked: backend.setUnits("metric")
                    }

                    KosButton {
                        id: imperialButton
                        text: "°F"
                        checkable: true
                        leftPadding: 0
                        rightPadding: 0
                        Layout.preferredWidth: root.trayControlHeight
                        Layout.preferredHeight: root.trayControlHeight // §3 control.compact.lg=30（窄窗）
                        background: GlassCircleBg {
                            focused: imperialButton.activeFocus && imperialButton.enabled
                            selected: imperialButton.checked
                            pressed: imperialButton.down
                            hovered: imperialButton.hovered
                        }
                        contentItem: Label {
                            text: imperialButton.text
                            font: imperialButton.font
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        ButtonGroup.group: unitsGroup
                        checked: backend.units === "imperial"
                        Accessible.role: Accessible.RadioButton
                        Accessible.checked: checked
                        Accessible.name: qsTr("Use imperial units")
                        onClicked: backend.setUnits("imperial")
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: backend.stale
                        ? "●  " + qsTr("Cached")
                        : (backend.connected
                            ? "●  Open-Meteo"
                            : "○  " + qsTr("Offline cache"))
                    color: backend.connected && !backend.stale
                        ? AppTheme.positive : AppTheme.warning
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    Accessible.name: backend.stale
                        ? qsTr("Weather service connected; showing cached data")
                        : (backend.connected
                            ? qsTr("Weather service connected")
                            : qsTr("Weather service disconnected; showing offline cache"))
                }
            }
        }

        // §2.7 光源左上 + §3 color.separator(0.10)：侧栏(左)的右缘属"下/右"暗侧，
        // 补 1px 暗分隔让侧栏与主区的玻璃边界可读（§2.2 边界），不新增第二层玻璃。
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Qt.rgba(0, 0, 0, 0.10)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 16

            Flickable {
                id: mainFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: content.implicitHeight + AppTheme.pageMargin
                clip: true

                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: content
                    width: parent.width
                    spacing: 16

                    ColumnLayout {
                        id: heroColumn
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2
                        // 0e：ref-main hero 小标签 ink 顶 74/498=14.9% 窗高；我方 ink 顶=margin20+ink4=24 起步。
                        // topMargin = 14.9% × flick 高 − 24，默认窗高(mainFlick 高≈687)时 ≈ 84px，ink 顶落位 ≈108px
                        Layout.topMargin: Math.max(0, mainFlick.height * 0.149 - 24)
                        // 0e：ref H·L ink 底→AQ 卡顶 30px@814 ×1.46 ≈ 44px；现 ink gap 22px（content spacing 16 + ink 余 ~6）
                        Layout.bottomMargin: 22
                        // Stage 3 motion B.3: hero parallax + slight shrink while the main area
                        // scrolls. Scroll-linked mapping (no timed animation): the hero tracks
                        // contentY at half speed and scales down gently; reduce-motion pins both.
                        transform: Translate {
                            y: AppTheme.reduceMotion ? 0 : Math.max(0, mainFlick.contentY) * 0.5
                        }
                        scale: AppTheme.reduceMotion
                            ? 1.0
                            : Math.max(1.0 - Math.max(0, mainFlick.contentY) / 240 * 0.12, 0.88)
                        transformOrigin: Item.Top

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("My Location")
                            visible: text.length > 0
                            color: root.skyTextMuted
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.locationName(backend.location)
                            color: root.skyText
                            // ref-main 城市名字高 15px/498 窗高 = 3.0-3.6%，×1.46 折算 ≈22-26px，取 26
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }

                        // R93（用户裁决 #0.7 第五轮「立体感仍然不够」）：根因 = 字面太透（深色厚度层
                        // 从字面里透出变"脏"）+ 仅 2 层厚度不足以形成可辨立体块。本轮改法（照数字实现）：
                        //   1. 挤出体：14 层堆叠（累计 translate(0,1)），fillStyle rgba(8,26,64, 0.88−i·0.045)，
                        //      shadowBlur=0；绘制顺序先挤出体后字面
                        //   2. 字面：体渐变 rgba(255,255,255,0.92/0.86/0.80)（上亮下暗，接近不透明）
                        //   3. 倒角两笔（字面之上）：上沿高光 translate(0,−1.2) rgba(255,255,255,0.55)；
                        //      下沿暗线 translate(0,+0.8) rgba(8,26,64,0.55)
                        //   4. 可选透视 scale(1,0.94)：未用（记 LEDGER）
                        // 呼吸保留；仍禁 lighter、禁移动高光带、禁纯白硬 rim。字族/字重/字号/位置不动
                        // （Ubuntu Sans 800 / 92px / topMargin −24 / opacity 0.86↔1.0 5s）。
                        // R94（用户裁决）：白色 50% 半透字 + 背景模糊（真·背板采样 + MultiEffect 遮罩）
                        Item {
                            id: heroTempLiquid
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: -24
                            width: 340
                            height: 124
                            property string digits: Math.round(root.number(backend.current, "temperature", 0)).toString()
                            Accessible.role: Accessible.StaticText
                            Accessible.name: digits + "°"

                            // 呼吸：整字 opacity 0.86↔1.0，周期 5s，InOutSine。
                            // CPU 轮（批 8）：原 SequentialAnimation 每个显示帧（60Hz）推进一次，
                            // 是晴/多云场景全窗口重绘的唯一 60fps 驱动源（实测基线 20.5–20.9%）。
                            // 改为 33ms 定时器驱动同一余弦曲线（cos 在两端导数为 0 = InOutSine 等价），
                            // 端点 0.86/1.0 与 5s 周期不变，仅时间分辨率降到 30fps（5s 慢渐变不可辨）。
                            // R108：33ms(30fps)→66ms(15fps)，opacity 单步 Δ≤0.006（5s 正弦），肉眼不可辨。
                            // R113：改由根级统一节拍驱动（不再单独占一条 Timer），
                            // 端点 0.86/1.0 与 5s 周期逐值不变。
                            opacity: AppTheme.reduceMotion ? 1.0
                                     : 0.86 + 0.14 * (0.5 + 0.5 * Math.cos(2 * Math.PI * root.ambientSec / 5.0))


                            // 4) 白色 50% 字面 + 柔光晕（磨砂感）
                            Text {
                                id: heroFaceText
                                anchors.centerIn: parent
                                text: heroTempLiquid.digits + "°"
                                color: "white"
                                opacity: 0.5
                                font.weight: Font.Black
                                font.pixelSize: 92
                            }

                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.conditionText(root.number(backend.current, "weatherCode", -1))
                            color: root.skyText
                            // ref 数字底→条件顶 gap 9px×1.46≈13px
                            Layout.topMargin: -14
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: backend.daily.length > 0
                                ? "H:" + Math.round(root.number(backend.daily[0], "temperatureMaximum", 0)) + "°  "
                                  + "L:" + Math.round(root.number(backend.daily[0], "temperatureMinimum", 0)) + "°"
                                : ""
                            color: root.skyText
                            // ref 条件底→H:L 顶 gap 6px×1.46≈9px
                            Layout.topMargin: -3
                            // ref H·L ink 8px×1.46≈11.7 → 字号 16；ref 墨均值 (224,230,239) 与条件行同白系，hero 仅小标签 muted
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: errorLabel.implicitHeight + 22
                        radius: AppTheme.smallRadius
                        color: AppTheme.withAlpha(AppTheme.warning, AppTheme.dark ? 0.16 : 0.12)
                        border.width: 1
                        border.color: AppTheme.withAlpha(AppTheme.warning, 0.38)
                        visible: backend.errorMessage.length > 0

                        Label {
                            id: errorLabel
                            anchors.fill: parent
                            anchors.margins: 11
                            text: qsTr("The latest update failed: %1").arg(backend.errorMessage)
                            color: AppTheme.text
                            wrapMode: Text.WordWrap
                        }
                    }

                    // 双列 masonry（ref-main 步骤 a+b+c）：GridLayout 内两个独立列容器 = 真 masonry——
                    // 行式布局曾把左列瓦片压到右列 Conditions 底下产生 86px 天窗；左列 AQ→指标瓦片、右列 Conditions→10 天卡各自独立堆叠；compact 窄窗回落单列
                    GridLayout {
                        id: cardGrid
                        Layout.fillWidth: true
                        // CPU 轮（R117）：卡片区是纯静态内容（圆角 AA 填充 + 双层软影 + 文字），
                        // 但随环境节拍（云漂移/hero 呼吸）每 100ms 被整窗重合成一次 →
                        // 每帧都把整片卡片重新光栅化。layer.enabled 让它只光栅化一次并缓存为
                        // 纹理，此后逐帧只做一次 blit；卡片内容/尺寸/主题变化时才重建。
                        // 视觉零改动（§1 L0 内容区，非玻璃）。
                        layer.enabled: true
                        columns: root.compact ? 1 : 2
                        // ref-main(814x498) y260 行实测 AQ 卡右缘 x505 → Conditions 卡左缘 x519 ≈13px 间隙 × 1.4598 窗高比 ≈ 19px
                        columnSpacing: 19
                        rowSpacing: 16
                        // ref-main 左列：AQ 卡 → 指标瓦片（独立堆叠，不随右列高度走；列缝 19 见 GridLayout）
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 16
                            KosCard {
                                id: airQualityCard
                                // 空态（快照无 airQuality 字段）下旧代码显示假 "0"、全宽渐变条与模板文案，属仍差 14a 收口；
                                // usAqi=0 是合法值（非负），故用 null 比较而非真值判断
                                readonly property bool hasAqi: root.value(backend.airQuality, "usAqi", null) !== null
                                Layout.fillWidth: true
                                // ref-main 两列等宽(239/241@814)：preferred 拉平让 GridLayout 等分剩余宽度
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop

                                background: KosSurface {
                                    // ref-main Pillow 实测 Conditions 卡圆角 r≈14px@814 × 1.4598 窗高比 ≈ 20.4 → 20（同心圆角锚点，阶段三 A）
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, root.cardGlassAlpha)
                                    // 用户裁决 2026-10-23（R80 0.5）：内容区白描边一律去掉，
                                    // 此为最后一处卡片 rim（R25 每卡一条 rim 的判定被本轮推翻）。
                                    strokeWidth: 0
                                    // innerHighlight（AppTheme 白@0.58 内侧 1px 高光线）同属白描边，一并去除
                                    showInnerHighlight: false
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    spacing: 10

                                    RowLayout {
                                        spacing: 6

                                        Canvas {
                                            width: 12
                                            height: 12

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                // ref-main.png 实测：AQ 卡头部点阵图标最亮点 (284,213)=(52,124,205) vs 卡面 (27,98,175)
                                                // → 峰值 Δ≈+27；"AIR QUALITY" 文字最亮 (322,218)=(96,162,241) vs 同底 → Δ≈+66；
                                                // 图标/文字对比度比 ≈ 0.38-0.41。且点阵亮度沿对角渐变：
                                                // 右上 (row0,col2) 最亮、左下 (row2,col0) 最淡（视觉近消失）。
                                                // 原统一 alpha 0.6 使 Δ≈+121 vs 文字 Δ≈+119（比 0.92），过亮且无渐隐；
                                                // 现按对角渐隐：峰值 0.26×(255−背景)≈+47 ≈ 0.4× 文字 Δ。
                                                for (let row = 0; row < 3; ++row) {
                                                    for (let col = 0; col < 3; ++col) {
                                                        // 亮度沿 col−row 对角：右上 (row0,col2)=0.26 最亮、左下 (row2,col0)=0.10 最淡
                                                        const alpha = 0.10 + 0.16 * (col - row + 2) / 4
                                                        ctx.fillStyle = Qt.rgba(1, 1, 1, alpha)
                                                        ctx.beginPath()
                                                        ctx.arc(1.5 + col * 4.5, 1.5 + row * 4.5, 1.3, 0, Math.PI * 2)
                                                        ctx.fill()
                                                    }
                                                }
                                            }
                                        }

                                        Label {
                                            text: qsTr("Air Quality").toUpperCase()
                                            color: root.cardHeaderText
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.4
                                        }
                                    }

                                    Label {
                                        visible: airQualityCard.hasAqi
                                        text: Math.round(root.number(backend.airQuality, "usAqi", 0))
                                        color: root.skyText
                                        font.pixelSize: 22
                                        font.weight: Font.DemiBold
                                    }

                                    Label {
                                        text: root.value(backend.airQuality, "category", "")
                                        visible: text.length > 0
                                        color: root.skyText
                                        Layout.topMargin: -12 // ref-main 实测数字底→rating cap 顶 ink gap 7px×1.46≈10，改前 22px（spacing 10 + 两行字体行高 padding），-12 只抵消行高 padding
                                        font.pixelSize: 13
                                    }

                                    Item {
                                        visible: airQualityCard.hasAqi
                                        Layout.topMargin: 7 // ref-main 实测 rating cap 顶→条顶 22px×1.4598≈32，改前 25px（同口径），+7 补齐；本轮 Pillow 实测 rating 基线→条顶 我方 16.5px vs ref 16px×1.4598≈23.3
                                        Layout.fillWidth: true
                                        height: 9

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            height: 4
                                            radius: 2
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                // ref-main 实测：EPA 0-500 线性映射，0.72 起平直 #80172b（Pillow 逐点采样）
                                                stops: [
                                                    GradientStop { position: 0.00; color: "#00de72" },
                                                    GradientStop { position: 0.15; color: "#fde620" },
                                                    GradientStop { position: 0.22; color: "#ffac0b" },
                                                    GradientStop { position: 0.29; color: "#fd5e21" },
                                                    GradientStop { position: 0.36; color: "#f30f5e" },
                                                    GradientStop { position: 0.43; color: "#cd08b2" },
                                                    GradientStop { position: 0.50; color: "#a805fa" },
                                                    GradientStop { position: 0.58; color: "#9a0aae" },
                                                    GradientStop { position: 0.65; color: "#8b1062" },
                                                    GradientStop { position: 0.72; color: "#80172b" },
                                                    GradientStop { position: 1.00; color: "#80172b" }
                                                ]
                                            }
                                        }

                                        Rectangle {
                                            // ref-main Pillow 实测 AQI 40 白点在条 8.33% 处，0–500（EPA AQI 满量程）预测 8.0% 吻合，0–300 预测 13.3% 偏差 10.5px
                                            x: Math.max(0, Math.min(1, root.number(backend.airQuality, "usAqi", 0) / 500)) * (parent.width - 9)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 9
                                            height: 9
                                            radius: 4.5
                                            color: "#ffffff"
                                        }
                                    }

                                    // ref-main 实测：说明文字峰值纯白 (255,255,255) 且重于 rating，Demibold 白字
                                    Label {
                                        visible: airQualityCard.hasAqi
                                        text: qsTr("Air quality index: %1.")
                                            .arg(Math.round(root.number(backend.airQuality, "usAqi", 0)))
                                        color: root.skyText
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // 指标瓦片容器：参考图（ref-main）里指标卡（WIND/月相/UV/SUNSET 等）
                            // 是散在天空上的独立圆角卡，卡与卡之间直接透天空，无外层容器卡——
                            // 故本 Pane 只做布局，不带任何卡面 chrome（Pillow 实测 ref 指标卡
                            // 填充 (38.5,115.8,196.9) vs 卡间天空 (54.7,124.3,197.0)，无白玻璃亮层）。
                            KosCard {
                                id: conditionsCard
                                // ref-main：瓦片区入左列 AQ 卡下方（左列 x271-505，与 AQ 同列对齐）；右列 dailyCard 不动（masonry 步骤 b 第一半）
                                Layout.fillWidth: true
                                // 镜像 airQualityCard/dailyCard 同族等宽修正（步 a 先例）：preferred 拉平让 GridLayout 等分列宽
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                // ref-main Pillow 实测：WIND 卡左缘 x271 与 AQ 卡左缘 x271 同列对齐；
                                // 本卡 padding≈20 导致瓦片 x272 vs AQ 卡 x252，置零水平 padding 对齐；
                                // topPadding/bottomPadding 保持不动——:2401 的 topMargin:-16 抵消方案按 padding 20 校准，勿动
                                leftPadding: 0
                                rightPadding: 0

                                background: Item {}

                                contentItem: ColumnLayout {
                                    spacing: 12

                                    KosEmptyState {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: !backend.ready
                                        symbol: backend.loading ? "↻" : "☁"
                                        titleColor: root.skyText
                                        descriptionColor: root.skyTextMuted
                                        title: backend.loading
                                            ? qsTr("Loading the forecast") : qsTr("No forecast available")
                                        description: backend.connected
                                            ? qsTr("Refresh or choose another saved location.")
                                            : qsTr("Start kos-data-service to fetch weather data.")
                                        actionText: backend.connected ? qsTr("Refresh") : ""
                                        actionEnabled: !backend.loading
                                        onActionTriggered: backend.refresh()
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        visible: backend.ready
                                        spacing: 12

                                        GridLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: -16 // ref-main AQ 底→WIND 顶 14px@814 × 1.4598 ≈ 20px;改前 36px = content spacing 16 + 本卡 padding ~20,-16 抵消 padding 多余部分(描边-描边 20px)
                                            columns: 2 // ref-main 左列瓦片区两列排布，compact 原本就是 2 列故统一
                                            columnSpacing: 8
                                            rowSpacing: 8

                                            // ref-main WIND 124 / gap 8 / MOON 102 → 半宽并排（235/15/193）
                                            RowLayout {
                                                Layout.columnSpan: 2
                                                Layout.fillWidth: true
                                                spacing: 15

                                                Rectangle {
                                                    id: windCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 235
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: windHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)

                                                    property real windDir: root.number(backend.current, "windDirection", 0)
                                                    // arrow points where the wind blows TO (Open-Meteo direction is where it comes FROM)
                                                    property real flowAngle: (windCard.windDir + 180) % 360
                                                    property real gustVal: root.number(backend.current, "windGust", Number.NaN)
                                                    property bool hasGust: Number.isFinite(gustVal)

                                                    onWindDirChanged: windCompass.requestPaint()
                                                    onFlowAngleChanged: windCompass.requestPaint()

                                                    HoverHandler { id: windHover }
                                                    ToolTip.visible: windHover.hovered
                                                    ToolTip.text: qsTr("Direction")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Wind") + ": " + Math.round(root.number(
                                                        backend.current, "windSpeed", 0)) + " " + root.speedUnit
                                                        + ", " + qsTr("Direction") + " " + Math.round(windCard.windDir) + "° " + windCard.cardinal
                                                        + (windCard.hasGust
                                                            ? " " + qsTr("Gusts") + ": " + Math.round(windCard.gustVal) + " " + root.speedUnit
                                                            : "")

                                                    property string cardinal: {
                                                        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
                                                        return names[Math.round(windCard.windDir / 45) % 8]
                                                    }

                                                    // ref-main WIND 头部：左/上 inset 14/12px，11px DemiBold + 字距全大写（同瓦片头家族）
                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Label {
                                                            text: "≋"
                                                            color: root.cardHeaderText
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                            Accessible.ignored: true
                                                        }

                                                        Label {
                                                            text: qsTr("Wind").toLocaleUpperCase(Qt.locale())
                                                            color: root.cardHeaderText
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 罗盘外径 72px@814 → 116×116，水平居中 y36
                                                    Item {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        y: 36
                                                        width: 116
                                                        height: 116

                                                        Canvas {
                                                            id: windCompass
                                                            anchors.fill: parent
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                var c = 58
                                                                // 内盘 r29 白 0.06（ref 内盘 (52,122,196) vs 卡面 (35,112,193) ≈ 白@0.06）
                                                                ctx.fillStyle = "rgba(255,255,255,0.06)"
                                                                ctx.beginPath()
                                                                ctx.arc(c, c, 29, 0, 2 * Math.PI)
                                                                ctx.fill()
                                                                // 刻度环带：tile-cards WIND 卡（538 宽切片，卡宽 ~223）实测参考为密集细刻度带
                                                                // r46→r57（0.206-0.256 卡宽比）；我方卡高 162 受 Gusts 行约束按高度缩放，
                                                                // 带取 r38→r46，密度取每 3°（120 根，ref 糊化不可数，密度系外推）
                                                                ctx.strokeStyle = "rgba(255,255,255,0.30)"
                                                                ctx.lineWidth = 1
                                                                for (var i = 0; i < 120; i++) {
                                                                    var a = i * Math.PI / 60
                                                                    ctx.beginPath()
                                                                    ctx.moveTo(c + Math.sin(a) * 38, c - Math.cos(a) * 38)
                                                                    ctx.lineTo(c + Math.sin(a) * 46, c - Math.cos(a) * 46)
                                                                    ctx.stroke()
                                                                }
                                                                // N/E/S/W 字母带内嵌 r35（tile-cards 实测参考字母嵌在刻度带内侧；r50 时 S 落 y144 被 Gusts 行墨区完全覆盖不可见）；N 用实测亮蓝，W/E/S 白 0.65
                                                                ctx.font = "600 10px sans-serif"
                                                                ctx.textAlign = "center"
                                                                ctx.textBaseline = "middle"
                                                                ctx.fillStyle = "#6CB1E0"
                                                                ctx.fillText("N", c, c - 35)
                                                                ctx.fillStyle = "rgba(255,255,255,0.65)"
                                                                ctx.fillText("E", c + 35, c)
                                                                ctx.fillText("S", c, c + 35)
                                                                ctx.fillText("W", c - 35, c)
                                                                // 两段式留空指针（ref-main WIND 卡实测：指针不穿
                                                                // 中心文字——箭头段在流向侧近外圈 + 来向侧短尾针，
                                                                // r<30 让位环心数字/单位）
                                                                ctx.save()
                                                                ctx.translate(c, c)
                                                                ctx.rotate(windCard.flowAngle * Math.PI / 180)
                                                                ctx.strokeStyle = "#ffffff"
                                                                ctx.fillStyle = "#ffffff"
                                                                ctx.lineWidth = 1.6
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, -30)
                                                                ctx.lineTo(0, -40)
                                                                ctx.stroke()
                                                                // 来向侧圆头短针（tile-cards WIND 卡 538 切片原生分辨率实测：头部圆
                                                                // ⌀~10@卡宽223 圆心在刻度带中线 r50.5（带 46-57），不出带外缘；细杆
                                                                // r27.5→45.5 宽 2-3px。按带我 38-46 同族映射（×0.727）→ 圆头 r4.3
                                                                // 圆心 r42=带中线、不出带外缘；杆 r24.5→38，内端让位环心单位文字）
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, 24.5)
                                                                ctx.lineTo(0, 38)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.arc(0, 42, 4.3, 0, 2 * Math.PI)
                                                                ctx.fill()
                                                                ctx.beginPath()
                                                                ctx.moveTo(0, -46)      // tip
                                                                ctx.lineTo(-3, -41)
                                                                ctx.lineTo(3, -41)
                                                                ctx.closePath()
                                                                ctx.fill()
                                                                ctx.restore()
                                                            }
                                                        }

                                                        // 环心速度：数字+单位整体居中于罗盘中心
                                                        ColumnLayout {
                                                            anchors.centerIn: parent
                                                            spacing: 1

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: Math.round(root.number(
                                                                    backend.current, "windSpeed", 0))
                                                                color: root.skyText
                                                                font.pixelSize: 30
                                                                font.weight: Font.DemiBold
                                                                Accessible.ignored: true
                                                            }

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: root.speedUnit
                                                                color: root.skyTextMuted
                                                                font.pixelSize: 13
                                                                // 单位墨底实测距刻度内缘仅 10px（patrol-1792322227：墨底 y500 vs 内缘 y510），上移 10px 贴 ref（tile-cards 数字→单位墨距 ~5px、单位全在环内）
                                                                transform: Translate { y: -10 }
                                                                Accessible.ignored: true
                                                            }
                                                        }
                                                    }

                                                    // ref-main Gusts 行：距卡底 9px@814、左 inset 12px@814
                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 17
                                                        anchors.bottom: parent.bottom
                                                        anchors.bottomMargin: 12
                                                        visible: windCard.hasGust
                                                        text: qsTr("Gusts: ") + Math.round(windCard.gustVal) + " " + root.speedUnit
                                                              + " " + windCard.cardinal
                                                        color: root.skyText
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                        Accessible.ignored: true
                                                    }
                                                }

                                                Rectangle {
                                                    id: moonCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 193
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: moonHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)

                                                    property real phaseVal: root.number(backend.current, "moonPhase", Number.NaN)
                                                    property bool hasPhase: Number.isFinite(phaseVal)
                                                    readonly property var phaseNames: [
                                                        qsTr("New Moon"), qsTr("Waxing Crescent"), qsTr("First Quarter"),
                                                        qsTr("Waxing Gibbous"), qsTr("Full Moon"), qsTr("Waning Gibbous"),
                                                        qsTr("Last Quarter"), qsTr("Waning Crescent")
                                                    ]
                                                    // 8 等分、以 0/0.25/0.5/0.75 为中心：round(p*8)%8
                                                    readonly property string phaseName: hasPhase
                                                        ? phaseNames[Math.round(((phaseVal % 1) + 1) % 1 * 8) % 8]
                                                        : "—"

                                                    onPhaseValChanged: {
                                                        moonCanvas.requestPaint()
                                                        moonGlyphCanvas.requestPaint()
                                                    }

                                                    HoverHandler { id: moonHover }
                                                    ToolTip.visible: moonHover.hovered
                                                    ToolTip.text: qsTr("Moon Phase")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Moon Phase") + ": " + moonCard.phaseName

                                                    // ref-main 头部=相位名 caps + 小月相 glyph（y338-344 实测）
                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: moonGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                var c = 6
                                                                var r = 5
                                                                // 暗面：整盘剪影（月亮相位剪影，同族白 0.14）
                                                                ctx.beginPath()
                                                                ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                                ctx.fillStyle = "rgba(255,255,255,0.14)"
                                                                ctx.fill()
                                                                if (!moonCard.hasPhase)
                                                                    return
                                                                // 亮面：外弧（盈月亮在右，亏月亮在左）+ 终止线半椭圆折线，一次成形
                                                                var p = ((moonCard.phaseVal % 1) + 1) % 1
                                                                var cosT = Math.cos(2 * Math.PI * p)
                                                                var waxing = p < 0.5
                                                                ctx.beginPath()
                                                                if (waxing)
                                                                    ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, false)   // 顶极→底极经右侧
                                                                else
                                                                    ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, true)    // 顶极→底极经左侧
                                                                var steps = 32
                                                                for (var i = 0; i <= steps; i++) {
                                                                    var a = Math.PI / 2 - (Math.PI * i / steps)          // 底极→顶极
                                                                    // 带符号 cosT：蛾眉凸向亮侧、凸月凸向暗侧（|cosT| 会把凸月画成蛾眉、满月退化成零面积）
                                                                    var ex = waxing ? cosT * r * Math.cos(a) : -cosT * r * Math.cos(a)
                                                                    ctx.lineTo(c + ex, c + r * Math.sin(a))
                                                                }
                                                                ctx.closePath()
                                                                // ref tile-cards 月相卡头 glyph 峰值 (108,179,255)、同排头部文字 (113,183,255) 同浅蓝墨族 → 统一 #90cbff（与卡头标签/glyph 家族同墨，见 LEDGER 2026-10-18 hdrcol 轮）
                                                                ctx.fillStyle = "#90cbff"
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: moonCard.phaseName.toLocaleUpperCase(Qt.locale())
                                                            color: root.cardHeaderText
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            elide: Text.ElideRight
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 月亮盘 d≈71@814 ×1.46 ≈ 104，盘顶距卡顶 28×1.46 ≈ 41，水平居中
                                                    Canvas {
                                                        id: moonCanvas
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        y: 41
                                                        width: 104
                                                        height: 104
                                                        antialiasing: true
                                                        contextType: "2d"
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            var c = 52
                                                            var r = 52
                                                            if (!moonCard.hasPhase) {
                                                                // 无数据：整盘剪影（同族白 0.14）
                                                                ctx.beginPath()
                                                                ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                                ctx.fillStyle = "rgba(255,255,255,0.14)"
                                                                ctx.fill()
                                                                return
                                                            }
                                                            var p = ((moonCard.phaseVal % 1) + 1) % 1
                                                            var cosT = Math.cos(2 * Math.PI * p)
                                                            var waxing = p < 0.5
                                                            // 暗面：ref tile-cards 月相卡暗侧明显暗于卡底（非白 0.14 剪影）→ 深蓝灰实影
                                                            ctx.beginPath()
                                                            ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                            ctx.fillStyle = "rgba(43,60,94,0.55)"
                                                            ctx.fill()
                                                            // 裁到盘内：终止线 shadow 不越月盘外缘
                                                            ctx.save()
                                                            ctx.beginPath()
                                                            ctx.arc(c, c, r, 0, 2 * Math.PI)
                                                            ctx.clip()
                                                            // 亮面：外弧（盈月亮在右，亏月亮在左）+ 终止线半椭圆折线，一次成形
                                                            ctx.beginPath()
                                                            if (waxing)
                                                                ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, false)   // 顶极→底极经右侧
                                                            else
                                                                ctx.arc(c, c, r, -Math.PI / 2, Math.PI / 2, true)    // 顶极→底极经左侧
                                                            var steps = 32
                                                            for (var i = 0; i <= steps; i++) {
                                                                var a = Math.PI / 2 - (Math.PI * i / steps)          // 底极→顶极
                                                                // 带符号 cosT：蛾眉凸向亮侧、凸月凸向暗侧（|cosT| 会把凸月画成蛾眉、满月退化成零面积）
                                                                var ex = waxing ? cosT * r * Math.cos(a) : -cosT * r * Math.cos(a)
                                                                ctx.lineTo(c + ex, c + r * Math.sin(a))
                                                            }
                                                            ctx.closePath()
                                                            // 亮面冷蓝白：ref tile-cards 月亮相照片亮面实测均值 (161,192,228)；峰值 (228,236,247) 系纹理不可平面复刻
                                                            // 填充带暗影（shadow 落在暗侧）→ ref 的软终止线：界线由亮面实缘渐入暗面
                                                            ctx.save()
                                                            ctx.shadowColor = "rgba(43,60,94,0.55)"
                                                            ctx.shadowBlur = 6
                                                            ctx.fillStyle = "#a1c0e4"
                                                            ctx.fill()
                                                            ctx.restore()
                                                            // 亮面程序化斑驳纹理：ref tile-cards 月亮相照片分布校准（中位 159,189,228 / p90 184,208,234 / 峰值 228,236,247）；
                                                            // 全部确定性坐标（无随机），保证逐帧稳定可做帧差回归
                                                            ctx.save()
                                                            ctx.clip()   // 裁到亮面路径内
                                                            // 月海暗斑（低覆盖低透明度，只把分布下沿拉低，不拉中位数；径向渐变柔边，避免硬圆 rim）
                                                            var mare = [[0.30, 0.38, 0.26], [0.66, 0.28, 0.20], [0.48, 0.66, 0.22], [0.78, 0.60, 0.15]]
                                                            for (var m = 0; m < mare.length; m++) {
                                                                var mx = c + mare[m][0] * r
                                                                var my = c + mare[m][1] * r
                                                                var mr = mare[m][2] * r
                                                                ctx.beginPath()
                                                                ctx.arc(mx, my, mr, 0, 2 * Math.PI)
                                                                var mg = ctx.createRadialGradient(mx, my, 0, mx, my, mr)
                                                                mg.addColorStop(0, "rgba(126,155,201,0.28)")
                                                                mg.addColorStop(0.7, "rgba(126,155,201,0.18)")
                                                                mg.addColorStop(1, "rgba(126,155,201,0)")
                                                                ctx.fillStyle = mg
                                                                ctx.fill()
                                                            }
                                                            // 高地亮斑（抬 p90 到 ~(184,208,234)；径向渐变柔边）
                                                            var high = [[0.55, 0.15, 0.17], [0.14, 0.45, 0.15], [0.70, 0.36, 0.14], [0.40, 0.30, 0.12], [0.60, 0.78, 0.16], [0.20, 0.20, 0.11], [0.80, 0.74, 0.11]]
                                                            for (var h = 0; h < high.length; h++) {
                                                                var hx = c + high[h][0] * r
                                                                var hy = c + high[h][1] * r
                                                                var hr = high[h][2] * r
                                                                ctx.beginPath()
                                                                ctx.arc(hx, hy, hr, 0, 2 * Math.PI)
                                                                var hg = ctx.createRadialGradient(hx, hy, 0, hx, hy, hr)
                                                                hg.addColorStop(0, "rgba(196,214,240,0.62)")
                                                                hg.addColorStop(0.7, "rgba(196,214,240,0.35)")
                                                                hg.addColorStop(1, "rgba(196,214,240,0)")
                                                                ctx.fillStyle = hg
                                                                ctx.fill()
                                                            }
                                                            // 左上软高光（拉出峰值 ~228,236,247；alpha 0.42 压峰值防纯白打满）
                                                            var glow = ctx.createRadialGradient(c - 0.30 * r, c - 0.35 * r, 0, c - 0.30 * r, c - 0.35 * r, 0.85 * r)
                                                            glow.addColorStop(0, "rgba(228,236,247,0.42)")
                                                            glow.addColorStop(1, "rgba(228,236,247,0)")
                                                            ctx.fillStyle = glow
                                                            ctx.fillRect(0, 0, 2 * r, 2 * r)
                                                            // 环形山：ref tile-cards 月相照可见的小坑细节——暗底 + 右下亮缘（左上光源），确定性坐标
                                                            var craters = [[0.42, 0.30, 0.07], [0.62, 0.48, 0.05], [0.34, 0.62, 0.06],
                                                                           [0.72, 0.68, 0.05], [0.50, 0.18, 0.045], [0.25, 0.48, 0.05],
                                                                           [0.58, 0.78, 0.045]]
                                                            for (var cr = 0; cr < craters.length; cr++) {
                                                                var cx = c + craters[cr][0] * r
                                                                var cy = c + craters[cr][1] * r
                                                                var crx = craters[cr][2] * r
                                                                ctx.beginPath()
                                                                ctx.arc(cx, cy, crx, 0, 2 * Math.PI)
                                                                ctx.fillStyle = "rgba(126,155,201,0.30)"
                                                                ctx.fill()
                                                                ctx.beginPath()
                                                                ctx.arc(cx, cy, crx, Math.PI * 0.15, Math.PI * 0.85, false)   // 右下弧 = 受光缘
                                                                ctx.strokeStyle = "rgba(222,232,246,0.45)"
                                                                ctx.lineWidth = 1
                                                                ctx.stroke()
                                                            }
                                                            ctx.restore()
                                                            ctx.restore()
                                                        }
                                                    }
                                                }
                                            }

                                            // ref-main SUNSET 卡 x272-380 顶 y453：头部 glyph+SUNSET caps、大号时间左对齐（字形顶=卡顶+30、字高 ~14.4px@814 → 30px）；底缘被参考窗裁切，底部内容外推待确认
                                            // ref tile-cards 实测 SUNSET/UV 等宽对半（221/221@tile；ref-main 109/~117 近等宽）→ RowLayout 等分（214/15/214），镜像 wind/moon 先例
                                            RowLayout {
                                                Layout.columnSpan: 2
                                                Layout.topMargin: 8
                                                Layout.fillWidth: true
                                                spacing: 15

                                                Rectangle {
                                                    id: sunsetCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 214
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: sunsetHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)

                                                    // daily[0].sunset 形如 "2026-10-17T17:57"（Open-Meteo 本地 ISO，无时区后缀）——自旧 66px 日落瓦片原样迁入
                                                    readonly property string sunsetRaw:
                                                        backend.daily.length > 0 ? String(root.value(backend.daily[0], "sunset", "")) : ""
                                                    readonly property bool hasSunset: /T\d{1,2}:\d{2}/.test(sunsetRaw)
                                                    readonly property string sunsetText: {
                                                        if (!hasSunset) return "—"
                                                        const m = /T(\d{1,2}):(\d{2})/.exec(sunsetRaw)
                                                        let h = parseInt(m[1], 10)
                                                        const ap = h >= 12 ? qsTr("PM") : qsTr("AM")
                                                        h = h % 12
                                                        if (h === 0) h = 12
                                                        return h + ":" + m[2] + ap
                                                    }

                                                    HoverHandler { id: sunsetHover }
                                                    ToolTip.visible: sunsetHover.hovered
                                                    ToolTip.text: qsTr("Sunset")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("Sunset") + ": " + sunsetCard.sunsetText

                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: sunsetGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            Accessible.ignored: true
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                // mini 日落 glyph（ref ~8px@814 → 12px）：地平线 + 上半圆太阳 + 下落箭头，同旧 46px sunCanvas 家族缩比（墨色 #90cbff，见下实测依据）
                                                                ctx.strokeStyle = "#90cbff"
                                                                ctx.lineWidth = 1.2
                                                                ctx.beginPath()
                                                                ctx.moveTo(0.5, 9)
                                                                ctx.lineTo(11.5, 9)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.arc(6, 9, 3.5, Math.PI, 2 * Math.PI, false)
                                                                ctx.closePath()
                                                                // ref-main.png (814×498) SUNSET glyph 区 (277,457,291,471) 峰值 (144,203,255)=#90cbff、
                                                                // UV glyph 区 (400,457,414,471) 峰值 (142,202,255)；tile-cards.png 原生切片佐证
                                                                // SUNSET (154,214,255) / UV (151,210,255)、头部文字峰值 (146,205,255) 与 glyph 同族 ——
                                                                // 参考里 glyph 与头部文字同墨色（浅蓝 #90cbff 族），不是白。
                                                                // 旧记载峰值 (224,240,255)/(239,251,255) 系误采样（混入邻近白色大数字墨），作废。
                                                                ctx.fillStyle = "#90cbff"
                                                                ctx.fill()
                                                                ctx.strokeStyle = "#90cbff"
                                                                ctx.fillStyle = "#90cbff"
                                                                ctx.lineWidth = 1.2
                                                                ctx.beginPath()
                                                                ctx.moveTo(6, 2)
                                                                ctx.lineTo(6, 4.5)
                                                                ctx.stroke()
                                                                ctx.beginPath()
                                                                ctx.moveTo(6, 6)
                                                                ctx.lineTo(4.4, 4.2)
                                                                ctx.lineTo(7.6, 4.2)
                                                                ctx.closePath()
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: qsTr("Sunset").toLocaleUpperCase(Qt.locale())
                                                            color: root.cardHeaderText
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    // ref-main 大号时间墨顶=卡顶+30×1.4598≈44、左 inset ~7-9@814 → 与头部 glyph 同列 14（30px 字体行高空隙 ~9，盒顶取 35）
                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 35
                                                        text: sunsetCard.sunsetText
                                                        color: root.skyText
                                                        font.pixelSize: 30
                                                        font.weight: Font.DemiBold
                                                        Accessible.ignored: true
                                                    }
                                                }

                                                // ref tile-cards UV 卡：头部太阳光线 glyph + "UV INDEX" caps + 左对齐大数字（ink 高与 SUNSET 大号时间同为 27@tile → 30px DemiBold）；卡底被参考窗裁切，底部内容不发明
                                                Rectangle {
                                                    id: uvCard
                                                    Layout.fillWidth: true
                                                    Layout.preferredWidth: 214
                                                    implicitHeight: 162
                                                    radius: root.tileRadius
                                                    // 昼夜分材质：ref-main 白天所有卡填充暗于天空（α~0.30 深蓝玻璃）；夜间维持白玻璃
                                                    property bool hot: uvHover.hovered
                                                    property real hoverFill: hot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                                    Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }
                                                    color: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, hoverFill)

                                                    readonly property real uvVal: root.number(backend.current, "uvIndex", NaN)
                                                    readonly property string uvText: Number.isFinite(uvVal) ? String(Math.round(uvVal)) : "—"

                                                    HoverHandler { id: uvHover }
                                                    ToolTip.visible: uvHover.hovered
                                                    ToolTip.text: qsTr("UV Index")
                                                    Accessible.role: Accessible.StaticText
                                                    Accessible.name: qsTr("UV Index") + ": " + uvCard.uvText

                                                    RowLayout {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 12
                                                        spacing: 8

                                                        Canvas {
                                                            id: uvGlyphCanvas
                                                            implicitWidth: 12
                                                            implicitHeight: 12
                                                            antialiasing: true
                                                            contextType: "2d"
                                                            Accessible.ignored: true
                                                            onPaint: {
                                                                var ctx = getContext("2d")
                                                                ctx.reset()
                                                                // mini UV glyph（ref tile-cards ~14px@tile → 12px）：中心日盘 + 8 根射线
                                                                ctx.strokeStyle = "#90cbff"
                                                                ctx.lineWidth = 1.2
                                                                for (var i = 0; i < 8; i++) {
                                                                    var a = i * Math.PI / 4
                                                                    ctx.beginPath()
                                                                    ctx.moveTo(6 + Math.cos(a) * 3.2, 6 + Math.sin(a) * 3.2)
                                                                    ctx.lineTo(6 + Math.cos(a) * 5.4, 6 + Math.sin(a) * 5.4)
                                                                    ctx.stroke()
                                                                }
                                                                ctx.beginPath()
                                                                ctx.arc(6, 6, 2, 0, 2 * Math.PI, false)
                                                                ctx.closePath()
                                                                // ref-main.png UV glyph 区 (400,457,414,471) 峰值 (142,202,255)，与 SUNSET 同浅蓝 #90cbff 单色墨（同族实测），非白
                                                                ctx.fillStyle = "#90cbff"
                                                                ctx.fill()
                                                            }
                                                        }

                                                        Label {
                                                            text: qsTr("UV Index").toLocaleUpperCase(Qt.locale())
                                                            color: root.cardHeaderText
                                                            font.pixelSize: 11
                                                            font.letterSpacing: 1.4
                                                            Accessible.ignored: true
                                                        }
                                                    }

                                                    Label {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 14
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 35
                                                        text: uvCard.uvText
                                                        color: root.skyText
                                                        font.pixelSize: 30
                                                        font.weight: Font.DemiBold
                                                        Accessible.ignored: true
                                                    }
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "%"
                                                labelText: qsTr("Humidity")
                                                valueText: Math.round(root.number(
                                                    backend.current, "relativeHumidity", 0)) + "%"
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◷"
                                                labelText: qsTr("Observed")
                                                valueText: root.localTime(root.value(
                                                    backend.current, "time", ""))
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◉"
                                                labelText: qsTr("Visibility")
                                                valueText: {
                                                    const meters = root.number(backend.current, "visibility", NaN)
                                                    if (!Number.isFinite(meters))
                                                        return "—"
                                                    return backend.units === "imperial"
                                                        ? Math.round(meters / 1609.344) + " " + root.distanceUnit
                                                        : Math.round(meters / 1000) + " " + root.distanceUnit
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "◐"
                                                labelText: qsTr("Pressure")
                                                valueText: {
                                                    const hpa = root.number(backend.current, "pressure", NaN)
                                                    return Number.isFinite(hpa) ? Math.round(hpa) + " hPa" : "—"
                                                }
                                            }

                                            WeatherMetric {
                                                Layout.fillWidth: true
                                                symbol: "≈"
                                                labelText: qsTr("Feels Like")
                                                valueText: {
                                                    const feels = root.number(backend.current, "apparentTemperature", NaN)
                                                    return Number.isFinite(feels) ? Math.round(feels) + "°" : "—"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // ref-main 右列：Conditions 卡 → 10 天卡（独立堆叠，不随左列高度走；列缝 19 见 GridLayout）
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.alignment: Qt.AlignTop
                            spacing: 16
                            // Conditions 单卡：包住 头部行 + 右上分段胶囊 + 逐小时列（对齐 ref-main）
                            KosCard {
                                id: hourlyConditionsCard
                                Layout.fillWidth: true
                                // ref-main 两列等宽(239/241@814)：preferred 拉平让 GridLayout 等分剩余宽度
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop

                                background: KosSurface {
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, root.currentIsDay ? root.cardGlassAlpha : 0.16)
                                    strokeWidth: 0 // 用户裁决 2026-10-23（R80 0.5）：内容区白描边去除
                                    // innerHighlight（AppTheme 白@0.58 内侧 1px 高光线）同属白描边，一并去除
                                    showInnerHighlight: false
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ColumnLayout {
                                            spacing: 1
                                            Layout.fillWidth: true

                                            Label {
                                                Layout.fillWidth: true
                                                text: qsTr("Conditions")
                                                color: root.skyText
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                                Accessible.name: qsTr("Hourly forecast")
                                            }

                                            // 副标题为外推：固定展示温度单位，不随 segment 切换
                                            Label {
                                                Layout.fillWidth: true
                                                text: qsTr("Temperature (%1)").arg(root.temperatureUnit)
                                                // tile-conditions 原生分辨率实测副标题淡天蓝峰值 #b3f4ff (179,244,255)；文字亮于卡面，AA 只往暗混，真值≥峰值（旧 ref-main 814 降采样值 #a7ecff 系稀释低估）；非 muted 灰白
                                                color: "#b3f4ff"
                                                font.pixelSize: 11
                                            }
                                        }

                                        // 三段胶囊切换钮，参照 ref-main Conditions 卡右上分段控件。
                                        // segment 0 = 温度/图标视图（默认，参考图选中态），
                                        // segment 1 = 逐小时降水概率视图；
                                        // segment 2 = 逐小时风速视图（后端 hourlyPoint.windSpeed 已有）。
                                        Item {
                                            id: hourlySegmented
                                            implicitWidth: 132
                                            // §4 分段控件「高 28/34」（原 36 超标）：默认 34、窄窗（compact）取 28
                                            implicitHeight: root.compact ? 28 : 34
                                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                            property int segment: 0

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: hourlySegmented.height / 2 // 胶囊 = h/2（高 34；窄窗 28）
                                                // 参考实测（ref-main 814×498 Pillow 采样）：胶囊内 (28,90,168) vs 卡面 (0,83,180)
                                                // ——相对卡面 R+28/G+7/B−12，解出脱饱和中性灰 ≈#767676 @ α0.22-0.26（压暗蓝通道）；白@0.14 方向相反（整体提亮），故按参考改灰。
                                                color: Qt.rgba(0.46, 0.46, 0.46, 0.24)
                                            }

                                            // 选中段胶囊（当前段背后）——ref-main 814×498 Pillow 实测：选中胶囊 26×22@814（段宽 28、胶囊高 24，
                                            // 四周内缩 ~1px，宽>高的 stadium 近乎填满段），×1.45 → 38×32；取 40×32、内缩 2px 同族。
                                            Rectangle {
                                                x: 2 + 44 * hourlySegmented.segment
                                                y: 2
                                                width: 40
                                                height: hourlySegmented.height - 4 // 滑块内缩 2（§4 分段控件「滑块内缩 2」）
                                                radius: height / 2 // 胶囊随高（34→30、28→24）
                                                color: Qt.rgba(1, 1, 1, 0.27)
                                            }

                                            AbstractButton {
                                                x: 0
                                                width: 44
                                                height: hourlySegmented.height
                                                background: Rectangle {
                                                    // §5 Focus：2px accent 外环，偏移 2（margins −4 扣描边 2 留白恰 2px）；
                                                    // 圆角 = 胶囊 17+2（R10/LiquidSelect 先例）；失焦或禁用即移除
                                                    visible: parent.activeFocus && parent.enabled
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    radius: hourlySegmented.height / 2 + 2 // 胶囊 r+2（§5 Focus「圆角 +2」）
                                                    border.width: 2
                                                    border.color: LiquidStyle.focusColor(AppTheme.accent)
                                                    color: "transparent"
                                                }
                                                // ref tile-conditions：实心云体 + 右上探出小日盘，云与日之间有缺口（SF cloud.sun.fill 构图）
                                                // Control 会覆写 contentItem 几何，Canvas 需包 Item 再居中；segment 属于外层 hourlySegmented
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: cloudSunCanvas
                                                        width: 20
                                                        height: 15
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            // 日盘（右上探出）
                                                            ctx.beginPath()
                                                            ctx.arc(13.5, 4.5, 3.2, 0, 2 * Math.PI)
                                                            ctx.fillStyle = hourlySegmented.segment === 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.fill()
                                                            // 云体：底边 y=14 平直，大鼓包 (6,10) r4.5、小鼓包 (11,10.5) r3.8，弧线顺滑闭合
                                                            ctx.beginPath()
                                                            ctx.moveTo(2.0, 14)
                                                            ctx.lineTo(12.49, 14)
                                                            ctx.arc(11, 10.5, 3.8, 1.168, -2.006, true)   // 右侧上行翻过小包顶
                                                            ctx.arc(6, 10, 4.5, -0.716, 2.15, true)       // 越谷扫过大包顶到左侧
                                                            ctx.quadraticCurveTo(2.0, 13.9, 2.0, 14)      // 左下角微圆收口
                                                            ctx.closePath()
                                                            // 缺口：沿云体路径 stroke 打孔（先于云体 fill，fill 会盖回内侧一半）
                                                            ctx.globalCompositeOperation = "destination-out"
                                                            ctx.strokeStyle = "#000000"
                                                            ctx.lineWidth = 2.4
                                                            ctx.lineCap = "round"
                                                            ctx.lineJoin = "round"
                                                            ctx.stroke()
                                                            ctx.globalCompositeOperation = "source-over"
                                                            ctx.fill()
                                                        }
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { cloudSunCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 0
                                                Accessible.name: qsTr("Hourly conditions")
                                            }
                                            AbstractButton {
                                                x: 44
                                                width: 44
                                                height: hourlySegmented.height
                                                background: Rectangle {
                                                    // §5 Focus：同段 0（2px accent 外环偏移 2，胶囊 17+2）
                                                    visible: parent.activeFocus && parent.enabled
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    radius: hourlySegmented.height / 2 + 2 // 胶囊 r+2（§5 Focus「圆角 +2」）
                                                    border.width: 2
                                                    border.color: LiquidStyle.focusColor(AppTheme.accent)
                                                    color: "transparent"
                                                }
                                                // ref-main 实测降水段为实心水滴 6×9px@814（胶囊高 25px），我方胶囊 36px 按 1.44 折算 ≈ 9×13
                                                // Control 会覆写 contentItem 几何，Canvas 需包 Item 再居中（ref 胶囊中心 225 vs 水滴中心 225.5 居中）
                                                // LEDGER 仍差 15：ref 水滴墨/胶囊高比 0.386，canvas 12×16→15×20（×1.25），墨迹 8×11→~10×14
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: dropCanvas
                                                        width: 15
                                                        height: 20
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            ctx.beginPath()
                                                            ctx.moveTo(7.5, 1.9)
                                                            ctx.bezierCurveTo(10.25, 6.25, 12.5, 9.5, 12.5, 13.1)  // 右侧下行到圆右端
                                                            ctx.arc(7.5, 13.1, 5, 0, Math.PI, false)              // 经底部从右到左
                                                            ctx.bezierCurveTo(2.5, 9.5, 4.75, 6.25, 7.5, 1.9)     // 左侧收回尖点
                                                            ctx.closePath()
                                                            ctx.fillStyle = hourlySegmented.segment === 1 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.fill()
                                                        }
                                                        // segment 属于外层 hourlySegmented，Canvas 上无法直接写 onSegmentChanged
                                                        //（qmllint: no matching signal，运行时不触发），改用 Connections 监听后重绘
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { dropCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 1
                                                Accessible.name: qsTr("Hourly precipitation")
                                            }
                                            AbstractButton {
                                                x: 88
                                                width: 44
                                                height: hourlySegmented.height
                                                background: Rectangle {
                                                    // §5 Focus：同段 0（2px accent 外环偏移 2，胶囊 17+2）
                                                    visible: parent.activeFocus && parent.enabled
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    radius: hourlySegmented.height / 2 + 2 // 胶囊 r+2（§5 Focus「圆角 +2」）
                                                    border.width: 2
                                                    border.color: LiquidStyle.focusColor(AppTheme.accent)
                                                    color: "transparent"
                                                }
                                                // ref SF wind：三道横向流线，右端卷成小螺旋，整体重心居中
                                                contentItem: Item {
                                                    anchors.fill: parent
                                                    Canvas {
                                                        id: windCanvas
                                                        width: 16
                                                        height: 13
                                                        anchors.centerIn: parent
                                                        antialiasing: true
                                                        onPaint: {
                                                            var ctx = getContext("2d")
                                                            ctx.reset()
                                                            ctx.strokeStyle = hourlySegmented.segment === 2 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.9)
                                                            ctx.lineWidth = 1.8
                                                            ctx.lineCap = "round"
                                                            ctx.lineJoin = "round"
                                                            ctx.beginPath()
                                                            // 上线：右端 r2 向上卷
                                                            ctx.moveTo(2.0, 3.4)
                                                            ctx.quadraticCurveTo(6.0, 3.65, 10.0, 3.4)
                                                            ctx.arc(10.0, 1.4, 2.0, Math.PI / 2, 0, true)
                                                            // 中线：最长，右端 r2.4 卷
                                                            ctx.moveTo(1.5, 7.2)
                                                            ctx.quadraticCurveTo(6.5, 6.95, 12.3, 7.2)
                                                            ctx.arc(12.3, 4.8, 2.4, Math.PI / 2, -0.4, true)
                                                            // 下线：短，右端小卷
                                                            ctx.moveTo(3.0, 11.2)
                                                            ctx.quadraticCurveTo(5.5, 11.4, 8.0, 11.2)
                                                            ctx.arc(8.0, 9.6, 1.6, Math.PI / 2, 0.3, true)
                                                            ctx.stroke()
                                                        }
                                                        Connections {
                                                            target: hourlySegmented
                                                            function onSegmentChanged() { windCanvas.requestPaint() }
                                                        }
                                                        Component.onCompleted: requestPaint()
                                                        Accessible.ignored: true
                                                    }
                                                }
                                                onClicked: hourlySegmented.segment = 2
                                                Accessible.name: qsTr("Hourly wind")
                                            }
                                        }
                                    }

                                    Flickable {
                                        id: hourlyFlick
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 142
                                        // ref-main 逐小时行为整列满卡（列距 40.4@814，末列墨右缘距卡缘 ~8px，无半列字形）。
                                        // 旧固定 pitch 60（delegate 50 + spacing 10）在现视口宽下呈 6.45 列，第 7 列被
                                        // 卡缘截断出半列 "0" 残影。改为按视口整除自适应：列数 = floor((宽+10)/60)
                                        // （10 = 最小间距，向下列数取整），pitch = 宽/列数，delegate 保持 ref 的
                                        // delegate/pitch ≈ 5/6 比例，间距 = 余量均摊 → 行恰好满宽，静止时右缘恒为整列。
                                        readonly property int hourlyColumnCount: Math.max(3, Math.floor((width + 10) / 60))
                                        readonly property real hourlyPitch: width / hourlyColumnCount
                                        readonly property real hourlyDelegateWidth: hourlyPitch * 5 / 6
                                        readonly property real hourlySpacing: (width - hourlyColumnCount * hourlyDelegateWidth) / Math.max(1, hourlyColumnCount - 1)
                                        contentWidth: hourlyRow.implicitWidth
                                        contentHeight: height
                                        boundsBehavior: Flickable.StopAtBounds
                                        clip: true

                                        ScrollBar.horizontal: ScrollBar {}

                                        // ref-main（参考图）Conditions 卡本无温度曲线；本条系 TASK.md
                                        // 用户裁定（2026-10-18）按 Apple Weather 惯例外推。
                                        // 布局适配：温度墨底 content 96（real 362）、☂ 行墨顶
                                        // content 114-115（real 380-381，Pillow 实测
                                        // tmp/shots/patrol-1792320265.png），真实空档为 96..115。
                                        // 曲线带 100..110 渲染于 real 365..377（content→real
                                        // 偏移实测 +266），与温度墨/☂ 墨各留 2-3px。旧值 97..113
                                        // 系行高钉死/列密度改动前的旧测量、带值未随动，导致曲线
                                        // 左端压到温度墨上（同一截图实证）。曲线带据此落位。
                                        // 层位：Canvas 位于 Flickable 内容区内部、Row 之前声明（先声明者
                                        // 先画、z 序在下），随 contentX 一起横滚覆盖逐小时列。
                                        Canvas {
                                            id: hourlyCurve

                                            readonly property int bandTop: 100
                                            readonly property int bandInner: 10
                                            readonly property int bandBottom: 110

                                            // draw-on 揭示动画：0..1，1 = 完整曲线。1000ms 系外推：
                                            // 内容揭示类动效，HIG 环境量级（阶段三 B.6，用户裁定 1）。
                                            property real drawProgress: 1.0
                                            Behavior on drawProgress {
                                                id: drawProgressBehavior
                                                NumberAnimation { duration: 1000; easing.type: Easing.OutCubic }
                                            }

                                            function replayDraw() {
                                                if (AppTheme.reduceMotion) {
                                                    // reduce-motion：永远完整曲线，动画不跑
                                                    drawProgressBehavior.enabled = false
                                                    drawProgress = 1
                                                    drawProgressBehavior.enabled = true
                                                    requestPaint()
                                                    return
                                                }
                                                // 先在 Behavior 关闭时归零（保证落 0），再开启 Behavior
                                                // 写 1 触发 0→1 动画；同块直写 0 再写 1 会被 Behavior
                                                // 重定向为 1→1 而吞掉动画。
                                                drawProgressBehavior.enabled = false
                                                drawProgress = 0
                                                requestPaint()
                                                drawProgressBehavior.enabled = true
                                                drawProgress = 1
                                            }

                                            x: 0
                                            y: 0
                                            width: hourlyRow.implicitWidth
                                            height: 142
                                            antialiasing: true
                                            visible: hourlySegmented.segment === 0
                                            Accessible.ignored: true

                                            onWidthChanged: requestPaint()
                                            onDrawProgressChanged: requestPaint()
                                            Component.onCompleted: replayDraw()

                                            Connections {
                                                target: root
                                                function onUpcomingHoursChanged() {
                                                    hourlyCurve.replayDraw()
                                                }
                                            }

                                            Connections {
                                                target: hourlySegmented
                                                function onSegmentChanged() {
                                                    if (hourlySegmented.segment === 0)
                                                        hourlyCurve.replayDraw()
                                                }
                                            }

                                            onPaint: {
                                                var ctx = hourlyCurve.getContext("2d")
                                                ctx.clearRect(0, 0, hourlyCurve.width, hourlyCurve.height)
                                                if (hourlyCurve.drawProgress <= 0)
                                                    return
                                                var pts = []
                                                for (var i = 0; i < root.upcomingHours.length; ++i) {
                                                    var t = root.number(root.upcomingHours[i], "temperature", NaN)
                                                    if (isFinite(t))
                                                        // 与 delegate width / Row spacing 联动（hourlyPitch 自适应）：中心 x = delegateWidth/2，列距 hourlyPitch
                                                        pts.push({ x: hourlyFlick.hourlyDelegateWidth / 2 + i * hourlyFlick.hourlyPitch, t: t })
                                                }
                                                if (pts.length < 2)
                                                    return
                                                var minT = pts[0].t
                                                var maxT = pts[0].t
                                                for (var j = 1; j < pts.length; ++j) {
                                                    minT = Math.min(minT, pts[j].t)
                                                    maxT = Math.max(maxT, pts[j].t)
                                                }
                                                function yFor(t) {
                                                    if (maxT === minT)
                                                        return hourlyCurve.bandTop + hourlyCurve.bandInner / 2
                                                    return hourlyCurve.bandTop
                                                        + (1 - (t - minT) / (maxT - minT)) * hourlyCurve.bandInner
                                                }
                                                var ys = []
                                                for (var k = 0; k < pts.length; ++k)
                                                    ys.push(yFor(pts[k].t))

                                                // 把二次贝塞尔路径展平为稠密折线，便于按累计弧长截断
                                                var samples = [{ x: pts[0].x, y: ys[0] }]
                                                for (var m = 1; m < pts.length - 1; ++m) {
                                                    var p0x = samples[samples.length - 1].x
                                                    var p0y = samples[samples.length - 1].y
                                                    var cx = pts[m].x
                                                    var cy = ys[m]
                                                    var p1x = (pts[m].x + pts[m + 1].x) / 2
                                                    var p1y = (ys[m] + ys[m + 1]) / 2
                                                    for (var s = 1; s <= 16; ++s) {
                                                        var u = s / 16
                                                        var a = (1 - u) * (1 - u)
                                                        var b = 2 * (1 - u) * u
                                                        var c = u * u
                                                        samples.push({
                                                            x: a * p0x + b * cx + c * p1x,
                                                            y: a * p0y + b * cy + c * p1y
                                                        })
                                                    }
                                                }
                                                samples.push({
                                                    x: pts[pts.length - 1].x,
                                                    y: ys[ys.length - 1]
                                                })

                                                var total = 0
                                                var segLen = []
                                                for (var d = 1; d < samples.length; ++d) {
                                                    var len = Math.hypot(samples[d].x - samples[d - 1].x,
                                                                         samples[d].y - samples[d - 1].y)
                                                    segLen.push(len)
                                                    total += len
                                                }
                                                var budget = total * Math.min(1, Math.max(0, hourlyCurve.drawProgress))
                                                var cutX = samples[samples.length - 1].x
                                                var cutY = samples[samples.length - 1].y
                                                var cutIdx = samples.length - 1
                                                if (budget < total) {
                                                    var acc = 0
                                                    for (var e = 0; e < segLen.length; ++e) {
                                                        if (acc + segLen[e] >= budget) {
                                                            var f = segLen[e] > 0 ? (budget - acc) / segLen[e] : 0
                                                            cutX = samples[e].x + (samples[e + 1].x - samples[e].x) * f
                                                            cutY = samples[e].y + (samples[e + 1].y - samples[e].y) * f
                                                            cutIdx = e
                                                            break
                                                        }
                                                        acc += segLen[e]
                                                    }
                                                }

                                                ctx.beginPath()
                                                ctx.moveTo(samples[0].x, samples[0].y)
                                                for (var g = 1; g <= cutIdx; ++g)
                                                    ctx.lineTo(samples[g].x, samples[g].y)
                                                ctx.lineTo(cutX, cutY)

                                                ctx.strokeStyle = "rgba(255,255,255,0.85)"
                                                ctx.lineWidth = 2
                                                ctx.lineJoin = "round"
                                                ctx.lineCap = "round"
                                                ctx.stroke()

                                                var grad = ctx.createLinearGradient(0, hourlyCurve.bandTop, 0, hourlyCurve.bandBottom)
                                                grad.addColorStop(0, "rgba(255,255,255,0.20)")
                                                grad.addColorStop(1, "rgba(255,255,255,0)")
                                                ctx.lineTo(cutX, hourlyCurve.bandBottom)
                                                ctx.lineTo(samples[0].x, hourlyCurve.bandBottom)
                                                ctx.closePath()
                                                ctx.fillStyle = grad
                                                ctx.fill()
                                            }
                                        }

                                        Row {
                                            id: hourlyRow
                                            height: parent.height - 12
                                            spacing: hourlyFlick.hourlySpacing

                                            Repeater {
                                                model: root.upcomingHours

                                                delegate: Item {
                                                    id: hourlyCard

                                                    required property var modelData
                                                    required property int index
                                                    // ref-main Conditions 卡首列标签实测为 "Now"（当前小时），其余列为 localTime
                                                    readonly property bool isCurrentHour: {
                                                        const current = String(root.value(backend.current, "time", "")).substring(0, 13)
                                                        return current.length > 0
                                                            && String(root.value(hourlyCard.modelData, "time", "")).substring(0, 13) === current
                                                    }
                                                    // ref-main 逐小时 6 列满卡（列距 40.4@814）；列距随视口自适应（hourlyPitch），整列满宽杜绝半列残影
                                                    width: hourlyFlick.hourlyDelegateWidth
                                                    height: hourlyRow.height
                                                    opacity: 0
                                                    transform: Translate { id: entranceShift; y: 14 }

                                                    Component.onCompleted: {
                                                        if (AppTheme.reduceMotion) {
                                                            hourlyCard.opacity = 1
                                                            entranceShift.y = 0
                                                            iconBounceShift.y = 0
                                                            return
                                                        }
                                                        entranceAnim.restart()
                                                        iconBounceAnim.restart()
                                                    }

                                                    SequentialAnimation {
                                                        id: entranceAnim
                                                        PauseAnimation { duration: 40 * hourlyCard.index }
                                                        ParallelAnimation {
                                                            NumberAnimation { target: hourlyCard; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                                                            NumberAnimation { target: entranceShift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                                                        }
                                                    }

                                                    SequentialAnimation {
                                                        id: iconBounceAnim
                                                        PauseAnimation { duration: 300 + 40 * hourlyCard.index }
                                                        NumberAnimation { target: iconBounceShift; property: "y"; to: -6; duration: 110; easing.type: Easing.OutCubic }
                                                        NumberAnimation { target: iconBounceShift; property: "y"; to: 0; duration: 160; easing.type: Easing.OutBack }
                                                    }

                                                    ColumnLayout {
                                                        anchors.fill: parent
                                                        spacing: 4

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            // CJK 回退字形行盒高于数字（"现在"墨高 274-285 vs "17:00" 274-283），钉死行高防列内重排
                                                            Layout.preferredHeight: Math.ceil(font.pixelSize * 1.5)
                                                            verticalAlignment: Text.AlignVCenter
                                                            text: hourlyCard.isCurrentHour ? qsTr("Now")
                                                                : root.localTime(root.value(hourlyCard.modelData, "time", ""))
                                                            // ref-main 实测小时标签峰值 (255,255,255)（Now/12PM/2PM 三点采样一致），非 muted；同 hero H·L 轮判据
                                                            color: root.skyText
                                                        }

                                                        WeatherIcon {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            Layout.preferredWidth: 26
                                                            Layout.preferredHeight: 26
                                                            code: root.number(hourlyCard.modelData, "weatherCode", -1)
                                                            isDay: Boolean(root.value(hourlyCard.modelData, "isDay", true))
                                                            pulse: backend.loading && !AppTheme.reduceMotion
                                                            transform: Translate { id: iconBounceShift; y: 0 }
                                                            Accessible.ignored: true
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 0
                                                            // Ref hourly temps are unitless degrees ("68°"); the unit lives in the
                                                            // card subtitle "Temperature (°C)" only (see :2369).
                                                            text: Math.round(root.number(
                                                                hourlyCard.modelData, "temperature", 0)) + "°"
                                                            color: root.skyText
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 1
                                                            text: Math.round(root.number(
                                                                hourlyCard.modelData,
                                                                "precipitationProbability", 0)) + "%"
                                                            color: root.skyText
                                                            font.weight: Font.DemiBold
                                                            Accessible.name: qsTr("%1% chance of precipitation").arg(
                                                                Math.round(root.number(hourlyCard.modelData,
                                                                                       "precipitationProbability", 0)))
                                                        }

                                                        // 实测风段 "12 千米/时" ~70px 超出 50px 列宽（tmp/shots/windseg-probe-1792318936.png），
                                                        // 数字/单位分两行，单位行占用 segment 2 下 ☂ 占位行空出的位置、净行高不变；
                                                        // ref 无风段形态，两行结构系外推（Apple hourly wind 视图惯例数字大/单位小）
                                                        ColumnLayout {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            visible: hourlySegmented.segment === 2
                                                            spacing: 1
                                                            Accessible.name: qsTr("Wind speed %1 %2").arg(
                                                                Math.round(root.number(hourlyCard.modelData, "windSpeed", 0)))
                                                                                .arg(root.speedUnit)

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: Math.round(root.number(
                                                                    hourlyCard.modelData, "windSpeed", 0))
                                                                color: root.skyText
                                                                font.weight: Font.DemiBold
                                                            }

                                                            Label {
                                                                Layout.alignment: Qt.AlignHCenter
                                                                text: root.speedUnit
                                                                color: root.skyTextMuted
                                                                font.pixelSize: 10
                                                            }
                                                        }

                                                        Label {
                                                            Layout.alignment: Qt.AlignHCenter
                                                            // ref-main Conditions 卡无 ☂ 行（可见小时全 0%）：0% 隐文字但保留占位，防 ColumnLayout 重排使温度行下坠（最小 repro 实证）
                                                            visible: hourlySegmented.segment === 0
                                                            text: Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) > 0
                                                                ? "☂︎  " + Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) + "%"
                                                                : ""
                                                            color: root.skyTextMuted
                                                            font.pixelSize: 10
                                                            Accessible.name: Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)) > 0
                                                                ? qsTr("%1% chance of precipitation").arg(Math.round(root.number(hourlyCard.modelData, "precipitationProbability", 0)))
                                                                : ""
                                                        }
                                                    }
                                                }
                                            }
                                    }
                                        }
                                }
                            }

                            KosCard {
                                id: dailyCard
                                // ref-main 实测：10 天卡与 Conditions 同右列（x519-760），Conditions 底 y≈317 → 10 天卡顶 y≈329，gap ~12px@814 × 1.4598 ≈ 17.5 → rowSpacing 16 吻合（masonry 步骤 c）
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredWidth: 0
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredHeight: dailyColumn.implicitHeight + padding * 2

                                HoverHandler { id: dailyHover }
                                property bool cardHot: dailyHover.hovered
                                property real hoverFill: cardHot ? root.cardGlassAlphaHot : root.cardGlassAlpha
                                Behavior on hoverFill { NumberAnimation { duration: AppTheme.motionNormal; easing.type: Easing.OutCubic } }

                                background: KosSurface {
                                    radius: 20
                                    fillColor: Qt.rgba(root.cardGlassRgb.r, root.cardGlassRgb.g, root.cardGlassRgb.b, dailyCard.hoverFill)
                                    strokeWidth: 0 // 用户裁决 2026-10-23（R80 0.5）：内容区白描边去除
                                    // innerHighlight（AppTheme 白@0.58 内侧 1px 高光线）同属白描边，一并去除
                                    showInnerHighlight: false
                                    elevation: 0
                                }

                                contentItem: ColumnLayout {
                                    id: dailyColumn
                                    spacing: 0

                                    // ref-ipad-small.png 实测：10 天卡头部 "10-DAY FORECAST" 在卡内顶部——
                                    // calendar glyph + caps 字距 muted 文本（文本带 y321-329、glyph x276-284、与文字同色）；
                                    // ref-main 该卡被窗底裁切无头部可见，以 ipad 参考为准。
                                    // 文案照参考 "10-Day Forecast"（数据上限 7 天，差异记 LEDGER）。
                                    // 头部→首行 ink gap：ipad 参考实测 29px（头部墨底 y328 → Today 墨顶 y357），我方实测 33px（patrol-1792318394：头部墨底 y471 → 今天墨顶 y504），bottomMargin 8→4 收敛 +4px。
                                    RowLayout {
                                        spacing: 6
                                        Layout.fillWidth: true
                                        Layout.bottomMargin: 4
                                        visible: backend.daily.length > 0

                                        Canvas {
                                            width: 12
                                            height: 12
                                            Accessible.ignored: true

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = root.skyTextMuted
                                                ctx.lineWidth = 1.2
                                                // 圆角方框（calendar 外形）：x1.5..10.5、y1.5..10.5，radius 3
                                                ctx.beginPath()
                                                ctx.moveTo(4.5, 1.5)
                                                ctx.lineTo(7.5, 1.5)
                                                ctx.arcTo(10.5, 1.5, 10.5, 4.5, 3)
                                                ctx.lineTo(10.5, 7.5)
                                                ctx.arcTo(10.5, 10.5, 7.5, 10.5, 3)
                                                ctx.lineTo(4.5, 10.5)
                                                ctx.arcTo(1.5, 10.5, 1.5, 7.5, 3)
                                                ctx.lineTo(1.5, 4.5)
                                                ctx.arcTo(1.5, 1.5, 4.5, 1.5, 3)
                                                ctx.closePath()
                                                ctx.stroke()
                                                // 框内两条横线（calendar 行）：y=4.8 与 y=7.6，x 3.6..8.4
                                                ctx.beginPath()
                                                ctx.moveTo(3.6, 4.8)
                                                ctx.lineTo(8.4, 4.8)
                                                ctx.moveTo(3.6, 7.6)
                                                ctx.lineTo(8.4, 7.6)
                                                ctx.stroke()
                                            }
                                        }

                                        Label {
                                            text: qsTr("10-Day Forecast").toLocaleUpperCase(Qt.locale())
                                            color: root.cardHeaderText
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.4
                                            Accessible.name: qsTr("10-day forecast")
                                        }
                                    }

                                    KosEmptyState {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 130
                                        visible: backend.daily.length === 0
                                        symbol: "☂"
                                        titleColor: root.skyText
                                        descriptionColor: root.skyTextMuted
                                        title: qsTr("Daily forecast unavailable")
                                        description: qsTr("Cached current conditions can still be used.")
                                    }

                                    Repeater {
                                        model: backend.daily

                                        delegate: Item {
                                            id: dailyRow

                                            required property int index
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 54

                                            readonly property real dayMinimum: root.number(
                                                dailyRow.modelData, "temperatureMinimum", 0)
                                            readonly property real dayMaximum: root.number(
                                                dailyRow.modelData, "temperatureMaximum", 0)
                                            readonly property real rangeSpan: root.dailyRange.maximum
                                                - root.dailyRange.minimum
                                            readonly property real uMin: root.clamp(
                                                (dailyRow.dayMinimum - root.dailyRange.minimum)
                                                    / dailyRow.rangeSpan, 0, 1)
                                            readonly property real uMax: root.clamp(
                                                (dailyRow.dayMaximum - root.dailyRange.minimum)
                                                    / dailyRow.rangeSpan, 0, 1)
                                            readonly property real uCurrent: dailyRow.index === 0
                                                ? root.clamp(
                                                    (root.number(backend.current, "temperature", Number.NaN)
                                                        - root.dailyRange.minimum) / dailyRow.rangeSpan,
                                                    0, 1)
                                                : 0
                                            readonly property int precipChance: Math.round(root.number(
                                                dailyRow.modelData, "precipitationProbability", 0))

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 12

                                                Label {
                                                    Layout.preferredWidth: 88
                                                    text: root.dayLabel(root.value(
                                                        dailyRow.modelData, "date", ""), dailyRow.index)
                                                    color: root.skyText
                                                    font.weight: Font.DemiBold
                                                }

                                                Column {
                                                    spacing: 1

                                                    WeatherIcon {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        width: 24
                                                        height: 24
                                                        code: root.number(dailyRow.modelData, "weatherCode", -1)
                                                        isDay: true
                                                        pulse: backend.loading && !AppTheme.reduceMotion
                                                        Accessible.ignored: true
                                                    }
                                                }

                                                Column {
                                                    Layout.preferredWidth: 44
                                                    spacing: 2

                                                    Label {
                                                        width: 44
                                                        text: Math.round(dailyRow.dayMinimum) + "°"
                                                        color: root.skyTextMuted
                                                        horizontalAlignment: Text.AlignRight
                                                    }

                                                    // ref tile-10day Fri 行实测：低温 "54°" 墨 x155-177、其下 "50%" 墨 x150-181（同列近居中），
                                                    // ref-main 同构——% 落低温列下方，不放图标列下
                                                    Label {
                                                        width: 44
                                                        visible: dailyRow.precipChance > 0
                                                        text: dailyRow.precipChance + "%"
                                                        color: "#3dcaf8"
                                                        font.pixelSize: 10
                                                        horizontalAlignment: Text.AlignRight
                                                        Accessible.name: qsTr("%1% chance of precipitation").arg(
                                                            dailyRow.precipChance)
                                                    }
                                                }

                                                Item {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 20

                                                    // ref-main 复测（2026-10-18 巡检轮，推翻旧"无轨道"记载——旧轮把轨道色 (42,109,179) 误当卡面色，
                                                    // 真实卡面 Thu 行 (49,120,196)）：五条行（Today/Thu/Fri/Sat/Sun）低/高温标签间整列均有固定全宽暗轨道，
                                                    // 高 ~5px（y382-386）、比卡面暗 Δ≈(-7,-12,-16) ≈ 黑@0.08-0.10；tile-10day（iPad 原生切片）同证。
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: 0
                                                        width: parent.width
                                                        height: 5
                                                        radius: 2.5
                                                        color: "#000000"
                                                        opacity: 0.09
                                                    }
                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: parent.width * dailyRow.uMin
                                                        width: Math.max(parent.width
                                                                        * (dailyRow.uMax - dailyRow.uMin), 14)
                                                        height: 5
                                                        radius: 2.5
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop {
                                                                position: 0
                                                                color: root.tempColor(dailyRow.dayMinimum)
                                                            }
                                                            GradientStop {
                                                                position: 1
                                                                color: root.tempColor(dailyRow.dayMaximum)
                                                            }
                                                        }
                                                    }

                                                    // Today 行当前温度标记（ref-main 实测：白点直径 ≈ 条高+1px，仅 Today 行有）
                                                    Rectangle {
                                                        visible: dailyRow.index === 0
                                                            && Number.isFinite(root.number(
                                                                backend.current, "temperature", Number.NaN))
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: parent.width * dailyRow.uCurrent - width / 2
                                                        width: 8
                                                        height: 8
                                                        radius: 4
                                                        color: "#ffffff"
                                                    }
                                                }

                                                Label {
                                                    Layout.preferredWidth: 44
                                                    text: Math.round(dailyRow.dayMaximum) + "°"
                                                    color: root.skyText
                                                    horizontalAlignment: Text.AlignLeft
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 1
                                                color: AppTheme.border
                                                visible: dailyRow.index < backend.daily.length - 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 6
                        text: qsTr("Weather data by Open-Meteo. Forecast times use the selected location's timezone.")
                        color: root.skyTextMuted
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    KosWindowControls {
        targetWindow: root
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        z: 10
    }

    Item {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: root.sidebarExpanded ? 0 : 10
        width: root.sidebarExpanded ? sidebar.expandedWidth : AppTheme.controlHeight
        height: root.sidebarExpanded ? 46 : 44
        z: 10
        KosSidebarToggle {
            id: sidebarToggle
            targetWindow: root
            anchors.right: parent.right
            anchors.rightMargin: root.sidebarExpanded ? 5 : 0
            anchors.top: parent.top
            anchors.topMargin: root.sidebarExpanded ? 10 : (44 - AppTheme.controlHeight) / 2
            implicitWidth: root.sidebarExpanded ? 26 : AppTheme.controlHeight
            implicitHeight: implicitWidth
            glyphColor: "#ffffff"
            glyphPaneColor: Qt.rgba(1, 1, 1, 0.95)
            background: Rectangle {
                radius: width / 2
                // 底 0.14 系 ref-main 拟合玻璃（§9 参考图优先）；hover 按 §4.1 玻璃项
                // 「叠 hoverFill」：0.14 上叠 dark hoverFill 白 .08 → 合成 α≈0.21。
                color: sidebarToggle.hovered
                    ? Qt.rgba(1, 1, 1, 1 - (1 - 0.14) * (1 - 0.08))
                    : Qt.rgba(1, 1, 1, 0.14)
                Behavior on color { ColorAnimation { duration: 150 } } // §4.1 过渡 150ms
                // 用户裁决 2026-10-23（R80 0.5）：白描边去掉，与 GlassCircleBg 同轮收口
                //（盘钮填充层即材质，spec §2.7 亮边由顶部 specular 高光承担）。
                border.width: 0
                Rectangle {
                    // specular top sheen, clipped to the circle
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.28) }
                        GradientStop { position: 0.22; color: Qt.rgba(1, 1, 1, 0) }
                    }
                }
            }
        }
    }
}
