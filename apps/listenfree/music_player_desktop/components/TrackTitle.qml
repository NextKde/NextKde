import QtQuick

Item {
    id: root
    property alias text: title.text
    property alias color: title.color
    property alias font: title.font
    property bool waiting: false
    implicitHeight: Math.max(title.implicitHeight, 18)
    implicitWidth: title.implicitWidth + (waiting ? 24 : 0)
    Text {
        id: title
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - (root.waiting ? 24 : 0))
        elide: Text.ElideRight
        font.family: AppTheme.fontFamily
    }
    LoadingIndicator {
        objectName: "trackWaitingIndicator"
        x: Math.min(title.implicitWidth, title.width) + 4
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18
        color: root.color
        visible: root.waiting
        description: qsTr("正在寻找或加载音源")
    }
}
