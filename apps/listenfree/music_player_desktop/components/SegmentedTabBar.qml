pragma ComponentBehavior: Bound

import QtQuick

Rectangle {
    id: root

    property var model: []
    property int currentIndex: 0
    property real cellWidth: 72
    property real cellHeight: 40
    property real cellRadius: cellHeight / 2
    property real outerPadding: 2
    property color accentColor: AppTheme.textPrimary
    property color textColor: AppTheme.textPrimary
    property color selectedBackground: AppTheme.tabSelected
    property color hoverBackground: "#24ffffff"
    property bool darkMode: AppTheme.darkMode
    property bool reduceMotion: false
    property bool controlled: false
    signal selected(int index, var value)

    implicitWidth: repeater.count * cellWidth + outerPadding * 2
    implicitHeight: cellHeight + outerPadding * 2
    radius: height / 2
    clip: true
    color: darkMode ? "#66303a43" : "#38ffffff"
    border.width: 1
    border.color: darkMode ? "#38ffffff" : "#2c000000"

    Rectangle {
        x: root.outerPadding
        y: (root.height - height) / 2
        width: root.cellWidth
        height: root.cellHeight
        radius: root.cellRadius
        color: root.selectedBackground
        Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : AppTheme.duration(150) } }
        transform: Translate {
            x: root.currentIndex * root.cellWidth
            Behavior on x {
                NumberAnimation {
                    duration: root.reduceMotion ? 0 : AppTheme.duration(220)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                }
            }
        }
    }

    Row {
        x: root.outerPadding
        y: (root.height - height) / 2

        Repeater {
            id: repeater
            model: root.model

            delegate: Rectangle {
                id: tabCell
                required property int index
                required property var modelData
                width: root.cellWidth
                height: root.cellHeight
                radius: root.cellRadius
                color: cellHover.hovered && tabCell.index !== root.currentIndex
                       ? root.hoverBackground : "transparent"

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    text: typeof tabCell.modelData === "string" ? tabCell.modelData
                                                                  : (tabCell.modelData.label || tabCell.modelData.title || "")
                    color: tabCell.index === root.currentIndex ? root.accentColor
                                                       : root.textColor
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 13
                    font.weight: tabCell.index === root.currentIndex ? Font.Bold : Font.Medium
                }

                HoverHandler { id: cellHover }
                TapHandler {
                    onTapped: {
                        if (!root.controlled) root.currentIndex = tabCell.index
                        root.selected(tabCell.index, tabCell.modelData)
                    }
                }
            }
        }
    }
}
