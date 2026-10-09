import QtQuick
import QtQuick.Controls as Basic

Item {
    id: root

    property string kind: "play"
    property string tooltip: ""
    Basic.ToolTip.visible: hover.hovered && tooltip.length > 0
    Basic.ToolTip.text: tooltip
    Basic.ToolTip.delay: 500
    // Compatibility with call sites that use the sidebar/button naming scheme.
    // `kind` remains the canonical public API; setting iconKind overrides it.
    property string iconKind: ""
    property real diameter: 36
    property real glyphSize: diameter * .52
    property color hoverColor: AppTheme.actionHover
    property color pressedColor: AppTheme.actionPressed
    property bool prominent: false
    property bool transparentSurface: kind === "chevronDown" || kind === "chevronLeft" || kind === "back"
    property bool glassSurface: false
    property bool raisedSurface: false
    readonly property bool pressed: tap.pressed
    readonly property color raisedEdgeColor: darkMode ? "#36ffffff" : "#d9ffffff"
    readonly property real raisedShadowOpacity: pressed ? .10 : darkMode ? .30 : .22
    readonly property real raisedShadowOffset: pressed ? 1 : 4
    property bool darkMode: false
    property bool reducedMotion: false
    property bool holdEnabled: false
    property int holdDuration: 700
    property real holdProgress: 0
    property bool holdConsumed: false
    property int volumeLevel: 3
    property real glyphRotation: 0
    property color glyphColor: darkMode ? "#eef2f5" : "#394149"
    property color accentColor: AppTheme.accent
    property color surfaceColor: raisedSurface ? (darkMode ? "#e0444e58" : "#edf4f8fa")
                                             : darkMode ? (prominent ? "#30ffffff" : "#18ffffff") : (prominent ? "#32606a74" : "#22606a74")
    signal clicked
    signal longPressed
    signal wheelScrolled(var event)

    width: diameter
    height: diameter
    scale: tap.pressed ? 0.96 : hover.hovered ? 1.025 : 1

    Behavior on scale {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : AppTheme.duration(120)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
        }
    }

    // Raised controls opt into the island's separate button layer. Other uses
    // keep the existing flat surface and transparent navigation treatment.
    Rectangle {
        anchors.fill: parent
        visible: !root.transparentSurface && !root.glassSurface && !root.raisedSurface
        radius: root.diameter / 2
        color: root.surfaceColor
        border.width: root.prominent ? 0 : 1
        border.color: root.darkMode ? "#15ffffff" : "#0b283847"
    }

    Loader {
        anchors.fill: parent
        active: (root.glassSurface || root.raisedSurface) && !root.transparentSurface
        sourceComponent: GlassSurface {
            cornerRadius: root.diameter / 2
            tint: root.raisedSurface ? root.surfaceColor : root.darkMode ? "#203a4249" : "#20606a74"
            edgeColor: root.raisedSurface ? root.raisedEdgeColor : root.prominent ? "#58ffffff" : root.darkMode ? "#4cffffff" : "#d9ffffff"
            softShadow: root.raisedSurface
            shadowOpacity: root.raisedSurface ? root.raisedShadowOpacity : root.prominent ? 0.2 : root.darkMode ? 0.2 : 0.12
            shadowOffset: root.raisedSurface ? root.raisedShadowOffset : 7
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: tap.pressed ? root.pressedColor : hover.hovered ? root.hoverColor : "transparent"
    }

    Canvas {
        id: holdRing
        x: -3; y: -3
        width: root.diameter + 6; height: width
        visible: root.holdEnabled && root.holdProgress > 0
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const center = width / 2
            const radius = center - 1.5
            ctx.lineWidth = 1.5
            ctx.strokeStyle = root.darkMode || root.transparentSurface ? "rgba(255,255,255,0.16)" : "rgba(57,65,73,0.16)"
            ctx.beginPath(); ctx.arc(center, center, radius, 0, Math.PI * 2); ctx.stroke()
            ctx.strokeStyle = root.darkMode || root.transparentSurface ? "rgba(255,255,255,0.72)" : "rgba(57,65,73,0.7)"
            ctx.beginPath(); ctx.arc(center, center, radius, -Math.PI / 2,
                                     -Math.PI / 2 + Math.PI * 2 * root.holdProgress); ctx.stroke()
        }
    }
    onHoldProgressChanged: holdRing.requestPaint()
    NumberAnimation { id: holdFill; target: root; property: "holdProgress"; from: 0; to: 1; duration: root.holdDuration }
    Timer {
        id: holdTimer
        interval: root.holdDuration
        onTriggered: if (tap.pressed && tap.containsMouse) { root.holdConsumed = true; root.longPressed() }
    }

    IconGlyph {
        anchors.centerIn: parent
        width: root.glyphSize
        height: width
        kind: root.iconKind.length > 0 ? root.iconKind : root.kind
        glyphColor: root.glyphColor
        volumeLevel: root.volumeLevel
        rotation: root.glyphRotation

        Behavior on rotation {
            NumberAnimation {
                duration: root.reducedMotion ? 0 : AppTheme.duration(180)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
            }
        }
    }

    HoverHandler { id: hover }
    opacity: enabled ? 1 : .38
    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: root.holdEnabled
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            root.holdConsumed = false
            if (root.holdEnabled) { root.holdProgress = 0; holdFill.start(); holdTimer.start() }
        }
        onReleased: { holdFill.stop(); holdTimer.stop(); root.holdProgress = 0 }
        onCanceled: { holdFill.stop(); holdTimer.stop(); root.holdProgress = 0 }
        onExited: if (pressed) { holdFill.stop(); holdTimer.stop(); root.holdProgress = 0 }
        onClicked: if (!root.holdConsumed) root.clicked()
        onWheel: wheel => { root.wheelScrolled(wheel); wheel.accepted = true }
    }
}
