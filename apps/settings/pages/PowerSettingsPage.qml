import Kos.Demo as Demo
import "../components" as Controls
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
        {
            key: "power-saver",
            title: I18n.tr("Power Saver"),
            detail: I18n.tr("Reduce energy use and extend battery life")
        },
        {
            key: "balanced",
            title: I18n.tr("Balanced"),
            detail: I18n.tr("Balance responsiveness and energy use")
        },
        {
            key: "performance",
            title: I18n.tr("Performance"),
            detail: I18n.tr("Prioritize performance with higher energy use")
        }
    ]
    spacing: 12
    Component.onCompleted: {
        if (backend)
            backend.refresh();
    }
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive && page.backend)
                page.backend.refresh();
        }
    }
    Demo.SettingsGroup {
        title: I18n.tr("Power mode")
        backgroundColor: page.colors.card
        Repeater {
            model: page.modes
            delegate: Demo.SettingsItem {
                id: modeRow
                required property var modelData
                readonly property bool supported: (page.snapshot.profiles || []).includes(modelData.key)
                readonly property bool selected: page.snapshot.activeProfile === modelData.key
                objectName: "powerMode-" + modelData.key
                title: modelData.title
                description: modelData.detail
                enabled: supported && !page.snapshot.busy
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                Accessible.onPressAction: {
                    if (enabled)
                        page.backend.setProfile(modelData.key);
                }
                Text {
                    text: modeRow.selected ? "✓" : ""
                    color: page.colors.accent
                    font.pixelSize: 16
                }
                property Item activationArea: MouseArea {
                    parent: modeRow
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.backend.setProfile(modeRow.modelData.key)
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: page.snapshot.busy ? I18n.tr(page.snapshot.pendingProfile ? "Changing power mode…" : "Loading power modes…") : page.snapshot.error ? I18n.tr(page.snapshot.error) : I18n.tr("Only power modes supported by this computer can be selected.")
        wrapMode: Text.Wrap
        color: page.colors.secondaryText
        font.pixelSize: 11
    }
    Text {
        visible: !!page.snapshot.degraded
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: I18n.tr("Performance is limited: %1").arg(page.snapshot.degraded || "")
        wrapMode: Text.Wrap
        color: page.colors.secondaryText
        font.pixelSize: 11
    }
}
