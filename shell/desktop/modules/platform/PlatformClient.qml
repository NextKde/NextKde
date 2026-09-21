pragma Singleton

import QtQuick
import Quickshell

// One connection shared by all shell surfaces, speaking versioned JSONL to
// the platform daemon. The transport — queueing, dedup, expiry, reconnection
// — is JsonlClient; only the socket path, the read/write split and the
// per-operation timeouts below are specific to this daemon.
JsonlClient {
    // KOS_PLATFORM_SOCKET redirects the shell to a development daemon (kosctl
    // dev); unset in the installed layout.
    socketPath: Quickshell.env("KOS_PLATFORM_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kos-platform.sock")
    logName: "PlatformClient"
    daemonName: "platform daemon"
    timeoutName: "platform"
    readOperations: ({
        "appmenu.active": true,
        "appmenu.layout": true,
        "audio.applications": true,
        "audio.get": true,
        "bluetooth.list": true,
        "clipboard.history.list": true,
        "clipboard.pinned.list": true,
        "clipboard.read": true,
        "clipboard.thumb": true,
        "display.brightness.get": true,
        "display.outputs.get": true,
        "file.open-with": true,
        "file.trash-state": true,
        "network.details": true,
        "network.refresh": true,
        "network.scan": true,
        "network.traffic": true,
        "nightlight.get": true,
        "platform.ping": true,
        "state.read": true,
        "tray.identify": true
    })
    // Per-operation expiry overrides for requests whose legitimate duration
    // exceeds the default: interactive screenshots and multi-gigabyte file
    // operations are unbounded (the daemon keeps working regardless, so a
    // client-side timeout would only report a false failure — the daemon
    // runs file.copy/file.transfer/file.empty-trash itself with no watchdog
    // and gives screenshot.capture's interactive tool a 0 watchdog, so a
    // daemon kill never races this client), while Wi-Fi and Bluetooth
    // association can legitimately approach a minute.
    // 0 disables expiry entirely.
    requestTimeoutOverrides: ({
        "bluetooth.connect": 90000,
        "bluetooth.disconnect": 90000,
        "file.copy": 0,
        "file.empty-trash": 0,
        "file.transfer": 0,
        "network.connect": 90000,
        "network.connect-enterprise": 90000,
        "screenshot.capture": 0
    })
}
