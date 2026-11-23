// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

// Only the KOS daemon's privacy-filtered projection is consumed. This does not
// own org.freedesktop.Notifications and exposes no application actions.
Column {
    id: root
    property real unit: 1
    property string fontFamily: "Inter"
    property Item glassTexture: null
    property Item glassFrame: null
    property var notifications: []
    // DBus.Properties updates individual property-map keys without emitting
    // refreshed(). Bind to the key so replacements and clears reach the UI.
    readonly property var notificationsPayload: properties.properties
        ? properties.properties["NotificationsJson"] : "[]"
    onNotificationsPayloadChanged: root.refresh()
    property date now: new Date()
    spacing: 8 * unit
    function applyPayload(raw) {
        try {
            const parsed = JSON.parse(String(raw || "[]"))
            root.notifications = Array.isArray(parsed) ? parsed.slice(0, 4).filter(item => item
                && typeof item.appName === "string" && typeof item.createdAt === "number") : []
        } catch (error) { root.notifications = [] }
    }
    function refresh() {
        if (!watcher.registered) { root.notifications = []; return }
        let value = root.notificationsPayload
        if (value && value.value !== undefined) value = value.value
        root.applyPayload(value)
    }
    DBus.DBusServiceWatcher {
        id: watcher
        busType: DBus.BusType.Session
        watchedService: "org.kos.LockScreen"
        onRegisteredChanged: root.refresh()
    }
    DBus.Properties {
        id: properties
        busType: DBus.BusType.Session
        service: watcher.registered ? watcher.watchedService : ""
        path: "/org/kos/LockScreen"
        iface: "org.kos.LockScreen1"
        onPropertiesChanged: function(iface, changed, invalidated) {
            if (invalidated && invalidated.indexOf("NotificationsJson") >= 0) update("NotificationsJson")
        }
        onRefreshed: root.refresh()
    }
    Timer { interval: 30000; running: root.visible; repeat: true; onTriggered: root.now = new Date() }
    Repeater {
        model: root.notifications
        delegate: Item {
            objectName: "lockNotificationCard"
            required property var modelData
            width: root.width; height: 62 * root.unit
            LockGlass { anchors.fill: parent; texture: root.glassTexture; frame: root.glassFrame; radius: 20 * root.unit; tint: 0.17 }
            Rectangle {
                x: 15 * root.unit; anchors.verticalCenter: parent.verticalCenter
                width: 30 * root.unit; height: width; radius: 7 * root.unit
                color: "#30ffffff"
                visible: !appIcon.valid || appIcon.status === Kirigami.Icon.Error
                Text {
                    anchors.centerIn: parent
                    text: modelData.appName.charAt(0).toUpperCase(); textFormat: Text.PlainText
                    color: "white"; font.pixelSize: 17 * root.unit; font.family: root.fontFamily
                }
            }
            Kirigami.Icon {
                id: appIcon
                objectName: "lockNotificationIcon"
                x: 15 * root.unit; anchors.verticalCenter: parent.verticalCenter
                width: 30 * root.unit; height: width
                source: modelData.appIcon || "dialog-information"
                fallback: "dialog-information"
            }
            Text {
                objectName: "lockNotificationAppName"
                font.family: root.fontFamily
                x: 59 * root.unit; y: 14 * root.unit
                width: parent.width - x - 74 * root.unit
                text: modelData.appName; textFormat: Text.PlainText
                elide: Text.ElideRight; color: "#ddffffff"
                font.pixelSize: Math.max(11, 14 * root.unit)
            }
            Text {
                font.family: root.fontFamily
                x: 59 * root.unit; y: 33 * root.unit
                text: qsTr("通知"); color: "#aaffffff"; font.pixelSize: Math.max(10, 12 * root.unit)
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14 * root.unit
                y: 15 * root.unit
                readonly property int minutes: Math.max(0, Math.floor((root.now.getTime() - modelData.createdAt) / 60000))
                text: minutes < 1 ? qsTr("刚刚") : qsTr("%1 分钟前").arg(minutes)
                color: "#99ffffff"; font.pixelSize: Math.max(9, 10 * root.unit)
            }
        }
    }
}
