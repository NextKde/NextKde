import Kos.Demo as Demo
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: integrationPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property var snapshot: ({})
    property string errorText: ""

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        // The reply lands on integrationSnapshotChanged; the bridge does
        // its D-Bus and /proc probes off the UI thread now, so this page's
        // 5s poll no longer freezes anything.
        bridge.integrationSnapshot();
    }

    Connections {
        target: integrationPage.bridge
        enabled: integrationPage.bridge !== null
        function onIntegrationSnapshotChanged(state) {
            integrationPage.snapshot = state;
            integrationPage.errorText = I18n.tr(integrationPage.bridge.lastError) || "";
        }
    }

    function notificationState() {
        const provider = snapshot.notificationProvider || "none";
        if (provider === "kos")
            return {
                label: I18n.tr("KOS has taken over"),
                color: "#30d158",
                detail: I18n.tr("Notifications will appear in the KOS notification center")
            };
        if (provider === "plasma")
            return {
                label: I18n.tr("Plasma takeover"),
                color: "#ff9f0a",
                detail: I18n.tr("KOS is waiting for the org.freedesktop.Notifications name")
            };
        if (provider === "other")
            return {
                label: I18n.tr("Another program has taken over"),
                color: "#ff9f0a",
                detail: snapshot.notificationCommand || snapshot.notificationOwner || I18n.tr("Unknown notification service")
            };
        return {
            label: I18n.tr("Not registered"),
            color: "#ff453a",
            detail: I18n.tr("No desktop notification service available")
        };
    }

    function statusRow(icon, tint, title, ready, readyLabel, detail) {
        return {
            icon: icon,
            tint: tint,
            title: title,
            label: ready ? readyLabel : I18n.tr("Not connected"),
            color: ready ? "#30d158" : "#ff453a",
            detail: detail
        };
    }

    readonly property var notification: notificationState()
    readonly property var rows: [statusRow("K", "#0a84ff", "KOS Shell", !!snapshot.shellReady, I18n.tr("Running"), I18n.tr("Settings page and Quickshell IPC channel")), statusRow("↔", "#5ac8fa", I18n.tr("Platform bridge"), !!snapshot.platformConnected, I18n.tr("Connected"), I18n.tr("Windows, network, audio and system actions")), statusRow("D", "#34c759", I18n.tr("Data service"), !!snapshot.dataConnected, I18n.tr("Connected"), I18n.tr("System metrics, activity records and desktop files")), statusRow("▦", "#af52de", I18n.tr("Desktop widgets"), !!snapshot.desktopWidgetsVisible, I18n.tr("Shown"), snapshot.desktopFilesReady ? I18n.tr("Clock, weather, resource cards and desktop files are ready") : I18n.tr("Widget layer shown; desktop files still syncing")),
        {
            icon: "N",
            tint: "#ff9500",
            title: I18n.tr("Notification takeover"),
            label: notification.label,
            color: notification.color,
            detail: notification.detail
        },
        statusRow("G", "#64d2ff", I18n.tr("Glass effects"), !!snapshot.glassLoaded, I18n.tr("Loaded"), I18n.tr("KWin blur and liquid glass effects")), statusRow("A", "#ff375f", I18n.tr("Dock window animation"), !!snapshot.dockAnimationLoaded, I18n.tr("Loaded"), I18n.tr("KWin Dock zoom / genie animation")), statusRow("I", "#bf5af2", I18n.tr("Desktop input bridge"), !!snapshot.contextMenuInputLoaded, I18n.tr("Loaded"), I18n.tr("Global clicks and menu dismiss events"))]

    Demo.SettingsGroup {
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: snapshot.updatedAt ? I18n.tr("Last checked ") + snapshot.updatedAt : I18n.tr("Reading live state…")
            Demo.LiquidActionButton {
                text: I18n.tr("Refresh")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: integrationPage.refresh()
            }
        }
        Repeater {
            model: integrationPage.rows
            delegate: Demo.SettingsItem {
                required property var modelData
                title: modelData.title
                description: modelData.detail
                Text {
                    text: modelData.label
                    color: modelData.color
                    font.pixelSize: 11
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: errorText.length > 0
        text: errorText
        color: "#ff453a"
        font.pixelSize: 10
        wrapMode: Text.Wrap
    }

    Timer {
        interval: 5000
        repeat: true
        running: integrationPage.visible
        onTriggered: integrationPage.refresh()
    }
    Component.onCompleted: refresh()
}
