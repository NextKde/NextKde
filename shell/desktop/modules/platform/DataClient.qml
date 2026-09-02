pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// JSONL client for the durable Go data service. It deliberately has a
// separate socket and pending-request table from PlatformClient so restarting
// either service cannot corrupt the other's response stream.
QtObject {
    id: client

    readonly property int protocolVersion: 1
    // KOS_DATA_SOCKET redirects the shell to a development data service
    // (kosctl dev); unset in the installed layout.
    readonly property string socketPath:
        Quickshell.env("KOS_DATA_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kos-data.sock")
    property bool enabled: true
    property var _queue: []
    property var _pending: ({})
    property int _nextRequestId: 1
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)

    function _requestId() {
        return String(Date.now()) + "-" + String(_nextRequestId++)
    }

    function request(operation, payload, callback) {
        const requestId = _requestId()
        _pending[requestId] = callback || null
        _queue.push({ version: protocolVersion, requestId: requestId,
            operation: String(operation || ""), payload: payload || ({}) })
        _flush()
        return requestId
    }

    function _flush() {
        if (!socket.connected)
            return
        while (_queue.length > 0)
            socket.write(JSON.stringify(_queue.shift()) + "\n")
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
        const callback = _pending[requestId]
        delete _pending[requestId]
        if (callback)
            callback(message)
    }

    property Socket socket: Socket {
        path: client.socketPath
        connected: client.enabled
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => client._readLine(data)
        }
        onConnectedChanged: {
            client.transportChanged(connected)
            if (connected)
                client._flush()
        }
        onError: error => console.warn("[DataClient] socket error: " + error)
    }
}
