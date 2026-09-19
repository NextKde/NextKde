pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// JSONL client for the durable Go data service. It deliberately has a
// separate socket and pending-request table from PlatformClient so restarting
// either service cannot corrupt the other's response stream.
// The disconnect semantics match PlatformClient: reads queue bounded and
// deduplicated, writes fail fast, sent-but-unanswered requests expire, and a
// disconnect fails everything outstanding so consumer state cannot wedge.
QtObject {
    id: client

    readonly property int protocolVersion: 1
    // KOS_DATA_SOCKET redirects the shell to a development data service
    // (kosctl dev); unset in the installed layout.
    readonly property string socketPath:
        Quickshell.env("KOS_DATA_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kos-data.sock")
    property bool enabled: true
    // Public transport state for status surfaces; guarded so callers never
    // dereference the lazily created socket while it is null.
    readonly property bool connected: !!(socket && socket.connected)
    // Snapshot reads may queue while the transport is down and flush once on
    // reconnect. Reports such as activity.active-app are writes: they fail
    // immediately while disconnected so nothing stale replays afterwards.
    readonly property var readOperations: ({
        "activity.snapshot": true,
        "desktop.refresh": true,
        "desktop.snapshot": true,
        "metrics.snapshot": true,
        "weather.refresh": true,
        "weather.snapshot": true
    })
    readonly property int maxQueueSize: 200
    readonly property int requestTimeoutMs: 30000
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
                console.warn("[DataClient] callback error: " + error)
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
                            "data service unavailable"))
                })
            return requestId
        }

        const entry = {
            callbacks: callback ? [callback] : [],
            enqueuedAt: Date.now(),
            sentAt: 0,
            dedupKey: "",
            timeoutMs: requestTimeoutMs
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
                "data service request queue full")
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
            _failRequest(expired[i], "timeout", "data service request timed out")
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
            console.warn("[DataClient] invalid response: " + error)
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
                        "data service disconnected")
                }
                client.transportChanged(connected)
            }
            onError: error => {
                if (socketInstance.stale)
                    return
                if (!client._socketErrorWarned) {
                    client._socketErrorWarned = true
                    console.warn("[DataClient] socket error: " + error)
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
