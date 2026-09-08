pragma Singleton

import QtQuick
import QtQml.Models
import Quickshell.Services.SystemTray
import "TrayAttentionMatch.mjs" as TrayAttentionMatch

QtObject {
    id: service

    property var attentionKeys: []
    property int revision: 0

    function _normalize(value) {
        return AppPresentationService.normalize(value)
    }

    function _refresh() {
        const items = []
        for (let index = 0; index < trayItems.count; ++index) {
            const delegate = trayItems.objectAt(index)
            if (delegate?.modelData)
                items.push(delegate.modelData)
        }
        const keys = TrayAttentionMatch.collectAttentionKeys(items,
            SystemTrayItem.NeedsAttention, service._normalize)
        if (JSON.stringify(keys) === JSON.stringify(attentionKeys))
            return
        attentionKeys = keys
        revision++
    }

    function needsAttention(appId, appName) {
        const observedRevision = revision
        return TrayAttentionMatch.matchesAttention(attentionKeys,
            appId, appName, service._normalize)
    }

    property Instantiator trayItems: Instantiator {
        model: SystemTray.items
        delegate: QtObject {
            required property var modelData
            property Connections statusWatch: Connections {
                target: modelData
                function onStatusChanged() { service._refresh() }
                function onIdChanged() { service._refresh() }
                function onTitleChanged() { service._refresh() }
            }
        }
        onObjectAdded: service._refresh()
        onObjectRemoved: service._refresh()
    }
}
