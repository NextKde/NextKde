import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("WindowService.qml", import.meta.url), "utf8");
const match = source.match(
    /^    function _handlePlatformTransport\(connected\) \{[^]*?^    \}/m);
assert.ok(match, "WindowService must own platform transport fallback logic");

let subscribed = 0;
let timerStops = 0;
const cachedWindows = [{ id: "kwin-1" }, { id: "kwin-2" }];
const cachedRecords = [{ windowId: "window-1" }, { windowId: "window-2" }];
const cachedDesktops = [{ id: "desktop-1" }];
const svc = {
    _kwinSubscribePending: true,
    _pendingKwinActivation: { action: "activate" },
    _kwinActivationTimer: { stop: () => timerStops++ },
    _kwinWindows: cachedWindows,
    _kwinReceivedInitialSnapshot: true,
    _kwinReceivedDesktopSnapshot: true,
    _lastSnapshotJson: "cached",
    desktops: cachedDesktops,
    currentDesktopId: "desktop-1",
    records: cachedRecords,
    _thumbnailPendingByHandle: { "kwin-1": true },
    _thumbnailUrlsByHandle: { "kwin-1": "file:///tmp/old.png" },
    thumbnailRevision: 4,
    _subscribeKwin: () => subscribed++,
};
const context = vm.createContext({ svc, console: { warn() {} }, Object });
vm.runInContext(match[0], context);
svc._handlePlatformTransport = context._handlePlatformTransport;

svc._handlePlatformTransport(false);
assert.equal(timerStops, 1);
assert.equal(svc._kwinSubscribePending, false);
assert.equal(svc._pendingKwinActivation, null);
assert.equal(Object.keys(svc._thumbnailPendingByHandle).length, 0);
assert.equal(Object.keys(svc._thumbnailUrlsByHandle).length, 0);
assert.equal(svc.thumbnailRevision, 5);
assert.equal(svc._kwinWindows, cachedWindows,
    "disconnect must retain the last KWin window snapshot");
assert.equal(svc.records, cachedRecords,
    "disconnect must retain Dock presentation records");
assert.equal(svc.desktops, cachedDesktops,
    "disconnect must retain virtual desktop placement");
assert.equal(svc.currentDesktopId, "desktop-1");
assert.equal(svc._kwinReceivedInitialSnapshot, true);
assert.equal(svc._kwinReceivedDesktopSnapshot, true);
assert.equal(svc._lastSnapshotJson, "cached");

svc._handlePlatformTransport(true);
assert.equal(subscribed, 1, "reconnect must request a fresh subscription");

console.log("window transport fallback: passed");
