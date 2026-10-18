import QtQuick
import QtQuick.Layouts
import "../../../shared/qml/i18n"

ColumnLayout {
    id: page
    objectName: "powerSettingsPage"
    required property var colors
    property bool materialForm: false
    property var backend: null
    readonly property var snapshot: backend ? backend.state : ({})
    readonly property var modes: [
        { key: "power-saver", title: I18n.tr("Power Saver"), detail: I18n.tr("Reduce energy use and extend battery life") },
        { key: "balanced", title: I18n.tr("Balanced"), detail: I18n.tr("Balance responsiveness and energy use") },
        { key: "performance", title: I18n.tr("Performance"), detail: I18n.tr("Prioritize performance with higher energy use") }
    ]
    spacing: 10
    Component.onCompleted: { if (backend) backend.refresh() }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && page.backend)
                page.backend.refresh()
        }
    }
    Text {
        text: I18n.tr("Power mode")
        color: page.colors.secondaryText; font.pixelSize: 12; font.weight: Font.DemiBold
        Layout.leftMargin: 13
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: rows.implicitHeight
        radius: page.materialForm ? 20 : 18
        color: page.colors.card
        Column {
            id: rows
            width: parent.width
            Repeater {
                model: page.modes
                delegate: Item {
                    id: modeRow
                    required property var modelData
                    required property int index
                    readonly property bool supported: (page.snapshot.profiles || []).includes(modelData.key)
                    readonly property bool selected: page.snapshot.activeProfile === modelData.key
                    objectName: "powerMode-" + modelData.key
                    width: rows.width; height: 72
                    enabled: supported && !page.snapshot.busy
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData.title
                    Accessible.checked: selected
                    Accessible.onPressAction: { if (enabled) page.backend.setProfile(modelData.key) }
                    RowLayout {
                        anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                        spacing: 14
                        ColumnLayout {
                            Layout.fillWidth: true
                            opacity: modeRow.supported ? 1 : 0.4
                            spacing: 3
                            Text { text: modeRow.modelData.title; color: page.colors.primaryText; font.pixelSize: 14 }
                            Text {
                                text: modeRow.modelData.detail
                                color: page.colors.secondaryText; font.pixelSize: 11
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                            }
                        }
                        Text { text: modeRow.selected ? "✓" : ""; color: page.colors.accent; font.pixelSize: 18 }
                    }
                    Rectangle {
                        visible: modeRow.index < page.modes.length - 1
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18 }
                        height: 1; color: page.colors.separator
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.backend.setProfile(modeRow.modelData.key)
                    }
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
        text: page.snapshot.busy ? I18n.tr(page.snapshot.pendingProfile ? "Changing power mode…" : "Loading power modes…")
            : page.snapshot.error ? I18n.tr(page.snapshot.error)
            : I18n.tr("Only power modes supported by this computer can be selected.")
        wrapMode: Text.Wrap; color: page.colors.secondaryText; font.pixelSize: 11
    }
    Text {
        visible: !!page.snapshot.degraded
        Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
        text: I18n.tr("Performance is limited: %1").arg(page.snapshot.degraded || "")
        wrapMode: Text.Wrap; color: page.colors.secondaryText; font.pixelSize: 11
    }
}
