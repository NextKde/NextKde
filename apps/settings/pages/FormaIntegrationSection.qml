import Kos.Demo as Demo
import QtQuick
import QtQuick.Layouts
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: section
    objectName: "formaIntegrationSection"
    required property var colors
    property var bridge: null
    property var state: ({ready: false, enabled: false, busy: false, applications: []})
    property bool requestPending: false
    readonly property bool busy: requestPending || state.busy === true
    readonly property bool available: state.available === true || state.ready === true
    readonly property var applications: state.applications || []
    readonly property var availableApps: applications.filter(app => app.installed === true)
    readonly property var missingApps: applications.filter(app => app.installed !== true)
    readonly property string errorText: state.error || ""
    Layout.fillWidth: true
    spacing: 8

    function refresh() {
        if (!bridge || requestPending)
            return;
        bridge.formaIntegrationSnapshot();
    }

    function requestEnabled(enabled) {
        if (!bridge || busy || !available || (enabled && state.restorePending === true))
            return;
        requestPending = true;
        bridge.setFormaIntegrationEnabled(enabled);
    }

    Connections {
        target: section.bridge
        enabled: section.bridge !== null
        function onFormaIntegrationSnapshotChanged(snapshot) {
            section.requestPending = false;
            section.state = snapshot;
        }
    }

    Demo.SettingsGroup {
        title: I18n.tr("Forma applications")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Enable Forma")
            description: I18n.tr("Use installed Forma apps for files, media and desktop actions. KOS Settings stays unchanged.")
            Controls.SettingsSwitch {
                objectName: "enableFormaSwitch"
                enabled: section.bridge !== null && section.available && !section.busy
                    && section.state.restorePending !== true
                checked: section.state.enabled === true
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function(checked) { section.requestEnabled(checked); }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Available Forma apps: %1").arg(section.availableApps.length)
            description: section.busy ? I18n.tr("Applying application preferences…")
                : I18n.tr("Missing apps are skipped. No software is installed or removed.")
            Demo.LiquidActionButton {
                objectName: "reapplyFormaButton"
                text: I18n.tr("Apply again")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                enabled: section.bridge !== null && section.state.ready === true
                    && section.state.enabled === true && section.state.restorePending !== true && !section.busy
                onClicked: section.requestEnabled(true)
            }
        }
        Demo.SettingsItem {
            visible: section.state.restorePending === true
            title: I18n.tr("Restore previous preferences")
            description: I18n.tr("A previous change did not finish. Restore it before applying Forma again.")
            Demo.LiquidActionButton {
                objectName: "restoreFormaButton"
                text: I18n.tr("Restore")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                enabled: section.bridge !== null && section.available && !section.busy
                onClicked: section.requestEnabled(false)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: section.state.terminalCommandSupported === false
            && section.availableApps.some(app => app.role === "terminal")
        text: I18n.tr("Forma Terminal opens from the Dock. Command-line apps keep their existing terminal because Forma does not yet support command execution.")
        color: colors.secondaryText
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: section.missingApps.length > 0
        text: I18n.tr("Not installed: %1").arg(section.missingApps.map(app => app.name).join(", "))
        color: colors.secondaryText
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: I18n.tr("Turning Forma off restores preferences still owned by Forma. Later manual changes are kept.")
        color: colors.secondaryText
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
    Text {
        objectName: "formaIntegrationError"
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: section.errorText.length > 0
        text: I18n.tr(section.errorText)
        color: colors.role ? colors.role("error", "#ff453a") : "#ff453a"
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
    Timer {
        interval: section.busy || (section.state.ready !== true && !section.errorText) ? 250 : 5000
        repeat: true
        running: section.visible && section.bridge !== null
        onTriggered: section.refresh()
    }
    Component.onCompleted: refresh()
}
