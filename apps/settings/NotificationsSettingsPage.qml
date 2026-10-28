import "components" as SettingsControls
import Kos.Demo as Demo
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/i18n"

ColumnLayout {
    id: page
    required property var theme
    property var bridge: null
    property var state: ({})
    property bool pending: false
    property string errorText: ""
    property string appFilter: ""
    readonly property bool ready: state.ready === true && bridge !== null
    readonly property var applications: (state.sources || []).filter(source => source.appName.toLowerCase().indexOf(appFilter.toLowerCase()) >= 0)
    spacing: 12
    function refresh() {
        if (!bridge || pending)
            return;
        pending = true;
        bridge.notificationSnapshot();
    }
    function setPreference(key, value) {
        if (!ready || pending)
            return;
        pending = true;
        bridge.setNotificationPreference(key, value);
    }
    Connections {
        target: page.bridge
        enabled: page.bridge !== null
        function onNotificationSnapshotChanged(snapshot) {
            page.pending = false;
            if (snapshot.ready !== undefined)
                page.state = snapshot;
            page.errorText = page.bridge.lastError || snapshot.saveError || "";
        }
    }
    Component.onCompleted: refresh()
    // Synchronize changes made by the Control Center and newly discovered apps.
    Timer {
        interval: 2500
        running: page.visible && page.bridge !== null
        repeat: true
        onTriggered: page.refresh()
    }
    Text {
        Layout.fillWidth: true
        text: I18n.tr("The notification center shows the latest three message cards; expand it to browse everything. Long messages expand on click.")
        color: page.theme.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 13
    }
    Demo.SettingsGroup {
        title: I18n.tr("Notifications")
        backgroundColor: page.theme.card
        Repeater {
            model: [
                {
                    key: "doNotDisturbEnabled",
                    title: I18n.tr("Do Not Disturb"),
                    detail: I18n.tr("Pauses notification banners; messages still land in history")
                },
                {
                    key: "bannersEnabled",
                    title: I18n.tr("Show notification banners"),
                    detail: I18n.tr("Show a popup banner when a new message arrives")
                },
                {
                    key: "soundEnabled",
                    title: I18n.tr("Play notification sounds"),
                    detail: I18n.tr("Play the built-in tone for new notifications. Off by default; Do Not Disturb silences it.")
                },
                {
                    key: "historyEnabled",
                    title: I18n.tr("Keep notification history"),
                    detail: I18n.tr("Keeps the latest 50 messages of this session; turning it off stops saving new ones")
                },
                {
                    key: "showPreview",
                    title: I18n.tr("Show message previews"),
                    detail: I18n.tr("Hides titles and bodies in the notification center and banners when off")
                },
                {
                    key: "showNotificationBadges",
                    title: I18n.tr("Show notification badges"),
                    detail: I18n.tr("Shows counts and alert dots on Dock app icons")
                }
            ]
            delegate: Demo.SettingsItem {
                required property var modelData
                title: modelData.title
                description: modelData.detail
                SettingsControls.SettingsSwitch {
                    objectName: "notification-" + modelData.key + "-switch"
                    checked: page.state[modelData.key] === true
                    enabled: page.ready && !page.pending
                    accentColor: page.theme.accent
                    trackColor: page.theme.divider
                    Accessible.name: modelData.title
                    onToggled: checked => page.setPreference(modelData.key, checked)
                }
            }
        }
    }
    Demo.SettingsGroup {
        title: I18n.tr("App notifications")
        backgroundColor: page.theme.card
        Demo.SettingsItem {
            title: I18n.tr("Search")
            Demo.LiquidTextField {
                Layout.preferredWidth: 240
                implicitHeight: 24
                materialForm: true
                placeholderText: I18n.tr("Search apps that sent notifications")
                onTextChanged: page.appFilter = text
                Accessible.name: placeholderText
            }
        }
        Repeater {
            model: page.applications
            delegate: Demo.SettingsItem {
                id: appRow
                required property var modelData
                readonly property bool blocked: (page.state.blockedKeys || []).indexOf(modelData.key) >= 0
                title: modelData.appName
                description: blocked ? I18n.tr("New notifications blocked") : I18n.tr("Notifications allowed")
                SettingsControls.SettingsSwitch {
                    checked: !appRow.blocked
                    enabled: page.ready && !page.pending
                    accentColor: page.theme.accent
                    trackColor: page.theme.divider
                    Accessible.name: I18n.tr("Allow notifications from %1").arg(appRow.modelData.appName)
                    onToggled: checked => {
                        page.pending = true;
                        page.bridge.setNotificationBlocked(appRow.modelData.key, !checked);
                    }
                }
            }
        }
        Demo.SettingsItem {
            visible: page.applications.length === 0
            description: page.appFilter ? I18n.tr("No matching apps") : I18n.tr("Apps appear here once they send notifications")
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !page.ready || page.errorText.length > 0
        text: page.errorText || (page.bridge ? I18n.tr("Connecting to the notification service…") : I18n.tr("Notification service not connected"))
        color: page.errorText ? "#ff453a" : page.theme.secondaryText
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }
}
