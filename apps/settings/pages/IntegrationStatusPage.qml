import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    required property var colors
    property bool materialForm: false
    id: integrationPage

    Layout.fillWidth: true
    spacing: 8
    property var bridge: null
    property var snapshot: ({})
    property string errorText: ""

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built")
            return
        }
        // The reply lands on integrationSnapshotChanged; the bridge does
        // its D-Bus and /proc probes off the UI thread now, so this page's
        // 5s poll no longer freezes anything.
        bridge.integrationSnapshot()
    }

    Connections {
        target: integrationPage.bridge
        enabled: integrationPage.bridge !== null
        function onIntegrationSnapshotChanged(state) {
            integrationPage.snapshot = state
            integrationPage.errorText = I18n.tr(integrationPage.bridge.lastError) || ""
        }
    }

    function notificationState() {
        const provider = snapshot.notificationProvider || "none"
        if (provider === "kos")
            return { label: I18n.tr("KOS has taken over"), color: "#30d158",
                detail: I18n.tr("Notifications will appear in the KOS notification center") }
        if (provider === "plasma")
            return { label: I18n.tr("Plasma takeover"), color: "#ff9f0a",
                detail: I18n.tr("KOS is waiting for the org.freedesktop.Notifications name") }
        if (provider === "other")
            return { label: I18n.tr("Another program has taken over"), color: "#ff9f0a",
                detail: snapshot.notificationCommand || snapshot.notificationOwner || I18n.tr("Unknown notification service") }
        return { label: I18n.tr("Not registered"), color: "#ff453a",
            detail: I18n.tr("No desktop notification service available") }
    }

    function statusRow(icon, tint, title, ready, readyLabel, detail) {
        return { icon: icon, tint: tint, title: title,
            label: ready ? readyLabel : I18n.tr("Not connected"),
            color: ready ? "#30d158" : "#ff453a", detail: detail }
    }

    readonly property var notification: notificationState()
    readonly property var rows: [
        statusRow("K", "#0a84ff", "KOS Shell", !!snapshot.shellReady,
            I18n.tr("Running"), I18n.tr("Settings page and Quickshell IPC channel")),
        statusRow("↔", "#5ac8fa", I18n.tr("Platform bridge"), !!snapshot.platformConnected,
            I18n.tr("Connected"), I18n.tr("Windows, network, audio and system actions")),
        statusRow("D", "#34c759", I18n.tr("Data service"), !!snapshot.dataConnected,
            I18n.tr("Connected"), I18n.tr("System metrics, activity records and desktop files")),
        statusRow("▦", "#af52de", I18n.tr("Desktop widgets"), !!snapshot.desktopWidgetsVisible,
            I18n.tr("Shown"), snapshot.desktopFilesReady
                ? I18n.tr("Clock, weather, resource cards and desktop files are ready")
                : I18n.tr("Widget layer shown; desktop files still syncing")),
        { icon: "N", tint: "#ff9500", title: I18n.tr("Notification takeover"),
            label: notification.label, color: notification.color,
            detail: notification.detail },
        statusRow("G", "#64d2ff", I18n.tr("Glass effects"), !!snapshot.glassLoaded,
            I18n.tr("Loaded"), I18n.tr("KWin blur and liquid glass effects")),
        statusRow("A", "#ff375f", I18n.tr("Dock window animation"),
            !!snapshot.dockAnimationLoaded, I18n.tr("Loaded"), I18n.tr("KWin Dock zoom / genie animation")),
        statusRow("I", "#bf5af2", I18n.tr("Desktop input bridge"),
            !!snapshot.contextMenuInputLoaded, I18n.tr("Loaded"), I18n.tr("Global clicks and menu dismiss events"))
    ]

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13

        Text {
            Layout.fillWidth: true
            text: snapshot.updatedAt
                ? I18n.tr("Last checked ") + snapshot.updatedAt : I18n.tr("Reading live state…")
            color: colors.secondaryText
            font.pixelSize: 12
        }

        Rectangle {
            implicitWidth: 72
            implicitHeight: 30
            radius: 15
            color: refreshPointer.containsMouse
                ? colors.sidebarHover : colors.card
            border.width: 1
            border.color: colors.floatingBorder

            Text {
                anchors.centerIn: parent
                text: I18n.tr("Refresh")
                color: colors.primaryText
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: refreshPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: integrationPage.refresh()
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: statusColumn.implicitHeight + 8
        radius: 24
        color: colors.card

        Column {
            id: statusColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4

            Repeater {
                model: integrationPage.rows

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: statusColumn.width
                    height: 62

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 11

                        Controls.SettingIcon {
                            colors: integrationPage.colors
                            materialForm: integrationPage.materialForm
                            symbol: modelData.icon
                            tint: modelData.tint
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: modelData.title
                                color: colors.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.detail
                                color: colors.secondaryText
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            implicitWidth: statusLabel.implicitWidth + 18
                            implicitHeight: 24
                            radius: 12
                            color: colors.dark
                                ? Qt.rgba(1, 1, 1, 0.09)
                                : Qt.rgba(0, 0, 0, 0.055)
                            Text {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: modelData.color
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 49
                        anchors.bottom: parent.bottom
                        height: 1
                        color: colors.separator
                        visible: index < integrationPage.rows.length - 1
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: errorText.length > 0
        text: errorText
        color: "#ff453a"
        font.pixelSize: 12
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
