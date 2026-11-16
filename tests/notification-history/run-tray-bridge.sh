#!/usr/bin/env bash
set -euo pipefail
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
source_root=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$fixture_root/desktop/modules/bar" "$fixture_root/desktop/modules/platform" "$fixture_root/shared/qml/i18n"
cp "$source_root/shell/desktop/modules/bar/TrayNotificationBridge.qml" "$fixture_root/desktop/modules/bar/"
cat > "$fixture_root/desktop/modules/bar/qmldir" <<'QML'
module qs.desktop.modules.bar
TrayNotificationBridge 1.0 TrayNotificationBridge.qml
singleton SysTrayIdentityService 1.0 SysTrayIdentityService.qml
QML
cat > "$fixture_root/desktop/modules/bar/SysTrayIdentityService.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { function friendlyName(item) { return "Synthetic mail" } }
QML
cat > "$fixture_root/desktop/modules/platform/qmldir" <<'QML'
module qs.desktop.modules.platform
singleton PlatformClient 1.0 PlatformClient.qml
QML
cat > "$fixture_root/desktop/modules/platform/PlatformClient.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property int requests: 0
    function request(operation, payload, callback) { requests++; callback({ok: true}) }
}
QML
cat > "$fixture_root/shared/qml/i18n/qmldir" <<'QML'
singleton I18n 1.0 I18n.qml
QML
cat > "$fixture_root/shared/qml/i18n/I18n.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { function tr(text) { return text } }
QML
cat > "$fixture_root/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.desktop.modules.bar
import qs.desktop.modules.platform
Scope {
    id: root
    QtObject {
        id: item
        property string id: "synthetic-mail"
        property int status: SystemTrayItem.Active
        property string title: "Synthetic mail"
        property string icon: "first-icon"
        property string tooltipTitle: "Mail"
        property string tooltipDescription: "No unread messages"
    }
    TrayNotificationBridge { trayModel: [item]; dedupeIntervalMs: 0 }
    property int phase: 0
    function requireCount(expected) {
        if (PlatformClient.requests !== expected) {
            console.error("FAIL phase " + phase + ": expected " + expected + ", got " + PlatformClient.requests)
            Qt.exit(1)
        }
    }
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                root.requireCount(0)
                item.icon = "badge-12"; item.tooltipTitle = "12 unread"; item.tooltipDescription = "Inbox count"
            } else if (root.phase === 1) {
                root.requireCount(0)
                item.icon = "badge-0"; item.tooltipTitle = "No unread"; item.tooltipDescription = "Cleared"
            } else if (root.phase === 2) {
                root.requireCount(0)
                item.status = SystemTrayItem.NeedsAttention
            } else if (root.phase === 3) {
                root.requireCount(1)
                item.icon = "attention-icon"; item.tooltipTitle = "Attention detail"; item.tooltipDescription = "More detail"
            } else if (root.phase === 4) {
                root.requireCount(1)
                item.status = SystemTrayItem.Active
            } else if (root.phase === 5) {
                root.requireCount(1)
                item.status = SystemTrayItem.NeedsAttention
            } else {
                root.requireCount(2)
                console.log("TRAY_NOTIFICATION_INTENT_PASS")
                Qt.quit()
            }
            root.phase++
        }
    }
}
QML
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 10 "${1:-quickshell}" -p "$fixture_root" > "$fixture_root/result.log" 2>&1 || {
    cat "$fixture_root/result.log"
    exit 1
}
cat "$fixture_root/result.log"
grep -q TRAY_NOTIFICATION_INTENT_PASS "$fixture_root/result.log"
