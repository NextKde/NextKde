import QtQuick

Item {
    id: root

    property color fillColor: AppTheme.cardSurface
    property color strokeColor: AppTheme.border
    property real strokeWidth: 1
    property real radius: AppTheme.mediumRadius
    property real elevation: 0.5
    property bool hovered: false
    property bool pressed: false
    property bool focused: false
    property bool showInnerHighlight: true

    readonly property real effectiveElevation: Math.max(0, elevation)
        * (pressed ? 0.42 : (hovered ? 1.18 : 1))

    implicitWidth: 48
    implicitHeight: AppTheme.controlHeight

    // Two inexpensive translucent layers create a restrained ambient/key
    // shadow without allocating a ShaderEffect for every list delegate.
    Rectangle {
        x: -2
        y: root.pressed ? 1 : 2
        width: root.width + 4
        height: root.height + 5
        radius: root.radius + 3
        color: AppTheme.shadowAmbient
        opacity: root.effectiveElevation
        visible: opacity > 0.001
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: AppTheme.motionFast }
        }
    }

    Rectangle {
        x: -1
        y: root.pressed ? 1 : 2
        width: root.width + 2
        height: root.height + 2
        radius: root.radius + 1
        color: AppTheme.shadowKey
        opacity: root.effectiveElevation * 0.72
        visible: opacity > 0.001
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: AppTheme.motionFast }
        }
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.radius
        color: root.fillColor
        border.width: root.focused ? Math.max(2, root.strokeWidth)
                                   : root.strokeWidth
        border.color: root.focused ? AppTheme.focusRing
            : (root.hovered ? AppTheme.borderHover : root.strokeColor)
        antialiasing: true

        Behavior on color {
            ColorAnimation { duration: AppTheme.motionFast }
        }
        Behavior on border.color {
            ColorAnimation { duration: AppTheme.motionFast }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: Math.max(1, surface.border.width)
            radius: Math.max(0, parent.radius - anchors.margins)
            color: "transparent"
            border.width: root.showInnerHighlight ? 1 : 0
            border.color: AppTheme.innerHighlight
        }
    }
}
