pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// One connection shared by all shell surfaces. Requests are versioned JSONL
// messages and callbacks are kept in-memory until the platform daemon replies.
// A disconnected daemon is not fatal, but nothing buffers forever either:
// read-only operations queue with deduplication and a hard cap so a long
// outage cannot accumulate thousands of stale polls, while writes fail
// immediately instead of replaying after the reconnect. Sent-but-unanswered
// requests expire on a timeout, and a disconnect fails everything
// outstanding, so no in-flight flag in a consumer can stay wedged.
QtObject {
    id: client

    readonly property int protocolVersion: 1
    // KOS_PLATFORM_SOCKET redirects the shell to a development daemon (kosctl
    // dev); unset in the installed layout.
    readonly property string socketPath:
        Quickshell.env("KOS_PLATFORM_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kos-platform.sock")
    property bool enabled: true
    // Public transport state for status surfaces; guarded so callers never
    // dereference the lazily created socket while it is null.
    readonly property bool connected: !!(socket && socket.connected)
    // Idempotent reads may queue while the transport is down and flush once
    // on reconnect. Everything else is treated as a write: it fails
    // immediately while disconnected so a stale "empty trash" or "power off"
    // can never replay an hour after the user clicked it.
    readonly property var readOperations: ({
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
    readonly property int maxQueueSize: 200
    readonly property int requestTimeoutMs: 30000
    // Per-operation expiry overrides for requests whose legitimate duration
    // exceeds the default: interactive screenshots and multi-gigabyte file
    // operations are unbounded (the daemon keeps working regardless, so a
    // client-side timeout would only report a false failure), while Wi-Fi
    // and Bluetooth association can legitimately approach a minute.
    // 0 disables expiry entirely.
    readonly property var requestTimeoutOverrides: ({
        "bluetooth.connect": 90000,
        "bluetooth.disconnect": 90000,
        "file.copy": 0,
        "file.empty-trash": 0,
        "file.transfer": 0,
        "network.connect": 90000,
        "network.connect-enterprise": 90000,
        "screenshot.capture": 0
    })
    property var _queue: []
    // requestId -> { callbacks: [...], enqueuedAt: epoch ms, sentAt: epoch ms
    // (0 while queued), dedupKey: string, timeoutMs: int }
    property var _pending: ({})
    // dedupKey -> requestId, for queued idempotent reads only.
    property var _queuedByKey: ({})
    property int _nextRequestId: 1
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)

    function _requestId() {
        return String(Date.now()) + "-" + String(_nextRequestId++)
    }

    function _failure(requestId, code, message) {
        return { version: protocolVersion, requestId: requestId, ok: false,
            error: { code: code, message: message, retryable: true } }
    }

    function _invokeCallbacks(entry, response) {
        const callbacks = entry ? (entry.callbacks || []) : []
        for (let i = 0; i < callbacks.length; i++) {
            try {
                callbacks[i](response)
            } catch (error) {
                console.warn("[PlatformClient] callback error: " + error)
            }
        }
    }

    function request(operation, payload, callback) {
        const op = String(operation || "")
        const isRead = readOperations[op] === true
        const requestId = _requestId()

        if ((!socket || !socket.connected) && !isRead) {
            // Writes are never buffered across a disconnect. The callback is
            // deferred so callers observe the same asynchronous timing as a
            // real response.
            if (callback)
                Qt.callLater(function() {
                    _invokeCallbacks({ callbacks: [callback] },
                        _failure(requestId, "disconnected",
                            "platform daemon unavailable"))
                })
            return requestId
        }

        const timeoutOverride = requestTimeoutOverrides[op]
        const entry = {
            callbacks: callback ? [callback] : [],
            enqueuedAt: Date.now(),
            sentAt: 0,
            dedupKey: "",
            timeoutMs: timeoutOverride !== undefined
                ? Number(timeoutOverride) : requestTimeoutMs
        }
        _pending[requestId] = entry

        if (isRead) {
            // Only the newest queued read for the same operation+payload
            // survives; superseded callers share its callback so their
            // bookkeeping still resolves.
            const dedupKey = op + " " + JSON.stringify(payload || ({}))
            entry.dedupKey = dedupKey
            const previousId = _queuedByKey[dedupKey]
            if (previousId !== undefined) {
                const previous = _pending[previousId]
                if (previous)
                    entry.callbacks = previous.callbacks.concat(entry.callbacks)
                delete _pending[previousId]
                _dropQueued(previousId)
            }
            _queuedByKey[dedupKey] = requestId
        }

        _queue.push({ version: protocolVersion, requestId: requestId,
            operation: op, payload: payload || ({}) })
        _enforceQueueLimit()
        _flush()
        return requestId
    }

    function _enforceQueueLimit() {
        while (_queue.length > maxQueueSize) {
            let index = -1
            for (let i = 0; i < _queue.length; i++) {
                if (readOperations[_queue[i].operation] === true) {
                    index = i
                    break
                }
            }
            // Only reads can actually sit in the queue; if nothing is
            // droppable, reject the request that just arrived instead.
            if (index < 0)
                index = _queue.length - 1
            const dropped = _queue.splice(index, 1)[0]
            _failRequestLater(dropped.requestId, "queue-overflow",
                "platform request queue full")
        }
    }

    // A failed queued entry must leave the queue too, or it would still be
    // written on reconnect and answered into the void.
    function _dropQueued(requestId) {
        for (let i = 0; i < _queue.length; i++) {
            if (_queue[i].requestId === requestId) {
                _queue.splice(i, 1)
                return
            }
        }
    }

    // Removes the bookkeeping immediately but delivers the failure on the
    // next event turn: this runs inside request(), so a synchronous callback
    // would break the callers' assumption that request() returns first.
    function _failRequestLater(requestId, code, message) {
        const entry = _pending[requestId]
        if (entry === undefined)
            return
        delete _pending[requestId]
        _dropQueued(requestId)
        if (entry.dedupKey && _queuedByKey[entry.dedupKey] === requestId)
            delete _queuedByKey[entry.dedupKey]
        const response = _failure(requestId, code, message)
        Qt.callLater(function() { _invokeCallbacks(entry, response) })
    }

    function _failRequest(requestId, code, message) {
        const entry = _pending[requestId]
        if (entry === undefined)
            return
        delete _pending[requestId]
        _dropQueued(requestId)
        if (entry.dedupKey && _queuedByKey[entry.dedupKey] === requestId)
            delete _queuedByKey[entry.dedupKey]
        _invokeCallbacks(entry, _failure(requestId, code, message))
    }

    // Snapshots the tables before invoking callbacks: a failure handler may
    // issue a fresh request, which must land in the post-disconnect queue.
    function _failAll(code, message) {
        const pending = _pending
        _pending = ({})
        _queue = []
        _queuedByKey = ({})
        for (const requestId in pending)
            _invokeCallbacks(pending[requestId],
                _failure(requestId, code, message))
    }

    // Queued entries count from enqueue and sent ones from send: either way
    // a request gets ~timeoutMs to resolve before its callback is failed and
    // its callers' in-flight flags release — even mid-outage.
    function _expireRequests() {
        const now = Date.now()
        const expired = []
        for (const requestId in _pending) {
            const entry = _pending[requestId]
            if (!entry || entry.timeoutMs <= 0)
                continue
            const since = entry.sentAt > 0 ? entry.sentAt : entry.enqueuedAt
            if (now - since > entry.timeoutMs)
                expired.push(requestId)
        }
        for (let i = 0; i < expired.length; i++)
            _failRequest(expired[i], "timeout", "platform request timed out")
    }

    function _flush() {
        if (!socket || !socket.connected)
            return
        while (_queue.length > 0) {
            const message = _queue.shift()
            const entry = _pending[message.requestId]
            if (entry) {
                entry.sentAt = Date.now()
                if (entry.dedupKey
                        && _queuedByKey[entry.dedupKey] === message.requestId)
                    delete _queuedByKey[entry.dedupKey]
            }
            socket.write(JSON.stringify(message) + "\n")
        }
        socket.flush()
    }

    function _readLine(raw) {
        let message
        try {
            message = JSON.parse(String(raw).trim())
        } catch (error) {
            console.warn("[PlatformClient] invalid response: " + error)
            return
        }
        if (message.event) {
            eventReceived(String(message.event), message.payload || ({}))
            return
        }
        const requestId = String(message.requestId || "")
        if (!requestId || _pending[requestId] === undefined)
            return
        const entry = _pending[requestId]
        delete _pending[requestId]
        _invokeCallbacks(entry, message)
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
                        "platform daemon disconnected")
                }
                client.transportChanged(connected)
            }
            onError: error => {
                if (socketInstance.stale)
                    return
                if (!client._socketErrorWarned) {
                    client._socketErrorWarned = true
                    console.warn("[PlatformClient] socket error: " + error)
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
