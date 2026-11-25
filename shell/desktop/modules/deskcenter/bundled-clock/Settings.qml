import QtQuick
import QtQuick.Controls

// Optional per-SDK-convention settings view (see
// docs/plugins/WidgetSDK.zh-CN.md section 6). Present only if the package
// wants a configuration surface; the host decides whether and how to show
// it (currently: a gear affordance on the card that opens this inside a
// host-drawn floating popup). Like Widget.qml, this file never creates its
// own window and never touches the real data/IPC layer itself -- it only
// edits a plain settings object and hands the result back to the host.
Item {
    id: root

    required property var data
    signal apply(var next)

    implicitWidth: 220
    implicitHeight: column.implicitHeight + 24

    Column {
        id: column
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Label {
            text: qsTr("Clock Settings")
            font.weight: Font.DemiBold
        }

        Row {
            width: column.width
            spacing: 8

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("24-hour time")
            }
            Switch {
                anchors.verticalCenter: parent.verticalCenter
                checked: root.data.format24h === true
                onToggled: root.apply({ format24h: checked })
            }
        }
    }
}
