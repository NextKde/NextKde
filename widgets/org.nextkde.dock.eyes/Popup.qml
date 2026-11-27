import QtQuick

// Hover detail panel for Dock Buddy: displays current live mood explanation,
// 20-20-20 eye-care timer controls, and character skin switcher. Host owns the
// 300px popup shell.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property bool material: appearance ? appearance.style === "material" : false
    readonly property bool isZh: String(appearance && appearance.locale ? appearance.locale : "").toLowerCase().startsWith("zh")
    readonly property bool isDark: Boolean(appearance && appearance.isDark)
    readonly property var pal: material && appearance && appearance.palette ? appearance.palette : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? (appearance ? appearance.foreground : "#1e293b"))
        : (appearance && appearance.foreground ? appearance.foreground : (isDark ? "#fbfcff" : "#0e1015"))
    readonly property color subInk: material
        ? (pal.onSurfaceVariant ?? "#64748b")
        : Qt.rgba(ink.r, ink.g, ink.b, 0.68)
    readonly property color accent: material
        ? (pal.primary ?? "#2563eb")
        : "#0a84ff"
    readonly property color accentInk: "#ffffff"
    readonly property color cardBg: material
        ? (pal.surfaceContainerHigh ?? Qt.rgba(ink.r, ink.g, ink.b, 0.08))
        : Qt.rgba(ink.r, ink.g, ink.b, isDark ? 0.12 : 0.07)

    readonly property var hostSettings: (host && host.settings) ? host.settings : ({})
    readonly property string skin: String(
        hostSettings.skin !== undefined && hostSettings.skin !== null
            ? hostSettings.skin
            : (snapshot && snapshot.skin ? snapshot.skin : "cat")
    )
    readonly property string eyeCarePhase: String(hostSettings.eyeCarePhase ?? "idle")
    readonly property real eyeCareEndMs: Number(hostSettings.eyeCareEndMs ?? 0)

    readonly property var sys: (liveMode && host) ? host.system : null
    readonly property var med: (liveMode && host) ? host.media : null
    readonly property var wea: (liveMode && host) ? host.weather : null
    readonly property var act: (liveMode && host) ? host.activity : null
    readonly property var clk: (liveMode && host) ? host.clock : null
    readonly property var livePointer: (liveMode && host) ? host.pointer : null

    readonly property real tempC: sys && Number(sys.temperatureMilliC ?? -1) >= 0
        ? Math.round(Number(sys.temperatureMilliC) / 1000) : Number(snapshot ? (snapshot.tempC ?? -1) : -1)
    readonly property int cpuPct: sys
        ? Math.round(Math.max(0, Math.min(1, Number(sys.cpuUsage ?? 0))) * 100)
        : Number(snapshot ? (snapshot.cpuPercent ?? 24) : 24)
    readonly property bool hotState: (tempC >= 75) || (cpuPct >= 85)
    readonly property bool playingMusic: Boolean(med && med.hasPlayer && med.playing)
    readonly property int weatherCode: wea ? Number(wea.weatherCode ?? -1) : Number(snapshot ? (snapshot.weatherCode ?? -1) : -1)
    readonly property bool rainyState: weatherCode >= 51 && weatherCode <= 99
    readonly property int uptimeSec: act ? Number(act.todayUptimeSeconds ?? 0) : Number(snapshot ? (snapshot.uptimeSeconds ?? 0) : 0)
    readonly property int currentHour: clk ? Number(clk.hours ?? 12) : 12
    readonly property bool sleepyState: uptimeSec >= 7200 || currentHour >= 23 || currentHour < 5

    property real nowMs: Date.now()
    readonly property bool focusFinished: eyeCarePhase === "focus" && eyeCareEndMs > 0 && nowMs >= eyeCareEndMs
    readonly property bool breakActive: eyeCarePhase === "break" && eyeCareEndMs > nowMs
    readonly property int remainingSeconds: {
        if (eyeCarePhase === "focus" && eyeCareEndMs > nowMs)
            return Math.max(0, Math.ceil((eyeCareEndMs - nowMs) / 1000))
        if (eyeCarePhase === "break" && eyeCareEndMs > nowMs)
            return Math.max(0, Math.ceil((eyeCareEndMs - nowMs) / 1000))
        return focusFinished ? 20 : 20 * 60
    }

    function formatClock(totalSec) {
        const s = Math.max(0, Math.floor(totalSec))
        const mm = Math.floor(s / 60)
        const ss = s % 60
        return (mm < 10 ? "0" : "") + mm + ":" + (ss < 10 ? "0" : "") + ss
    }

    function formatUptime(sec) {
        const s = Math.max(0, Math.floor(sec))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (isZh) return h > 0 ? (h + "h " + m + "m") : (m + " 分钟")
        return h > 0 ? (h + "h " + m + "m") : (m + "m")
    }

    readonly property string statusLine: {
        if (focusFinished || breakActive)
            return isZh ? "该远眺 20 秒放松眼睛啦" : "Look 20 ft away for 20 seconds"
        if (hotState)
            return isZh
                ? ("有点烫 · CPU " + cpuPct + "%" + (tempC >= 0 ? (" · " + tempC + "°C") : ""))
                : ("Running hot · CPU " + cpuPct + "%" + (tempC >= 0 ? (" · " + tempC + "°C") : ""))
        if (playingMusic)
            return (isZh ? "听歌摇摆 · " : "Vibing to · ") + String(med && med.title ? med.title : "Music")
        if (rainyState)
            return isZh ? "窗外有雨 · 注意添衣哦" : "Rainy outside · stay cozy"
        if (sleepyState)
            return isZh
                ? ("在线 " + formatUptime(uptimeSec) + " · 有点犯困")
                : ("Up " + formatUptime(uptimeSec) + " · feeling sleepy")
        if (livePointer && livePointer.available)
            return isZh ? "正在全屏追踪鼠标 · 试试快速晃动或戳我" : "Tracking cursor globally · shake or poke me"
        return isZh ? "扒在 Dock 边陪你 · 右侧会随状态自动切换" : "Peeking on your Dock · reactive bubble & meters"
    }

    function startFocusTimer() {
        if (!liveMode || !host || typeof host.patchSettings !== "function") return
        const t = Date.now()
        root.nowMs = t
        host.patchSettings({ eyeCarePhase: "focus", eyeCareEndMs: t + 20 * 60 * 1000 })
    }

    function startBreakTimer() {
        if (!liveMode || !host || typeof host.patchSettings !== "function") return
        const t = Date.now()
        root.nowMs = t
        host.patchSettings({ eyeCarePhase: "break", eyeCareEndMs: t + 20 * 1000 })
    }

    function resetEyeCare() {
        if (!liveMode || !host || typeof host.patchSettings !== "function") return
        host.patchSettings({ eyeCarePhase: "idle", eyeCareEndMs: 0 })
    }

    function selectSkin(id) {
        if (!liveMode || !host || typeof host.patchSettings !== "function") return
        host.patchSettings({ skin: id })
    }

    Timer {
        interval: 500
        repeat: true
        running: root.visible && root.eyeCarePhase !== "idle"
        onTriggered: {
            const t = Date.now()
            root.nowMs = t
            if (root.eyeCarePhase === "break" && t >= root.eyeCareEndMs)
                root.resetEyeCare()
        }
    }

    implicitHeight: bodyCol.implicitHeight + 28

    Column {
        id: bodyCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // ── Mood Header ───────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4

            Row {
                width: parent.width
                spacing: 8

                Text {
                    text: root.isZh ? "灵动小伴" : "Dock Buddy"
                    color: root.ink
                    font { pixelSize: 15; weight: Font.Bold }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: sysBadgeText.implicitWidth + 12
                    height: 18
                    radius: 9
                    color: root.hotState ? Qt.rgba(0.94, 0.27, 0.27, 0.20) : root.cardBg
                    Text {
                        id: sysBadgeText
                        anchors.centerIn: parent
                        text: root.tempC >= 0
                            ? ("CPU " + root.cpuPct + "% · " + root.tempC + "°C")
                            : ("CPU " + root.cpuPct + "%")
                        color: root.hotState ? "#ef4444" : root.subInk
                        font { pixelSize: 10; weight: Font.DemiBold }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.statusLine
                color: root.subInk
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        // ── 20-20-20 Eye-Care Card ────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: eyeCareInner.implicitHeight + 20
            radius: 14
            color: (root.focusFinished || root.breakActive)
                ? Qt.rgba(0.06, 0.72, 0.50, 0.16)
                : root.cardBg

            Row {
                id: eyeCareInner
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                spacing: 10

                Column {
                    width: parent.width - btnRow.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: root.isZh ? "20-20-20 护眼计时" : "20-20-20 Eye Care"
                        color: root.ink
                        font { pixelSize: 12; weight: Font.DemiBold }
                    }
                    Text {
                        text: root.formatClock(root.remainingSeconds) + " · " + (
                            root.breakActive ? (root.isZh ? "远眺倒计时" : "Looking away")
                            : root.focusFinished ? (root.isZh ? "请看远处 20 秒" : "Time for a break")
                            : root.eyeCarePhase === "focus" ? (root.isZh ? "用眼计时中" : "Focusing")
                            : (root.isZh ? "每 20 分钟远眺 20 秒" : "Rest 20s every 20m")
                        )
                        color: (root.focusFinished || root.breakActive) ? "#10b981" : root.subInk
                        font { pixelSize: 11; weight: Font.Medium }
                    }
                }

                Row {
                    id: btnRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: primaryBtnTxt.implicitWidth + 18
                        height: 26
                        radius: 13
                        color: (root.focusFinished || root.breakActive)
                            ? "#10b981"
                            : (root.eyeCarePhase === "focus" ? "#ef4444" : root.accent)
                        Text {
                            id: primaryBtnTxt
                            anchors.centerIn: parent
                            text: root.focusFinished
                                ? (root.isZh ? "开始远眺" : "Rest 20s")
                                : root.eyeCarePhase === "idle"
                                    ? (root.isZh ? "开始" : "Start")
                                    : (root.isZh ? "结束" : "Stop")
                            color: root.accentInk
                            font { pixelSize: 11; weight: Font.DemiBold }
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.focusFinished) root.startBreakTimer()
                                else if (root.eyeCarePhase === "idle") root.startFocusTimer()
                                else root.resetEyeCare()
                            }
                        }
                    }
                }
            }
        }

        // ── Character Skins ───────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Text {
                text: root.isZh ? "角色造型" : "Companion"
                color: root.subInk
                font { pixelSize: 11; weight: Font.DemiBold }
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { id: "cat", zh: "小黑猫", en: "Kitty" },
                        { id: "robot", zh: "机器人", en: "Bot" },
                        { id: "glasses", zh: "眼镜仔", en: "Specs" },
                        { id: "ghost", zh: "小幽灵", en: "Ghost" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool selected: root.skin === modelData.id
                        width: (parent.width - 18) / 4
                        height: 28
                        radius: 14
                        color: selected ? root.accent : root.cardBg
                        border.width: selected ? 1.5 : 1
                        border.color: selected
                            ? Qt.rgba(1, 1, 1, 0.45)
                            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)

                        Text {
                            anchors.centerIn: parent
                            text: root.isZh ? modelData.zh : modelData.en
                            color: selected ? root.accentInk : root.ink
                            font { pixelSize: 11; weight: selected ? Font.Bold : Font.Medium }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectSkin(modelData.id)
                        }
                    }
                }
            }
        }
    }
}
