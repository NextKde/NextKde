import QtQuick

// Compact iOS-style slider for continuous color ramps. The caller owns the
// value so preview updates can remain local and persistence can happen only
// after the pointer is released.
Item {
    id: root

    implicitWidth: 250
    implicitHeight: 26

    property real value: 0.5
    property var rampColors: []
    property color thumbColor: "#ffffff"
    property bool enabled: true

    signal previewChanged(real value)
    signal commitRequested(real value)

    readonly property real clampedValue: Math.max(0, Math.min(1, value))
    readonly property real thumbDiameter: 18
    readonly property real trackInset: thumbDiameter / 2
    readonly property real travel: Math.max(1, width - trackInset * 2)
    readonly property real thumbCenterX: trackInset + clampedValue * travel

    opacity: enabled ? 1 : 0.45

    function rampColor(index) {
        return rampColors.length > index ? rampColors[index] : "transparent"
    }

    function valueAt(pointerX) {
        return Math.max(0, Math.min(1, (pointerX - trackInset) / travel))
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.trackInset
        anchors.rightMargin: root.trackInset
        anchors.verticalCenter: parent.verticalCenter
        height: 8
        radius: height / 2
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.16)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0 / 6; color: root.rampColor(0) }
            GradientStop { position: 1 / 6; color: root.rampColor(1) }
            GradientStop { position: 2 / 6; color: root.rampColor(2) }
            GradientStop { position: 3 / 6; color: root.rampColor(3) }
            GradientStop { position: 4 / 6; color: root.rampColor(4) }
            GradientStop { position: 5 / 6; color: root.rampColor(5) }
            GradientStop { position: 6 / 6; color: root.rampColor(6) }
        }
    }

    Rectangle {
        x: root.thumbCenterX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.thumbDiameter
        height: width
        radius: width / 2
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)
        scale: pointerArea.pressed ? 1.12 : 1

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: width / 2
            color: root.thumbColor
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.12)
        }
    }

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor

        onPressed: function(mouse) {
            root.previewChanged(root.valueAt(mouse.x))
        }
        onPositionChanged: function(mouse) {
            if (pressed)
                root.previewChanged(root.valueAt(mouse.x))
        }
        onReleased: root.commitRequested(root.value)
    }
}
