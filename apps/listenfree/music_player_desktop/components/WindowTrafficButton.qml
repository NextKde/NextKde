pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: control

    property string action: "close"
    property color fillColor: "#ff5f57"
    property bool revealGlyph: false
    property bool reducedMotion: false
    signal clicked

    implicitWidth: 22
    implicitHeight: AppTheme.toolbarControlHeight

    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: 18
        height: 18
        radius: 9
        color: control.fillColor
        border.width: 1
        border.color: Qt.darker(control.fillColor, 1.28)
        scale: trafficTap.pressed ? .88 : localHover.hovered ? 1.04 : 1

        Behavior on scale {
            NumberAnimation {
                duration: control.reducedMotion ? 0 : AppTheme.duration(90)
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: glyph
            anchors.centerIn: parent
            width: 9
            height: 9
            opacity: control.revealGlyph ? .72 : 0

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 1.35
                radius: height / 2
                color: "#000000"
                rotation: 45
                antialiasing: true
                visible: control.action === "close"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 1.35
                radius: height / 2
                color: "#000000"
                rotation: -45
                antialiasing: true
                visible: control.action === "close"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 1.35
                radius: height / 2
                color: "#000000"
                antialiasing: true
                visible: control.action === "minimize"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: .6
                color: "transparent"
                border.width: 1.2
                border.color: "#000000"
                antialiasing: true
                visible: control.action === "maximize"
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: control.reducedMotion ? 0 : AppTheme.duration(115)
                    easing.type: control.revealGlyph ? Easing.OutCubic : Easing.InCubic
                }
            }
        }
    }

    HoverHandler { id: localHover }
    TapHandler {
        id: trafficTap
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: control.clicked()
    }
}
