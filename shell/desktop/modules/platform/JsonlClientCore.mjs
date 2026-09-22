// Shared transport core for the JSONL socket clients (PlatformClient and
// DataClient). The two singletons differ only in socket path, the read
// operation set, per-operation timeout overrides and log/daemon naming; the
// queue/dedup/timeout/readline logic lived in both files line for line, so a
// fix in one routinely missed the other. It lives here once now, behind a
// factory whose `config` supplies exactly those differences:
//
//   makeClientCore({
//       name: "PlatformClient",            // log prefix
//       daemonName: "platform daemon",     // "unavailable"/"disconnected"
//       timeoutName: "platform",           // "request timed out"/"queue full"
//       readOperations: { "platform.ping": true, ... },
//       requestTimeoutMs: 30000,
//       requestTimeoutOverrides: { "file.copy": 0, ... },  // optional
//       maxQueueSize: 200,                 // optional
//       protocolVersion: 1,                // optional
//       getSocket: () => client.socket,    // transport accessors
//       invokeCallbacks: (entry, response) => ...,
//       eventReceived: (name, payload) => ...,
//       callLater: fn => Qt.callLater(fn),
//   })
//
// The returned object also exposes the state tables (`queue`, `pending`,
// `queuedByKey`, `nextRequestId`) so the owning QML object can keep them as
// bindable properties: pass an object whose getters/setters forward to those
// properties as `config.state`; without one the core keeps its own tables.
// failAll() swaps the pending/queue/dedup tables wholesale, which is why the
// state indirection goes through getters/setters rather than captured
// references. `invokeCallbacks`, `callLater` and `now` are injectable so
// platform/tests/test_jsonl_client.mjs can drive the same code without a
// QML engine.

export function failure(protocolVersion, requestId, code, message) {
    return { version: protocolVersion, requestId: requestId, ok: false,
        error: { code: code, message: message, retryable: true } };
}

export function makeClientCore(config) {
    const protocolVersion = config.protocolVersion !== undefined
        ? config.protocolVersion : 1;
    const requestTimeoutMs = config.requestTimeoutMs !== undefined
        ? config.requestTimeoutMs : 30000;
    const requestTimeoutOverrides = config.requestTimeoutOverrides || ({});
    const maxQueueSize = config.maxQueueSize !== undefined
        ? config.maxQueueSize : 200;
    const readOperations = config.readOperations || ({});
    const callLater = config.callLater;
    const now = config.now || Date.now;
    const log = message => console.warn("[" + config.name + "] " + message);
    // PlatformClient's timeout/queue-full messages historically said
    // "platform" while its disconnect messages said "platform daemon";
    // DataClient used "data service" for both. Keep the strings identical.
    const timeoutName = config.timeoutName || config.daemonName;
    const state = config.state || {
        queue: [],
        pending: ({}),
        queuedByKey: ({}),
        nextRequestId: 1
    };

    function makeFailure(requestId, code, message) {
        return failure(protocolVersion, requestId, code, message);
    }

    function requestId() {
        return String(now()) + "-" + String(state.nextRequestId++);
    }

    function socketConnected() {
        const socket = config.getSocket();
        return !!(socket && socket.connected);
    }

    function request(operation, payload, callback) {
        const op = String(operation || "");
        const isRead = readOperations[op] === true;
        const id = requestId();

        if (!socketConnected() && !isRead) {
            // Writes are never buffered across a disconnect. The callback is
            // deferred so callers observe the same asynchronous timing as a
            // real response.
            if (callback)
                callLater(function() {
                    config.invokeCallbacks({ callbacks: [callback] },
                        makeFailure(id, "disconnected",
                            config.daemonName + " unavailable"));
                });
            return id;
        }

        const timeoutOverride = requestTimeoutOverrides[op];
        const entry = {
            callbacks: callback ? [callback] : [],
            enqueuedAt: now(),
            sentAt: 0,
            dedupKey: "",
            timeoutMs: timeoutOverride !== undefined
                ? Number(timeoutOverride) : requestTimeoutMs
        };
        state.pending[id] = entry;

        if (isRead) {
            // Only the newest queued read for the same operation+payload
            // survives; superseded callers share its callback so their
            // bookkeeping still resolves.
            const dedupKey = op + " " + JSON.stringify(payload || ({}));
            entry.dedupKey = dedupKey;
            const previousId = state.queuedByKey[dedupKey];
            if (previousId !== undefined) {
                const previous = state.pending[previousId];
                if (previous)
                    entry.callbacks = previous.callbacks.concat(entry.callbacks);
                delete state.pending[previousId];
                dropQueued(previousId);
            }
            state.queuedByKey[dedupKey] = id;
        }

        state.queue.push({ version: protocolVersion, requestId: id,
            operation: op, payload: payload || ({}) });
        enforceQueueLimit();
        flush();
        return id;
    }

    function enforceQueueLimit() {
        while (state.queue.length > maxQueueSize) {
            let index = -1;
            for (let i = 0; i < state.queue.length; i++) {
                if (readOperations[state.queue[i].operation] === true) {
                    index = i;
                    break;
                }
            }
            // Only reads can actually sit in the queue; if nothing is
            // droppable, reject the request that just arrived instead.
            if (index < 0)
                index = state.queue.length - 1;
            const dropped = state.queue.splice(index, 1)[0];
            failRequestLater(dropped.requestId, "queue-overflow",
                timeoutName + " request queue full");
        }
    }

    // A failed queued entry must leave the queue too, or it would still be
    // written on reconnect and answered into the void.
    function dropQueued(requestId) {
        for (let i = 0; i < state.queue.length; i++) {
            if (state.queue[i].requestId === requestId) {
                state.queue.splice(i, 1);
                return;
            }
        }
    }

    // Removes the bookkeeping immediately but delivers the failure on the
    // next event turn: this runs inside request(), so a synchronous callback
    // would break the callers' assumption that request() returns first.
    function failRequestLater(id, code, message) {
        const entry = state.pending[id];
        if (entry === undefined)
            return;
        delete state.pending[id];
        dropQueued(id);
        if (entry.dedupKey && state.queuedByKey[entry.dedupKey] === id)
            delete state.queuedByKey[entry.dedupKey];
        const response = makeFailure(id, code, message);
        callLater(function() { config.invokeCallbacks(entry, response) });
    }

    function failRequest(id, code, message) {
        const entry = state.pending[id];
        if (entry === undefined)
            return;
        delete state.pending[id];
        dropQueued(id);
        if (entry.dedupKey && state.queuedByKey[entry.dedupKey] === id)
            delete state.queuedByKey[entry.dedupKey];
        config.invokeCallbacks(entry, makeFailure(id, code, message));
    }

    // Snapshots the tables before invoking callbacks: a failure handler may
    // issue a fresh request, which must land in the post-disconnect queue.
    function failAll(code, message) {
        const pending = state.pending;
        state.pending = ({});
        state.queue = [];
        state.queuedByKey = ({});
        for (const id in pending)
            config.invokeCallbacks(pending[id],
                makeFailure(id, code, message));
    }

    // Queued entries count from enqueue and sent ones from send: either way
    // a request gets ~timeoutMs to resolve before its callback is failed and
    // its callers' in-flight flags release — even mid-outage.
    function expireRequests() {
        const nowMs = now();
        const expired = [];
        for (const id in state.pending) {
            const entry = state.pending[id];
            if (!entry || entry.timeoutMs <= 0)
                continue;
            const since = entry.sentAt > 0 ? entry.sentAt : entry.enqueuedAt;
            if (nowMs - since > entry.timeoutMs)
                expired.push(id);
        }
        for (let i = 0; i < expired.length; i++)
            failRequest(expired[i], "timeout",
                timeoutName + " request timed out");
    }

    function flush() {
        const socket = config.getSocket();
        if (!socket || !socket.connected)
            return;
        while (state.queue.length > 0) {
            const message = state.queue.shift();
            const entry = state.pending[message.requestId];
            if (entry) {
                entry.sentAt = now();
                if (entry.dedupKey
                        && state.queuedByKey[entry.dedupKey] === message.requestId)
                    delete state.queuedByKey[entry.dedupKey];
            }
            socket.write(JSON.stringify(message) + "\n");
        }
        socket.flush();
    }

    function readLine(raw) {
        let message;
        try {
            message = JSON.parse(String(raw).trim());
        } catch (error) {
            log("invalid response: " + error);
            return;
        }
        if (message.event) {
            config.eventReceived(String(message.event), message.payload || ({}));
            return;
        }
        const requestId = String(message.requestId || "");
        if (!requestId || state.pending[requestId] === undefined)
            return;
        const entry = state.pending[requestId];
        delete state.pending[requestId];
        config.invokeCallbacks(entry, message);
    }

    return {
        get queue() { return state.queue },
        set queue(value) { state.queue = value },
        get pending() { return state.pending },
        set pending(value) { state.pending = value },
        get queuedByKey() { return state.queuedByKey },
        set queuedByKey(value) { state.queuedByKey = value },
        get nextRequestId() { return state.nextRequestId },
        set nextRequestId(value) { state.nextRequestId = value },
        request: request,
        dropQueued: dropQueued,
        failRequestLater: failRequestLater,
        failRequest: failRequest,
        failAll: failAll,
        expireRequests: expireRequests,
        flush: flush,
        readLine: readLine
    };
}
