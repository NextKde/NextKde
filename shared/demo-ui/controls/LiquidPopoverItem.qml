import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

MenuItem {
    id: root
    property string iconName: ""
    property real iconStrokeWidth: 1.6
    implicitHeight: 30
    implicitWidth: implicitContentWidth + leftPadding + rightPadding
    leftPadding: 8
    rightPadding: 8
    font.pixelSize: 13
    font.weight: Font.Normal
    indicator: null
    arrow: null
    contentItem: Item {
        implicitWidth: label.implicitWidth + (root.iconName ? 24 : 0)
        implicitHeight: 18
        VectorIcon {
            visible: root.iconName !== ""
            name: root.iconName
            strokeWidth: root.iconStrokeWidth
            width: 16
            height: 16
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.enabled ? Foundation.AppTheme.text : Foundation.AppTheme.disabledText
        }
        Text {
            id: label
            anchors.left: parent.left
            anchors.leftMargin: root.iconName ? 24 : 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font: root.font
            color: root.enabled ? Foundation.AppTheme.text : Foundation.AppTheme.disabledText
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: 6
        color: root.enabled && (root.highlighted || root.hovered || root.down)
            ? (Foundation.AppTheme.dark ? "#24FFFFFF" : "#10000000") : "transparent"
    }
}
