import QtQuick
import QtQuick.Effects

// iOS-style liquid glass button with pure QML rendering.
// No external texture needed - uses mathematical gradients to simulate refraction.
Item {
    id: root

    // Public API
    property string symbol: ""
    property bool primary: false
    property bool enabled: true
    property color accentColor: "#0a84ff"
    signal triggered()

    // Internal state
    property bool _pressed: false
    property bool _hovered: false

    // Size
    implicitWidth: primary ? 52 : 40
    implicitHeight: implicitWidth

    // Expansion animation (0 = rest, 1 = fully expanded glass)
    property real _expansion: _pressed ? 1.0 : (_hovered ? 0.3 : 0.0)
    Behavior on _expansion {
        NumberAnimation {
            duration: _pressed ? 200 : 350
            easing.type: _pressed ? Easing.OutBack : Easing.OutQuint
            easing.overshoot: _pressed ? 1.4 : 1.0
        }
    }

    // Squash-stretch wobble on press
    property real _stretch: 0.0
    SequentialAnimation on _stretch {
        id: wobbleAnim
        running: false
        NumberAnimation { to: 0.15; duration: 80; easing.type: Easing.OutQuad }
        NumberAnimation { to: -0.06; duration: 120; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.03; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 80; easing.type: Easing.OutQuad }
    }

    opacity: enabled ? 1.0 : 0.5
    scale: _pressed ? 0.92 : (_hovered ? 1.05 : 1.0)
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // Drop shadow (fades out as glass expands)
    Rectangle {
        id: shadow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        width: parent.width * 0.9
        height: parent.height * 0.9
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: (1 - root._expansion) * 0.6
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // Glass body - multi-layer gradients simulate refraction
    Item {
        id: glassBody
        anchors.centerIn: parent
        width: parent.width * (0.85 + 0.35 * root._expansion) * (1 - 0.15 * root._stretch)
        height: parent.height * (0.85 + 0.35 * root._expansion) * (1 + 0.25 * root._stretch)

        // Layer 1: Base glass with radial gradient (edge bright, center dark)
        Rectangle {
            id: baseGlass
            anchors.fill: parent
            radius: width / 2

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.25 + 0.15 * root._expansion) }
                GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.12 + 0.08 * root._expansion) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.06 + 0.04 * root._expansion) }
                GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.10 + 0.06 * root._expansion) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.20 + 0.10 * root._expansion) }
            }

            // Inner rim light
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35 + 0.25 * root._expansion)
            }
        }

        // Layer 2: Chromatic aberration (RGB split edges)
        // Red channel offset
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 0.25, 0.25, 0.20 * root._expansion)
            x: -0.5
            visible: root._expansion > 0.1
        }
        // Cyan channel offset
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.25, 0.85, 1, 0.20 * root._expansion)
            x: 0.5
            visible: root._expansion > 0.1
        }

        // Layer 3: Specular highlight (soft, top-positioned)
        Rectangle {
            id: specular
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.08
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.45
            height: parent.height * 0.28
            radius: width / 2

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45 + 0.25 * root._expansion) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.15 + 0.10 * root._expansion) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
            }
            opacity: 0.6 + 0.4 * root._expansion
        }

        // Layer 4: Accent tint (subtle color bleed when expanded)
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.accentColor
            opacity: 0.08 * root._expansion
        }

        // Layer 5: Inner glow (soft fill from edges)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.08 * root._expansion)
        }
    }

    // Icon (crisp layer on top)
    Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.symbol === "▶" ? 1 : 0
        text: root.symbol
        color: "white"
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.45)
        font.pixelSize: root.primary ? 16 : 12
        font.weight: Font.Medium
    }

    // Interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: root._hovered = true
        onExited: root._hovered = false

        onPressed: {
            root._pressed = true
            wobbleAnim.restart()
        }

        onReleased: {
            root._pressed = false
            root.triggered()
        }

        onCanceled: {
            root._pressed = false
        }
    }
}
