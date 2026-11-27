pragma Singleton

import QtQuick
import QtCore
import Quickshell
import "WidgetCrashGuardLogic.mjs" as Logic

// Circuit breaker for in-process widget packages.
// Records a pending marker synchronously before loading a package's QML,
// clears it once the shell survives past `settleWindowMs`, and automatically
// pauses any package whose pending marker is still present after an
// unexpected process crash.
QtObject {
    id: guard

    property int revision: 0
    property var _pending: ({})
    property var _tripped: ({})
    property var _settleDeadlines: ({})
    readonly property int settleWindowMs: 600
    readonly property string _sessionId: {
        const inst = String(Quickshell.instanceId ?? "")
        if (inst.length > 0) return inst
        const pid = Number(Quickshell.processId ?? 0)
        return pid > 0 ? ("pid-" + pid) : ""
    }

    readonly property var trippedPackages: {
        const _rev = guard.revision
        return Logic.listTripped(guard._tripped)
    }

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/widget-crash-guard.ini"
        category: "CrashGuard"
        property string pendingJson: "{}"
        property string trippedJson: "{}"
    }

    function _persist() {
        _settings.pendingJson = JSON.stringify(guard._pending)
        _settings.trippedJson = JSON.stringify(guard._tripped)
        _settings.sync()
    }

    property Timer _settleTimer: Timer {
        interval: 200
        repeat: true
        running: false
        onTriggered: guard._flushSettled()
    }

    function _flushSettled() {
        const now = Date.now()
        let nextPending = guard._pending
        let changed = false
        let remaining = 0
        const nextDeadlines = ({})
        for (const id of Object.keys(guard._settleDeadlines)) {
            const deadline = Number(guard._settleDeadlines[id])
            if (now >= deadline) {
                const res = Logic.markLoadSettled(nextPending, id)
                nextPending = res.pending
                if (res.changed) changed = true
            } else {
                nextDeadlines[id] = deadline
                remaining++
            }
        }
        guard._settleDeadlines = nextDeadlines
        if (changed) {
            guard._pending = nextPending
            guard._persist()
        }
        if (remaining === 0)
            guard._settleTimer.running = false
    }

    function isBlocked(packageId, packageRevision) {
        const id = String(packageId ?? "")
        if (id.length === 0) return false
        const rev = String(packageRevision ?? "")
        const pruned = Logic.pruneRecovered(guard._tripped, id, rev)
        if (pruned.changed) {
            guard._tripped = pruned.tripped
            guard._persist()
            guard.revision++
            return false
        }
        return Logic.isTripped(guard._tripped, id, rev)
    }

    function beginLoad(packageId, packageRevision) {
        const id = String(packageId ?? "")
        if (id.length === 0) return
        const now = Date.now()
        guard._pending = Logic.markLoadStart(guard._pending, id, String(packageRevision ?? ""), now, guard._sessionId)
        guard._persist()
        const deadlines = Object.assign({}, guard._settleDeadlines)
        deadlines[id] = now + guard.settleWindowMs
        guard._settleDeadlines = deadlines
        guard._settleTimer.running = true
    }

    function finishLoad(packageId) {
        const id = String(packageId ?? "")
        if (id.length === 0) return
        if (!Object.prototype.hasOwnProperty.call(guard._pending, id)) return
        const fastDeadline = Date.now() + 250
        const deadlines = Object.assign({}, guard._settleDeadlines)
        const existing = Number(deadlines[id])
        deadlines[id] = Number.isFinite(existing) ? Math.min(existing, fastDeadline) : fastDeadline
        guard._settleDeadlines = deadlines
        guard._settleTimer.running = true
    }

    function clearPending(packageId) {
        const id = String(packageId ?? "")
        if (id.length === 0) return
        if (Object.prototype.hasOwnProperty.call(guard._settleDeadlines, id)) {
            const deadlines = Object.assign({}, guard._settleDeadlines)
            delete deadlines[id]
            guard._settleDeadlines = deadlines
            if (Object.keys(deadlines).length === 0)
                guard._settleTimer.running = false
        }
        const res = Logic.markLoadSettled(guard._pending, id)
        if (res.changed) {
            guard._pending = res.pending
            guard._persist()
        }
    }

    function reEnable(packageId) {
        const id = String(packageId ?? "")
        if (id.length === 0) return false
        const res = Logic.reEnable(guard._tripped, id)
        if (!res.changed) return false
        guard._tripped = res.tripped
        guard._persist()
        guard.revision++
        return true
    }

    Component.onCompleted: {
        const pending = Logic.parseMap(_settings.pendingJson)
        const tripped = Logic.parseMap(_settings.trippedJson)
        const promoted = Logic.promotePendingToTripped(pending, tripped, Date.now(), guard._sessionId)
        guard._pending = promoted.pending
        guard._tripped = promoted.tripped
        if (promoted.newlyTrippedIds.length > 0 || Object.keys(pending).length > 0) {
            for (const id of promoted.newlyTrippedIds)
                console.warn("[WidgetCrashGuard] Paused widget after previous crash:", id)
            guard._persist()
        }
        guard.revision++
    }

    Component.onDestruction: {
        guard._settleTimer.running = false
        guard._settleDeadlines = ({})
        if (Object.keys(guard._pending).length > 0) {
            guard._pending = ({})
            _settings.pendingJson = "{}"
            _settings.sync()
        }
    }
}
