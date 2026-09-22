import QtQuick
import Quickshell
import Quickshell.Io
import "JsonlClientCore.mjs" as Core

// Transport base for the versioned JSONL daemon sockets. One connection is
// shared by all shell surfaces; requests are versioned JSONL messages and
// callbacks are kept in-memory until the daemon replies. A disconnected
// daemon is not fatal, but nothing buffers forever either: read-only
// operations queue with deduplication and a hard cap so a long outage cannot
// accumulate thousands of stale polls, while writes fail immediately instead
// of replaying after the reconnect. Sent-but-unanswered requests expire on a
// timeout, and a disconnect fails everything outstanding, so no in-flight
// flag in a consumer can stay wedged.
//
// This type is not a singleton: PlatformClient and DataClient subclass it
// and supply socketPath, readOperations, requestTimeoutOverrides and the
// daemon/log naming -- the only points where the two clients ever differed.
QtObject {
    id: client

    readonly property int protocolVersion: 1
    // Subclass supplies the daemon's socket path.
    property string socketPath: ""
    property bool enabled: true
    // Log prefix and the names used in failure messages: daemonName covers
    // "<daemonName> unavailable" / "<daemonName> disconnected"; timeoutName
    // covers "<timeoutName> request timed out" / "request queue full"
    // (PlatformClient historically shortened the latter to "platform").
    property string logName: "JsonlClient"
    property string daemonName: "daemon"
    property string timeoutName: "daemon"
    // Public transport state for status surfaces; guarded so callers never
    // dereference the lazily created socket while it is null.
    readonly property bool connected: !!(socket && socket.connected)
    // Idempotent reads may queue while the transport is down and flush once
    // on reconnect. Everything else is treated as a write: it fails
    // immediately while disconnected so a stale "empty trash" or "power off"
    // can never replay an hour after the user clicked it. Subclasses list
    // their read operations here.
    property var readOperations: ({})
    readonly property int maxQueueSize: 200
    readonly property int requestTimeoutMs: 30000
    // Per-operation expiry overrides for requests whose legitimate duration
    // exceeds the default; 0 disables expiry entirely. Empty here;
    // PlatformClient overrides it.
    property var requestTimeoutOverrides: ({})
    // Backed by _core's state so the tables stay inspectable as properties;
    // _core reads them through the live binding.
    property var _queue: []
    // requestId -> { callbacks: [...], enqueuedAt: epoch ms, sentAt: epoch ms
    // (0 while queued), dedupKey: string, timeoutMs: int }
    property var _pending: ({})
    // dedupKey -> requestId, for queued idempotent reads only.
    property var _queuedByKey: ({})
    property int _nextRequestId: 1
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)

    function _invokeCallbacks(entry, response) {
        const callbacks = entry ? (entry.callbacks || []) : []
        for (let i = 0; i < callbacks.length; i++) {
            try {
                callbacks[i](response)
            } catch (error) {
                console.warn("[" + logName + "] callback error: " + error)
            }
        }
    }

    readonly property var _core: Core.makeClientCore({
        name: client.logName,
        daemonName: client.daemonName,
        timeoutName: client.timeoutName,
        readOperations: client.readOperations,
        requestTimeoutMs: client.requestTimeoutMs,
        requestTimeoutOverrides: client.requestTimeoutOverrides,
        maxQueueSize: client.maxQueueSize,
        protocolVersion: client.protocolVersion,
        getSocket: function() { return client.socket },
        invokeCallbacks: function(entry, response) {
            client._invokeCallbacks(entry, response)
        },
        eventReceived: function(name, payload) {
            client.eventReceived(name, payload)
        },
        callLater: function(fn) { Qt.callLater(fn) },
        state: {
            get queue() { return client._queue },
            set queue(value) { client._queue = value },
            get pending() { return client._pending },
            set pending(value) { client._pending = value },
            get queuedByKey() { return client._queuedByKey },
            set queuedByKey(value) { client._queuedByKey = value },
            get nextRequestId() { return client._nextRequestId },
            set nextRequestId(value) { client._nextRequestId = value }
        }
    })

    function request(operation, payload, callback) {
        return _core.request(operation, payload, callback)
    }

    function _expireRequests() {
        _core.expireRequests()
    }

    function _flush() {
        _core.flush()
    }

    function _readLine(raw) {
        _core.readLine(raw)
    }

    function _failAll(code, message) {
        _core.failAll(code, message)
    }

    property Timer _timeoutSweep: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: client._expireRequests()
    }

    // Quickshell's Socket makes exactly one connectToServer attempt per
    // instance: a successful connect clears its retry flag, and a failed
    // attempt leaves a dead socket object that blocks later setConnected()
    // calls — so once a live connection drops it never reconnects on its
    // own. Reconnection is driven here instead: while enabled and
    // disconnected a fresh Socket replaces the dead one until the daemon
    // answers.
    property bool _socketErrorWarned: false
    property Component socketFactory: Component {
        Socket {
            id: socketInstance
            // Set by _reconnect() before its replacement is created. A
            // socket's handlers stay live until its deferred destroy() runs,
            // so a stale instance must never drive client state — a late
            // disconnect would otherwise fail the fresh socket's requests.
            // (An identity check cannot work here: a local socket emits
            // connected() synchronously inside createObject(), before the
            // `socket` property has been assigned.)
            property bool stale: false
            path: client.socketPath
            // Connected by the client once installed as `socket`: a local
            // socket can emit connected() synchronously during createObject,
            // so connecting only after assignment keeps every handler
            // observing a consistent `client.socket`.
            connected: false
            parser: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    if (!socketInstance.stale)
                        client._readLine(data)
                }
            }
            onConnectedChanged: {
                if (socketInstance.stale)
                    return
                if (connected) {
                    client._socketErrorWarned = false
                    client._flush()
                } else {
                    client._failAll("disconnected",
                        client.daemonName + " disconnected")
                }
                client.transportChanged(connected)
            }
            onError: error => {
                if (socketInstance.stale)
                    return
                if (!client._socketErrorWarned) {
                    client._socketErrorWarned = true
                    console.warn("[" + client.logName + "] socket error: " + error)
                }
            }
        }
    }
    property Socket socket: socketFactory.createObject(client)

    onSocketChanged: if (socket) socket.connected = enabled
    onEnabledChanged: if (socket) socket.connected = enabled

    function _reconnect() {
        const old = socket
        if (old)
            old.stale = true
        socket = socketFactory.createObject(client)
        if (old)
            old.destroy()
    }

    property Timer _reconnectTimer: Timer {
        interval: 2000
        repeat: true
        running: client.enabled && !(client.socket && client.socket.connected)
        onTriggered: client._reconnect()
    }
}
