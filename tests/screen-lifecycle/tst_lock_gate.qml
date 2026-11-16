import QtQuick
import QtTest
import "."

TestCase {
    name: "ScreenLifecycleLockGate"

    function resetState() {
        PlatformClient.visibilityHandler = null
        PlatformClient.calls = []
        PlatformClient.connected = true
        ScreenLifecycle.sessionLocked = false
        ScreenLifecycle.lockCheckPending = false
        ScreenLifecycle._lockCheckCallbacks = []
        Quickshell.screens = [{ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 }]
        tryVerify(function() { return ScreenLifecycle.outputAvailable && ScreenLifecycle.activeScreen !== null }, 1500)
        PlatformClient.calls = []
    }

    function test_pending_lock_check_queues_overlapping_callbacks() {
        resetState()
        let pendingReply = null
        PlatformClient.visibilityHandler = function(cb) { pendingReply = cb }

        let runs = []
        ScreenLifecycle.updateSessionVisibility(function() { runs.push("first") })
        verify(ScreenLifecycle.lockCheckPending)
        compare(runs.length, 0)

        // Overlapping check while in flight must queue rather than running early.
        ScreenLifecycle.updateSessionVisibility(function() { runs.push("second") })
        compare(runs.length, 0)
        compare(PlatformClient.calls.length, 1)

        pendingReply({ ok: true, result: { locked: false } })
        verify(!ScreenLifecycle.lockCheckPending)
        verify(!ScreenLifecycle.sessionLocked)
        compare(runs, ["first", "second"])
    }

    function test_stale_visibility_reply_cannot_override_newer_lock_signal() {
        resetState()
        let pendingReply = null
        PlatformClient.visibilityHandler = function(cb) { pendingReply = cb }

        let unlockedRuns = 0
        ScreenLifecycle.updateSessionVisibility(function() { unlockedRuns++ })
        verify(ScreenLifecycle.lockCheckPending)

        // Authoritative lock signal arrives while session.visibility is still in flight.
        PlatformClient.eventReceived("session.lock-changed", { locked: true })
        verify(ScreenLifecycle.sessionLocked)

        // Older GetActive reply (locked=false) arrives late and must be ignored.
        pendingReply({ ok: true, result: { locked: false } })
        verify(ScreenLifecycle.sessionLocked)
        compare(unlockedRuns, 0)
    }

    function test_lock_gate_preserves_screen_and_skips_probes_until_unlock() {
        resetState()
        const initialScreen = ScreenLifecycle.activeScreen
        verify(initialScreen !== null)
        verify(ScreenLifecycle.outputAvailable)

        PlatformClient.eventReceived("session.lock-changed", { locked: true })
        verify(ScreenLifecycle.sessionLocked)

        // DPMS off drops compositor outputs; ScreenLifecycle must keep binding and skip probes.
        Quickshell.screens = []
        Quickshell.screensChanged()
        compare(ScreenLifecycle.activeScreen, initialScreen)
        verify(ScreenLifecycle.outputAvailable)
        compare(PlatformClient.calls.length, 0)

        // Unlock triggers refreshAndSettle and restores probes.
        Quickshell.screens = [{ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 }]
        PlatformClient.eventReceived("session.lock-changed", { locked: false })
        verify(!ScreenLifecycle.sessionLocked)
        tryVerify(function() { return ScreenLifecycle.outputAvailable && ScreenLifecycle.activeScreen !== null }, 1500)
        verify(PlatformClient.calls.some(c => c.op === "display.outputs.get"))
    }

    function test_reconnect_resyncs_when_unlocked_during_daemon_restart() {
        resetState()
        PlatformClient.eventReceived("session.lock-changed", { locked: true })
        verify(ScreenLifecycle.sessionLocked)

        PlatformClient.visibilityHandler = function(cb) { cb({ ok: true, result: { locked: false } }) }
        PlatformClient.transportChanged(true)
        verify(!ScreenLifecycle.sessionLocked)
        verify(PlatformClient.calls.some(c => c.op === "session.visibility"))
    }
}
