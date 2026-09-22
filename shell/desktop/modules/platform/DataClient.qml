pragma Singleton

import QtQuick
import Quickshell

// JSONL client for the durable Go data service. It deliberately has a
// separate socket and pending-request table from PlatformClient so restarting
// either service cannot corrupt the other's response stream; the shared
// transport is JsonlClient, so both daemons get identical disconnect
// semantics — reads queue bounded and deduplicated, writes fail fast,
// sent-but-unanswered requests expire, and a disconnect fails everything
// outstanding so consumer state cannot wedge.
JsonlClient {
    // KOS_DATA_SOCKET redirects the shell to a development data service
    // (kosctl dev); unset in the installed layout.
    socketPath: Quickshell.env("KOS_DATA_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kos-data.sock")
    logName: "DataClient"
    daemonName: "data service"
    timeoutName: "data service"
    // Snapshot reads may queue while the transport is down and flush once on
    // reconnect. Reports such as activity.active-app are writes: they fail
    // immediately while disconnected so nothing stale replays afterwards.
    readOperations: ({
        "activity.snapshot": true,
        "desktop.refresh": true,
        "desktop.snapshot": true,
        "metrics.snapshot": true,
        "weather.refresh": true,
        "weather.snapshot": true
    })
}
