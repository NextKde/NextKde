pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// The Dock owns the destructive empty action.  Desktop file deletion itself
// remains recoverable (gio trash); only this explicit confirmation purges it.
QtObject {
    id: service

    property bool emptying: false
    property bool hasItems: false
    signal depositReceived()
    property bool _stateRequestPending: false

    function refreshContentState() {
        if (_stateRequestPending)
            return
        _stateRequestPending = true
        PlatformClient.request("file.trash-state", {}, function(response) {
            _stateRequestPending = false
            if (response?.ok)
                hasItems = !!response.result?.hasItems
        })
    }

    function open() {
        refreshContentState()
        PlatformClient.request("file.open-trash", {}, function(response) {
            if (!response?.ok)
                console.warn("[DockTrash] unable to open trash: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    function empty() {
        if (emptying)
            return
        emptying = true
        PlatformClient.request("file.empty-trash", {}, function(response) {
            emptying = false
            if (!response?.ok) {
                console.warn("[DockTrash] unable to empty trash: "
                    + (response?.error?.message || "platform unavailable"))
            } else {
                hasItems = false
            }
        })
    }

    function celebrateDeposit() {
        hasItems = true
        depositReceived()
    }

    Component.onCompleted: refreshContentState()
}
