import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var settings: ({})
    property var appearance: null
    signal apply(var next)

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool format24h: root.settings?.format24h !== false

    implicitWidth: 232
    implicitHeight: column.implicitHeight + 24

    Column {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Label {
            text: root.isZh ? "时钟设置" : "Clock Settings"
            font.weight: Font.DemiBold
        }

        Row {
            width: column.width
            spacing: 8

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: column.width - timeSwitch.implicitWidth - 8
                text: root.isZh ? "24 小时制" : "24-hour time"
            }
            Switch {
                id: timeSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: root.format24h
                onToggled: root.apply(Object.assign({}, root.settings, { format24h: checked }))
            }
        }
    }
}
