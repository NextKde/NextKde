import QtQuick
import QtQuick.Effects
import QtQml.Models
import QtCore
import Qt.labs.platform as Platform
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.desktop.modules.applauncher
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.weather
import "WidgetLayout.mjs" as WidgetLayout

// iPadOS-inspired desktop widgets. Keep this in the Bottom layer so Plasma's
// desktop surface cannot cover it when plasmashell starts after KOS. Normal and
// maximised application windows remain above it, and it reserves no usable
// desktop area.
PanelWindow {
    id: root

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Bottom
    // A desktop needs shortcuts only after the user explicitly clicks it.
    // OnDemand keeps active applications' Ctrl+C/V untouched otherwise.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    // Ten square units are derived exclusively from screen width. Every
    // widget uses integer spans, giving desktop cards the intentional, large
    // iPadOS scale rather than a collection of small floating macOS tiles.
    readonly property int columns: 10
    readonly property int widgetColumns: Math.min(4, columns)
    readonly property real sideMargin: 20
    // Keep card sizing tied to the original grid metrics. The larger visual
    // insets should consume the flexible desktop-file field on the right,
    // rather than shrinking or reflowing the established widget layout.
    readonly property real layoutBaseSideMargin: 8
    readonly property real layoutBaseGap: 10
    // The standalone Bar needs its 35px strip plus breathing room. Once Bar
    // content is hosted by Dock, reclaim that strip for widgets and desktop
    // files regardless of which edge hosts the Dock.
    readonly property bool barIntegratedWithDock:
        AppearanceConfigService.barIntegratedWithDock
    readonly property real topInset: barIntegratedWithDock
        ? 24 : Math.max(56, ConfigService.barHeight + 21)
    readonly property real bottomInset: Math.max(96, AppLauncherService.dockHeight + 24)
    // A side dock reserves its own strip on the left/right edge; shift the
    // grid and the desktop file field inward so the dock never covers them.
    // AppLauncherService.dockHeight is the dock's short edge, which is
    // exactly its width when the dock is docked to a side.
    // Only "always" mode actually reserves that strip (the dock also sets a
    // non-zero exclusiveZone only then); hidden/auto modes float over content,
    // so reserving would leave an empty gap next to the collapsed bar.
    readonly property real leftInset: ConfigService.position === "left"
        && ConfigService.visibilityMode === "always"
        ? AppLauncherService.dockHeight + 24 : root.sideMargin
    readonly property real rightInset: ConfigService.position === "right"
        && ConfigService.visibilityMode === "always"
        ? AppLauncherService.dockHeight + 24 : root.sideMargin
    readonly property real gap: AppearanceTokens.widget.gap
    readonly property real cellSize: Math.max(1,
        (width - layoutBaseSideMargin * 2
            - layoutBaseGap * (columns - 1)) / columns)
    readonly property int usableRows: Math.max(0, Math.floor(
        (height - topInset - bottomInset + gap) / (cellSize + gap)))
    property int timerSeconds: 0
    property int timerDuration: 0
    property bool timerRunning: false
    property bool timerHasStarted: false
    property bool timerView: false
    // Referencing the singleton starts the shared activity recorder once the
    // desktop surface is available.
    readonly property var activityUsage: ActivityUsageService
    // File metadata is supplied by kos-data-service; this surface only
    // lays it out as a right-aligned desktop grid.
    readonly property var desktopFiles: DesktopFilesService

    function formattedTimer() {
        const hours = Math.floor(timerSeconds / 3600)
        const minutes = Math.floor((timerSeconds % 3600) / 60)
        const seconds = timerSeconds % 60
        return (hours < 10 ? "0" : "") + hours + ":"
            + (minutes < 10 ? "0" : "") + minutes + ":"
            + (seconds < 10 ? "0" : "") + seconds
    }

    function formattedTimerEndTime() {
        const end = new Date(Date.now() + timerSeconds * 1000)
        return Qt.formatTime(end, "h:mm")
    }

    function lunarDate(date) {
        try {
            return new Intl.DateTimeFormat("zh-CN-u-ca-chinese", {
                month: "long",
                day: "numeric"
            }).format(date)
        } catch (error) {
            return "农历日期"
        }
    }

    function formatMetricBytes(bytes) {
        if (!Number.isFinite(bytes) || bytes <= 0)
            return "--"
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(1) + " GB"
        return Math.round(bytes / 1048576) + " MB"
    }

    function formatDuration(seconds) {
        const total = Math.max(0, Math.round(seconds || 0))
        const hours = Math.floor(total / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        return hours > 0 ? hours + "小时" + (minutes ? minutes + "分" : "") : minutes + "分"
    }

    function addTimerMinute() {
        addTimerMinutes(1)
    }

    function addTimerMinutes(minutes) {
        timerSeconds += minutes * 60
        timerDuration += minutes * 60
    }

    function toggleTimer() {
        if (timerRunning) {
            timerRunning = false
            return
        }
        if (timerSeconds === 0) {
            timerSeconds = 60
            timerDuration = 60
        } else if (timerDuration < timerSeconds) {
            timerDuration = timerSeconds
        }
        timerRunning = true
        timerHasStarted = true
        sendTimerNotification("倒计时开始", "剩余 " + formattedTimer())
    }

    Timer {
        interval: 1000
        running: root.timerRunning
        repeat: true
        onTriggered: {
            if (root.timerSeconds > 1) {
                root.timerSeconds--
                return
            }
            root.timerSeconds = 0
            root.timerRunning = false
            root.timerHasStarted = false
            root.sendTimerNotification("倒计时结束", "计时已完成")
        }
    }

    property Component notificationProcess: Component {
        Process {}
    }

    function sendTimerNotification(summary, body) {
        const process = notificationProcess.createObject(root, {
            command: ["notify-send", "--app-name=DeskCenter", summary, body]
        })
        process.exited.connect(function() { process.destroy() })
        process.running = true
    }

    // Higher priority widgets win when a short display cannot accommodate all
    // rows. The desktop never scrolls and cards never shrink their type.
    function configuredWidget(id, priority, startColor, endColor) {
        const span = DeskCenterConfigService.spanFor(id)
        return { id: id, title: "", columns: span[0], rows: span[1],
            priority: priority, startColor: startColor, endColor: endColor,
            surface: false }
    }
    readonly property var widgetDefinitions: {
        // Make the binding depend on persisted configuration changes.
        const revision = DeskCenterConfigService.revision
        return [
            configuredWidget("clock", 100, "#536783", "#35465f"),
            configuredWidget("weather", 90, "#536b94", "#394b70"),
            configuredWidget("calendar", 80, "#fff8fa", "#f3e8ed"),
            configuredWidget("todo", 75, "#f2faf7", "#e2f1eb"),
            configuredWidget("system", 70, "#f5f8fc", "#e6edf6"),
            configuredWidget("activity", 60, "#40506a", "#29364e"),
            configuredWidget("music", 50, "#51415d", "#332a3d")
        ]
    }
    readonly property var weatherTheme: WeatherTheme.theme(WeatherService.weatherCode, WeatherService.isDay)

    function packWidgets(definitions, columnCount, rowCount) {
        return WidgetLayout.packWidgets(definitions, columnCount, rowCount)
    }

    readonly property var placements: packWidgets(widgetDefinitions, widgetColumns, usableRows)
    function placementFor(widgetId) {
        for (let i = 0; i < placements.length; i++)
            if (placements[i].id === widgetId)
                return placements[i]
        return null
    }
    function spanSize(span) { return span * cellSize + (span - 1) * gap }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Global desktop background click handler: catches clicks on any empty area of the desktop
    // (left widget columns, margins, empty spaces between widgets, and background wallpaper).
    MouseArea {
        id: globalDesktopBackgroundArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                desktopFileGrid.setSelectedPaths([])
                desktopFileGrid.contextEntry = null
                desktopFileGrid.showMenu(null,
                    Qt.point(mouse.x - desktopFileGrid.x, mouse.y - desktopFileGrid.y))
                return
            }
            desktopFileGrid.clearDesktopSelection()
        }
    }

    Repeater {
        model: root.widgetDefinitions

        delegate: DeskWidgetCard {
            id: card
            required property var modelData
            readonly property var placement: root.placementFor(modelData.id)
            visible: placement !== null
            title: modelData.title
            startColor: modelData.id === "weather" ? root.weatherTheme.primary : modelData.startColor
            endColor: modelData.id === "weather" ? root.weatherTheme.secondary : modelData.endColor
            showSurface: modelData.surface
            x: root.leftInset + (placement?.column ?? 0) * (root.cellSize + root.gap)
            y: root.topInset + (placement?.row ?? 0) * (root.cellSize + root.gap)
            width: root.spanSize(placement?.columns ?? 1)
            height: root.spanSize(placement?.rows ?? 1)
            Behavior on x { NumberAnimation { duration: AppearanceTokens.motion.normalDuration; easing.type: AppearanceTokens.motion.standardEasing } }
            Behavior on y { NumberAnimation { duration: AppearanceTokens.motion.normalDuration; easing.type: AppearanceTokens.motion.standardEasing } }
            Behavior on width { NumberAnimation { duration: AppearanceTokens.motion.normalDuration; easing.type: AppearanceTokens.motion.standardEasing } }
            Behavior on height { NumberAnimation { duration: AppearanceTokens.motion.normalDuration; easing.type: AppearanceTokens.motion.standardEasing } }

            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: DeskCenterConfigService.cycleSize(card.modelData.id)
            }

            HoverHandler { id: widgetHover }

            Rectangle {
                z: 50
                visible: widgetHover.hovered
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                width: sizeLabel.implicitWidth + 14
                height: 24
                radius: 12
                color: Qt.rgba(0, 0, 0, 0.52)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)
                Text {
                    id: sizeLabel
                    anchors.centerIn: parent
                    text: ({ small: "小", medium: "中", large: "大" })[
                        DeskCenterConfigService.sizeFor(card.modelData.id)] + " · 右键切换"
                    color: "white"
                    font { pixelSize: 9; weight: Font.DemiBold }
                }
            }

            // Instantiate only this card's content. `visible: false` keeps a
            // QML tree alive, so the old delegate built every widget for every
            // card even though only one could be shown.
            Item {
                id: widgetContentLayer
                anchors.fill: parent
	                // Tint is applied by each widget to its semantic content.
	                // A single post-process layer flattened that tonal styling
	                // back into raw tint on some renderers.
	                layer.enabled: IconAppearanceService.mode === "grayscale"
	                layer.effect: MultiEffect {
	                    saturation: 0.0
	                    colorization: 0.0
                }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "clock"
                sourceComponent: Component {
	                    Item {
	                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"
                clip: true

                Item {
                    id: clockPage
                    width: parent.width
                    height: parent.height
                    y: root.timerView ? -height : 0
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                Canvas {
                    id: analogClock
                    anchors.fill: parent
                    anchors.margins: 14
                    onPaint: {
                        const ctx = getContext("2d")
                        const size = Math.min(width, height)
                        const center = size / 2
                        const radius = Math.max(0, size / 2 - 3)
                        if (radius <= 0)
                            return
                        const date = clock.date
                        const glassMode = IconAppearanceService.mode !== "color"
                        ctx.reset()
                        ctx.translate((width - size) / 2 + center, (height - size) / 2 + center)
                        // In the shared glass modes the card material is the
                        // face: do not paint a second opaque white disc.
                        if (!glassMode) {
                            ctx.fillStyle = "#fafafa"
                            ctx.beginPath(); ctx.arc(0, 0, radius, 0, Math.PI * 2); ctx.fill()
                        }
	                        ctx.strokeStyle = glassMode ? IconAppearanceService.glassContentColor(0.42).toString() : "#dedede"
                        ctx.lineWidth = 1
                        ctx.beginPath(); ctx.arc(0, 0, radius, 0, Math.PI * 2); ctx.stroke()
	                        ctx.strokeStyle = glassMode ? IconAppearanceService.glassContentColor().toString() : "#171717"
                        ctx.lineCap = "round"
                        for (let mark = 0; mark < 12; mark++) {
                            const angle = mark * Math.PI / 6
                            ctx.lineWidth = mark % 3 === 0 ? 1.8 : 0.8
                            ctx.beginPath()
                            ctx.moveTo(Math.sin(angle) * (radius - 4), -Math.cos(angle) * (radius - 4))
                            ctx.lineTo(Math.sin(angle) * (radius - (mark % 3 === 0 ? 10 : 7)), -Math.cos(angle) * (radius - (mark % 3 === 0 ? 10 : 7)))
                            ctx.stroke()
                        }
                        // Full hour numerals make the small analogue clock
                        // readable at a glance, rather than relying on ticks
                        // alone. Their radius leaves a clear channel for the
                        // hands in this one-cell tile.
	                        ctx.fillStyle = glassMode ? IconAppearanceService.glassContentColor().toString() : "#242126"
                        ctx.font = "bold " + Math.max(7, Math.round(radius * 0.18)) + "px sans-serif"
                        ctx.textAlign = "center"
                        ctx.textBaseline = "middle"
                        for (let number = 1; number <= 12; number++) {
                            const angle = number * Math.PI / 6
                            const numberRadius = radius * 0.68
                            ctx.fillText(String(number),
                                Math.sin(angle) * numberRadius,
                                -Math.cos(angle) * numberRadius)
                        }
                        const hour = (date.getHours() % 12 + date.getMinutes() / 60) * Math.PI / 6
                        const minute = date.getMinutes() * Math.PI / 30
                        const second = date.getSeconds() * Math.PI / 30
                        ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(hour) * radius * 0.48, -Math.cos(hour) * radius * 0.48); ctx.stroke()
                        ctx.lineWidth = 1.8; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(minute) * radius * 0.70, -Math.cos(minute) * radius * 0.70); ctx.stroke()
	                        ctx.strokeStyle = glassMode ? IconAppearanceService.glassContentColor().toString() : "#ee7659"; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(second) * radius * 0.76, -Math.cos(second) * radius * 0.76); ctx.stroke()
	                        ctx.fillStyle = glassMode ? IconAppearanceService.glassContentColor().toString() : "#ee7659"; ctx.beginPath(); ctx.arc(0, 0, 2.2, 0, Math.PI * 2); ctx.fill()
                    }
                    Connections { target: clock; function onDateChanged() { analogClock.requestPaint() } }
	                    Connections {
	                        target: IconAppearanceService
	                        function onModeChanged() { analogClock.requestPaint() }
	                        function onTintColorChanged() { analogClock.requestPaint() }
                    }
                }

	                Rectangle {
                    id: timerButton
                    width: 21
                    height: 21
                    radius: width / 2
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 12 }
	                    color: "transparent"
                    border.width: 0
                    Image {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1
                        width: 17
                        height: 17
                        source: "../../assets/countdown.svg"
                        sourceSize.width: 26
                        sourceSize.height: 26
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    MouseArea {
                        id: timerPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.timerView = true
                    }
                }
                }

                Item {
                    id: timerPage
                    width: parent.width
                    height: parent.height
                    y: root.timerView ? 0 : height
                    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Item {
                        id: timerDial
                        width: Math.min(parent.width - 28, parent.height - 45)
                        height: width
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 5 }
                        Canvas {
                            id: timerProgress
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d")
                                const center = width / 2
                                const radius = Math.max(0, center - 7)
                                if (radius <= 0)
                                    return
                                const amount = root.timerDuration > 0
                                    ? Math.max(0, Math.min(1, root.timerSeconds / root.timerDuration)) : 1
                                ctx.reset()
                                ctx.lineWidth = Math.max(8, width * 0.08)
                                ctx.lineCap = "round"
                                ctx.strokeStyle = "rgba(255, 255, 255, 0.10)"
                                ctx.beginPath(); ctx.arc(center, center, radius, -Math.PI / 2, Math.PI * 1.5); ctx.stroke()
                                if (amount > 0) {
	                                ctx.strokeStyle = timerPage.parent.glassMode ? "#ffffff" : "#ffa515"
                                    ctx.beginPath(); ctx.arc(center, center, radius, -Math.PI / 2,
                                        -Math.PI / 2 + Math.PI * 2 * amount); ctx.stroke()
                                }
                            }
	                            Connections {
	                                target: root
                                function onTimerSecondsChanged() { timerProgress.requestPaint() }
                                function onTimerDurationChanged() { timerProgress.requestPaint() }
	                            }
	                            Connections {
	                                target: IconAppearanceService
	                                function onModeChanged() { timerProgress.requestPaint() }
	                                function onTintColorChanged() { timerProgress.requestPaint() }
	                            }
                            Component.onCompleted: requestPaint()
                        }
                        Text {
                            id: timerTimeText
                            anchors.centerIn: parent
                            text: root.formattedTimer()
                            color: "white"
                            font { family: "SF Pro Display"; pixelSize: Math.min(16, timerDial.width * 0.15); weight: Font.Medium }
                        }
                    }
                    Row {
                        visible: root.timerSeconds > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: timerDial.y + timerTimeText.y - height - 2
                        spacing: 5
                        Canvas {
                            width: 14
                            height: 16
                            onPaint: {
                                const ctx = getContext("2d")
	                                ctx.reset(); ctx.strokeStyle = timerPage.parent.glassMode ? "#ffffff" : "#ffb028"; ctx.lineWidth = 1.3; ctx.lineCap = "round"
                                ctx.beginPath(); ctx.moveTo(3, 10); ctx.quadraticCurveTo(4, 8.7, 4, 6.4)
                                ctx.quadraticCurveTo(4, 3.8, 7, 3.8); ctx.quadraticCurveTo(10, 3.8, 10, 6.4)
                                ctx.quadraticCurveTo(10, 8.7, 11, 10); ctx.lineTo(3, 10); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(5.3, 12); ctx.lineTo(8.7, 12); ctx.stroke()
                            }
                        }
                        Text {
                            text: "结束于 " + root.formattedTimerEndTime()
                            color: Qt.rgba(1, 1, 1, 0.72)
                            font { pixelSize: 10; weight: Font.DemiBold }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: timerDial.y + timerTimeText.y + timerTimeText.height + 2
                        spacing: 5
                        Repeater {
                            model: [1, 5, 15]
                            delegate: Rectangle {
                                required property int modelData
                                width: modelData === 15 ? 30 : 25
                                height: 17
                                radius: height / 2
	                                color: parent.parent.parent.glassMode
	                                    ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(255 / 255, 165 / 255, 21 / 255, 0.16)
                                border.width: 1
	                                border.color: parent.parent.parent.glassMode
	                                    ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(255 / 255, 165 / 255, 21 / 255, 0.72)
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + "分"
	                                    color: parent.parent.parent.parent.parent.glassMode ? "white" : "#ffb028"
                                    font { pixelSize: 8; weight: Font.DemiBold }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.addTimerMinutes(modelData)
                                }
                            }
                        }
                    }
                    Row {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
                        spacing: 22
                        Repeater {
                            model: ["取消", root.timerRunning ? "暂停"
                                : (root.timerHasStarted ? "继续" : "开始")]
                            delegate: Rectangle {
                                required property var modelData
                                width: 38
                                height: 21
                                radius: height / 2
	                                color: modelData !== "取消"
	                                    ? (parent.parent.parent.glassMode ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(255 / 255, 165 / 255, 21 / 255, 0.24))
                                    : Qt.rgba(1, 1, 1, 0.13)
                                border.width: 1
	                                border.color: modelData !== "取消"
	                                    ? (parent.parent.parent.glassMode ? "white" : "#ffa515") : Qt.rgba(1, 1, 1, 0.22)
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
	                                    color: modelData !== "取消"
	                                        ? (parent.parent.parent.parent.glassMode ? "white" : "#ffb028") : "white"
                                    font { pixelSize: 9; weight: Font.DemiBold }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData === "取消") {
                                            root.timerRunning = false
                                            root.timerSeconds = 0
                                            root.timerDuration = 0
                                            root.timerHasStarted = false
                                        } else {
                                            root.toggleTimer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        anchors { left: parent.left; top: parent.top; leftMargin: 10; topMargin: 7 }
                        text: "×"
                        color: Qt.rgba(1, 1, 1, 0.74)
                        font { pixelSize: 18; weight: Font.Light }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.timerView = false
                        }
                    }
                }
            }
            }
                }
            }

            Loader {
                anchors.fill: parent
	                active: card.modelData.id === "date"
	                sourceComponent: Component {
	                    Item {
	                anchors.fill: parent
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 27
                    color: "#ff626a"
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 5 }
                    text: Qt.formatDateTime(clock.date, "yyyy年M月")
                    color: "white"
                    font { pixelSize: 11; weight: Font.Bold }
                }
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: 10; text: Qt.formatDateTime(clock.date, "d日 dddd"); color: "#111118"; font { pixelSize: 24; weight: Font.Bold } }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                    text: Qt.formatDateTime(clock.date, "dddd")
                    color: "#3c3c43"
                    font.pixelSize: 9
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
	                active: card.modelData.id === "weather"
	                sourceComponent: Component {
	                    Item {
	                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"

                // The card-level gradient establishes the theme, while this
                // explicit content-layer wash keeps that transition visible
                // beneath the weather artwork on every compositor.
                Rectangle {
                    anchors.fill: parent
                    radius: 26
	                    color: "transparent"
	                    visible: !parent.glassMode
	                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.weatherTheme.primary }
                        GradientStop { position: 0.58; color: root.weatherTheme.secondary }
                        GradientStop { position: 1; color: Qt.darker(root.weatherTheme.secondary, 1.16) }
                    }
                }

                // Keep the weather artwork static. Continuous transforms on
                // this always-visible background card force redraws even when
                // the desktop is otherwise idle.
                Item {
                    id: deskWeatherMotion
                    anchors.fill: parent
                    clip: true
                    opacity: 0.34

                    Item {
                        id: deskSunLayer
                        visible: WeatherTheme.category(WeatherService.weatherCode) === "clear" && WeatherService.isDay
                        width: 70
                        height: 70
                        anchors { right: parent.right; top: parent.top; rightMargin: 20; topMargin: 5 }
                        Repeater {
                            model: 8
                            delegate: Rectangle {
                                required property int index
                                width: 2
                                height: 12
                                radius: 1
	                                color: deskWeatherMotion.parent.glassMode ? IconAppearanceService.glassContentColor() : "#ffe36a"
                                x: deskSunLayer.width / 2 - width / 2
                                y: 2
                                transform: Rotation { origin.x: 1; origin.y: 33; angle: index * 45 }
                            }
                        }
	                        Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 14; color: deskWeatherMotion.parent.glassMode ? IconAppearanceService.glassContentColor() : "#ffe36a" }
                    }

                    Item {
                        id: deskCloudLayer
                        anchors.fill: parent
                        visible: WeatherTheme.category(WeatherService.weatherCode) === "partlyCloudy"
                            || WeatherTheme.category(WeatherService.weatherCode) === "overcast"
                        Image {
                            id: deskCloudBack
                            width: parent.width * 0.34
                            height: parent.height * 0.36
                            y: 2
                            x: -width
                            source: "../../assets/weather-cloud.svg"
                            fillMode: Image.PreserveAspectFit
	                            smooth: true
	                            layer.enabled: IconAppearanceService.mode !== "color"
	                            layer.effect: MultiEffect {
	                                saturation: IconAppearanceService.mode === "grayscale" ? 0 : 1
	                                colorization: IconAppearanceService.mode === "tint" ? 1 : 0
	                                colorizationColor: IconAppearanceService.styledSymbolicColor()
	                            }
                        }
                        Image {
                            id: deskCloudFront
                            width: parent.width * 0.30
                            height: parent.height * 0.29
                            y: parent.height * 0.18
                            x: parent.width
                            source: "../../assets/weather-cloud-wide.svg"
                            fillMode: Image.PreserveAspectFit
	                            smooth: true
	                            layer.enabled: IconAppearanceService.mode !== "color"
	                            layer.effect: MultiEffect {
	                                saturation: IconAppearanceService.mode === "grayscale" ? 0 : 1
	                                colorization: IconAppearanceService.mode === "tint" ? 1 : 0
	                                colorizationColor: IconAppearanceService.styledSymbolicColor()
	                            }
                        }
                    }

                    Item {
                        id: deskRainLayer
                        anchors.fill: parent
                        visible: WeatherTheme.isRain(WeatherService.weatherCode)
                            || WeatherTheme.isStorm(WeatherService.weatherCode)
                        Repeater {
                            model: 9
                            delegate: Rectangle {
                                required property int index
                                width: 1
                                height: 12
                                radius: 1
	                                color: deskWeatherMotion.parent.glassMode ? IconAppearanceService.glassContentColor() : "#d9f1ff"
                                x: deskRainLayer.width * (index + 0.4) / 9
                                rotation: -13
                            }
                        }
                    }

                    Item {
                        id: deskFogLayer
                        anchors.fill: parent
                        visible: WeatherTheme.isFog(WeatherService.weatherCode)
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: deskFogLayer.width * (0.54 + index * 0.09)
                                height: 10
                                radius: height / 2
                                x: -width * 0.15 + index * 24
                                y: 16 + index * 26
                                color: Qt.rgba(1, 1, 1, 0.20 - index * 0.035)
                            }
                        }
                    }

                    Item {
                        id: deskSnowLayer
                        anchors.fill: parent
                        visible: WeatherTheme.isSnow(WeatherService.weatherCode)
                        Repeater {
                            model: 14
                            delegate: Rectangle {
                                required property int index
                                width: index % 3 === 0 ? 4 : 2
                                height: width
                                radius: width / 2
                                x: deskSnowLayer.width * ((index * 37) % 100) / 100
                                y: 8 + (index * 19) % Math.max(1, deskSnowLayer.height - 12)
                                color: Qt.rgba(1, 1, 1, 0.62)
                            }
                        }
                    }

                    Text {
                        anchors { right: parent.right; top: parent.top; rightMargin: 26; topMargin: 8 }
                        visible: WeatherTheme.isStorm(WeatherService.weatherCode)
                        text: "ϟ"
	                        color: parent.glassMode ? IconAppearanceService.glassContentColor(0.68) : "#e0ccff"
                        opacity: 0.68
                        font { family: "SF Pro Display"; pixelSize: 42; weight: Font.DemiBold }
                    }
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 12 }
                    text: WeatherService.cityName
	                    color: parent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                    font { pixelSize: 15; weight: Font.DemiBold }
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 15; topMargin: 29 }
                    text: WeatherService.temperature
	                    color: parent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                    font { family: "SF Pro Display"; pixelSize: Math.min(42, parent.height * 0.32); weight: Font.Normal }
                }
                Text {
                    anchors { right: parent.right; top: parent.top; rightMargin: 18; topMargin: 14 }
                    text: WeatherService.conditionSymbol(WeatherService.weatherCode, WeatherService.isDay)
	                    color: parent.glassMode ? IconAppearanceService.glassContentColor() : root.weatherTheme.accent
                    font.pixelSize: Math.min(34, parent.height * 0.26)
                }
                Text {
                    anchors { right: parent.right; top: parent.top; rightMargin: 16; topMargin: 48 }
                    text: WeatherService.conditionText(WeatherService.weatherCode)
	                    color: parent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                    font { pixelSize: 15; weight: Font.DemiBold }
                }
                Text {
                    anchors { right: parent.right; bottom: weeklyForecast.top; rightMargin: 16; bottomMargin: 3 }
                    text: WeatherService.forecastDays.length > 0
                        ? "最高 " + WeatherService.forecastDays[0].high + "°  最低 "
                            + WeatherService.forecastDays[0].low + "°" : "正在更新预报"
	                    color: parent.glassMode ? IconAppearanceService.glassContentColor(0.74) : Qt.rgba(1, 1, 1, 0.74)
                    font.pixelSize: 11
                }
                Item {
                    id: weeklyForecast
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 10; rightMargin: 10; bottomMargin: 8 }
                    height: Math.min(62, parent.height * 0.46)
                    Repeater {
                        model: WeatherService.forecastDays
                        delegate: Item {
                            required property var modelData
                            required property int index
                            x: index * weeklyForecast.width / 7
                            width: weeklyForecast.width / 7
                            height: weeklyForecast.height
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                                text: WeatherService.forecastLabel(modelData.date, index)
	                                color: weeklyForecast.parent.glassMode ? IconAppearanceService.glassContentColor(0.72) : Qt.rgba(1, 1, 1, 0.72)
                                font { pixelSize: 10; weight: Font.DemiBold }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                                text: WeatherService.conditionSymbol(modelData.code, true)
	                                color: weeklyForecast.parent.glassMode ? IconAppearanceService.glassContentColor() : root.weatherTheme.accent
                                font.pixelSize: 22
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                                text: modelData.high + "°/" + modelData.low + "°"
	                                color: weeklyForecast.parent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                                font { pixelSize: 10; weight: Font.DemiBold }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: WeatherService.forecastDays.length === 0
                        text: WeatherService.loading ? "正在获取 7 日预报…" : "暂无 7 日预报"
	                        color: parent.glassMode ? IconAppearanceService.glassContentColor(0.65) : Qt.rgba(1, 1, 1, 0.65)
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const locationId = String(WeatherService.location?.id ?? "")
                        AppActionService.launchById("kos-weather",
                            locationId ? ["--location", locationId] : [])
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "status"
                sourceComponent: Component {
                    Item {
                anchors.fill: parent
                Row {
                    anchors.centerIn: parent
                    spacing: 18
                    Repeater {
                        model: [
                            { label: "音量", value: Math.round(ControlCenterService.volumePercent) + "%", amount: ControlCenterService.volumePercent / 100 },
                            { label: "湿度", value: WeatherService.humidity, amount: Math.min(1, Number(WeatherService.humidity.replace("%", "")) / 100) },
                            { label: "天气", value: WeatherService.temperature, amount: 0.72 }
                        ]
                        delegate: Item {
                            required property var modelData
                            width: 54; height: 74
                            Canvas {
                                id: ring
                                width: 48; height: 48
                                anchors.horizontalCenter: parent.horizontalCenter
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset(); ctx.lineWidth = 6; ctx.lineCap = "round"
                                    ctx.strokeStyle = "#f7f4f7"; ctx.beginPath(); ctx.arc(24, 24, 18, -Math.PI / 2, Math.PI * 1.5); ctx.stroke()
                                    ctx.strokeStyle = "#08be72"; ctx.beginPath(); ctx.arc(24, 24, 18, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * modelData.amount); ctx.stroke()
                                }
                                Component.onCompleted: requestPaint()
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; top: ring.bottom; topMargin: 2 }
                                text: modelData.value
                                color: "#36313a"
                                font { pixelSize: 10; weight: Font.Bold }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                                text: modelData.label
                                color: "#5e5660"
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "photo"
                sourceComponent: Component {
                    Item {
                anchors.fill: parent
                Image { anchors.fill: parent; source: "../../assets/defaultCover.png"; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 28
                    color: Qt.rgba(0, 0, 0, 0.34)
                }
                Text {
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 12; bottomMargin: 8 }
                    text: "精选画面"
                    color: "white"
                    font { pixelSize: 11; weight: Font.DemiBold }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "system"
                sourceComponent: Component {
                    Item {
	                id: systemContent
	                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"
                // The kos-data-service snapshot drives this card through
                // the shared MetricsService, so the rings and trends read the
                // exact values the Bar's thermal indicator shows.
                readonly property var metrics: MetricsService
                function historyValues(name) {
                    const live = name === "memory" ? MetricsService.memoryHistoryValues
                        : name === "cpu" ? MetricsService.cpuHistoryValues
                        : MetricsService.frequencyHistoryValues
                    return live
                }
                // The system card is a 4:6 split: the Activity rings use the
                // left 40%, while hover details have a calm 60% reading area.
                Item {
                    id: activityRings
                    anchors { left: parent.left; leftMargin: parent.width * 0.02; top: parent.top; topMargin: parent.height * 0.035 }
                    width: Math.min(parent.width * 0.36, parent.height * 0.7)
                    height: width
                    property int hoveredMetric: -1
                    readonly property real cpuValue: systemContent.metrics.cpuUsage ?? 0
                    readonly property real memoryValue: systemContent.metrics.memoryTotalBytes > 0
                        ? systemContent.metrics.memoryUsedBytes / systemContent.metrics.memoryTotalBytes : 0
                    readonly property real storageValue: systemContent.metrics.diskTotalBytes > 0
                        ? systemContent.metrics.diskUsedBytes / systemContent.metrics.diskTotalBytes : 0
                    readonly property var labels: ["CPU", "内存", "存储"]
                    readonly property var icons: ["", "󰍛", "󰋊"]
                    readonly property var values: [cpuValue, memoryValue, storageValue]
	                    readonly property var colors: systemContent.glassMode
	                        ? [IconAppearanceService.glassContentColor().toString(),
	                           IconAppearanceService.glassContentColor().toString(),
	                           IconAppearanceService.glassContentColor().toString()]
	                        : ["#ff375f", "#30d158", "#64d2ff"]

                    function detailFor(metric) {
                        if (metric === 0)
                            return "实时使用率"
                        if (metric === 1)
                            return root.formatMetricBytes(systemContent.metrics.memoryUsedBytes)
                                + " / " + root.formatMetricBytes(systemContent.metrics.memoryTotalBytes)
                        return root.formatMetricBytes(systemContent.metrics.diskUsedBytes)
                            + " / " + root.formatMetricBytes(systemContent.metrics.diskTotalBytes)
                    }

                    Canvas {
                        id: activityCanvas
                        anchors.fill: parent

                        function drawRing(ctx, radius, value, color) {
                            const center = width / 2
                            const amount = Math.max(0, Math.min(1, value))
                            const start = -Math.PI / 2
                            ctx.lineWidth = Math.max(5, width * 0.065)
                            ctx.lineCap = "round"
	                            ctx.strokeStyle = systemContent.glassMode
	                                ? IconAppearanceService.glassContentColor(0.25).toString()
	                                : Qt.rgba(0.19, 0.17, 0.2, 0.12)
                            ctx.beginPath()
                            ctx.arc(center, center, radius, 0, Math.PI * 2)
                            ctx.stroke()
                            ctx.strokeStyle = color
                            ctx.beginPath()
                            ctx.arc(center, center, radius, start, start + Math.PI * 2 * amount)
                            ctx.stroke()
                        }

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            drawRing(ctx, width * 0.39, activityRings.cpuValue, activityRings.colors[0])
                            drawRing(ctx, width * 0.285, activityRings.memoryValue, activityRings.colors[1])
                            drawRing(ctx, width * 0.18, activityRings.storageValue, activityRings.colors[2])
                        }
                        Component.onCompleted: requestPaint()
	                        Connections {
	                            target: activityRings
                            function onCpuValueChanged() { activityCanvas.requestPaint() }
                            function onMemoryValueChanged() { activityCanvas.requestPaint() }
                            function onStorageValueChanged() { activityCanvas.requestPaint() }
	                        }
	                        Connections {
	                            target: IconAppearanceService
	                            function onModeChanged() { activityCanvas.requestPaint() }
	                            function onTintColorChanged() { activityCanvas.requestPaint() }
	                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: activityRings.hoveredMetric >= 0
                        spacing: -2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: activityRings.hoveredMetric >= 0
                                ? (activityRings.icons[activityRings.hoveredMetric] ?? "")
                                : ""
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#7d7782"
                            font { family: "LXGW WenKai Mono Nerd Font"; pixelSize: Math.max(10, activityRings.width * 0.1) }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: activityRings.labels[activityRings.hoveredMetric] + " "
                                + Math.round(activityRings.values[activityRings.hoveredMetric] * 100) + "%"
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#7d7782"
                            font { family: "SF Pro Display"; pixelSize: Math.max(8, activityRings.width * 0.075); weight: Font.DemiBold }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: activityRings.hoveredMetric = 0
                        onPositionChanged: function(mouse) {
                            const dx = mouse.x - width / 2
                            const dy = mouse.y - height / 2
                            const distance = Math.sqrt(dx * dx + dy * dy) / width
                            if (distance >= 0.335)
                                activityRings.hoveredMetric = 0
                            else if (distance >= 0.23)
                                activityRings.hoveredMetric = 1
                            else
                                activityRings.hoveredMetric = 2
                        }
                        onExited: activityRings.hoveredMetric = -1
                    }
                }

                // The lower two tenths of the left 4/10 column reuse the
                // service snapshot's temperatures; no second sensor poll.
                Item {
                    id: temperatureSummary
                    anchors { left: parent.left; leftMargin: parent.width * 0.02; bottom: parent.bottom; bottomMargin: parent.height * 0.045 }
                    width: parent.width * 0.36
                    height: parent.height * 0.17
                    readonly property real currentC: Number(
                        systemContent.metrics.currentMilliC ?? -1) / 1000
                    readonly property real maximum5MinuteC: Number(
                        systemContent.metrics.maximum5MinuteMilliC ?? -1) / 1000
                    readonly property bool available: currentC >= 0
                        && maximum5MinuteC >= 0

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.max(4, temperatureSummary.width * 0.04)
                        Text {
                            text: ""
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#7d7782"
                            font { family: "LXGW WenKai Mono Nerd Font"; pixelSize: Math.max(12, temperatureSummary.height * 0.54) }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            spacing: -1
                            Text {
                                text: temperatureSummary.available
                                    ? Math.round(temperatureSummary.currentC) + "°" : "--"
	                                color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#7d7782"
                                font { family: "SF Pro Display"; pixelSize: Math.max(10, temperatureSummary.height * 0.42); weight: Font.DemiBold }
                            }
                            Text {
                                text: "当前"
	                                color: systemContent.glassMode ? IconAppearanceService.glassContentColor(0.72) : Qt.rgba(0.49, 0.47, 0.51, 0.76)
                                font.pixelSize: Math.max(8, temperatureSummary.height * 0.25)
                            }
                        }
                        Rectangle {
                            width: 1
                            height: temperatureSummary.height * 0.56
	                            color: systemContent.glassMode ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(0.19, 0.17, 0.2, 0.12)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            spacing: -1
                            Text {
                                text: temperatureSummary.available
                                    ? Math.round(temperatureSummary.maximum5MinuteC) + "°" : "--"
	                                color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#7d7782"
                                font { family: "SF Pro Display"; pixelSize: Math.max(10, temperatureSummary.height * 0.42); weight: Font.DemiBold }
                            }
                            Text {
                                text: "最高"
	                                color: systemContent.glassMode ? IconAppearanceService.glassContentColor(0.72) : Qt.rgba(0.49, 0.47, 0.51, 0.76)
                                font.pixelSize: Math.max(8, temperatureSummary.height * 0.25)
                            }
                        }
                    }
                }

                Column {
                    anchors { left: parent.left; right: parent.right; leftMargin: parent.width * 0.47; rightMargin: parent.width * 0.07; verticalCenter: parent.verticalCenter }
                    height: parent.height * 0.76
                    spacing: Math.max(2, height * 0.035)

                    Item {
                        width: parent.width
                        height: (parent.height - parent.spacing * 2) / 3
                        Text {
                            id: memoryTrendLabel
                            anchors { left: parent.left; top: parent.top }
                            text: "内存  " + Math.round(activityRings.memoryValue * 100) + "%"
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : activityRings.hoveredMetric === 1
                                ? Qt.rgba(0.12, 0.50, 0.31, 0.84) : Qt.rgba(0.30, 0.29, 0.33, 0.78)
                            font { pixelSize: Math.max(8, systemContent.height * 0.06); weight: Font.DemiBold }
                        }
                        UsageSparkline {
                            anchors { left: parent.left; right: parent.right; top: memoryTrendLabel.bottom; topMargin: 1; bottom: parent.bottom }
                            values: systemContent.historyValues("memory")
	                            lineColor: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#30d158"
                            adaptiveRange: true
                            maxPoints: 36
                            smoothingWindow: 5
                        }
                    }

                    Item {
                        width: parent.width
                        height: (parent.height - parent.spacing * 2) / 3
                        Text {
                            id: cpuTrendLabel
                            anchors { left: parent.left; top: parent.top }
                            text: "CPU  " + Math.round(activityRings.cpuValue * 100) + "%"
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : activityRings.hoveredMetric === 0
                                ? Qt.rgba(0.76, 0.14, 0.23, 0.84) : Qt.rgba(0.30, 0.29, 0.33, 0.78)
                            font { pixelSize: Math.max(8, systemContent.height * 0.06); weight: Font.DemiBold }
                        }
                        UsageSparkline {
                            anchors { left: parent.left; right: parent.right; top: cpuTrendLabel.bottom; topMargin: 1; bottom: parent.bottom }
                            values: systemContent.historyValues("cpu")
	                            lineColor: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#ff375f"
                            maxPoints: 36
                            smoothingWindow: 5
                        }
                    }

                    Item {
                        width: parent.width
                        height: (parent.height - parent.spacing * 2) / 3
                        Text {
                            id: frequencyTrendLabel
                            anchors { left: parent.left; top: parent.top }
                            text: "平均频率  " + Math.round(systemContent.metrics.cpuFrequencyMhz ?? 0) + " MHz"
	                            color: systemContent.glassMode ? IconAppearanceService.glassContentColor() : Qt.rgba(0.30, 0.29, 0.33, 0.78)
                            font { pixelSize: Math.max(8, systemContent.height * 0.06); weight: Font.DemiBold }
                        }
                        UsageSparkline {
                            anchors { left: parent.left; right: parent.right; top: frequencyTrendLabel.bottom; topMargin: 1; bottom: parent.bottom }
                            values: systemContent.historyValues("frequency")
	                            lineColor: systemContent.glassMode ? IconAppearanceService.glassContentColor() : "#64d2ff"
                            adaptiveRange: true
                            maxPoints: 36
                            smoothingWindow: 5
                        }
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "activity"
                sourceComponent: Component {
                    Item {
                id: activityContent
                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"

                Item {
                    id: activityBody
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 15; rightMargin: 15; topMargin: 15; bottomMargin: 15 }
                    clip: true
                    readonly property real paneGap: 20

                    Item {
                        id: activityLeftPane
                        x: 0
                        y: 0
                        width: (activityBody.width - activityBody.paneGap) / 2
                        height: activityBody.height

                        Item {
                            id: activityUptimeHeader
                            x: 0
                            y: 0
                            width: activityLeftPane.width
                            height: activityLeftPane.height * 0.3
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: uptimeHeatmap.hoveredDay
                                    ? uptimeHeatmap.hoveredDay.key + " · 开机时长："
                                        + root.formatDuration(uptimeHeatmap.hoveredDay.seconds)
                                    : "已开机：" + root.formatDuration(
                                        root.activityUsage.uptimeByDay[root.activityUsage.dayKey(Date.now())] ?? 0)
	                                        color: activityContent.glassMode ? IconAppearanceService.glassContentColor(0.86) : Qt.rgba(1, 1, 1, 0.86)
                                font { family: "SF Pro Display"; pixelSize: 14; weight: Font.DemiBold }
                            }
                        }
                        Item {
                            id: uptimeHeatmap
                            x: 0
                            y: activityUptimeHeader.height
                            width: activityLeftPane.width
                            height: activityLeftPane.height - y
                            property var hoveredDay: null
                            Grid {
                                x: 0
                                y: 0
                                width: uptimeHeatmap.width
                                columns: 10
                                rowSpacing: 3
                                columnSpacing: 3
                                Repeater {
                                    model: root.activityUsage.recentUptimeDays(60)
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: Math.max(4, (uptimeHeatmap.width - 27) / 10)
                                        height: width
                                        radius: 2
                                        readonly property real level: Math.min(1, modelData.seconds / (8 * 3600))
	                                        color: level <= 0 ? Qt.rgba(1, 1, 1, 0.08)
	                                            : (activityContent.glassMode
	                                                ? Qt.rgba(1, 1, 1, 0.22 + level * 0.72)
	                                                : Qt.rgba(0.33, 0.84, 0.58, 0.22 + level * 0.72))
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onEntered: uptimeHeatmap.hoveredDay = modelData
                                            onExited: uptimeHeatmap.hoveredDay = null
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: activityRightPane
                        x: activityLeftPane.width + activityBody.paneGap
                        y: 0
                        width: activityLeftPane.width
                        height: activityBody.height
                        readonly property var entries: root.activityUsage.todayApps().slice(0, 8)

                        Column {
                            id: appUsageList
                            width: activityRightPane.width
                            anchors.verticalCenter: activityRightPane.verticalCenter
                            spacing: 2
                            Repeater {
                                model: activityRightPane.entries
                                delegate: Item {
                                    id: appUsageRow
                                    required property var modelData
                                    width: activityRightPane.width
                                    height: 16
                                    IconImage {
                                        id: appUsageIcon
                                        width: 12
                                        height: 12
                                        source: modelData.icon || ""
                                        smooth: true
	                                        asynchronous: true
	                                        anchors { left: appUsageRow.left; verticalCenter: appUsageRow.verticalCenter }
	                                        layer.enabled: IconAppearanceService.mode !== "color"
	                                        layer.effect: MultiEffect {
	                                            saturation: 0
	                                            colorization: 1
	                                            colorizationColor: IconAppearanceService.glassContentColor()
	                                        }
                                    }
                                    Text {
                                        id: appDurationText
                                        anchors { right: appUsageRow.right; verticalCenter: appUsageRow.verticalCenter }
                                        text: root.formatDuration(modelData.seconds)
	                                        color: activityContent.glassMode ? IconAppearanceService.glassContentColor(0.46) : Qt.rgba(1, 1, 1, 0.46)
                                        font { family: "SF Pro Display"; pixelSize: 9 }
                                    }
                                    Text {
                                        anchors { left: appUsageIcon.right; right: appDurationText.left; verticalCenter: appUsageRow.verticalCenter; leftMargin: 6; rightMargin: 6 }
                                        text: modelData.name || modelData.id
                                        elide: Text.ElideRight
	                                        color: activityContent.glassMode ? IconAppearanceService.glassContentColor(0.78) : Qt.rgba(1, 1, 1, 0.78)
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "notes"
                sourceComponent: Component {
                    Item {
                anchors.fill: parent
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 27
                    color: "#f5c400"
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 12; topMargin: 7 }
                    text: "备忘录"
                    color: "white"
                    font { pixelSize: 11; weight: Font.Bold }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12; topMargin: 42 }
                    text: "暂时没有更多备忘"
                    color: "#333238"
                    font.pixelSize: 11
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "overview"
                sourceComponent: Component {
                    Item {
                anchors.fill: parent
                Text {
                    text: "桌面工作区"
                    color: "white"
                    anchors { left: parent.left; top: parent.top; leftMargin: 18; topMargin: 42 }
                    font { pixelSize: 24; weight: Font.DemiBold }
                }
                GlassText {
                    text: "日历、天气和媒体会在此保持一目了然"
                    wrapMode: Text.Wrap
                    color: Qt.rgba(1, 1, 1, 0.74)
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 20 }
                    font.pixelSize: 14
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "music"
                sourceComponent: Component {
                    Item {
                id: musicContent
                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"
                readonly property var player: DockMprisService.activePlayer
                readonly property bool hasPlayer: player !== null
                readonly property url artworkSource: {
                    const revision = DockMprisService.metadataRevision
                    return player?.trackArtUrl ? player.trackArtUrl : Qt.resolvedUrl("../../assets/defaultCover.png")
                }
                readonly property real safeLength: player?.lengthSupported && player.length > 0
                    ? player.length : 0
                readonly property real progress: safeLength > 0
                    ? Math.max(0, Math.min(1, (player?.position ?? 0) / safeLength)) : 0

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AppActionService.launchById("kos-music", [])
                }

                function artworkTint(color, alpha) {
                    return Qt.rgba(color.r, color.g, color.b, alpha)
                }
                function formatPlaybackTime(seconds) {
                    const value = Math.max(0, Math.floor(seconds || 0))
                    return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
                }

                Timer {
                    interval: 250
                    repeat: true
                    running: musicContent.visible
                        && !!musicContent.player?.isPlaying
                    onTriggered: {
                        if (musicContent.player)
                            musicContent.player.positionChanged()
                    }
                }
                ArtworkPalette {
                    id: musicArtworkPalette
                    source: musicContent.artworkSource
                }
                Rectangle {
                    anchors.fill: parent
	                    visible: musicContent.hasPlayer && !musicContent.glassMode
                    radius: 26
                    clip: true
                    color: "transparent"
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: musicContent.artworkTint(musicArtworkPalette.primary, 0.82) }
                        GradientStop { position: 0.52; color: musicContent.artworkTint(musicArtworkPalette.secondary, 0.64) }
                        GradientStop { position: 1; color: musicContent.artworkTint(musicArtworkPalette.primary, 0.38) }
                    }
                    z: 0
                }
                Item {
                    id: musicNotes
                    anchors { right: parent.right; top: parent.top; rightMargin: 24; topMargin: 17 }
                    width: 72
                    height: 62
                    clip: true
                    z: 2
                    readonly property bool running: musicContent.player?.isPlaying ?? false
                    visible: running
                    Repeater {
                        model: ["♪", "♫", "♪"]
                        delegate: Text {
                            required property var modelData
                            required property int index
                            readonly property var offsets: [4, 34, 54]
                            x: offsets[index]
                            text: modelData
                            color: Qt.rgba(1, 1, 1, 0.60)
                            font { family: "SF Pro Display"; pixelSize: index === 1 ? 18 : 14; weight: Font.DemiBold }
                            SequentialAnimation on y {
                                running: musicNotes.running
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 620 }
                                NumberAnimation { from: musicNotes.height - 14; to: -20; duration: 2200 + index * 180; easing.type: Easing.OutSine }
                            }
                            SequentialAnimation on opacity {
                                running: musicNotes.running
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 620 }
                                NumberAnimation { from: 0; to: 0.64; duration: 360 }
                                NumberAnimation { from: 0.64; to: 0; duration: 1840 + index * 180; easing.type: Easing.InSine }
                            }
                        }
                    }
                }

                Item {
                    id: musicBody
                    anchors { fill: parent; margins: 16 }
                    readonly property real splitGap: 20
                    z: 1

                    Item {
                        id: musicCoverPane
                        x: 0
                        y: 0
                        width: (musicBody.width - musicBody.splitGap) * 0.3
                        height: musicBody.height
                        Rectangle {
                            id: musicArtwork
                            anchors.centerIn: parent
                            width: Math.min(musicCoverPane.width, musicCoverPane.height)
                            height: width
                            radius: width * 0.1
                            color: Qt.rgba(1, 1, 1, 0.10)
                            Image {
                                id: musicArtworkSource
                                anchors.fill: parent
                                visible: false
                                source: musicContent.artworkSource
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: Math.max(1, Math.ceil(width * 2))
                                sourceSize.height: Math.max(1, Math.ceil(height * 2))
                                asynchronous: true
                                cache: false
                            }
	                            OpacityMask {
	                                anchors.fill: parent
	                                visible: musicContent.hasPlayer
	                                source: musicArtworkSource
	                                layer.enabled: musicContent.glassMode
	                                layer.effect: MultiEffect {
	                                    saturation: IconAppearanceService.mode === "grayscale" ? 0 : 1
	                                    colorization: IconAppearanceService.mode === "tint" ? 1 : 0
	                                    colorizationColor: IconAppearanceService.styledSymbolicColor()
	                                }
                                maskSource: Rectangle {
                                    width: musicArtwork.width
                                    height: musicArtwork.height
                                    radius: musicArtwork.width * 0.1
                                }
                            }
                            Text {
                                anchors.centerIn: parent
	                                visible: !musicContent.hasPlayer
                                text: "♫"
                                color: Qt.rgba(1, 1, 1, 0.46)
                                font { family: "SF Pro Display"; pixelSize: musicArtwork.width * 0.42 }
                            }
                        }
                    }

                    Item {
                        id: musicDetailsPane
                        x: musicCoverPane.width + musicBody.splitGap
                        y: 0
                        width: musicBody.width - x
                        height: musicBody.height
                        Text {
                            id: musicTitle
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -22 }
                            text: musicContent.player?.trackTitle || "暂无播放内容"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
	                            color: musicContent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                            font { pixelSize: 14; weight: Font.DemiBold }
                        }
                        Text {
                            id: musicArtist
                            anchors { left: parent.left; right: parent.right; top: musicTitle.bottom; topMargin: 3 }
                            text: musicContent.player?.trackArtist || ""
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
	                            color: musicContent.glassMode ? IconAppearanceService.glassContentColor(0.68) : Qt.rgba(1, 1, 1, 0.68)
                            font.pixelSize: 10
                        }
                        Item {
                            id: musicProgressTrack
                            anchors { left: parent.left; right: parent.right; top: musicArtist.bottom; topMargin: 12 }
                            height: 5
                            visible: musicContent.safeLength > 0
                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Qt.rgba(1, 1, 1, 0.20)
                            }
                            Rectangle {
                                width: parent.width * musicContent.progress
                                height: parent.height
                                radius: height / 2
                                color: Qt.rgba(1, 1, 1, 0.82)
                            }
                        }
                        Item {
                            id: musicProgressTimes
                            anchors { left: parent.left; right: parent.right; top: musicProgressTrack.bottom; topMargin: 4 }
                            height: 11
                            visible: musicProgressTrack.visible
                            Text {
                                anchors.left: parent.left
                                text: musicContent.formatPlaybackTime(musicContent.player?.position ?? 0)
	                                color: musicContent.glassMode ? IconAppearanceService.glassContentColor(0.60) : Qt.rgba(1, 1, 1, 0.60)
                                font.pixelSize: 8
                            }
                            Text {
                                anchors.right: parent.right
                                text: musicContent.formatPlaybackTime(musicContent.safeLength)
	                                color: musicContent.glassMode ? IconAppearanceService.glassContentColor(0.60) : Qt.rgba(1, 1, 1, 0.60)
                                font.pixelSize: 8
                            }
                        }
                        Row {
                            id: musicControls
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                                bottomMargin: 2
                            }
                            height: 30
                            spacing: 14
                            Repeater {
                                model: ["⏮", musicContent.player?.isPlaying ? "⏸" : "▶", "⏭"]
                                delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool controlEnabled: musicContent.hasPlayer
                                && (index === 0 ? (musicContent.player?.canGoPrevious ?? false)
                                    : index === 2 ? (musicContent.player?.canGoNext ?? false)
                                    : (musicContent.player?.canTogglePlaying ?? false))
                            width: index === 1 ? 30 : 24
                            height: width
                            y: (parent.height - height) / 2
                            radius: width / 2
                            color: index === 1
                                ? Qt.rgba(1, 1, 1, controlEnabled ? 0.24 : 0.10)
                                : Qt.rgba(1, 1, 1, controlEnabled ? 0.12 : 0.055)
                            Text {
                                anchors.centerIn: parent
                                text: modelData
	                                color: musicContent.glassMode
	                                    ? IconAppearanceService.glassContentColor(parent.controlEnabled ? 0.88 : 0.28)
	                                    : Qt.rgba(1, 1, 1, parent.controlEnabled ? 0.88 : 0.28)
                                font {
                                    family: "SF Pro Display"
                                    pixelSize: index === 1 ? 15 : 11
                                    weight: Font.DemiBold
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: parent.controlEnabled
                                cursorShape: parent.controlEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (index === 0) DockMprisService.previous()
                                    else if (index === 1) DockMprisService.togglePlayPause()
                                    else DockMprisService.next()
                                }
                            }
                        }
                    }
                        }
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "shortcuts"
                sourceComponent: Component {
                    Item {
                anchors.fill: parent
                Row {
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 18; topMargin: 44 }
                    spacing: 10
                    Repeater {
                        model: ["应用库", "刷新天气", "媒体"]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - parent.spacing * 2) / 3
                            height: 58
                            radius: 15
                            color: Qt.rgba(1, 1, 1, 0.14)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                            GlassText { anchors.centerIn: parent; text: modelData; color: "white"; font { pixelSize: 12; weight: Font.DemiBold } }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData === "应用库")
                                        AppLauncherService.show()
                                    else if (modelData === "刷新天气")
                                        WeatherService.refresh()
                                    else
                                        DockMprisService.togglePlayPause()
                                }
                            }
                        }
                    }
                }
            }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "todo"
                sourceComponent: Component {
                    Item {
                        id: todoContent
                        anchors.fill: parent
                        readonly property string widgetSize:
                            DeskCenterConfigService.sizeFor("todo")
                        readonly property int itemLimit: widgetSize === "large" ? 6
                            : widgetSize === "medium" ? 3 : 0
                        readonly property var tasks:
                            PimWidgetService.pendingTodos(itemLimit)
                        // In the shared glass modes the card material is the
                        // face: skip the opaque reminder-red band and pick
                        // content colours from the appearance service, the
                        // same way the clock and calendar widgets do.
                        readonly property bool glassMode: IconAppearanceService.mode !== "color"

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AppActionService.launchById(
                                "kos-todo", ["--view", "today"])
                        }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: Math.min(42, parent.height * 0.28)
                            color: "#ff5d66"
                            visible: !todoContent.glassMode
                        }
                        Text {
                            anchors { left: parent.left; top: parent.top; margins: 14 }
                            text: "提醒事项"
                            color: todoContent.glassMode ? IconAppearanceService.glassContentColor() : "white"
                            font { pixelSize: 13; weight: Font.Bold }
                        }
                        Text {
                            visible: todoContent.widgetSize === "small"
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 12
                            text: String(PimWidgetService.pendingTodos(99).length)
                            color: todoContent.glassMode ? IconAppearanceService.glassContentColor() : "#33333a"
                            font { pixelSize: 38; weight: Font.DemiBold }
                        }
                        Text {
                            visible: todoContent.widgetSize === "small"
                            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                            text: "项待办"
                            color: todoContent.glassMode ? IconAppearanceService.glassContentColor(0.6) : "#686873"
                            font.pixelSize: 10
                        }
                        Column {
                            visible: todoContent.widgetSize !== "small"
                            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 14; rightMargin: 14; topMargin: 50; bottomMargin: 10 }
                            spacing: 4
                            Repeater {
                                model: todoContent.tasks
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width
                                    height: Math.max(24,
                                        (parent.height - Math.max(0, todoContent.tasks.length - 1) * parent.spacing)
                                        / Math.max(1, todoContent.tasks.length))
                                    Rectangle {
                                        width: 13; height: 13; radius: 7
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                        color: "transparent"
                                        border.width: 1.5
                                        border.color: todoContent.glassMode ? IconAppearanceService.glassContentColor(0.7) : "#ff5d66"
                                    }
                                    Text {
                                        anchors { left: parent.left; right: dueText.left; verticalCenter: parent.verticalCenter; leftMargin: 22; rightMargin: 8 }
                                        text: String(PimWidgetService.value(parent.modelData, "title", "未命名任务"))
                                        color: todoContent.glassMode ? IconAppearanceService.glassContentColor() : "#303038"
                                        elide: Text.ElideRight
                                        font { pixelSize: 11; weight: Font.Medium }
                                    }
                                    Text {
                                        id: dueText
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        text: String(PimWidgetService.value(parent.modelData, "due", "")).slice(0, 10)
                                        color: todoContent.glassMode
                                            ? (text && text < PimWidgetService.today
                                                ? IconAppearanceService.glassContentColor()
                                                : IconAppearanceService.glassContentColor(0.6))
                                            : (text && text < PimWidgetService.today ? "#e23d52" : "#7b7b84")
                                        font.pixelSize: 9
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: AppActionService.launchById("kos-todo", [
                                            "--item", String(PimWidgetService.value(parent.modelData,
                                                "id", PimWidgetService.value(parent.modelData, "seriesId", "")))
                                        ])
                                    }
                                }
                            }
                            Text {
                                visible: todoContent.tasks.length === 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                // Distinguish a starting service from one
                                // that never produced data (uninstalled or
                                // not yet activated); tapping the card
                                // launches the app, whose PIM client
                                // activates the service on demand.
                                text: PimWidgetService.ready
                                    ? "今天已全部完成"
                                    : (PimWidgetService.state === PimWidgetService.stateLoading
                                       ? "正在载入待办…" : "未连接待办服务")
                                color: todoContent.glassMode ? IconAppearanceService.glassContentColor(0.6) : "#6c6c75"
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Loader {
                anchors.fill: parent
                active: card.modelData.id === "calendar"
                sourceComponent: Component {
                    Item {
	                id: calendarContent
	                anchors.fill: parent
	                readonly property bool glassMode: IconAppearanceService.mode !== "color"
                readonly property int year: clock.date.getFullYear()
                readonly property int month: clock.date.getMonth()
                // Monday-first month layout: 星期一 is the first column and
                // 星期日 is the final column, matching the requested reading order.
                readonly property int firstWeekday: (new Date(year, month, 1).getDay() + 6) % 7
                readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
                // Do not reserve a sixth, empty week: five-week months use
                // the whole panel height instead of ending with a blank band.
                readonly property int weekCount: Math.ceil((firstWeekday + daysInMonth) / 7)
                readonly property int headerHeight: 38
                readonly property string widgetSize:
                    DeskCenterConfigService.sizeFor("calendar")
                readonly property var todayEvents: PimWidgetService.eventsForToday(
                    widgetSize === "large" ? 3 : 1)

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AppActionService.launchById("kos-calendar", [
                        "--date", Qt.formatDate(clock.date, "yyyy-MM-dd")
                    ])
                }

                Rectangle {
                    // Draw the pale right pane before the header. Its own
                    // rounded lower corner keeps it from covering the card
                    // outline even though QML clipping is rectangular.
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right; left: parent.left; leftMargin: parent.width * 0.42 }
	                    radius: card.radius
	                    color: "#fafafa"
	                    visible: !calendarContent.glassMode
                }
                Canvas {
                    id: calendarHeader
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: calendarContent.headerHeight
                    onPaint: {
                        const ctx = getContext("2d")
                        const corner = Math.min(card.radius, height)
	                        ctx.reset()
	                        if (calendarContent.glassMode)
	                            return
                        ctx.fillStyle = "#ff5d66"
                        ctx.beginPath()
                        ctx.moveTo(0, height)
                        ctx.lineTo(0, corner)
                        ctx.quadraticCurveTo(0, 0, corner, 0)
                        ctx.lineTo(width - corner, 0)
                        ctx.quadraticCurveTo(width, 0, width, corner)
                        ctx.lineTo(width, height)
                        ctx.closePath()
                        ctx.fill()
	                }
	                Connections {
	                    target: IconAppearanceService
	                    function onModeChanged() { calendarHeader.requestPaint() }
	                }
                }
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: parent.width * 0.42; topMargin: calendarContent.headerHeight; bottomMargin: 8 }
                    width: 1
	                    color: calendarContent.glassMode ? IconAppearanceService.glassContentColor(0.28) : Qt.rgba(0, 0, 0, 0.10)
                }

                Text {
                    anchors.centerIn: calendarHeader
                    text: Qt.formatDateTime(clock.date, "yyyy年M月")
                    horizontalAlignment: Text.AlignHCenter
                    color: "white"
                    font { pixelSize: 15; weight: Font.Bold }
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 15; topMargin: calendarContent.headerHeight + 7 }
                    text: Qt.formatDateTime(clock.date, "d日")
	                    color: calendarContent.glassMode ? IconAppearanceService.glassContentColor() : "#15151a"
                    font { family: "SF Pro Display"; pixelSize: 32; weight: Font.DemiBold }
                }
                Text {
                    anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: calendarContent.headerHeight + 46 }
                    text: Qt.formatDateTime(clock.date, "ddd") + " · " + root.lunarDate(clock.date)
	                    color: calendarContent.glassMode ? IconAppearanceService.glassContentColor(0.74) : "#4d4d55"
                    font { pixelSize: 10; weight: Font.DemiBold }
                }
                Column {
                    visible: calendarContent.widgetSize !== "small"
                        && calendarContent.todayEvents.length > 0
                    anchors { left: parent.left; right: monthGrid.left; bottom: parent.bottom; leftMargin: 16; rightMargin: 8; bottomMargin: 10 }
                    spacing: 3
                    Repeater {
                        model: calendarContent.todayEvents
                        delegate: Text {
                            required property var modelData
                            width: parent.width
                            text: "• " + String(PimWidgetService.value(modelData, "title", "日程"))
                            color: "#4d4d55"
                            elide: Text.ElideRight
                            font.pixelSize: 9
                        }
                    }
                    Text {
                        visible: calendarContent.todayEvents.length === 0
                            && PimWidgetService.state === PimWidgetService.stateUnavailable
                        text: "未连接日历服务"
                        color: calendarContent.glassMode ? IconAppearanceService.glassContentColor(0.55) : "#9a9aa2"
                        elide: Text.ElideRight
                        font.pixelSize: 9
                    }
                }
                Item {
                    id: monthGrid
                    anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: parent.width * 0.42 + 10; rightMargin: 10; topMargin: calendarContent.headerHeight + 6; bottomMargin: 7 }
                    Row {
                        width: parent.width
                        height: 15
                        Repeater {
                            model: ["一", "二", "三", "四", "五", "六", "日"]
                            delegate: Text {
                                required property var modelData
                                required property int index
                                width: parent.width / 7
                                text: modelData
                                horizontalAlignment: Text.AlignHCenter
	                                color: calendarContent.glassMode ? IconAppearanceService.glassContentColor() : (index >= 5 ? "#e95a63" : "#5d5d65")
                                font { pixelSize: 10; weight: Font.Bold }
                            }
                        }
                    }
                    Grid {
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 15 }
                        columns: 7
                        Repeater {
                            model: calendarContent.weekCount * 7
                            delegate: Item {
                                required property int index
                                width: parent.width / 7
                                height: parent.height / calendarContent.weekCount
                                readonly property int day: index - calendarContent.firstWeekday + 1
                                readonly property bool today: day === clock.date.getDate()
                                    && calendarContent.month === clock.date.getMonth()
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    radius: 8
	                                    color: parent.today
	                                        ? (calendarContent.glassMode ? IconAppearanceService.glassContentColor(0.22) : "#ef5661")
	                                        : "transparent"
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.day > 0 && parent.day <= calendarContent.daysInMonth
                                    text: parent.day
	                                    color: calendarContent.glassMode ? IconAppearanceService.glassContentColor() : (parent.today ? "white" : "#29292f")
                                    font { pixelSize: 10; weight: parent.today ? Font.Bold : Font.DemiBold }
                                }
                            }
                        }
                    }
                }
            }
                }
            }
        }
    }

    // The file area intentionally has no panel background. It uses the empty
    // right side of the desktop as a calm, macOS-like icon field, filling
    // columns from right to left and rows from top to bottom.
    Item {
        id: desktopFileGrid
        x: root.leftInset + 4 * (root.cellSize + root.gap)
        y: root.topInset
        width: root.width - x - root.rightInset
        height: root.height - y - root.bottomInset
        clip: false
        readonly property int iconSize: desktopLayout.iconSize
        // Keep the label optically paired with the three user-selectable
        // icon sizes instead of leaving it at a fixed desktop-small size.
        readonly property int fileNameFontSize: iconSize === 72 ? 14
            : iconSize === 56 ? 11 : 9
        readonly property int fileNameFontWeight: iconSize === 72 ? Font.Bold
            : iconSize === 56 ? Font.DemiBold : Font.Medium
        // Reserve real gutters around every icon.  The gaps are not merely
        // visual: they belong to the desktop background so users can start a
        // rubber-band selection between neighbouring files.
        readonly property int preferredItemWidth: iconSize + 72
        readonly property int columnCount: Math.max(1, Math.floor(width / preferredItemWidth))
        readonly property real itemWidth: width / columnCount
        readonly property real itemHeight: iconSize + 58
        readonly property int rowCount: Math.max(1, Math.floor(height / itemHeight))
        property var selectedPaths: []
        property var contextEntry: null
        property string renamingPath: ""
        property string pendingRenamePath: ""
        property string folderDropCandidatePath: ""
        property string dropFolderPath: ""
        property real folderDropProgress: 0
        property string draggingPath: ""
        property real groupDragOffsetX: 0
        property real groupDragOffsetY: 0
        property var reorderSettleFrom: ({})
        property bool reorderSettleActive: false
        property string reorderDragSourcePath: ""
        property string reorderPreviewSourcePath: ""
        property int reorderInsertionIndex: -1
        property bool reorderDragging: false
        property real reorderPressPointerX: 0
        property real reorderPressPointerY: 0
        property real reorderDragOffsetX: 0
        property real reorderDragOffsetY: 0
        property real reorderPointerX: 0
        property real reorderPointerY: 0
        property int reorderDragEntryCount: 0
        property var reorderActiveHandler: null
        property var reorderPreviewOffsets: ({})
        property bool selectionBoxActive: false
        property real selectionStartX: 0
        property real selectionStartY: 0
        property real selectionEndX: 0
        property real selectionEndY: 0
        property var selectionBase: []
        readonly property var orderedEntries: ordered(root.desktopFiles.entries)

        Settings {
            id: desktopLayout
            location: "file://" + Quickshell.stateDir + "/deskcenter-desktop-files.ini"
            category: "DesktopFiles"
            property string orderJson: "[]"
            property int iconSize: 56
            property bool showExtensions: true
            // Per-entry customisation keyed by absolute path. The historical
            // key name is retained so existing folder settings stay intact;
            // files and folders both use the same payload.
            // Each value is { "color": "#hex", "emoji": "📁" }.
            property string folderCustomJson: "{}"
        }

        // Parsed cache of folderCustomJson, rebuilt only when the raw string
        // changes so delegates don't re-parse on every paint.
        readonly property var _folderCustomCache: {
            try { return JSON.parse(desktopLayout.folderCustomJson) } catch (_) { return {} }
        }

        function folderCustomFor(path) {
            const map = desktopFileGrid._folderCustomCache
            return map && map[path] ? map[path] : null
        }

        function _writeFolderCustom(path, color, emoji) {
            let map
            try { map = JSON.parse(desktopLayout.folderCustomJson) } catch (_) { map = {} }
            if (!color && !emoji)
                delete map[path]
            else
                map[path] = { "color": color || "", "emoji": emoji || "" }
            desktopLayout.folderCustomJson = JSON.stringify(map)
            desktopLayout.sync()
        }

        function setFolderColor(path, color) {
            const existing = folderCustomFor(path)
            _writeFolderCustom(path, color, existing ? existing.emoji : "")
        }

        function setFolderEmoji(path, emoji) {
            const existing = folderCustomFor(path)
            _writeFolderCustom(path, existing ? existing.color : "", emoji)
        }

        function removeFolderCustom(path) {
            _writeFolderCustom(path, "", "")
        }

        function migrateFolderCustom(oldPath, newPath) {
            if (oldPath === newPath)
                return
            const existing = folderCustomFor(oldPath)
            if (!existing)
                return
            _writeFolderCustom(oldPath, "", "")
            _writeFolderCustom(newPath, existing.color, existing.emoji)
        }


        // A visible hold-to-drop progress, mirroring the App Launcher folder
        // interaction. Only a completed bar arms the actual file operation.
        NumberAnimation {
            id: folderDropProgressAnimation
            target: desktopFileGrid
            property: "folderDropProgress"
            from: 0
            to: 1
            duration: 380
            easing.type: Easing.Linear
            onFinished: {
                if (desktopFileGrid.folderDropCandidatePath !== "") {
                    desktopFileGrid.dropFolderPath = desktopFileGrid.folderDropCandidatePath
                }
            }
        }

        function updateFolderDropTarget(pointX, pointY, sourcePath) {
            const target = folderAtDropPoint(pointX, pointY, sourcePath)
            const path = target?.path ?? ""
            if (folderDropCandidatePath === path)
                return
            folderDropCandidatePath = path
            dropFolderPath = ""
            folderDropProgressAnimation.stop()
            folderDropProgress = 0
            if (path)
                folderDropProgressAnimation.restart()
        }

        function clearFolderDropTarget() {
            folderDropProgressAnimation.stop()
            folderDropCandidatePath = ""
            dropFolderPath = ""
            folderDropProgress = 0
        }

        function clearGroupDrag() {
            draggingPath = ""
            groupDragOffsetX = 0
            groupDragOffsetY = 0
        }

        Timer {
            id: reorderSettleTimer
            interval: 16
            repeat: false
            onTriggered: desktopFileGrid.reorderSettleActive = false
        }

        function clearReorderSettle() {
            reorderSettleTimer.stop()
            reorderSettleActive = false
            reorderSettleFrom = ({})
        }

        function updateReorderInsertion(path, destinationIndex) {
            const sourceIndex = orderedEntries.findIndex(function(entry) {
                return entry.path === path
            })
            const targetIndex = Math.max(0,
                Math.min(orderedEntries.length - 1, destinationIndex))
            if (sourceIndex === targetIndex) {
                clearReorderInsertion()
                return
            }
            if (reorderPreviewSourcePath === path && reorderInsertionIndex === targetIndex)
                return
            reorderPreviewSourcePath = path
            reorderInsertionIndex = targetIndex
            const offsets = ({})
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                const offset = reorderPreviewOffsetFor(index, entry.path, path, targetIndex)
                if (offset.x !== 0 || offset.y !== 0)
                    offsets[entry.path] = offset
            }
            reorderPreviewOffsets = offsets
        }

        function clearReorderInsertion() {
            reorderInsertionIndex = -1
            reorderPreviewSourcePath = ""
            reorderPreviewOffsets = ({})
        }

        // Pointer translation feeds the dragged icon directly.  Reordering
        // and folder hit-testing are semantic updates, so cap them to the
        // display cadence instead of doing JS work for every raw motion event.
        Timer {
            id: reorderSemanticTimer
            interval: 16
            repeat: true
            running: desktopFileGrid.reorderDragging
            onTriggered: {
                const sourcePath = desktopFileGrid.reorderDragSourcePath
                const handler = desktopFileGrid.reorderActiveHandler
                if (sourcePath === "" || !handler)
                    return
                const offsetX = handler.activeTranslation.x
                const offsetY = handler.activeTranslation.y
                desktopFileGrid.reorderPointerX = desktopFileGrid.reorderPressPointerX + offsetX
                desktopFileGrid.reorderPointerY = desktopFileGrid.reorderPressPointerY + offsetY
                if (desktopFileGrid.reorderDragEntryCount > 1) {
                    desktopFileGrid.draggingPath = sourcePath
                    desktopFileGrid.groupDragOffsetX = offsetX
                    desktopFileGrid.groupDragOffsetY = offsetY
                }
                desktopFileGrid.updateFolderDropTarget(
                    desktopFileGrid.reorderPointerX, desktopFileGrid.reorderPointerY, sourcePath)
                if (desktopFileGrid.reorderDragEntryCount === 1
                        && desktopFileGrid.folderDropCandidatePath === "")
                    desktopFileGrid.updateReorderInsertion(sourcePath,
                        desktopFileGrid.indexAt(desktopFileGrid.reorderPointerX,
                            desktopFileGrid.reorderPointerY))
            }
        }

        function gridPositionForIndex(index) {
            return {
                x: (columnCount - 1 - Math.floor(index / rowCount)) * itemWidth,
                y: (index % rowCount) * itemHeight
            }
        }

        // This is deliberately only a visual translation. Delegates retain
        // their unique grid coordinates until the drop commits the order,
        // so a transient preview can never assign two entries to one slot.
        function reorderPreviewOffsetFor(index, path, sourcePath, targetIndex) {
            if (targetIndex < 0 || path === sourcePath)
                return ({ x: 0, y: 0 })
            const sourceIndex = orderedEntries.findIndex(function(entry) {
                return entry.path === sourcePath
            })
            if (sourceIndex < 0)
                return ({ x: 0, y: 0 })
            let previewIndex = index
            if (sourceIndex < targetIndex && index > sourceIndex && index <= targetIndex)
                previewIndex = index - 1
            else if (sourceIndex > targetIndex
                    && index >= targetIndex && index < sourceIndex)
                previewIndex = index + 1
            if (previewIndex === index)
                return ({ x: 0, y: 0 })
            const from = gridPositionForIndex(index)
            const to = gridPositionForIndex(previewIndex)
            return ({ x: to.x - from.x, y: to.y - from.y })
        }

        function ordered(source) {
            let saved = []
            try { saved = JSON.parse(desktopLayout.orderJson) } catch (_) {}
            const positions = ({})
            for (let index = 0; index < saved.length; ++index)
                positions[saved[index]] = index
            return source.slice().sort(function(left, right) {
                const leftIndex = positions[left.path]
                const rightIndex = positions[right.path]
                // Manually placed icons always stay put. New paths have no
                // saved slot yet, so append them in a stable, visible order
                // instead of relying on an ambiguous comparator result.
                if (leftIndex === undefined && rightIndex === undefined) {
                    const leftTime = Number(left.modifiedAt) || 0
                    const rightTime = Number(right.modifiedAt) || 0
                    if (leftTime !== rightTime)
                        return leftTime - rightTime
                    return (left.name || "").localeCompare(right.name || "")
                }
                if (leftIndex === undefined) return 1
                if (rightIndex === undefined) return -1
                return leftIndex - rightIndex
            })
        }

        function reorder(path, destinationIndex, wasPreviewed) {
            const next = orderedEntries.slice()
            const sourceIndex = next.findIndex(function(entry) { return entry.path === path })
            if (sourceIndex < 0)
                return
            const targetIndex = Math.max(0, Math.min(next.length - 1, destinationIndex))
            if (sourceIndex === targetIndex)
                return
            const previousPositions = ({})
            for (let index = 0; index < next.length; ++index) {
                previousPositions[next[index].path] = ({
                    x: (columnCount - 1 - Math.floor(index / rowCount)) * itemWidth,
                    y: (index % rowCount) * itemHeight
                })
            }
            const entry = next.splice(sourceIndex, 1)[0]
            next.splice(targetIndex, 0, entry)
            // The dragged item itself is already under the pointer. Only the
            // displaced neighbours animate into their new positions after a
            // successful drop, never while the user is still deciding.
            const sourceNewIndex = next.findIndex(function(candidate) {
                return candidate.path === path
            })
            previousPositions[path] = ({
                x: (columnCount - 1 - Math.floor(sourceNewIndex / rowCount)) * itemWidth,
                y: (sourceNewIndex % rowCount) * itemHeight
            })
            if (!wasPreviewed) {
                reorderSettleFrom = previousPositions
                reorderSettleActive = true
            }
            saveOrder(next)
            if (!wasPreviewed)
                reorderSettleTimer.restart()
        }

        function saveOrder(entries) {
            desktopLayout.orderJson = JSON.stringify(entries.map(function(item) { return item.path }))
            desktopLayout.sync()
        }

        function saveVisualOrder() {
            const next = []
            for (let index = 0; index < desktopFileVisualModel.items.count; ++index) {
                const item = desktopFileVisualModel.items.get(index)
                if (item?.model)
                    next.push(item.model)
            }
            if (next.length === orderedEntries.length)
                saveOrder(next)
        }

        function arrange(compare) {
            const next = root.desktopFiles.entries.slice().sort(function(left, right) {
                const leftIsFolder = left.kind === "folder"
                const rightIsFolder = right.kind === "folder"
                if (leftIsFolder !== rightIsFolder)
                    return leftIsFolder ? -1 : 1
                const result = compare(left, right)
                return result || (left.name || "").localeCompare(right.name || "")
            })
            saveOrder(next)
        }

        function arrangeByName() {
            arrange(function(left, right) {
                return (left.name || "").localeCompare(right.name || "")
            })
        }

        function arrangeByType() {
            arrange(function(left, right) {
                return (left.kind || "").localeCompare(right.kind || "")
            })
        }

        function arrangeByModified(newestFirst) {
            arrange(function(left, right) {
                const leftTime = Number(left.modifiedAt) || 0
                const rightTime = Number(right.modifiedAt) || 0
                return newestFirst ? rightTime - leftTime : leftTime - rightTime
            })
        }

        function resetLayout() {
            desktopLayout.orderJson = "[]"
            desktopLayout.sync()
            clearDesktopSelection()
        }

        function setIconSize(size) {
            if (size !== 40 && size !== 56 && size !== 72)
                return
            desktopLayout.iconSize = size
            desktopLayout.sync()
        }

        function displayName(entry) {
            const name = entry?.title || entry?.name || ""
            if (desktopLayout.showExtensions || entry?.kind === "folder")
                return name
            const extensionIndex = name.lastIndexOf(".")
            return extensionIndex > 0 ? name.slice(0, extensionIndex) : name
        }

        function beginInlineRename(entry) {
            if (!entry?.path)
                return
            root.desktopFiles.lastError = ""
            const path = entry.path
            // Platform.Menu owns focus while it is closing. Defer editor
            // activation by one event-loop turn so the menu cannot immediately
            // steal focus back and trigger the editor's focus-loss commit.
            Qt.callLater(function() {
                freeSlotDesktop.beginRename(path)
            })
        }

        function commitRename(entry, name) {
            const newName = (name ?? "").trim()
            if (!entry?.path || !root.desktopFiles.validName(newName)) {
                root.desktopFiles.lastError = "名称不能为空，且不能包含 /"
                return false
            }
            const newPath = root.desktopFiles.directory + "/" + newName
            if (newPath !== entry.path) {
                const clash = root.desktopFiles.entries.some(function(candidate) {
                    return candidate.path === newPath
                })
                if (clash) {
                    root.desktopFiles.lastError = "该名称已被占用"
                    return false
                }
            }
            const oldPath = entry.path
            return root.desktopFiles.renameEntry(entry, newName, function() {
                if (newPath !== oldPath)
                    desktopFileGrid.migrateFolderCustom(oldPath, newPath)
            })
        }

        function createNewFolder() {
            pendingRenamePath = ""
            root.desktopFiles.createUntitledFolder(function(path) {
                desktopFileGrid.pendingRenamePath = path
            })
        }

        function createNewFile() {
            pendingRenamePath = ""
            root.desktopFiles.createUntitledFile(function(path) {
                desktopFileGrid.pendingRenamePath = path
            })
        }

        function startPendingRename() {
            if (!pendingRenamePath)
                return
            const entry = orderedEntries.find(function(candidate) {
                return candidate.path === pendingRenamePath
            })
            if (!entry)
                return
            pendingRenamePath = ""
            selectOnly(entry.path)
            beginInlineRename(entry)
        }

        function renameSelectionEnd(entry) {
            const name = entry?.name ?? ""
            if (entry?.kind === "folder")
                return name.length
            const extensionIndex = name.lastIndexOf(".")
            // Finder keeps the suffix in the editor but initially selects
            // only the base name, so typing does not accidentally change the
            // file type.
            return extensionIndex > 0 ? extensionIndex : name.length
        }

        function isSelected(path) {
            return selectedPaths.indexOf(path) >= 0
        }

        function selectedEntries() {
            return orderedEntries.filter(function(entry) {
                return isSelected(entry.path)
            })
        }

        function activateKeyboard() {
            desktopKeyboard.forceActiveFocus()
        }

        function handleClipboardShortcut(event) {
            if (!(event.modifiers & Qt.ControlModifier))
                return false
            if (event.key === Qt.Key_C) {
                root.desktopFiles.copyEntries(selectedEntries(), "copy")
            } else if (event.key === Qt.Key_X) {
                root.desktopFiles.copyEntries(selectedEntries(), "cut")
            } else if (event.key === Qt.Key_V) {
                root.desktopFiles.pasteIntoDesktop()
            } else {
                return false
            }
            event.accepted = true
            return true
        }

        function setSelectedPaths(paths) {
            selectedPaths = paths.slice()
        }

        function selectOnly(path) {
            setSelectedPaths(path ? [path] : [])
        }

        function toggleSelection(path) {
            const next = selectedPaths.slice()
            const index = next.indexOf(path)
            if (index >= 0)
                next.splice(index, 1)
            else
                next.push(path)
            setSelectedPaths(next)
        }

        function selectInBox(left, top, right, bottom, additive) {
            const minX = Math.min(left, right)
            const maxX = Math.max(left, right)
            const minY = Math.min(top, bottom)
            const maxY = Math.max(top, bottom)
            const next = additive ? selectionBase.slice() : []
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                const column = columnCount - 1 - Math.floor(index / rowCount)
                const row = index % rowCount
                if (column < 0)
                    continue
                const itemX = column * itemWidth
                const itemY = row * itemHeight
                const intersects = itemX < maxX && itemX + itemWidth > minX
                    && itemY < maxY && itemY + itemHeight > minY
                if (intersects && next.indexOf(entry.path) < 0)
                    next.push(entry.path)
            }
            setSelectedPaths(next)
        }

        function gridPoint(pointer, mouse) {
            return pointer.mapToItem(desktopFileGrid, mouse.x, mouse.y)
        }

        function iconFor(kind) {
            if (kind === "folder") return ""
            if (kind === "image") return ""
            if (kind === "pdf") return ""
            if (kind === "code") return ""
            if (kind === "text") return "󰈙"
            if (kind === "launcher") return ""
            return ""
        }

        function canChooseOpenWith(entry) {
            // Background menus have no entry.  Treating undefined as a
            // non-folder used to make showMenu() dereference entry.path.
            return !!entry && entry.kind !== "folder" && entry.kind !== "launcher"
        }

        function applicationName(id) {
            // Resolve through the same desktop-entry identity layer used by
            // the Dock.  gio returns filenames (for example nvim.desktop),
            // while the visible label must be the entry's Name field.
            try { return AppIdentityService.resolve(id)?.name || id } catch (_) { return id || "默认应用" }
        }

        function openWithIdAt(index) {
            return root.desktopFiles.openWith.handlers[index] || ""
        }

        function defaultOpenText() {
            const handler = root.desktopFiles.openWith.defaultId
            return handler ? "使用 " + applicationName(handler) + " 打开" : "打开"
        }

        function showMenu(entry, windowPoint) {
            contextEntry = entry || null
            // Build and show immediately - never block the right click on the
            // async gio open-with query (a slow/failed query must not make a
            // right click appear to do nothing).
            //
            // Do not use a timed rebuild here: setItems() intentionally resets
            // ContextMenu's navigation path, which made a folder's appearance
            // submenu disappear while it was being browsed.
            if (entry && canChooseOpenWith(entry)) {
                const entryPath = entry.path
                root.desktopFiles.queryOpenWith(entry, function() {
                    // A result may arrive after another item was right-clicked.
                    // Refresh only the still-open root menu; once the user has
                    // entered a submenu, keep that interaction stable and show
                    // the refreshed open-with list on the next invocation.
                    if (desktopContextMenu.visible
                            && contextEntry?.path === entryPath
                            && desktopContextMenu.atRoot)
                        desktopFileGrid.setContextMenuItems()
                })
            }
            desktopFileGrid.setContextMenuItems()
            const pt = windowPoint && windowPoint.x !== undefined
                ? windowPoint : Qt.point(desktopFileGrid.width - 12, 12)
            desktopContextAnchor.x = pt.x
            desktopContextAnchor.y = pt.y
            desktopContextMenu.show()
        }

        function clearDesktopSelection() {
            selectedPaths = []
            freeSlotDesktop.selectedIds = []
            desktopContextMenu.hide()
            contextEntry = null
        }

        function triggerContextAction(kind) {
            const entry = contextEntry
            desktopContextMenu.hide()
            contextEntry = null
            if (kind === "folder")
                createNewFolder()
            else if (kind === "file")
                createNewFile()
            else if (kind === "openEntry")
                root.desktopFiles.openEntry(entry)
            else if (kind === "rename")
                beginInlineRename(entry)
            else if (kind === "openWithMore")
                openWithDialog.show(entry)
            else if (kind === "trash") {
                const entries = selectedEntries()
                selectedPaths = []
                freeSlotDesktop.selectedIds = []
                root.desktopFiles.trashEntries(entries, function() {
                    DockTrashService.celebrateDeposit()
                })
            }
            else if (kind === "copy")
                root.desktopFiles.copyEntries(selectedEntries(), "copy")
            else if (kind === "cut")
                root.desktopFiles.copyEntries(selectedEntries(), "cut")
            else if (kind === "paste")
                root.desktopFiles.pasteIntoDesktop()
            else if (kind === "open")
                root.desktopFiles.openDirectory()
            else if (kind === "arrange")
                arrangeByName()
            else if (kind === "resetLayout")
                resetLayout()
            else if (kind === "refresh")
                root.desktopFiles.reload()
        }

        // ── Liquid context-menu data + builder ──

        function _ctxSub(label, children, icon) {
            return { icon: icon || "", label: label, children: children }
        }
        function _ctxAct(label, cmd, icon) {
            return { icon: icon || "", label: label, cmd: cmd, enabled: true }
        }
        function _ctxCheck(label, cmd, value, checked, icon) {
            return { icon: icon || "", label: label, cmd: cmd,
                checkable: true, checked: checked, value: value, enabled: true }
        }

        function buildContextItems() {
        const FOLDER_COLORS = [
            ["默认", ""], ["🔴 红", "#FF6B6B"], ["🟠 橙", "#FFA94D"], ["🟡 黄", "#FFD43B"],
            ["🟢 绿", "#69DB7C"], ["🔵 蓝", "#4DABF7"], ["🟣 紫", "#9775FA"],
            ["🩷 粉", "#F783AC"], ["⚫ 灰", "#868E96"]
            ]
            const EMOJI_CATS = [
            ["常用", [["📁 文件夹","📁"],["📂 打开的文件夹","📂"],["🗂️ 分类文件夹","🗂️"],["📦 包裹","📦"],["⭐ 星标","⭐"],["🔥 热门","🔥"],["💡 灵感","💡"],["❤️ 收藏","❤️"],["✨ 精选","✨"],["📌 置顶","📌"],["🎯 目标","🎯"],["💎 珍藏","💎"]]],
            ["学习", [["📚 书籍","📚"],["📖 阅读","📖"],["✏️ 笔记","✏️"],["📝 备忘录","📝"],["🎓 学业","🎓"],["🔬 研究","🔬"],["🧪 实验","🧪"],["💻 编程","💻"],["🖥️ 工作站","🖥️"],["📐 设计","📐"],["🎨 创意","🎨"],["🎵 音乐","🎵"]]],
            ["生活", [["🏠 主页","🏠"],["🏡 居家","🏡"],["🛒 购物","🛒"],["🍳 烹饪","🍳"],["☕ 咖啡","☕"],["🌿 植物","🌿"],["🎮 游戏","🎮"],["🎬 影视","🎬"],["📷 照片","📷"],["✈️ 旅行","✈️"],["🚗 出行","🚗"],["💰 财务","💰"]]],
            ["符号", [["🔵 蓝点","🔵"],["🟢 绿点","🟢"],["🟡 黄点","🟡"],["🟠 橙点","🟠"],["🔴 红点","🔴"],["🟣 紫点","🟣"],["⚫ 黑点","⚫"],["⚪ 白点","⚪"],["⬛ 方块","⬛"],["🔶 菱形","🔶"],["⚡ 闪电","⚡"],["🌈 彩虹","🌈"]]]
            ]
            const e = contextEntry
            const path = e?.path ?? ""
            const custom = folderCustomFor(path)
            const curColor = custom?.color ?? ""
            const curEmoji = custom?.emoji ?? ""
            const root = []

            if (e) {
                root.push(_ctxAct(defaultOpenText(), "openEntry", ""))
                if (selectedEntries().length === 1)
                    root.push(_ctxAct("重命名", "rename", ""))

                // 自定义外观 applies to every desktop entry. The path-based
                // storage retains the setting across filesystem snapshots.
                const colorKids = FOLDER_COLORS.map(([label, val]) =>
                    _ctxCheck(label, "setColor", val, curColor === val, ""))
                const appearKids = [ _ctxSub("颜色", colorKids, "") ]
                for (const [catTitle, list] of EMOJI_CATS) {
                    const rows = [_ctxCheck("无", "setEmoji", "", curEmoji === "", "")]
                        .concat(list.map(([label, em]) =>
                            _ctxCheck(label, "setEmoji", em, curEmoji === em, "")))
                    const categoryIcon = catTitle === "学习" ? ""
                        : catTitle === "生活" ? ""
                        : catTitle === "符号" ? "" : ""
                    appearKids.push(_ctxSub(catTitle, rows, categoryIcon))
                }
                appearKids.push(_ctxAct("移除自定义", "removeCustom", ""))
                root.push(_ctxSub("自定义外观", appearKids, ""))

                // 打开方式（动态）
                if (canChooseOpenWith(e)) {
                    const owKids = []
                    for (let i = 0; i < 6; i++) {
                        const id = openWithIdAt(i)
                        if (id)
                            owKids.push({ icon: "", label: applicationName(id), cmd: "openWith", value: id, enabled: true })
                    }
                    owKids.push(_ctxAct("其他应用程序…", "openWithMore", ""))
                    root.push(_ctxSub("打开方式", owKids, ""))
                }

                root.push(_ctxAct("复制", "copy", ""))
                root.push(_ctxAct("剪切", "cut", ""))
                root.push(_ctxAct("移到废纸篓", "trash", ""))
                root.push(_ctxAct("在文件管理器中打开", "open", ""))
            } else {
                // desktop background
                root.push(_ctxAct("新建文件", "newFile", ""))
                root.push(_ctxAct("新建文件夹", "newFolder", ""))
                root.push(_ctxAct("粘贴", "paste", ""))
                const arrange = [
                    _ctxAct("按名称", "arrangeByName", ""), _ctxAct("按类型", "arrangeByType", ""),
                    _ctxAct("按修改时间（最新）", "arrangeModifiedNew", ""),
                    _ctxAct("按修改时间（最早）", "arrangeModifiedOld", "")
                ]
                root.push(_ctxSub("整理方式", arrange, ""))
                root.push(_ctxAct("重置图标排序", "resetLayout", ""))
                root.push(_ctxCheck("显示文件扩展名", "toggleExtensions", null,
                    desktopLayout.showExtensions, ""))
                const sizeKids = [[40, "小"], [56, "中"], [72, "大"]]
                    .map(([px, l]) => _ctxCheck(l, "setIconSize", px,
                        iconSize === px, ""))
                root.push(_ctxSub("图标大小", sizeKids, ""))
                root.push(_ctxAct("刷新", "refresh", ""))
            }
            return root
        }

        function setContextMenuItems() {
            desktopContextMenu.setItems(buildContextItems())
        }

        function runContextCmd(cmd, item) {
            const e = contextEntry
            const path = e?.path ?? ""
            const v = item?.value
            switch (cmd) {
            case "openEntry": triggerContextAction("openEntry"); break
            case "rename": triggerContextAction("rename"); break
            case "setColor": setFolderColor(path, v); break
            case "setEmoji": setFolderEmoji(path, v); break
            case "removeCustom": removeFolderCustom(path); break
            case "openWith": root.desktopFiles.launchWith(e, v); break
            case "openWithMore": root.desktopFiles.showKdeOpenWith(e); break
            case "copy": triggerContextAction("copy"); break
            case "cut": triggerContextAction("cut"); break
            case "trash": triggerContextAction("trash"); break
            case "open": triggerContextAction("open"); break
            case "newFile": triggerContextAction("file"); break
            case "newFolder": triggerContextAction("folder"); break
            case "paste": triggerContextAction("paste"); break
            case "arrangeByName": arrangeByName(); break
            case "arrangeByType": arrangeByType(); break
            case "arrangeModifiedNew": arrangeByModified(true); break
            case "arrangeModifiedOld": arrangeByModified(false); break
            case "resetLayout": triggerContextAction("resetLayout"); break
            case "toggleExtensions":
                desktopLayout.showExtensions = !desktopLayout.showExtensions
                desktopLayout.sync()
                break
            case "setIconSize": setIconSize(v); break
            case "refresh": triggerContextAction("refresh"); break
            }
        }

        function indexAt(pointX, pointY) {
            const column = Math.max(0, Math.min(columnCount - 1, Math.floor(pointX / itemWidth)))
            const row = Math.max(0, Math.min(rowCount - 1, Math.floor(pointY / itemHeight)))
            const index = (columnCount - 1 - column) * rowCount + row
            return Math.max(0, Math.min(orderedEntries.length - 1, index))
        }

        function folderAtDropPoint(pointX, pointY, sourcePath) {
            if (!Number.isFinite(pointX) || !Number.isFinite(pointY)
                    || pointX < 0 || pointY < 0
                    || pointX >= width || pointY >= height)
                return null
            // Check the folder's rendered position rather than its original
            // grid cell: a neighbour may currently be shifted by the live
            // reorder preview. The hit area includes the icon and filename,
            // but deliberately leaves the cell gutters free for sorting.
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                if (entry?.kind !== "folder" || entry.path === sourcePath)
                    continue
                const base = gridPositionForIndex(index)
                const offset = reorderPreviewOffsets[entry.path] ?? ({ x: 0, y: 0 })
                const hitWidth = Math.min(itemWidth - 16, iconSize + 40)
                const hitLeft = base.x + offset.x + (itemWidth - hitWidth) / 2
                const hitTop = base.y + offset.y + 5
                const hitHeight = Math.min(itemHeight - 10, iconSize + 42)
                if (pointX >= hitLeft && pointX <= hitLeft + hitWidth
                        && pointY >= hitTop && pointY <= hitTop + hitHeight)
                    return entry
            }
            return null
        }

        Item {
            id: desktopKeyboard
            anchors.fill: parent
            focus: true
            Keys.onPressed: function(event) {
                if (desktopFileGrid.handleClipboardShortcut(event))
                    return
                if (event.key === Qt.Key_Return && !desktopFileGrid.renamingPath
                        && desktopFileGrid.selectedEntries().length === 1) {
                    desktopFileGrid.beginInlineRename(desktopFileGrid.selectedEntries()[0])
                    event.accepted = true
                }
            }
        }

        Connections {
            target: root.desktopFiles
            function onEntriesChanged() {
                // Let orderedEntries and the free-slot surface consume the new
                // service snapshot before focusing the newly-created item.
                Qt.callLater(function() {
                    desktopFileGrid.startPendingRename()
                })
            }
            function onLastErrorChanged() {
                if (root.desktopFiles.lastError)
                    root.sendTimerNotification("桌面文件", root.desktopFiles.lastError)
            }
        }

        DropArea {
            id: externalDesktopDrop
            anchors.fill: parent
            z: 20
            enabled: false
            onEntered: function(drag) {
                // Ignore a desktop icon's own outgoing URI drag.
                drag.accepted = drag.hasUrls && !drag.source
            }
            onDropped: function(drop) {
                if (!drop.hasUrls || drop.source) {
                    drop.accepted = false
                    return
                }
                root.desktopFiles.importExternalUrls(drop.urls)
                drop.accepted = true
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: externalDesktopDrop.containsDrag
            color: Qt.rgba(1, 1, 1, 0.06)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.32) }
            radius: 16
            z: 19
            Text {
                anchors.centerIn: parent
                text: "复制到桌面"
                color: Qt.rgba(1, 1, 1, 0.78)
                font { pixelSize: 13; weight: Font.DemiBold }
            }
        }

        MouseArea {
            id: desktopBackgroundPointer
            anchors.fill: parent
            acceptedButtons: Qt.RightButton | Qt.LeftButton
            enabled: false
            onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    // Right-click is pointer-only: requesting focus here can
                    // interfere with the platform menu's dismissal path.
                    desktopFileGrid.setSelectedPaths([])
                    desktopFileGrid.contextEntry = null
                    desktopFileGrid.showMenu(null,
                        desktopBackgroundPointer.mapToItem(root, mouse.x, mouse.y))
                    return
                }
                desktopContextMenu.hide()
                desktopFileGrid.contextEntry = null
                const point = desktopFileGrid.gridPoint(desktopBackgroundPointer, mouse)
                desktopFileGrid.selectionStartX = point.x
                desktopFileGrid.selectionStartY = point.y
                desktopFileGrid.selectionEndX = point.x
                desktopFileGrid.selectionEndY = point.y
                desktopFileGrid.selectionBoxActive = false
                desktopFileGrid.selectionBase = (mouse.modifiers & Qt.ControlModifier)
                    ? desktopFileGrid.selectedPaths.slice() : []
                desktopFileGrid.activateKeyboard()
            }
            onPositionChanged: function(mouse) {
                if (!pressed || !(mouse.buttons & Qt.LeftButton))
                    return
                const point = desktopFileGrid.gridPoint(desktopBackgroundPointer, mouse)
                desktopFileGrid.selectionEndX = point.x
                desktopFileGrid.selectionEndY = point.y
                if (!desktopFileGrid.selectionBoxActive
                        && (Math.abs(point.x - desktopFileGrid.selectionStartX) > 4
                            || Math.abs(point.y - desktopFileGrid.selectionStartY) > 4))
                    desktopFileGrid.selectionBoxActive = true
                if (desktopFileGrid.selectionBoxActive)
                    desktopFileGrid.selectInBox(
                        desktopFileGrid.selectionStartX, desktopFileGrid.selectionStartY,
                        point.x, point.y, !!(mouse.modifiers & Qt.ControlModifier))
            }
            onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton)
                    return
                const wasBoxSelection = desktopFileGrid.selectionBoxActive
                desktopFileGrid.selectionBoxActive = false
                // A plain empty click clears the selection only after it is
                // known not to have become a drag-selection gesture.
                if (!wasBoxSelection && !(mouse.modifiers & Qt.ControlModifier))
                    desktopFileGrid.setSelectedPaths([])
            }
        }

        Rectangle {
            x: Math.min(desktopFileGrid.selectionStartX, desktopFileGrid.selectionEndX)
            y: Math.min(desktopFileGrid.selectionStartY, desktopFileGrid.selectionEndY)
            width: Math.abs(desktopFileGrid.selectionEndX - desktopFileGrid.selectionStartX)
            height: Math.abs(desktopFileGrid.selectionEndY - desktopFileGrid.selectionStartY)
            opacity: desktopFileGrid.selectionBoxActive ? 1 : 0
            visible: false
            color: Qt.rgba(0, 0, 0, 0.20)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.34) }
            z: 1
            Behavior on opacity {
                NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
            }
        }

        GridView {
            id: desktopFileView
            anchors.fill: parent
            visible: false
            interactive: false
            clip: true
            flow: GridView.FlowLeftToRight
            layoutDirection: Qt.RightToLeft
            verticalLayoutDirection: GridView.TopToBottom
            cellWidth: desktopFileGrid.itemWidth
            cellHeight: desktopFileGrid.itemHeight
            displaced: Transition {
                NumberAnimation { properties: "x,y"; easing.type: Easing.OutQuad }
            }
            model: DelegateModel {
                id: desktopFileVisualModel
                // FreeSlotDesktopDemo is the active desktop implementation.
                // This legacy GridView remains only as dormant reference code;
                // an invisible QML view can still instantiate delegates, which
                // would decode every image thumbnail a second time. Keep its
                // model empty unless it is deliberately made visible again.
                model: desktopFileView.visible
                    ? desktopFileGrid.orderedEntries : []
                delegate: DropArea {
                id: fileDelegate
                required property var modelData
                width: desktopFileView.cellWidth
                height: desktopFileView.cellHeight
                onEntered: function(drag) {
                    desktopFileVisualModel.items.move(
                        drag.source.DelegateModel.itemsIndex,
                        minimalDragIcon.DelegateModel.itemsIndex)
                }

                // Intentionally mirrors Qt's Dynamic View Ordering example:
                // a visual DelegateModel, a DropArea per cell, and one item
                // reparented to the GridView while DragHandler moves it.
                Item {
                    id: minimalDragIcon
                    width: fileDelegate.width
                    height: fileDelegate.height
                    z: minimalDragHandler.active ? 100 : 0
                    Drag.active: minimalDragHandler.active
                    Drag.source: minimalDragIcon
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    states: State {
                        when: minimalDragHandler.active
                        ParentChange { target: minimalDragIcon; parent: desktopFileView.contentItem }
                    }

                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                        text: desktopFileGrid.iconFor(modelData.kind)
                        color: Qt.rgba(1, 1, 1, 0.88)
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.50)
                        font { family: "LXGW WenKai Mono Nerd Font"; pixelSize: desktopFileGrid.iconSize * 0.75 }
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: desktopFileGrid.iconSize + 12; leftMargin: 5; rightMargin: 5 }
                        text: desktopFileGrid.displayName(modelData)
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: "white"
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.72)
                        font { pixelSize: desktopFileGrid.fileNameFontSize; weight: desktopFileGrid.fileNameFontWeight }
                    }
                    DragHandler {
                        id: minimalDragHandler
                        onActiveChanged: {
                            if (!active)
                                desktopFileGrid.saveVisualOrder()
                        }
                    }
                }

                Item {
                    id: fileVisual
                    visible: false
                    width: fileDelegate.width
                    height: fileDelegate.height
                    z: reorderDrag.active ? 100 : 0
                    Drag.active: reorderDrag.active && fileDelegate.draggingSingle
                    Drag.source: fileDelegate
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    states: State {
                        when: reorderDrag.active && fileDelegate.draggingSingle
                        ParentChange { target: fileVisual; parent: desktopFileView.contentItem }
                        PropertyChanges { target: fileVisual; x: fileDelegate.x; y: fileDelegate.y }
                    }

                Rectangle {
                    // Match the actual pointer target rather than colouring
                    // the complete grid cell.  The cell edge stays visibly
                    // and interactively empty for lasso selection.
                    anchors.fill: filePointer
                    radius: 10
                    // Hover is intentionally quieter than selection: both
                    // use the neutral black material introduced above.
                    opacity: desktopFileGrid.isSelected(modelData.path) ? 1
                        : filePointer.containsMouse ? 0.38 : 0
                    color: Qt.rgba(0, 0, 0, 0.46)
                    border { width: 1; color: Qt.rgba(1, 1, 1, 0.28) }
                    Behavior on opacity {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }
                }
                Item {
                    // The target folder shows the exact hold progress rather
                    // than a vague hover state. Releasing before it fills is
                    // always treated as an icon reorder.
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: desktopFileGrid.iconSize + 5 }
                    width: desktopFileGrid.iconSize
                    height: 4
                    visible: modelData.kind === "folder"
                        && desktopFileGrid.folderDropCandidatePath === modelData.path
                    opacity: visible ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.22)
                    }
                    Rectangle {
                        width: parent.width * desktopFileGrid.folderDropProgress
                        height: parent.height
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.88)
                    }
                }
                // Finder-style destination feedback: only actual folders can
                // receive a drop, so files never imply an unsupported action.
                Rectangle {
                    anchors { fill: parent; margins: 3 }
                    radius: 10
                    visible: opacity > 0.01
                    opacity: modelData.kind === "folder"
                        && desktopFileGrid.dropFolderPath === modelData.path ? 1 : 0
                    color: Qt.rgba(0, 0, 0, 0.56)
                    border { width: 1; color: Qt.rgba(1, 1, 1, 0.62) }
                    Behavior on opacity {
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                }
                Item {
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                    width: desktopFileGrid.iconSize
                    height: desktopFileGrid.iconSize
                    scale: (filePointer.containsMouse ? 1.035 : 1)
                        * (fileDelegate.opening ? 0.96 : 1)
                    transform: Translate {
                        y: filePointer.containsMouse ? -2 : 0
                        Behavior on y {
                            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                    }
                    Item {
                        id: imageThumbnailFrame
                        anchors { fill: parent; margins: 4 }
                        visible: modelData.kind === "image"
                        opacity: imageThumbnail.status === Image.Ready ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                        }
                        Image {
                            id: imageThumbnail
                            anchors.fill: parent
                            source: modelData.kind === "image" ? "file://" + modelData.path : ""
                            fillMode: Image.PreserveAspectCrop
                            // Keep this dormant legacy delegate safe if it is
                            // ever re-enabled: desktop thumbnails must never
                            // decode their original multi-megapixel images.
                            sourceSize.width: Math.max(1, Math.ceil(width * 2))
                            sourceSize.height: Math.max(1, Math.ceil(height * 2))
                            asynchronous: true
                            cache: false
                            smooth: true
                            // OpacityMask below renders this source. A plain
                            // Rectangle.clip only clips to a rectangle and
                            // cannot apply radius to the image pixels.
                            visible: false
                        }
                        Rectangle {
                            id: imageThumbnailMask
                            anchors.fill: parent
                            radius: 5
                            visible: false
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: imageThumbnail
                            maskSource: imageThumbnailMask
                        }
                    }
                    IconImage {
                        id: launcherIcon
                        anchors.fill: parent
                        source: modelData.kind === "launcher"
                            ? AppPresentationService.iconSource(modelData.icon) : ""
                        asynchronous: true
                        visible: source !== "" && status === Image.Ready
                    }
                    // Folder icon: a unified Canvas-drawn folder shape used
                    // for both default and customised folders. When a custom
                    // color is set the folder is tinted with it; when an emoji
                    // is set it is drawn centered inside the folder body so
                    // both the folder and the symbol are visible.
                    Item {
                        readonly property var folderCustom: modelData.kind === "folder"
                            ? desktopFileGrid.folderCustomFor(modelData.path) : null
                        anchors.centerIn: parent
                        width: desktopFileGrid.iconSize
                        height: desktopFileGrid.iconSize
                        visible: modelData.kind === "folder"

                        Canvas {
                            id: folderCanvas
                            anchors.fill: parent
                            readonly property color baseColor: {
                                const c = parent.folderCustom
                                if (c && c.color)
                                    return c.color
                                return "#70b6ff"
                            }
                            onBaseColorChanged: requestPaint()
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            function shade(hex, factor) {
                                // Darken/lighten an rgba/hex color by factor
                                // (0..1 = darker, >1 = lighter).
                                const ctx = getContext("2d")
                                const c = Qt.color(hex)
                                const r = Math.max(0, Math.min(255, Math.round(c.r * 255 * factor)))
                                const g = Math.max(0, Math.min(255, Math.round(c.g * 255 * factor)))
                                const b = Math.max(0, Math.min(255, Math.round(c.b * 255 * factor)))
                                return "rgba(" + r + "," + g + "," + b + "," + c.a + ")"
                            }

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const w = width
                                const h = height
                                const margin = w * 0.10
                                const tabH = h * 0.14
                                const bodyX = margin
                                const bodyY = margin + tabH
                                const bodyW = w - margin * 2
                                const bodyH = h - margin - bodyY
                                const r = Math.min(bodyW, bodyH) * 0.18

                                // Back tab (folder flap) - darker shade for depth
                                ctx.fillStyle = folderCanvas.shade(folderCanvas.baseColor, 0.72)
                                ctx.globalAlpha = 0.92
                                ctx.beginPath()
                                ctx.moveTo(bodyX, bodyY)
                                ctx.lineTo(bodyX + bodyW * 0.42, bodyY)
                                ctx.lineTo(bodyX + bodyW * 0.42 + tabH * 0.7, bodyY - tabH)
                                ctx.lineTo(bodyX + bodyW * 0.72, bodyY - tabH)
                                ctx.arcTo(bodyX + bodyW * 0.72 + r, bodyY - tabH,
                                          bodyX + bodyW * 0.72 + r, bodyY - tabH + r, r)
                                ctx.lineTo(bodyX + bodyW * 0.72 + r, bodyY)
                                ctx.closePath()
                                ctx.fill()

                                // Front body - base color fill
                                ctx.fillStyle = folderCanvas.shade(folderCanvas.baseColor, 1.0)
                                ctx.globalAlpha = 0.90
                                roundRect(ctx, bodyX, bodyY, bodyW, bodyH, r)
                                ctx.fill()

                                // Top highlight strip on the front body
                                ctx.fillStyle = "rgba(255,255,255,0.18)"
                                ctx.globalAlpha = 1.0
                                ctx.beginPath()
                                ctx.moveTo(bodyX + r, bodyY)
                                ctx.lineTo(bodyX + bodyW - r, bodyY)
                                ctx.lineTo(bodyX + bodyW - r, bodyY + bodyH * 0.12)
                                ctx.lineTo(bodyX + r, bodyY + bodyH * 0.12)
                                ctx.closePath()
                                ctx.fill()

                                // Subtle inner border for definition
                                ctx.strokeStyle = "rgba(0,0,0,0.16)"
                                ctx.lineWidth = 1
                                roundRect(ctx, bodyX, bodyY, bodyW, bodyH, r)
                                ctx.stroke()
                            }

                            function roundRect(ctx, x, y, w, h, r) {
                                ctx.beginPath()
                                ctx.moveTo(x + r, y)
                                ctx.lineTo(x + w - r, y)
                                ctx.arcTo(x + w, y, x + w, y + r, r)
                                ctx.lineTo(x + w, y + h - r)
                                ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
                                ctx.lineTo(x + r, y + h)
                                ctx.arcTo(x, y + h, x, y + h - r, r)
                                ctx.lineTo(x, y + r)
                                ctx.arcTo(x, y, x + r, y, r)
                                ctx.closePath()
                            }
                        }

                        // Emoji centered inside the folder body.
                        Text {
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                top: parent.top
                                topMargin: parent.height * 0.36
                            }
                            visible: parent.folderCustom && parent.folderCustom.emoji
                            text: parent.folderCustom ? parent.folderCustom.emoji : ""
                            font { family: "Noto Color Emoji"; pixelSize: desktopFileGrid.iconSize * 0.36 }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        // A broken or unsupported image still behaves like a
                        // normal desktop file instead of becoming invisible.
                        // Folders are drawn by the Canvas Item above.
                        visible: (modelData.kind !== "image" || imageThumbnail.status !== Image.Ready)
                            && (modelData.kind !== "launcher" || launcherIcon.status !== Image.Ready)
                            && modelData.kind !== "folder"
                        text: desktopFileGrid.iconFor(modelData.kind)
                        color: Qt.rgba(1, 1, 1, 0.88)
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.50)
                        font { family: "LXGW WenKai Mono Nerd Font"; pixelSize: desktopFileGrid.iconSize * 0.75 }
                    }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: desktopFileGrid.iconSize + 12; leftMargin: 5; rightMargin: 5 }
                    opacity: fileDelegate.isRenaming ? 0 : 1
                    visible: opacity > 0.01
                    text: desktopFileGrid.displayName(modelData)
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    color: "white"
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.72)
                    font { pixelSize: desktopFileGrid.fileNameFontSize; weight: desktopFileGrid.fileNameFontWeight }
                    Behavior on opacity {
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                }
                MouseArea {
                    id: filePointer
                    enabled: false
                    // The complete cell used to be clickable, leaving no
                    // genuine blank area between adjacent files.  Keep a
                    // compact content target around the icon and label.
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: 9
                        rightMargin: 9
                        topMargin: 4
                        bottomMargin: 6
                    }
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onPressed: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            if (!desktopFileGrid.isSelected(modelData.path))
                                desktopFileGrid.selectOnly(modelData.path)
                            desktopFileGrid.contextEntry = modelData
                            desktopFileGrid.showMenu(modelData,
                                fileDelegate.mapToItem(root, mouse.x, mouse.y))
                        } else {
                            fileDelegate.dragEnabled = !(mouse.modifiers & Qt.ControlModifier)
                            if (mouse.modifiers & Qt.ControlModifier)
                                desktopFileGrid.toggleSelection(modelData.path)
                            else if (!desktopFileGrid.isSelected(modelData.path))
                                desktopFileGrid.selectOnly(modelData.path)
                            fileDelegate.dragMoved = false
                            desktopFileGrid.activateKeyboard()
                        }
                    }
                    onClicked: function(mouse) {
                        if (fileDelegate.dragMoved || mouse.button !== Qt.LeftButton
                                || (mouse.modifiers & Qt.ControlModifier))
                            return
                        if (!desktopFileGrid.isSelected(modelData.path)) {
                            desktopFileGrid.selectOnly(modelData.path)
                            return
                        }
                        // Finder icon view enters rename after a second,
                        // deliberately slow click on an already selected item.
                        const now = Date.now()
                        const elapsed = now - previousClickTime
                        previousClickTime = now
                        if (!fileDelegate.dragMoved && elapsed >= 350 && elapsed <= 1200)
                            desktopFileGrid.beginInlineRename(modelData)
                    }
                    onDoubleClicked: function(mouse) {
                        if (fileDelegate.dragMoved || Date.now() < fileDelegate.suppressOpenUntil
                                || mouse.button !== Qt.LeftButton)
                            return
                        fileDelegate.opening = true
                        openFeedback.restart()
                    }
                }
                // DragHandler supplies a direct gesture translation. Unlike
                // MouseArea's positional callback it never derives the next
                // pointer position from an item that is itself transformed.
                DragHandler {
                    id: reorderDrag
                    enabled: false
                    target: fileVisual
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.NoModifier
                    onActiveChanged: {
                        if (active) {
                            fileDelegate.dragHandlerStarted = true
                            fileDelegate.dragMoved = true
                            fileDelegate.draggingSingle = true
                        } else if (fileDelegate.dragHandlerStarted) {
                            if (fileDelegate.draggingSingle)
                                desktopFileGrid.saveVisualOrder()
                            fileDelegate.draggingSingle = false
                            fileDelegate.dragHandlerStarted = false
                        }
                    }
                }
                Timer {
                    id: openFeedback
                    interval: 90
                    repeat: false
                    onTriggered: {
                        fileDelegate.opening = false
                        root.desktopFiles.openEntry(modelData)
                    }
                }
                Rectangle {
                    id: inlineRenameFrame
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: desktopFileGrid.iconSize + 10 }
                    width: Math.min(parent.width - 10, Math.max(68, inlineRenameInput.contentWidth + 18))
                    height: 23
                    radius: 5
                    opacity: fileDelegate.isRenaming ? 1 : 0
                    visible: opacity > 0.01
                    color: "#ffffff"
                    border { width: 1; color: "#0a84ff" }
                    z: 2
                    transform: Translate {
                        y: fileDelegate.isRenaming ? 0 : 2
                        Behavior on y {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    function commit() {
                        if (desktopFileGrid.renamingPath !== modelData.path)
                            return
                        const newName = inlineRenameInput.text.trim()
                        const newPath = root.desktopFiles.directory + "/" + newName
                        // Reject name collisions synchronously so the folder
                        // customisation is not migrated to a path that will
                        // never be created.
                        if (newPath !== modelData.path) {
                            const clash = root.desktopFiles.entries.some(function(e) {
                                return e.path === newPath
                            })
                            if (clash) {
                                root.desktopFiles.lastError = "该名称已被占用"
                                return
                            }
                        }
                        if (root.desktopFiles.renameEntry(modelData, inlineRenameInput.text)) {
                            // Migrate folder customisation to the new path so
                            // renaming a folder does not discard its color/emoji.
                            if (newPath !== modelData.path)
                                desktopFileGrid.migrateFolderCustom(modelData.path, newPath)
                            desktopFileGrid.renamingPath = ""
                        }
                    }
                    onVisibleChanged: {
                        if (!visible)
                            return
                        inlineRenameInput.text = modelData.name
                        inlineRenameInput.forceActiveFocus()
                        inlineRenameInput.select(0, desktopFileGrid.renameSelectionEnd(modelData))
                    }
                    TextInput {
                        id: inlineRenameInput
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        color: "#1d1d1f"
                        selectByMouse: true
                        selectionColor: "#252529"
                        selectedTextColor: "white"
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        font { pixelSize: desktopFileGrid.fileNameFontSize; weight: desktopFileGrid.fileNameFontWeight }
                        onActiveFocusChanged: {
                            if (!activeFocus && fileDelegate.isRenaming)
                                inlineRenameFrame.commit()
                        }
                        Keys.onReturnPressed: function(event) {
                            inlineRenameFrame.commit()
                            event.accepted = true
                        }
                        Keys.onEscapePressed: function(event) {
                            desktopFileGrid.renamingPath = ""
                            event.accepted = true
                        }
                    }
                }
            }
        }

            }
        }

        FreeSlotDesktopDemo {
            id: freeSlotDesktop
            x: -desktopFileGrid.x
            y: -desktopFileGrid.y
            width: root.width
            height: root.height
            validX: desktopFileGrid.x
            validY: desktopFileGrid.y
            validWidth: desktopFileGrid.width
            validHeight: desktopFileGrid.height
            cellWidth: desktopFileGrid.itemWidth
            cellHeight: desktopFileGrid.itemHeight
            iconVisualSize: desktopFileGrid.iconSize + 12
            showExtensions: desktopLayout.showExtensions
            folderCustomizations: desktopFileGrid._folderCustomCache
            renameCallback: function(entry, name) {
                return desktopFileGrid.commitRename(entry, name)
            }
            // Reuse the existing notify-backed service snapshot together with
            // the persisted desktop order. The drag demo only replaces the
            // layout algorithm, not the desktop's data pipeline.
            entries: desktopFileGrid.orderedEntries
            onMoveIntoFolderRequested: function(sourceEntries, targetFolder) {
                root.desktopFiles.moveEntriesToFolder(sourceEntries, targetFolder)
            }
            onSelectedIdsChanged: {
                desktopFileGrid.setSelectedPaths(selectedIds)
            }
            onContextMenuRequested: function(entry, pos) {
                desktopFileGrid.setSelectedPaths(freeSlotDesktop.selectedIds)
                desktopFileGrid.contextEntry = entry
                // freeSlotDesktop is offset by (-gridX,-gridY); translate its
                // local click point back into window coords for the anchor.
                desktopFileGrid.showMenu(entry,
                    Qt.point(pos.x + freeSlotDesktop.x, pos.y + freeSlotDesktop.y))
            }
            onOpenRequested: function(entry) {
                root.desktopFiles.openEntry(entry)
            }
            onActivityRequested: desktopFileGrid.activateKeyboard()
            onExternalUrlsDropped: function(urls, action) {
                root.desktopFiles.importExternalUrls(urls, action)
            }
            z: 30
        }

        // A quiet icon-sized placeholder marks the future slot without
        // moving neighbours, keeping ordering distinct from a folder drop.
        Rectangle {
            id: reorderInsertionMarker
            readonly property int markerColumn: desktopFileGrid.reorderInsertionIndex < 0 ? 0
                : desktopFileGrid.columnCount - 1
                    - Math.floor(desktopFileGrid.reorderInsertionIndex / desktopFileGrid.rowCount)
            readonly property int markerRow: desktopFileGrid.reorderInsertionIndex < 0 ? 0
                : desktopFileGrid.reorderInsertionIndex % desktopFileGrid.rowCount
            x: markerColumn * desktopFileGrid.itemWidth + 7
            y: markerRow * desktopFileGrid.itemHeight + 4
            width: Math.max(36, desktopFileGrid.itemWidth - 14)
            height: Math.max(40, desktopFileGrid.itemHeight - 8)
            radius: 11
            visible: false
            opacity: visible ? 0.42 : 0
            color: Qt.rgba(1, 1, 1, 0.055)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.48) }
            z: 8
            Behavior on opacity {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
        }

        ContextMenu {
            id: desktopContextMenu
            anchorItem: desktopContextAnchor
            position: "bottom"
            placeBelow: true
            baseColor: ThemeService.backgroundColor
            foregroundColor: ThemeService.foregroundColor
            onAction: function(cmd, item) {
                desktopFileGrid.runContextCmd(cmd, item)
            }
        }

        // Kept mapped but invisible (opacity 0 - NOT visible:false, which the
        // compositor window-anchor ignores and falls back to the window corner).
        // It follows the right-click point so the menu opens beside the cursor.
        Item {
            id: desktopContextAnchor
            opacity: 0
            width: 4
            height: 4
        }

        // Desktop-wide dismissal scrim: active only while the context menu is
        // open, so any click on the empty desktop closes it. It does not steal
        // selection/drag events when the menu is closed.
        MouseArea {
            anchors.fill: parent
            z: 999
            enabled: desktopContextMenu.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: desktopContextMenu.hide()
        }

        Rectangle {
            id: desktopDialogScrim
            anchors.fill: parent
            visible: openWithDialog.visible
            color: Qt.rgba(0, 0, 0, 0.22)
            z: 29
            // Modal prompts should never let an outside click activate or
            // rearrange a desktop icon underneath them.
            MouseArea { anchors.fill: parent }
        }

        Rectangle {
            id: openWithDialog
            anchors.centerIn: parent
            width: 340
            height: 250
            radius: 16
            visible: false
            color: Qt.rgba(0.12, 0.12, 0.15, 0.98)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }
            z: 31
            property var entry: null
            property string selectedHandler: ""
            function appName(id) {
                try { return AppIdentityService.resolve(id)?.name || id } catch (_) { return id }
            }
            function show(target) {
                entry = target
                visible = false
                root.desktopFiles.queryOpenWith(target, function(info) {
                    if (openWithDialog.entry?.path !== target?.path)
                        return
                    openWithDialog.selectedHandler = info.defaultId || info.handlers[0] || ""
                    openWithDialog.visible = true
                })
            }
            Text {
                anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 14 }
                text: "打开方式"
                color: "white"
                font { pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 36 }
                text: "“" + (openWithDialog.entry?.name ?? "") + "”"
                color: Qt.rgba(1, 1, 1, 0.54)
                elide: Text.ElideRight
                font.pixelSize: 10
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 57 }
                text: root.desktopFiles.openWith.mime || "未能识别文件类型"
                color: Qt.rgba(1, 1, 1, 0.42)
                font.pixelSize: 9
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; topMargin: 78; bottomMargin: 46 }
                spacing: 4
                Repeater {
                    model: root.desktopFiles.openWith.handlers
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 28
                        radius: 7
                        color: openWithDialog.selectedHandler === modelData
                            ? Qt.rgba(0, 0, 0, 0.54) : Qt.rgba(1, 1, 1, 0.07)
                        Text {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 9; rightMargin: 9 }
                            text: openWithDialog.appName(modelData)
                            color: "white"
                            elide: Text.ElideRight
                            font.pixelSize: 10
                        }
                        MouseArea { anchors.fill: parent; onClicked: openWithDialog.selectedHandler = modelData }
                    }
                }
                Text {
                    visible: root.desktopFiles.openWith.handlers.length === 0
                    text: "系统没有找到可用的关联应用。"
                    color: Qt.rgba(1, 1, 1, 0.52)
                    font.pixelSize: 10
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 12 }
                spacing: 8
                Repeater {
                    model: ["取消", "仅此一次", "设为默认"]
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData === "设为默认" ? 64 : modelData === "仅此一次" ? 64 : 52
                        height: 26
                        radius: 7
                        color: modelData === "设为默认" ? "#4385dc" : Qt.rgba(1, 1, 1, 0.10)
                        opacity: modelData === "取消" || openWithDialog.selectedHandler ? 1 : 0.45
                        Text { anchors.centerIn: parent; text: modelData; color: "white"; font.pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData === "取消") openWithDialog.visible = false
                                else if (openWithDialog.selectedHandler) {
                                    if (modelData === "仅此一次")
                                        root.desktopFiles.launchWith(openWithDialog.entry, openWithDialog.selectedHandler)
                                    else
                                        root.desktopFiles.setDefaultOpenWith(root.desktopFiles.openWith.mime, openWithDialog.selectedHandler)
                                    openWithDialog.visible = false
                                }
                            }
                        }
                    }
                }
            }
            Keys.onEscapePressed: openWithDialog.visible = false
        }

    }
}
