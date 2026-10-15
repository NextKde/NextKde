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
    readonly property var applications: (state.sources || []).filter(source =>
        source.appName.toLowerCase().indexOf(appFilter.toLowerCase()) >= 0)
    spacing: 16
    function refresh() {
        if (!bridge || pending) return
        pending = true
        bridge.notificationSnapshot()
    }
    function setPreference(key, value) {
        if (!ready || pending) return
        pending = true
        bridge.setNotificationPreference(key, value)
    }
    Connections {
        target: page.bridge
        enabled: page.bridge !== null
        function onNotificationSnapshotChanged(snapshot) {
            page.pending = false
            if (snapshot.ready !== undefined) page.state = snapshot
            page.errorText = page.bridge.lastError || snapshot.saveError || ""
        }
    }
    Component.onCompleted: refresh()
    // Synchronize changes made by the Control Center and newly discovered apps.
    Timer { interval: 2500; running: page.visible && page.bridge !== null; repeat: true; onTriggered: page.refresh() }
    Text {
        Layout.fillWidth: true
        text: I18n.tr("The notification center shows the latest three message cards; expand it to browse everything. Long messages expand on click.")
        color: page.theme.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 13
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: preferences.implicitHeight
        radius: 18
        color: page.theme.card
        Column {
            id: preferences
            width: parent.width
            Repeater {
                model: [
                    {key: "doNotDisturbEnabled", title: I18n.tr("Do Not Disturb"), detail: I18n.tr("Pauses notification banners; messages still land in history")},
                    {key: "bannersEnabled", title: I18n.tr("Show notification banners"), detail: I18n.tr("Show a popup banner when a new message arrives")},
                    {key: "historyEnabled", title: I18n.tr("Keep notification history"), detail: I18n.tr("Keeps the latest 50 messages of this session; turning it off stops saving new ones")},
                    {key: "showPreview", title: I18n.tr("Show message previews"), detail: I18n.tr("Hides titles and bodies in the notification center and banners when off")},
                    {key: "hideControlCenterNotifications", title: I18n.tr("Hide notifications in Control Center"), detail: I18n.tr("Use the separate notification panel; keep notifications out of Control Center")},
                    {key: "showNotificationBadges", title: I18n.tr("Show notification badges"), detail: I18n.tr("Shows counts and alert dots on Dock app icons")}
                ]
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: preferences.width
                    height: Math.max(76, descriptions.implicitHeight + 26)
                    Column {
                        id: descriptions
                        anchors { left: parent.left; right: toggle.left; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 16 }
                        spacing: 5
                        Text { width: parent.width; text: modelData.title; color: page.theme.primaryText; font.pixelSize: 14; wrapMode: Text.Wrap }
                        Text { width: parent.width; text: modelData.detail; color: page.theme.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap }
                    }
                    LiquidControls.LiquidGlassSwitch {
                        id: toggle
                        objectName: "notification-" + modelData.key + "-switch"
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 18 }
                        checked: page.state[modelData.key] === true
                        enabled: page.ready && !page.pending
                        accentColor: page.theme.accent
                        trackColor: page.theme.divider
                        Accessible.name: modelData.title
                        onToggled: checked => page.setPreference(modelData.key, checked)
                    }
                    Rectangle { visible: index < 5; anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18 }
                    height: 1; color: page.theme.separator }
                }
            }
        }
    }
    Text { text: I18n.tr("App notifications"); color: page.theme.primaryText; font { pixelSize: 16; weight: Font.DemiBold } }
    TextField {
        Layout.fillWidth: true
        placeholderText: I18n.tr("Search apps that sent notifications")
        color: page.theme.primaryText
        onTextChanged: page.appFilter = text
        background: Rectangle { radius: 12; color: page.theme.card; border.width: parent.activeFocus ? 1 : 0; border.color: page.theme.accent }
        leftPadding: 16; rightPadding: 16; topPadding: 12; bottomPadding: 12
        Accessible.name: I18n.tr("Search app notifications")
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: appRows.implicitHeight
        radius: 18
        color: page.theme.card
        Column {
            id: appRows
            width: parent.width
            Repeater {
                model: page.applications
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool blocked: (page.state.blockedKeys || []).indexOf(modelData.key) >= 0
                    width: appRows.width
                    height: 70
                    Column {
                        anchors { left: parent.left; right: allowToggle.left; verticalCenter: parent.verticalCenter; leftMargin: 18; rightMargin: 16 }
                        spacing: 5
                        Text { width: parent.width; text: modelData.appName; textFormat: Text.PlainText; elide: Text.ElideRight; color: page.theme.primaryText; font.pixelSize: 14 }
                        Text { width: parent.width; text: parent.parent.blocked ? I18n.tr("New notifications blocked") : I18n.tr("Notifications allowed"); color: page.theme.secondaryText; font.pixelSize: 11 }
                    }
                    LiquidControls.LiquidGlassSwitch {
                        id: allowToggle
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 18 }
                        checked: !parent.blocked
                        enabled: page.ready && !page.pending
                        accentColor: page.theme.accent
                        trackColor: page.theme.divider
                        Accessible.name: I18n.tr("Allow notifications from %1").arg(modelData.appName)
                        onToggled: checked => {
                            page.pending = true
                            page.bridge.setNotificationBlocked(modelData.key, !checked)
                        }
                    }
                    Rectangle { visible: index < page.applications.length - 1; anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18 }
                    height: 1; color: page.theme.separator }
                }
            }
            Text {
                width: parent.width
                padding: 20
                visible: page.applications.length === 0
                text: page.appFilter ? I18n.tr("No matching apps") : I18n.tr("Apps appear here once they send notifications")
                color: page.theme.secondaryText
                wrapMode: Text.Wrap
                font.pixelSize: 13
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !page.ready || page.errorText.length > 0
        text: page.errorText || (page.bridge ? I18n.tr("Connecting to the notification service…") : I18n.tr("Notification service not connected"))
        color: page.errorText ? "#ff453a" : page.theme.secondaryText
        wrapMode: Text.Wrap
        font.pixelSize: 12
    }
}
