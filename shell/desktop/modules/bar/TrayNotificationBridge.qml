import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// Bridges system tray item attention signals into desktop notifications.
// When a tray icon starts flashing (status becomes NeedsAttention) or its
// tooltip/icon changes, we emit a freedesktop notification so the user sees
// it in the Quickshell notification center.
QtObject {
    id: root

    // How long to suppress repeated notifications with identical content
    // from the same tray item.
    property int dedupeIntervalMs: 5000

    // last notification key -> timestamp
    property var _lastSent: ({})

    // Reusable process for sending notifications.
    property Process _sender: Process {
        stdout: StdioCollector {}
        stderr: StdioCollector {}
    }

    function _now() { return Date.now() }

    function _canNotify(item, summary, body) {
        const key = item.id + "|" + summary + "|" + body
        const last = root._lastSent[key]
        if (last && (_now() - last) < dedupeIntervalMs)
            return false
        root._lastSent[key] = _now()
        return true
    }

    function _notify(item) {
        const appName = item.title || item.id || "System Tray"
        const summary = item.tooltipTitle || appName
        const body = item.tooltipDescription
            || (item.status === SystemTrayItem.NeedsAttention ? "新消息" : "状态更新")
        const icon = item.icon || ""

        if (!_canNotify(item, summary, body))
            return

        // Send through the session D-Bus notification interface.
        // Quickshell's NotificationServer owns org.freedesktop.Notifications
        // when Plasma's daemon is not present, so this lands in our own UI.
        root._sender.command = [
            "notify-send",
            "-a", appName,
            "-i", icon,
            summary,
            body,
            "-u", "normal",
            "-t", "5000"
        ]
        root._sender.running = true
    }

    // This bridge only needs one listener object per tray entry. A visual
    // Repeater tries to stack its Item delegates beside itself; because this
    // service is a QtObject, both the Repeater and delegates have no visual
    // parent and Qt emits stackBefore/stackAfter warnings. Instantiator owns
    // the same delegate lifecycle without attempting visual stacking.
    property Instantiator _trayRepeater: Instantiator {
        model: SystemTray.items
        delegate: Item {
            id: trayItemDelegate
            required property var modelData

            property int _lastStatus: modelData.status
            property string _lastIcon: modelData.icon
            property string _lastTooltipTitle: modelData.tooltipTitle
            property string _lastTooltipDescription: modelData.tooltipDescription

            Connections {
                target: modelData

                function onStatusChanged() {
                    if (modelData.status === SystemTrayItem.NeedsAttention
                        && trayItemDelegate._lastStatus !== SystemTrayItem.NeedsAttention) {
                        trayItemDelegate._lastStatus = modelData.status
                        root._notify(modelData)
                    } else {
                        trayItemDelegate._lastStatus = modelData.status
                    }
                }

                function onIconChanged() {
                    if (modelData.icon !== trayItemDelegate._lastIcon) {
                        trayItemDelegate._lastIcon = modelData.icon
                        // Some apps flash by toggling the icon without changing status.
                        if (modelData.status !== SystemTrayItem.NeedsAttention)
                            root._notify(modelData)
                    }
                }

                function onTooltipTitleChanged() {
                    if (modelData.tooltipTitle !== trayItemDelegate._lastTooltipTitle) {
                        trayItemDelegate._lastTooltipTitle = modelData.tooltipTitle
                        root._notify(modelData)
                    }
                }

                function onTooltipDescriptionChanged() {
                    if (modelData.tooltipDescription !== trayItemDelegate._lastTooltipDescription) {
                        trayItemDelegate._lastTooltipDescription = modelData.tooltipDescription
                        root._notify(modelData)
                    }
                }
            }
        }
    }
}
