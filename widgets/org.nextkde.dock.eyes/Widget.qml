import QtQuick

// Peeking Dock companion ("Dock Buddy"): atmospheric mini backdrop scene +
// left character peeking over the bottom edge with cursor tracking, + right
// dynamic mini panel showing speech bubble, 20-20-20 timer, music eq, or CPU pulse.
Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool vertical: host ? host.orientation === "vertical" : false
    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property bool material: appearance ? appearance.style === "material" : false
    readonly property bool isZh: String(appearance && appearance.locale ? appearance.locale : "").toLowerCase().startsWith("zh")
    readonly property bool isDark: Boolean(appearance && appearance.isDark)
    readonly property var pal: material && appearance && appearance.palette ? appearance.palette : ({})
    readonly property color ink: material
        ? (pal.onSurface ?? "#1e293b")
        : (appearance && appearance.foreground ? appearance.foreground : "white")
    readonly property color subInk: material
        ? (pal.onSurfaceVariant ?? "#64748b")
        : Qt.rgba(ink.r, ink.g, ink.b, 0.75)
    readonly property color accentCol: material
        ? (pal.primary ?? "#2563eb")
        : "#0a84ff"
    readonly property color chipBg: material
        ? (pal.surfaceContainerHigh ?? Qt.rgba(ink.r, ink.g, ink.b, 0.10))
        : Qt.rgba(0, 0, 0, isDark ? 0.34 : 0.20)

    // ── Reactive host settings & live telemetry (avoid ?. on var host) ───
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
    readonly property real cpuUsage: sys ? Math.max(0, Math.min(1, Number(sys.cpuUsage ?? 0))) : 0.24
    readonly property int cpuPct: Math.round(cpuUsage * 100)
    readonly property var cpuHist: (sys && Array.isArray(sys.cpuHistory) && sys.cpuHistory.length > 1)
        ? sys.cpuHistory : (snapshot && snapshot.cpuHistory ? snapshot.cpuHistory : [0.22, 0.28, 0.25, 0.34, 0.27, 0.24])
    readonly property bool hotState: (tempC >= 75) || (cpuUsage >= 0.85)
    readonly property bool playingMusic: Boolean(med && med.hasPlayer && med.playing)
    readonly property color musicColor: (playingMusic && med && med.artworkColors && med.artworkColors.ready)
        ? Qt.color(String(med.artworkColors.primary)) : accentCol
    readonly property int weatherCode: wea ? Number(wea.weatherCode ?? -1) : Number(snapshot ? (snapshot.weatherCode ?? -1) : -1)
    readonly property bool rainyState: weatherCode >= 51 && weatherCode <= 99
    readonly property int uptimeSec: act ? Number(act.todayUptimeSeconds ?? 0) : Number(snapshot ? (snapshot.uptimeSeconds ?? 0) : 0)
    readonly property int currentHour: clk ? Number(clk.hours ?? 12) : 12
    readonly property bool isNight: currentHour >= 20 || currentHour < 6
    readonly property bool isSunset: currentHour >= 17 && currentHour < 20
    readonly property bool sleepyState: uptimeSec >= 7200 || currentHour >= 23 || currentHour < 5

    // ── Interactive & timer states ────────────────────────────────────────
    property real nowMs: Date.now()
    readonly property bool focusFinished: eyeCarePhase === "focus" && eyeCareEndMs > 0 && nowMs >= eyeCareEndMs
    readonly property bool breakDue: eyeCarePhase === "break" || focusFinished
    readonly property int remainingSec: {
        if (eyeCarePhase === "focus" && eyeCareEndMs > nowMs)
            return Math.max(0, Math.ceil((eyeCareEndMs - nowMs) / 1000))
        if (eyeCarePhase === "break" && eyeCareEndMs > nowMs)
            return Math.max(0, Math.ceil((eyeCareEndMs - nowMs) / 1000))
        return focusFinished ? 20 : 20 * 60
    }
    readonly property real eyeCareProgress: {
        if (eyeCarePhase === "focus") {
            const total = 20 * 60
            return Math.max(0, Math.min(1, 1 - remainingSec / total))
        }
        if (eyeCarePhase === "break")
            return Math.max(0, Math.min(1, 1 - remainingSec / 20))
        return 0
    }

    property real pokedUntilMs: 0
    property int pokeCount: 0
    property real lastPokeMs: 0
    readonly property bool isPoked: nowMs < pokedUntilMs
    readonly property bool isGrumpy: isPoked && pokeCount >= 4

    property real dizzyUntilMs: 0
    readonly property bool isDizzy: nowMs < dizzyUntilMs

    property real dizzyPhase: 0
    property real animPhase: 0
    property real scenePhase: 0
    property real blinkAmount: 0
    property real duckAmount: isPoked ? 1.0 : 0.0
    property real idleLookX: 0.22
    property real idleLookY: -0.06
    property real targetGazeX: 0.22
    property real targetGazeY: -0.06
    property bool crossEyed: false
    property real pupilScale: 1.0

    property real smoothGazeX: targetGazeX
    property real smoothGazeY: targetGazeY
    Behavior on smoothGazeX { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
    Behavior on smoothGazeY { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
    Behavior on blinkAmount { NumberAnimation { duration: 75; easing.type: Easing.InOutQuad } }
    Behavior on duckAmount { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }
    Behavior on pupilScale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    onSmoothGazeXChanged: buddyCanvas.requestPaint()
    onSmoothGazeYChanged: buddyCanvas.requestPaint()
    onBlinkAmountChanged: buddyCanvas.requestPaint()
    onDuckAmountChanged: buddyCanvas.requestPaint()
    onPupilScaleChanged: buddyCanvas.requestPaint()
    onCrossEyedChanged: buddyCanvas.requestPaint()
    onSkinChanged: buddyCanvas.requestPaint()
    onMoodChanged: { buddyCanvas.requestPaint(); sceneCanvas.requestPaint() }
    onInkChanged: { buddyCanvas.requestPaint(); sceneCanvas.requestPaint() }
    onIsNightChanged: sceneCanvas.requestPaint()
    onIsSunsetChanged: sceneCanvas.requestPaint()
    onRainyStateChanged: sceneCanvas.requestPaint()
    onScenePhaseChanged: sceneCanvas.requestPaint()
    onAnimPhaseChanged: {
        if (mood === "music" || mood === "hot" || skin === "robot" || skin === "ghost")
            buddyCanvas.requestPaint()
        if (rightMode === "music")
            eqCanvas.requestPaint()
    }
    onDizzyPhaseChanged: if (isDizzy) buddyCanvas.requestPaint()
    onRemainingSecChanged: if (rightMode === "eyecare") ringCanvas.requestPaint()
    onCpuHistChanged: if (rightMode === "hot") pulseCanvas.requestPaint()

    readonly property string mood: {
        if (isPoked) return isGrumpy ? "grumpy" : "poked"
        if (isDizzy) return "dizzy"
        if (breakDue) return "breakDue"
        if (hotState) return "hot"
        if (playingMusic) return "music"
        if (rainyState) return "rain"
        if (sleepyState) return "sleepy"
        return "normal"
    }

    readonly property string rightMode: {
        if (eyeCarePhase !== "idle") return "eyecare"
        if (playingMusic) return "music"
        if (hotState) return "hot"
        return "bubble"
    }

    readonly property string bubbleText: {
        if (mood === "grumpy") return isZh ? "别戳啦!" : "Hey!"
        if (mood === "poked") return isZh ? "哎呀!" : "Oop!"
        if (mood === "dizzy") return isZh ? "好晕 @.@" : "Dizzy!"
        if (crossEyed) return isZh ? "好近!" : "Whoa!"
        if (mood === "rain") return isZh ? "下雨啦" : "Rainy"
        if (mood === "sleepy") return isZh ? "困了 zZ" : "Sleepy"
        if (livePointer && livePointer.available) {
            if (Math.abs(smoothGazeX) > 0.6)
                return smoothGazeX < 0 ? (isZh ? "看左边" : "Peek <") : (isZh ? "看右边" : "> Peek")
            return isZh ? "盯~" : "Peek~"
        }
        return isZh ? "摸鱼中" : "Chillin"
    }

    // Rich macOS time-of-day / mood gradient backdrop
    readonly property var backgroundSpec: {
        if (breakDue) {
            return {
                startColor: Qt.rgba(0.08, 0.48, 0.36, 0.72),
                endColor: Qt.rgba(0.16, 0.68, 0.50, 0.50),
                orientation: "horizontal"
            }
        }
        if (hotState) {
            return {
                startColor: Qt.rgba(0.66, 0.20, 0.16, 0.70),
                endColor: Qt.rgba(0.92, 0.46, 0.18, 0.48),
                orientation: "horizontal"
            }
        }
        if (playingMusic && med && med.artworkColors && med.artworkColors.ready) {
            const p = Qt.color(String(med.artworkColors.primary))
            const s = Qt.color(String(med.artworkColors.secondary))
            return {
                startColor: Qt.alpha(p, 0.64),
                endColor: Qt.alpha(s, 0.44),
                orientation: "horizontal"
            }
        }
        if (rainyState) {
            return {
                startColor: Qt.rgba(0.18, 0.28, 0.42, 0.66),
                endColor: Qt.rgba(0.28, 0.40, 0.56, 0.46),
                orientation: "vertical"
            }
        }
        if (isNight) {
            return {
                startColor: Qt.rgba(0.10, 0.14, 0.32, 0.74),
                endColor: Qt.rgba(0.22, 0.24, 0.48, 0.52),
                orientation: "vertical"
            }
        }
        if (isSunset) {
            return {
                startColor: Qt.rgba(0.38, 0.24, 0.48, 0.66),
                endColor: Qt.rgba(0.86, 0.46, 0.32, 0.52),
                orientation: "vertical"
            }
        }
        return {
            startColor: Qt.rgba(0.16, 0.44, 0.74, 0.60),
            endColor: Qt.rgba(0.32, 0.64, 0.88, 0.42),
            orientation: "vertical"
        }
    }

    // ── Pointer & shake detection ─────────────────────────────────────────
    property var _shakeHistory: []
    property real _lastShakeX: 0

    function recordMotionForShake(xVal, tMs) {
        const dx = xVal - _lastShakeX
        if (Math.abs(dx) < 28) return
        const dir = dx > 0 ? 1 : -1
        _lastShakeX = xVal
        const kept = []
        for (let i = 0; i < _shakeHistory.length; ++i) {
            if (tMs - _shakeHistory[i].t <= 850)
                kept.push(_shakeHistory[i])
        }
        if (kept.length === 0 || kept[kept.length - 1].dir !== dir)
            kept.push({ dir: dir, t: tMs })
        _shakeHistory = kept
        if (kept.length >= 6) {
            dizzyUntilMs = tMs + 2200
            _shakeHistory = []
        }
    }

    function updateGazeFromDelta(dx, dy) {
        const dist = Math.hypot(dx, dy)
        const closeThreshold = root.vertical ? 28 : 42
        root.crossEyed = dist < closeThreshold
        root.pupilScale = dist < 140 ? 1.15 : 1.0
        if (dist < 1) {
            root.targetGazeX = 0
            root.targetGazeY = 0
            return
        }
        const range = 260
        const mag = Math.min(1.0, dist / range)
        root.targetGazeX = (dx / dist) * mag
        root.targetGazeY = (dy / dist) * mag
    }

    onLivePointerChanged: {
        if (!livePointer || !livePointer.available) return
        if (localHover.hovered) return
        const center = (host && typeof host.globalCenter === "function") ? host.globalCenter() : null
        if (!center) return
        const t = Date.now()
        root.nowMs = t
        recordMotionForShake(Number(livePointer.x), t)
        updateGazeFromDelta(Number(livePointer.x) - center.x, Number(livePointer.y) - center.y)
    }

    HoverHandler {
        id: localHover
        onPointChanged: {
            const p = point.position
            const t = Date.now()
            root.nowMs = t
            root.recordMotionForShake(p.x * 6, t)
            root.updateGazeFromDelta((p.x - buddyCanvas.width * 0.5) * 4.0, (p.y - root.height * 0.5) * 4.0)
        }
        onHoveredChanged: {
            if (!hovered && (!root.livePointer || !root.livePointer.available)) {
                root.crossEyed = false
                root.pupilScale = 1.0
                root.targetGazeX = root.idleLookX
                root.targetGazeY = root.idleLookY
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const t = Date.now()
            root.nowMs = t
            root.pokeCount = (t - root.lastPokeMs <= 1800) ? (root.pokeCount + 1) : 1
            root.lastPokeMs = t
            root.pokedUntilMs = t + (root.pokeCount >= 4 ? 1200 : 750)
            buddyCanvas.requestPaint()
        }
    }

    Timer {
        interval: 300
        repeat: true
        running: root.visible && (root.isPoked || root.isDizzy || root.eyeCarePhase !== "idle")
        onTriggered: {
            const t = Date.now()
            root.nowMs = t
            if (root.eyeCarePhase === "break" && t >= root.eyeCareEndMs && root.host && typeof root.host.patchSettings === "function")
                root.host.patchSettings({ eyeCarePhase: "idle", eyeCareEndMs: 0 })
        }
    }

    Timer {
        interval: 45
        repeat: true
        running: root.visible && (root.isDizzy || root.rightMode === "music" || root.mood === "hot" || root.skin === "robot" || root.skin === "ghost")
        onTriggered: {
            if (root.isDizzy) root.dizzyPhase += 0.45
            root.animPhase += 0.24
        }
    }

    // Gentle sky/weather drift tick (~5Hz)
    Timer {
        interval: 220
        repeat: true
        running: root.visible
        onTriggered: root.scenePhase += 0.16
    }

    Timer {
        interval: 2800
        repeat: true
        running: root.visible && (!root.livePointer || !root.livePointer.available) && !localHover.hovered
        onTriggered: {
            const angles = [
                [-0.55, -0.15], [0.55, -0.12], [0.0, 0.25], [-0.25, 0.08], [0.38, 0.08]
            ]
            const pick = angles[Math.floor(Math.random() * angles.length)]
            root.idleLookX = pick[0]
            root.idleLookY = pick[1]
            root.targetGazeX = pick[0]
            root.targetGazeY = pick[1]
        }
    }

    Timer {
        interval: root.breakDue ? 1500 : (3000 + Math.random() * 2600)
        repeat: true
        running: root.visible && !root.isPoked && !root.isDizzy
        onTriggered: {
            root.blinkAmount = 1.0
            blinkOpenTimer.restart()
            interval = root.breakDue ? 1500 : (3000 + Math.random() * 2600)
        }
    }
    Timer {
        id: blinkOpenTimer
        interval: 115
        repeat: false
        onTriggered: root.blinkAmount = 0.0
    }

    // ── Atmospheric Mini Scene Backdrop Canvas ────────────────────────────
    Canvas {
        id: sceneCanvas
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width
            const h = height
            if (w < 16 || h < 16) return

            // Subtle ground/horizon hill curve along the very bottom so the buddy peeks over a real ledge
            ctx.save()
            ctx.fillStyle = root.material
                ? Qt.alpha(root.ink, 0.08).toString()
                : "rgba(255, 255, 255, 0.14)"
            ctx.beginPath()
            ctx.moveTo(0, h)
            ctx.lineTo(0, h * 0.78)
            ctx.quadraticCurveTo(w * 0.25, h * 0.66, w * 0.56, h * 0.80)
            ctx.quadraticCurveTo(w * 0.82, h * 0.90, w, h * 0.74)
            ctx.lineTo(w, h)
            ctx.closePath()
            ctx.fill()
            ctx.restore()

            const t = root.scenePhase
            const decoCol = root.material ? Qt.alpha(root.ink, 0.30).toString() : "rgba(255, 255, 255, 0.40)"
            const softCol = root.material ? Qt.alpha(root.ink, 0.16).toString() : "rgba(255, 255, 255, 0.22)"

            if (root.mood === "breakDue") {
                // Soft green sparkles
                ctx.save()
                ctx.fillStyle = "rgba(52, 211, 153, 0.50)"
                const pts = [[0.14, 0.24], [0.42, 0.16], [0.84, 0.22], [0.68, 0.72]]
                for (let i = 0; i < pts.length; ++i) {
                    const r = 1.6 + 0.8 * Math.sin(t + i * 1.4)
                    ctx.beginPath()
                    ctx.arc(w * pts[i][0], h * pts[i][1], r, 0, Math.PI * 2)
                    ctx.fill()
                }
                ctx.restore()
            } else if (root.rainyState) {
                // Gentle falling rain streaks
                ctx.save()
                ctx.strokeStyle = decoCol
                ctx.lineWidth = 1.1
                ctx.lineCap = "round"
                for (let i = 0; i < 6; ++i) {
                    const rx = ((i * 0.18 + t * 0.04) % 1.0) * w
                    const ry = ((i * 0.29 + t * 0.12) % 0.85) * h
                    ctx.beginPath()
                    ctx.moveTo(rx, ry)
                    ctx.lineTo(rx - 3, ry + 6)
                    ctx.stroke()
                }
                ctx.restore()
            } else if (root.playingMusic) {
                // Subtle floating notes
                ctx.save()
                ctx.fillStyle = decoCol
                ctx.font = "10px sans-serif"
                const yOff = Math.sin(t * 0.9) * 2
                ctx.fillText("♪", w * 0.10, h * 0.30 + yOff)
                ctx.fillText("♫", w * 0.44, h * 0.24 - yOff)
                ctx.restore()
            } else if (root.isNight) {
                // Crescent moon + twinkling stars
                ctx.save()
                const mx = w * 0.14
                const my = h * 0.26
                ctx.fillStyle = "rgba(253, 224, 71, 0.78)"
                ctx.beginPath()
                ctx.arc(mx, my, 4.8, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "destination-out"
                ctx.beginPath()
                ctx.arc(mx + 2.4, my - 1.4, 4.2, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "source-over"

                const stars = [[0.36, 0.20], [0.48, 0.34], [0.88, 0.18], [0.62, 0.18]]
                for (let s = 0; s < stars.length; ++s) {
                    const a = 0.25 + 0.45 * Math.abs(Math.sin(t * 0.7 + s * 1.5))
                    ctx.fillStyle = "rgba(255, 255, 255, " + a.toFixed(2) + ")"
                    ctx.beginPath()
                    ctx.arc(w * stars[s][0], h * stars[s][1], 1.2, 0, Math.PI * 2)
                    ctx.fill()
                }
                ctx.restore()
            } else {
                // Daytime / sunset sun + soft drifting clouds
                ctx.save()
                ctx.fillStyle = root.isSunset ? "rgba(251, 146, 60, 0.75)" : "rgba(250, 204, 21, 0.78)"
                ctx.beginPath()
                ctx.arc(w * 0.12, h * 0.26, 4.5, 0, Math.PI * 2)
                ctx.fill()

                const drift = Math.sin(t * 0.25) * 4
                ctx.fillStyle = softCol
                const clouds = [[w * 0.38 + drift, h * 0.24], [w * 0.76 - drift, h * 0.22]]
                for (let c = 0; c < clouds.length; ++c) {
                    const cx0 = clouds[c][0]
                    const cy0 = clouds[c][1]
                    ctx.beginPath()
                    ctx.arc(cx0, cy0, 4.2, 0, Math.PI * 2)
                    ctx.arc(cx0 + 5, cy0 - 1.5, 5.0, 0, Math.PI * 2)
                    ctx.arc(cx0 + 10, cy0, 3.8, 0, Math.PI * 2)
                    ctx.fill()
                }
                ctx.restore()
            }
        }
    }

    // ── Left Peeking Character Canvas ─────────────────────────────────────
    Canvas {
        id: buddyCanvas
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.vertical ? parent.width : Math.round(parent.width * 0.47)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width
            const h = height
            if (w < 18 || h < 18) return

            const m = root.mood
            const skin = root.skin
            const bobY = (m === "music") ? Math.sin(root.animPhase) * 1.8
                : (skin === "ghost" ? Math.sin(root.animPhase * 0.65) * 1.4 : 0)
            const duckY = root.duckAmount * (h * 0.14)
            const shakeX = (m === "hot") ? Math.sin(root.animPhase * 2.2) * 0.9 : 0

            const headW = Math.min(w * 0.78, h * 1.12)
            const headR = headW * 0.44
            const cx = w * 0.5 + shakeX
            const baseY = h - Math.max(2, h * 0.05)
            const headCy = baseY - headR * 0.74 + bobY + duckY

            const frameInk = root.material
                ? root.ink.toString()
                : (root.isDark ? "rgba(255,255,255,0.92)" : "rgba(30,41,59,0.92)")
            const accentStr = root.accentCol.toString()

            if (m === "breakDue") {
                ctx.save()
                ctx.fillStyle = "rgba(16, 185, 129, 0.24)"
                ctx.beginPath()
                ctx.arc(cx, headCy, headR * 1.24, 0, Math.PI * 2)
                ctx.fill()
                ctx.restore()
            }

            let bodyFill = "#1e293b"
            let bodyStroke = "rgba(255,255,255,0.20)"
            if (skin === "cat") {
                bodyFill = m === "hot" ? "#451a1a" : "#1c202a"
                bodyStroke = root.isDark ? "rgba(255,255,255,0.24)" : "rgba(15,23,42,0.30)"

                const twitch = root.smoothGazeX * 1.5
                ctx.save()
                ctx.fillStyle = bodyFill
                ctx.strokeStyle = bodyStroke
                ctx.lineWidth = 1.2
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(cx - headR * 0.84, headCy - headR * 0.25)
                ctx.lineTo(cx - headR * 0.92 + twitch, headCy - headR * 1.12)
                ctx.lineTo(cx - headR * 0.25, headCy - headR * 0.78)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(cx + headR * 0.84, headCy - headR * 0.25)
                ctx.lineTo(cx + headR * 0.92 + twitch, headCy - headR * 1.12)
                ctx.lineTo(cx + headR * 0.25, headCy - headR * 0.78)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
                ctx.fillStyle = "rgba(244, 114, 182, 0.58)"
                ctx.beginPath()
                ctx.moveTo(cx - headR * 0.72, headCy - headR * 0.42)
                ctx.lineTo(cx - headR * 0.78 + twitch, headCy - headR * 0.92)
                ctx.lineTo(cx - headR * 0.36, headCy - headR * 0.68)
                ctx.closePath()
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(cx + headR * 0.72, headCy - headR * 0.42)
                ctx.lineTo(cx + headR * 0.78 + twitch, headCy - headR * 0.92)
                ctx.lineTo(cx + headR * 0.36, headCy - headR * 0.68)
                ctx.closePath()
                ctx.fill()
                ctx.restore()
            } else if (skin === "robot") {
                bodyFill = root.material ? "#334155" : "#273449"
                bodyStroke = "rgba(148, 163, 184, 0.50)"
                ctx.save()
                ctx.strokeStyle = frameInk
                ctx.lineWidth = 1.6
                ctx.beginPath()
                ctx.moveTo(cx, headCy - headR * 0.82)
                ctx.lineTo(cx + root.smoothGazeX * 2, headCy - headR * 1.24)
                ctx.stroke()
                const pulse = 0.55 + 0.45 * Math.sin(root.animPhase * 0.9)
                ctx.fillStyle = m === "hot" ? "#ef4444"
                    : (m === "breakDue" ? "#10b981" : ("rgba(56, 189, 248, " + pulse.toFixed(2) + ")"))
                ctx.beginPath()
                ctx.arc(cx + root.smoothGazeX * 2, headCy - headR * 1.28, Math.max(2.2, headR * 0.16), 0, Math.PI * 2)
                ctx.fill()
                ctx.restore()
            } else if (skin === "ghost") {
                bodyFill = "#f1f5f9"
                bodyStroke = "rgba(15, 23, 42, 0.20)"
            } else {
                bodyFill = m === "hot" ? "#f97316" : accentStr
                bodyStroke = root.isDark ? "rgba(255,255,255,0.26)" : "rgba(15,23,42,0.20)"
            }

            ctx.save()
            ctx.beginPath()
            ctx.arc(cx, headCy, headR, Math.PI * 0.92, Math.PI * 2.08)
            ctx.lineTo(cx + headR * 0.96, h)
            ctx.lineTo(cx - headR * 0.96, h)
            ctx.closePath()
            ctx.fillStyle = bodyFill
            ctx.fill()
            ctx.strokeStyle = bodyStroke
            ctx.lineWidth = 1.2
            ctx.stroke()
            ctx.restore()

            const eyeR = headR * (skin === "glasses" ? 0.34 : 0.30)
            const eyeGap = headR * 0.24
            const eyeY = headCy - headR * 0.06
            const leftEx = cx - eyeR - eyeGap * 0.5
            const rightEx = cx + eyeR + eyeGap * 0.5
            const centers = [leftEx, rightEx]

            for (let i = 0; i < 2; ++i) {
                const ex = centers[i]
                const sign = i === 0 ? 1 : -1

                ctx.save()
                ctx.beginPath()
                ctx.arc(ex, eyeY, eyeR, 0, Math.PI * 2)
                ctx.fillStyle = (skin === "cat") ? "#fde047"
                    : (skin === "robot" ? "#0f172a" : "#ffffff")
                ctx.fill()
                ctx.clip()

                if (m === "poked" || m === "grumpy") {
                    ctx.strokeStyle = (skin === "robot") ? "#38bdf8" : "#111827"
                    ctx.lineWidth = Math.max(1.8, eyeR * 0.22)
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    const s = eyeR * 0.45
                    ctx.beginPath()
                    if (i === 0) {
                        ctx.moveTo(ex - s * 0.7, eyeY - s * 0.6)
                        ctx.lineTo(ex + s * 0.45, eyeY)
                        ctx.lineTo(ex - s * 0.7, eyeY + s * 0.6)
                    } else {
                        ctx.moveTo(ex + s * 0.7, eyeY - s * 0.6)
                        ctx.lineTo(ex - s * 0.45, eyeY)
                        ctx.lineTo(ex + s * 0.7, eyeY + s * 0.6)
                    }
                    ctx.stroke()
                } else if (m === "dizzy") {
                    ctx.strokeStyle = (skin === "robot") ? "#38bdf8" : "#1e293b"
                    ctx.lineWidth = Math.max(1.3, eyeR * 0.16)
                    ctx.beginPath()
                    for (let k = 0; k <= 30; ++k) {
                        const t = k / 30
                        const a = root.dizzyPhase + t * Math.PI * 4.6
                        const r = t * eyeR * 0.72
                        const px = ex + Math.cos(a) * r
                        const py = eyeY + Math.sin(a) * r
                        if (k === 0) ctx.moveTo(px, py)
                        else ctx.lineTo(px, py)
                    }
                    ctx.stroke()
                } else {
                    let gx = root.smoothGazeX
                    let gy = root.smoothGazeY
                    if (root.crossEyed) {
                        gx = sign * 0.68
                        gy = 0.08
                    }
                    const pBaseR = eyeR * 0.48 * root.pupilScale
                    const maxTravel = Math.max(0, eyeR - pBaseR - 1)
                    const px = ex + gx * maxTravel
                    const py = eyeY + gy * maxTravel

                    if (skin === "cat") {
                        const slitW = eyeR * (root.isDark ? 0.36 : 0.20) * root.pupilScale
                        const slitH = eyeR * 0.74
                        ctx.beginPath()
                        ctx.ellipse(px - slitW, py - slitH, slitW * 2, slitH * 2)
                        ctx.fillStyle = "#111827"
                        ctx.fill()
                        ctx.beginPath()
                        ctx.arc(px - slitW * 0.35, py - slitH * 0.45, Math.max(1.1, eyeR * 0.16), 0, Math.PI * 2)
                        ctx.fillStyle = "rgba(255,255,255,0.88)"
                        ctx.fill()
                    } else if (skin === "robot") {
                        ctx.beginPath()
                        ctx.arc(px, py, pBaseR, 0, Math.PI * 2)
                        ctx.fillStyle = m === "hot" ? "#f87171"
                            : (m === "breakDue" ? "#34d399" : "#38bdf8")
                        ctx.fill()
                    } else {
                        ctx.beginPath()
                        ctx.arc(px, py, pBaseR, 0, Math.PI * 2)
                        ctx.fillStyle = m === "breakDue" ? "#059669" : "#111827"
                        ctx.fill()
                        ctx.beginPath()
                        ctx.arc(px - pBaseR * 0.32, py - pBaseR * 0.34, Math.max(1.2, pBaseR * 0.28), 0, Math.PI * 2)
                        ctx.fillStyle = "rgba(255,255,255,0.92)"
                        ctx.fill()
                    }

                    const droop = (m === "sleepy") ? 0.46 : 0.0
                    const closeFrac = Math.max(root.blinkAmount, droop)
                    if (closeFrac > 0.02) {
                        ctx.fillStyle = bodyFill
                        ctx.fillRect(ex - eyeR - 2, eyeY - eyeR - 2, eyeR * 2 + 4, eyeR * 2 * Math.min(1, closeFrac) + 2)
                    }
                }
                ctx.restore()

                if (skin === "glasses") {
                    ctx.save()
                    ctx.beginPath()
                    ctx.arc(ex, eyeY, eyeR + 1.2, 0, Math.PI * 2)
                    ctx.strokeStyle = frameInk
                    ctx.lineWidth = Math.max(1.4, eyeR * 0.20)
                    ctx.stroke()
                    ctx.restore()
                }
            }

            if (skin === "glasses") {
                ctx.save()
                ctx.strokeStyle = frameInk
                ctx.lineWidth = Math.max(1.4, eyeR * 0.18)
                ctx.beginPath()
                ctx.moveTo(leftEx + eyeR, eyeY - eyeR * 0.15)
                ctx.quadraticCurveTo(cx, eyeY - eyeR * 0.45, rightEx - eyeR, eyeY - eyeR * 0.15)
                ctx.stroke()
                ctx.restore()
            } else if (skin === "cat") {
                ctx.save()
                ctx.fillStyle = "#f472b6"
                ctx.beginPath()
                ctx.arc(cx, eyeY + eyeR * 0.72, Math.max(1.3, headR * 0.08), 0, Math.PI * 2)
                ctx.fill()
                ctx.strokeStyle = "rgba(255,255,255,0.34)"
                ctx.lineWidth = 1.0
                ctx.beginPath()
                ctx.moveTo(cx - headR * 0.46, eyeY + eyeR * 0.55)
                ctx.lineTo(cx - headR * 0.94, eyeY + eyeR * 0.42)
                ctx.moveTo(cx - headR * 0.46, eyeY + eyeR * 0.85)
                ctx.lineTo(cx - headR * 0.92, eyeY + eyeR * 0.96)
                ctx.moveTo(cx + headR * 0.46, eyeY + eyeR * 0.55)
                ctx.lineTo(cx + headR * 0.94, eyeY + eyeR * 0.42)
                ctx.moveTo(cx + headR * 0.46, eyeY + eyeR * 0.85)
                ctx.lineTo(cx + headR * 0.92, eyeY + eyeR * 0.96)
                ctx.stroke()
                ctx.restore()
            } else if (skin === "ghost") {
                ctx.save()
                ctx.fillStyle = "rgba(244, 114, 182, 0.42)"
                ctx.beginPath()
                ctx.arc(leftEx - eyeR * 0.2, eyeY + eyeR * 0.95, eyeR * 0.34, 0, Math.PI * 2)
                ctx.arc(rightEx + eyeR * 0.2, eyeY + eyeR * 0.95, eyeR * 0.34, 0, Math.PI * 2)
                ctx.fill()
                ctx.restore()
            }

            const pawR = Math.max(3.2, headR * 0.28)
            const pawY = h - pawR * 0.42
            const pawLift = root.isPoked ? -pawR * 0.55 : 0
            ctx.save()
            ctx.fillStyle = bodyFill
            ctx.strokeStyle = bodyStroke
            ctx.lineWidth = 1.2
            const pawXs = [cx - headR * 0.72, cx + headR * 0.72]
            for (let p = 0; p < 2; ++p) {
                ctx.beginPath()
                ctx.arc(pawXs[p], pawY + pawLift, pawR, 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
            }
            ctx.restore()

            if (m === "hot") {
                const sx = cx + headR * 0.85
                const sy = headCy - headR * 0.45
                const sr = Math.max(2.0, headR * 0.14)
                ctx.save()
                ctx.fillStyle = "#38bdf8"
                ctx.beginPath()
                ctx.moveTo(sx, sy - sr * 1.4)
                ctx.quadraticCurveTo(sx + sr * 1.1, sy + sr * 0.3, sx, sy + sr * 1.0)
                ctx.quadraticCurveTo(sx - sr * 1.1, sy + sr * 0.3, sx, sy - sr * 1.4)
                ctx.fill()
                ctx.restore()
            } else if (m === "grumpy") {
                ctx.save()
                ctx.strokeStyle = "#ef4444"
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(leftEx - eyeR * 0.45, eyeY - eyeR * 1.15)
                ctx.lineTo(leftEx + eyeR * 0.45, eyeY - eyeR * 0.85)
                ctx.moveTo(rightEx + eyeR * 0.45, eyeY - eyeR * 1.15)
                ctx.lineTo(rightEx - eyeR * 0.45, eyeY - eyeR * 0.85)
                ctx.stroke()
                ctx.restore()
            }
        }
    }

    // ── Right Dynamic Panel (horizontal Dock only) ────────────────────────
    Item {
        visible: !root.vertical
        anchors {
            left: buddyCanvas.right
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            leftMargin: 2
            rightMargin: 2
        }

        // Mode 1: Active 20-20-20 Eye-Care Countdown Ring
        Row {
            visible: root.rightMode === "eyecare"
            anchors.centerIn: parent
            spacing: 6

            Canvas {
                id: ringCanvas
                width: Math.min(28, Math.round(root.height * 0.66))
                height: width
                anchors.verticalCenter: parent.verticalCenter
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2
                    const cy = height / 2
                    const r = Math.max(4, Math.min(cx, cy) - 3)
                    ctx.lineWidth = 2.6
                    ctx.lineCap = "round"
                    ctx.strokeStyle = Qt.alpha(root.ink, 0.18).toString()
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.stroke()

                    ctx.strokeStyle = root.breakDue ? "#10b981" : root.accentCol.toString()
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.05, root.eyeCareProgress))
                    ctx.stroke()
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    readonly property int m: Math.floor(root.remainingSec / 60)
                    readonly property int s: root.remainingSec % 60
                    text: (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
                    color: root.breakDue ? "#10b981" : root.ink
                    font { pixelSize: Math.max(10, Math.round(root.height * 0.27)); weight: Font.Bold }
                }
                Text {
                    text: root.breakDue ? (root.isZh ? "远眺!" : "Rest!") : (root.isZh ? "护眼" : "Focus")
                    color: root.subInk
                    font { pixelSize: Math.max(8, Math.round(root.height * 0.19)); weight: Font.Medium }
                }
            }
        }

        // Mode 2: Music Visualizer Bars
        Row {
            visible: root.rightMode === "music"
            anchors.centerIn: parent
            spacing: 5

            Canvas {
                id: eqCanvas
                width: Math.max(36, Math.round(root.height * 0.92))
                height: Math.round(root.height * 0.60)
                anchors.verticalCenter: parent.verticalCenter
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const n = 5
                    const gap = 3
                    const bw = Math.max(3, (width - (n - 1) * gap) / n)
                    ctx.fillStyle = root.material ? root.accentCol.toString() : root.musicColor.toString()
                    for (let i = 0; i < n; ++i) {
                        const wave = 0.28 + 0.72 * Math.abs(Math.sin(root.animPhase * (0.9 + i * 0.18) + i * 1.15))
                        const bh = Math.max(4, height * wave)
                        const bx = i * (bw + gap)
                        const by = height - bh
                        const r = bw / 2
                        ctx.beginPath()
                        ctx.moveTo(bx + r, by)
                        ctx.lineTo(bx + bw - r, by)
                        ctx.quadraticCurveTo(bx + bw, by, bx + bw, by + r)
                        ctx.lineTo(bx + bw, height - r)
                        ctx.quadraticCurveTo(bx + bw, height, bx + bw - r, height)
                        ctx.lineTo(bx + r, height)
                        ctx.quadraticCurveTo(bx, height, bx, height - r)
                        ctx.lineTo(bx, by + r)
                        ctx.quadraticCurveTo(bx, by, bx + r, by)
                        ctx.fill()
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "♫"
                color: root.ink
                opacity: 0.85
                font { pixelSize: Math.max(11, Math.round(root.height * 0.28)); weight: Font.Bold }
            }
        }

        // Mode 3: Hot CPU Sparkline + Temp
        Column {
            visible: root.rightMode === "hot"
            anchors.centerIn: parent
            width: Math.max(44, parent.width - 6)
            spacing: 1

            Canvas {
                id: pulseCanvas
                width: parent.width
                height: Math.round(root.height * 0.42)
                onWidthChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const hist = root.cpuHist
                    if (!hist || hist.length < 2) return
                    const count = Math.min(12, hist.length)
                    const slice = hist.slice(hist.length - count)
                    ctx.strokeStyle = "#f87171"
                    ctx.lineWidth = 1.8
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    for (let i = 0; i < slice.length; ++i) {
                        const v = Math.max(0, Math.min(1, Number(slice[i])))
                        const px = (i / (slice.length - 1)) * (width - 4) + 2
                        const py = height - 2 - v * (height - 4)
                        if (i === 0) ctx.moveTo(px, py)
                        else ctx.lineTo(px, py)
                    }
                    ctx.stroke()
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.tempC >= 0 ? (root.tempC + "°C") : ("CPU " + root.cpuPct + "%")
                color: "#fca5a5"
                font { pixelSize: Math.max(9, Math.round(root.height * 0.24)); weight: Font.Bold }
            }
        }

        // Mode 4: Witty Speech Bubble
        Item {
            visible: root.rightMode === "bubble"
            anchors.centerIn: parent
            width: Math.min(parent.width - 2, bubbleLabel.implicitWidth + 18)
            height: Math.min(parent.height - 6, bubbleLabel.implicitHeight + 10)

            Canvas {
                anchors { right: bubbleBox.left; rightMargin: -1; verticalCenter: bubbleBox.verticalCenter }
                width: 6; height: 8
                readonly property color fillCol: root.chipBg
                onFillColChanged: requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = fillCol.toString()
                    ctx.beginPath()
                    ctx.moveTo(width, 0)
                    ctx.lineTo(0, height / 2)
                    ctx.lineTo(width, height)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            Rectangle {
                id: bubbleBox
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: Math.max(32, parent.width - 5)
                height: parent.height
                radius: Math.min(11, height / 2)
                color: root.chipBg

                Text {
                    id: bubbleLabel
                    anchors.centerIn: parent
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.bubbleText
                    color: root.ink
                    font { pixelSize: Math.max(9, Math.round(root.height * 0.24)); weight: Font.DemiBold }
                }
            }
        }
    }
}
