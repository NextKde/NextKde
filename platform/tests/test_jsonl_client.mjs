// Node harness for the shared JSONL transport core behind PlatformClient and
// DataClient (shell/desktop/modules/platform/JsonlClientCore.mjs). Run
// directly:
//
//   node platform/tests/test_jsonl_client.mjs
//
// The socket itself is Quickshell's and cannot exist here, so each test stubs
// it with a FakeSocket (a write log + a connected flag). Everything else —
// dedup, queue cap, expiry, half-line handling, the disconnect fail-all — is
// the real production code path. Cases below are the daemon-restart failure
// modes this layer used to have zero coverage for.

import assert from "node:assert/strict";
import { makeClientCore } from "../../shell/desktop/modules/platform/JsonlClientCore.mjs";

const READ_OPS = {
    "test.read": true,
    "test.readOther": true
};

function makeClient(options = {}) {
    // Deferred callbacks mirror Qt.callLater: collected, then pumped.
    const deferred = [];
    const written = [];
    const events = [];
    const socket = {
        connected: options.connected !== undefined ? options.connected : true,
        write: data => written.push(data),
        flush: () => {}
    };
    let time = options.now !== undefined ? options.now : 1000000;
    const callbacks = [];
    const core = makeClientCore({
        name: "TestClient",
        daemonName: "test daemon",
        readOperations: READ_OPS,
        requestTimeoutMs: options.requestTimeoutMs !== undefined
            ? options.requestTimeoutMs : 30000,
        requestTimeoutOverrides: options.requestTimeoutOverrides || ({}),
        maxQueueSize: options.maxQueueSize !== undefined
            ? options.maxQueueSize : 200,
        getSocket: () => socket,
        invokeCallbacks: (entry, response) => {
            for (const fn of entry.callbacks || [])
                fn(response);
        },
        eventReceived: (name, payload) => events.push({ name, payload }),
        callLater: fn => deferred.push(fn),
        now: () => time
    });
    return {
        core,
        socket,
        written,
        events,
        deferred,
        // Advance the injectable clock.
        tick: ms => { time += ms; },
        pumpDeferred: () => {
            const batch = deferred.splice(0);
            for (const fn of batch) fn();
        },
        // Every line the daemon would have written to the socket.
        lines: () => written.join("").split("\n").filter(l => l.length > 0),
        respond: (requestId, result) =>
            core.readLine(JSON.stringify({
                version: 1, requestId: requestId, ok: true,
                result: result || ({})
            }))
    };
}

// A successful round trip: request goes on the wire, reply reaches the
// callback, pending bookkeeping empties.
{
    const c = makeClient();
    const seen = [];
    const id = c.core.request("test.read", { k: 1 }, r => seen.push(r));
    assert.equal(c.lines().length, 1);
    const wire = JSON.parse(c.lines()[0]);
    assert.equal(wire.requestId, id);
    assert.equal(wire.operation, "test.read");
    assert.deepEqual(wire.payload, { k: 1 });
    c.respond(id);
    assert.equal(seen.length, 1);
    assert.equal(seen[0].ok, true);
    assert.equal(Object.keys(c.core.pending).length, 0);
    console.log("ok  round-trip");
}

// Writes fail fast while disconnected — deferred, never buffered.
{
    const c = makeClient({ connected: false });
    const seen = [];
    const id = c.core.request("test.write", {}, r => seen.push(r));
    assert.equal(c.written.length, 0);
    assert.equal(c.core.queue.length, 0);
    // The failure must not have fired synchronously.
    assert.equal(seen.length, 0);
    c.pumpDeferred();
    assert.equal(seen.length, 1);
    assert.equal(seen[0].ok, false);
    assert.equal(seen[0].error.code, "disconnected");
    assert.equal(Object.keys(c.core.pending).length, 0);
    console.log("ok  write fails fast while disconnected (deferred)");
}

// Reads queue while disconnected and flush once on reconnect.
{
    const c = makeClient({ connected: false });
    const seen = [];
    c.core.request("test.read", { a: 1 }, r => seen.push(r));
    c.core.request("test.readOther", {}, r => seen.push(r));
    assert.equal(c.written.length, 0);
    assert.equal(c.core.queue.length, 2);
    assert.equal(Object.keys(c.core.pending).length, 2);

    // Daemon comes back; _flush writes the backlog in order.
    c.socket.connected = true;
    c.core.flush();
    assert.equal(c.lines().length, 2);
    assert.equal(JSON.parse(c.lines()[0]).operation, "test.read");
    assert.equal(JSON.parse(c.lines()[1]).operation, "test.readOther");
    console.log("ok  reads queue and flush on reconnect");
}

// Dedup: a second identical queued read supersedes the first and inherits its
// callback, so both callers resolve off one wire request.
{
    const c = makeClient({ connected: false });
    const seen1 = [];
    const seen2 = [];
    const id1 = c.core.request("test.read", { a: 1 }, r => seen1.push(r));
    const id2 = c.core.request("test.read", { a: 1 }, r => seen2.push(r));
    assert.notEqual(id1, id2);
    // Only the newest request survives in pending and the queue.
    assert.equal(c.core.pending[id1], undefined);
    assert.equal(c.core.queue.length, 1);
    assert.equal(JSON.parse(JSON.stringify(c.core.queue[0])).requestId, id2);
    assert.equal(c.core.queuedByKey["test.read {\"a\":1}"], id2);

    c.socket.connected = true;
    c.core.flush();
    assert.equal(c.lines().length, 1, "dedup must merge to one wire request");
    c.respond(id2);
    // Both callbacks fire — the superseded caller's bookkeeping resolves.
    assert.equal(seen1.length, 1);
    assert.equal(seen2.length, 1);
    assert.equal(seen1[0].requestId, id2);
    console.log("ok  dedup merges queued identical reads");
}

// Stale dedup key: after the queued request is flushed, _queuedByKey is
// cleared; a repeat read while the first is in flight is NOT deduped.
{
    const c = makeClient();
    const id1 = c.core.request("test.read", { a: 1 }, () => {});
    assert.equal(Object.keys(c.core.queuedByKey).length, 0,
        "sent request must clear its dedup key");
    const id2 = c.core.request("test.read", { a: 1 }, () => {});
    assert.notEqual(id1, id2);
    assert.equal(c.core.pending[id1] !== undefined, true);
    assert.equal(c.core.pending[id2] !== undefined, true);
    console.log("ok  dedup key does not outlive the queued state");
}

// Stale dedup key the other way: expiry removes a queued request, and a later
// identical read must not merge into the dead entry.
{
    const c = makeClient({ connected: false, requestTimeoutMs: 1000 });
    const seen = [];
    c.core.request("test.read", { a: 1 }, r => seen.push(r));
    c.tick(2000);
    c.core.expireRequests();
    assert.equal(seen.length, 1);
    assert.equal(seen[0].error.code, "timeout");
    assert.equal(Object.keys(c.core.queuedByKey).length, 0,
        "expired request must drop its dedup key");
    // A fresh read with the same key starts clean.
    const seen2 = [];
    const id = c.core.request("test.read", { a: 1 }, r => seen2.push(r));
    assert.equal(c.core.pending[id] !== undefined, true);
    assert.equal(c.core.queue.length, 1);
    console.log("ok  expiry clears _queuedByKey (no stale key)");
}

// Timeout: sent-but-unanswered requests fail with code "timeout" once past
// their budget, and the callback still fires exactly once.
{
    const c = makeClient({ requestTimeoutMs: 1000 });
    const seen = [];
    const id = c.core.request("test.read", {}, r => seen.push(r));
    c.tick(1500);
    c.core.expireRequests();
    assert.equal(seen.length, 1);
    assert.equal(seen[0].ok, false);
    assert.equal(seen[0].error.code, "timeout");
    // A late reply is ignored — no second callback.
    c.respond(id);
    assert.equal(seen.length, 1);
    console.log("ok  sent request expires, late reply ignored");
}

// Timeout override 0: never expires (the file.transfer/screenshot.capture
// contract — the daemon keeps working, a client timeout would lie).
{
    const c = makeClient({ requestTimeoutOverrides: { "test.write": 0 } });
    const seen = [];
    c.core.request("test.write", {}, r => seen.push(r));
    c.tick(600000);
    c.core.expireRequests();
    assert.equal(seen.length, 0);
    assert.equal(Object.keys(c.core.pending).length, 1);
    console.log("ok  timeout override 0 never expires");
}

// Queued requests age too: expiry counts from enqueue while disconnected, so
// a daemon outage cannot wedge a caller's in-flight flag forever.
{
    const c = makeClient({ connected: false, requestTimeoutMs: 1000 });
    const seen = [];
    c.core.request("test.read", {}, r => seen.push(r));
    c.tick(1500);
    c.core.expireRequests();
    assert.equal(seen.length, 1);
    assert.equal(seen[0].error.code, "timeout");
    assert.equal(c.core.queue.length, 0);
    console.log("ok  queued request expires mid-outage");
}

// Disconnect fails everything outstanding — sent and queued — and clears all
// tables so nothing replays after reconnect.
{
    const c = makeClient();
    const seenA = [];
    const seenB = [];
    c.core.request("test.read", { a: 1 }, r => seenA.push(r));
    c.socket.connected = false;
    c.core.request("test.readOther", {}, r => seenB.push(r));
    assert.equal(c.core.queue.length, 1);
    c.core.failAll("disconnected", "test daemon disconnected");
    assert.equal(seenA.length, 1);
    assert.equal(seenA[0].error.code, "disconnected");
    assert.equal(seenB.length, 1);
    assert.equal(seenB[0].error.code, "disconnected");
    assert.equal(c.core.queue.length, 0);
    assert.equal(Object.keys(c.core.pending).length, 0);
    assert.equal(Object.keys(c.core.queuedByKey).length, 0);

    // A failure handler that re-requests lands in the post-disconnect queue,
    // not the failed batch — exercised by snapshotting inside failAll.
    const c2 = makeClient();
    let requeued = false;
    c2.core.request("test.read", {}, () => {
        requeued = true;
        c2.core.request("test.readOther", {}, () => {});
    });
    c2.socket.connected = false;
    c2.core.failAll("disconnected", "test daemon disconnected");
    assert.equal(requeued, true);
    assert.equal(c2.core.queue.length, 1);
    assert.equal(JSON.parse(JSON.stringify(c2.core.queue[0])).operation,
        "test.readOther");
    console.log("ok  disconnect fails all, re-request lands post-failAll");
}

// Half-lines: the parser splits on '\n' before readLine ever runs, so a
// truncated chunk must be an isolated warning, not a crash or a lost entry.
// readLine is called per complete line; feed it garbage and a valid line.
{
    const c = makeClient();
    const seen = [];
    const id = c.core.request("test.read", {}, r => seen.push(r));
    // A partial/garbled chunk (what a half-received line looks like when the
    // socket parser hands us a fragment that isn't JSON yet) must not throw.
    const warnings = [];
    const origWarn = console.warn;
    console.warn = m => warnings.push(m);
    try {
        c.core.readLine("{\"version\":1,\"requ");
        c.core.readLine("not json at all");
        c.core.readLine("");
    } finally {
        console.warn = origWarn;
    }
    assert.equal(warnings.length, 3, "invalid lines warn and are skipped");
    assert.equal(c.core.pending[id] !== undefined, true,
        "garbage must not disturb pending state");
    c.respond(id);
    assert.equal(seen.length, 1);
    console.log("ok  invalid/half lines are skipped without state damage");
}

// Oversized line: a multi-megabyte response parses and routes normally.
{
    const c = makeClient();
    const seen = [];
    const id = c.core.request("test.read", {}, r => seen.push(r));
    const big = "x".repeat(4 * 1024 * 1024);
    c.core.readLine(JSON.stringify({
        version: 1, requestId: id, ok: true, result: { blob: big }
    }));
    assert.equal(seen.length, 1);
    assert.equal(seen[0].result.blob.length, big.length);
    console.log("ok  4 MiB response line routes correctly");
}

// Events route to eventReceived, not the pending table.
{
    const c = makeClient();
    c.core.readLine(JSON.stringify({ event: "audio.changed", payload: { n: 2 } }));
    assert.equal(c.events.length, 1);
    assert.equal(c.events[0].name, "audio.changed");
    assert.deepEqual(c.events[0].payload, { n: 2 });
    // Unknown requestId lines are dropped silently.
    c.core.readLine(JSON.stringify({ requestId: "nobody", ok: true }));
    console.log("ok  events and stray replies handled");
}

// Queue cap: reads drop oldest-first with a deferred "queue-overflow"
// failure; the queue never exceeds maxQueueSize.
{
    const c = makeClient({ connected: false, maxQueueSize: 5 });
    const failed = [];
    for (let i = 0; i < 8; i++)
        c.core.request("test.read", { i: i }, r => failed.push(r));
    assert.equal(c.core.queue.length, 5);
    c.pumpDeferred();
    // 3 dropped, each the oldest read at the time.
    assert.equal(failed.length, 3);
    assert.ok(failed.every(r => r.error.code === "queue-overflow"));
    assert.equal(Object.keys(c.core.pending).length, 5);
    console.log("ok  queue cap drops oldest reads with queue-overflow");
}

// Callback exceptions are contained by the QML side (_invokeCallbacks); the
// core's contract is that invokeCallbacks is invoked once per response.
// Verified here at the seam: a throwing consumer propagates to the wrapper,
// which is where PlatformClient/DataClient wrap it in try/catch.
{
    const c = makeClient();
    let calls = 0;
    c.core.request("test.read", {}, () => { calls++; throw new Error("boom"); });
    const id = JSON.parse(c.lines()[0]).requestId;
    assert.throws(() => c.respond(id), /boom/);
    assert.equal(calls, 1);
    console.log("ok  callback invocation is single-shot at the seam");
}

console.log("all jsonl client tests passed");
