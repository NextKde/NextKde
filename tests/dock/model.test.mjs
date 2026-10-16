import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";
import { matchEntryByHints, parseProbeOutput, probeCommand } from "../../shell/desktop/modules/dock/ProcessIdentity.mjs";
import { indexWindowRecords } from "../../shell/desktop/modules/dock/WindowRecordIndex.mjs";
import { toArray } from "../../shell/desktop/modules/dock/PayloadArray.mjs";
import { indexAt, parse } from "../../shell/desktop/modules/dock/TimedLyrics.mjs";
import { nextWindowToActivate } from "../../shell/desktop/modules/dock/WindowCycle.mjs";
import { test } from "node:test";

test("process identity", async () => {
    // The normaliser is shared with the rest of the shell, so the test runs the real
    // implementation rather than a copy that could drift away from it.
    const presentation = readFileSync(
        new URL("../../shell/desktop/modules/common/AppPresentationService.qml", import.meta.url), "utf8");
    const normalizerSource = presentation.slice(
        presentation.indexOf("    function normalize(value) {"),
        presentation.indexOf("    // QtObject has no default child property"));
    assert.ok(normalizerSource.includes("function normalize"),
        "AppPresentationService.normalize moved; update this slice");
    const context = vm.createContext({});
    vm.runInContext(normalizerSource, context);
    const normalize = context.normalize;
    assert.equal(normalize("yeshayun-4.0.11-linux-amd64.desktop"),
        "yeshayun4011linuxamd64");

    // ── probeCommand ──
    const probe = probeCommand(4242);
    assert.equal(probe[0], "sh");
    assert.equal(probe[1], "-c");
    assert.equal(probe.at(-2), "kos-window-identity");
    assert.equal(probe.at(-1), "4242");
    // The PID reaches a shell, so anything that is not an integer is discarded
    // instead of being interpolated.
    assert.equal(probeCommand("12; touch /tmp/pwned").at(-1), "0");
    assert.equal(probeCommand(-5).at(-1), "0");
    assert.equal(probeCommand(undefined).at(-1), "0");
    // Every source prints one line, so a failed read cannot shift the later hints
    // into the wrong slot.
    assert.equal((probe[2].match(/printf/g) || []).length, 3);

    // ── parseProbeOutput ──
    // A real AppImage launch: the runtime exports the file it was started from, the
    // executable lives in the mount directory, and argv[0] names the binary again.
    // The launcher path is kept first because external installers (including
    // ~/Downloads/install-appimage) name the desktop file after it.
    const appImageProbe = [
        "/home/amao/Applications/yeshayun-4.0.11-linux-amd64.appimage",
        "/tmp/.mount_yeshaABCDEF/yeshayun",
        "./yeshayun",
    ].join("\n");
    assert.deepEqual(parseProbeOutput(appImageProbe),
        ["yeshayun-4.0.11-linux-amd64", "yeshayun"]);

    // The same binary without the AppImage wrapper still yields its own name.
    assert.deepEqual(parseProbeOutput("\n/usr/lib/firefox/firefox\n/usr/bin/firefox"),
        ["firefox"]);

    // A missing source leaves an empty line rather than shifting the later ones.
    assert.deepEqual(parseProbeOutput("\n/usr/bin/hplip\nhplip"), ["hplip"]);

    // Runtimes and wrappers name the toolkit or the launcher, never the app, so a
    // match on one of them would identify the wrong entry.
    assert.deepEqual(parseProbeOutput("\n/usr/lib/electron/electron\nelectron"), []);
    assert.deepEqual(parseProbeOutput("\n/bin/sh\nsh"), []);
    assert.deepEqual(parseProbeOutput("\n/usr/bin/appimage/apprun\napprun"), []);
    assert.deepEqual(parseProbeOutput("\n/sbin/init\n/sbin/init"), []);
    assert.deepEqual(parseProbeOutput("\n/usr/bin/kdeinit6\nkdeinit6"), []);

    // Too short to be evidence.
    assert.deepEqual(parseProbeOutput("\n/usr/bin/qs\nqs"), []);

    // Nothing readable at all.
    assert.deepEqual(parseProbeOutput(""), []);
    assert.deepEqual(parseProbeOutput(undefined), []);

    // ── matchEntryByHints ──
    function entry(id, icon = "app-icon") {
        return { id, icon, name: id };
    }
    const hasIcon = app => !!app.icon;
    const catalogue = [
        entry("firefox.desktop"),
        entry("yeshayun-4.0.11-linux-amd64.desktop",
            "/home/amao/.local/share/icons/yeshayun-4.0.11-linux-amd64.png"),
        entry("code.desktop"),
    ];

    // The window reports `com.yesha.net`, which no entry carries, but the AppImage
    // the process was launched from is named exactly like the desktop file.
    assert.equal(
        matchEntryByHints(catalogue,
            ["yeshayun-4.0.11-linux-amd64", "yeshayun"], normalize, hasIcon)?.id,
        "yeshayun-4.0.11-linux-amd64.desktop");

    // The bare binary name is enough on its own: exactly one id contains it.
    assert.equal(
        matchEntryByHints(catalogue, ["yeshayun"], normalize, hasIcon)?.id,
        "yeshayun-4.0.11-linux-amd64.desktop");

    // Quickshell does not guarantee the `.desktop` suffix on `entry.id`; the shared
    // normaliser strips it either way.
    assert.equal(
        matchEntryByHints([entry("yeshayun-4.0.11-linux-amd64")], ["yeshayun"],
            normalize, hasIcon)?.id, "yeshayun-4.0.11-linux-amd64");

    // An id that normalises to the hint exactly beats a longer id containing it.
    assert.equal(
        matchEntryByHints([entry("firefox-esr.desktop"), entry("firefox.desktop")],
            ["firefox"], normalize, hasIcon)?.id, "firefox.desktop");

    // A hint shared by several entries proves nothing. The generic icon is a better
    // answer than another application's icon.
    assert.equal(
        matchEntryByHints([entry("yesha-one.desktop"), entry("yesha-two.desktop")],
            ["yesha"], normalize, hasIcon), null);

    // Two ids that normalise identically are the same app to this lookup; prefer
    // the one that can actually supply an icon.
    assert.equal(
        matchEntryByHints([entry("foo-bar.desktop", ""), entry("foo_bar.desktop")],
            ["foo-bar"], normalize, hasIcon)?.id, "foo_bar.desktop");

    // No evidence, no answer. This is also what keeps every app that already
    // resolves through its app id completely untouched by the fallback.
    assert.equal(matchEntryByHints(catalogue, [], normalize, hasIcon), null);
    assert.equal(matchEntryByHints([], ["firefox"], normalize, hasIcon), null);
    assert.equal(matchEntryByHints(catalogue, ["firefox"], null, hasIcon), null);
    assert.equal(matchEntryByHints(catalogue, ["redshift"], normalize, hasIcon), null);
    assert.equal(matchEntryByHints(catalogue, ["yeshayun", "redshift"],
        normalize, hasIcon)?.id, "yeshayun-4.0.11-linux-amd64.desktop");

    // ── The QML boundary ──
    // This is the shape that shipped broken: QML hands `list<T>` to JavaScript as a
    // V4Sequence, where `Array.isArray` is false even though length and indexing
    // work. An array-only guard disabled the entire fallback inside the shell while
    // every assertion above kept passing, because Node only ever passes real
    // Arrays. Same evidence, both container shapes, identical answer.
    function sequenceLike(items) {
        const sequence = { length: items.length };
        for (let i = 0; i < items.length; i++)
            sequence[i] = items[i];
        return sequence;
    }

    const arrayLikeCatalogue = sequenceLike(catalogue);
    assert.equal(Object.prototype.toString.call(arrayLikeCatalogue),
        "[object Object]", "the fixture must not accidentally be an Array");

    assert.equal(
        matchEntryByHints(arrayLikeCatalogue,
            sequenceLike(["yeshayun-4.0.11-linux-amd64"]), normalize, hasIcon)?.id,
        "yeshayun-4.0.11-linux-amd64.desktop",
        "array-like entries and hints must match exactly like real Arrays");
    assert.equal(
        matchEntryByHints(arrayLikeCatalogue, ["yeshayun"], normalize, hasIcon)?.id,
        "yeshayun-4.0.11-linux-amd64.desktop");
    assert.equal(
        matchEntryByHints(arrayLikeCatalogue, ["yesha"], normalize, hasIcon)?.id,
        matchEntryByHints(catalogue, ["yesha"], normalize, hasIcon)?.id,
        "array-like and real-Array input must reach the same verdict");
    assert.equal(
        matchEntryByHints(
            sequenceLike([entry("yesha-one.desktop"), entry("yesha-two.desktop")]),
            sequenceLike(["yesha"]), normalize, hasIcon), null,
        "the uniqueness guard must hold for array-like input too");

    console.log("process identity: ok");
});

test("unpin identity", async () => {
    const source=readFileSync(new URL("../../shell/desktop/modules/dock/DockModelService.qml", import.meta.url),'utf8');
    const unpin=source.match(/^    function unpinApp\(appId\) \{[^]*?^    \}/m)[0];
    let refreshes=0,saves=0;
    const config={dockItems:[{type:'app',appId:'code.desktop'},{type:'app',appId:'Code'},
        {type:'app',appId:'org.kde.dolphin.desktop'},{type:'separator'}],
        setDockItems(items){this.dockItems=items;return true;},scheduleSave(){saves++;}};
    const normalize=id=>['Code','code.desktop','com.microsoft.VSCode.desktop'].includes(id)?'vscode':id;
    const context=vm.createContext({ConfigService:config,
        AppIdentityService:{sameApp:(a,b)=>normalize(a)===normalize(b)},
        svc:{_refreshPresentation(){refreshes++;}}});
    vm.runInContext(unpin,context);
    context.unpinApp('com.microsoft.VSCode.desktop');
    assert.deepEqual(Array.from(config.dockItems,x=>x.appId||x.type),['org.kde.dolphin.desktop','separator']);
    assert.equal(saves,1);assert.equal(refreshes,1);
    context.unpinApp('missing.desktop');
    assert.equal(saves,1);assert.equal(refreshes,1);
    console.log('Unpin: removes all aliases, preserves unrelated items, saves and refreshes once');
});

test("window record index", async () => {
    const foreignTop = {};
    const records = [
        { provider: "kwin", handleId: "__proto__", windowId: "first" },
        { provider: "kwin", handleId: "__proto__", windowId: "duplicate" },
        { provider: "foreign", toplevel: foreignTop, windowId: "foreign" },
        { provider: "foreign", toplevel: {}, windowId: "other-object" },
        { provider: "unknown", handleId: "ignored" },
    ];
    const index = indexWindowRecords(records);
    assert.equal(index.kwin.get("__proto__"), records[0]);
    assert.equal(index.foreign.get(foreignTop), records[2]);
    assert.equal(index.foreign.get({}), undefined);
    assert.equal(index.kwin.get("ignored"), undefined);
    assert.equal(indexWindowRecords([]).kwin.size, 0);

    // Differential check against the previous strict-identity scan, including
    // reordered snapshots, missing IDs and distinct objects with the same fields.
    const tops = Array.from({ length: 100 }, () => ({}));
    const many = tops.flatMap((top, i) => [
        { provider: "foreign", toplevel: top, windowId: `f${i}` },
        { provider: "kwin", handleId: String(i), windowId: `k${i}` },
    ]).reverse();
    const indexed = indexWindowRecords(many);
    for (let i = 0; i <= 100; i++) {
        assert.equal(indexed.kwin.get(String(i)), many.find(record =>
            record.provider === "kwin" && record.handleId === String(i)));
        assert.equal(indexed.foreign.get(tops[i]), many.find(record =>
            record.provider === "foreign" && record.toplevel === tops[i]));
    }
    // One record-key read per input, not one whole-list scan per incoming window.
    let keyReads = 0;
    indexWindowRecords(Array.from({ length: 1000 }, (_, i) => ({
        provider: "kwin", get handleId() { keyReads++; return String(i); },
    })));
    assert.equal(keyReads, 1000);

    console.log("window record index: passed");
});

test("window placement updates", async () => {
    // Execute the production QML functions, mocking only provider and ListModel.
    const source = readFileSync(new URL("../../shell/desktop/modules/dock/WindowService.qml", import.meta.url), "utf8");
    // Also exercise the same update path after the independent indexing PR lands.
    const usesIndex = source.includes("WindowRecordIndex.indexWindowRecords");
    const WindowRecordIndex = usesIndex ? await import("../../shell/desktop/modules/dock/WindowRecordIndex.mjs") : null;
    // Payload arrays are coerced through this module; the extracted production
    // functions reference it, so the mock context has to provide it too.
    const usesPayloadArray = source.includes("PayloadArray.toArray");
    const PayloadArray = usesPayloadArray ? await import("../../shell/desktop/modules/dock/PayloadArray.mjs") : null;
    // Discover the private helpers instead of listing them by hand. A hand-written
    // list silently rots: the moment `_rebuild` starts calling a new helper (as it
    // did with `_pruneThumbnails`) the extraction skips it, the mock service has no
    // such method, and this test fails on a change that broke nothing.
    //
    // The skip list below is the mirror image: it names the helpers that read QML
    // runtime state (`_topRepeater`, `_updateTimer`, `PlatformClient`, ...) or that
    // drive the public API through side effects, and so cannot run against a bare
    // mock object. Keep it to those, and let everything else be picked up
    // automatically.
    const skip = ["_scheduleUpdate", "_collectToplevels", "_consumeKwinEvent",
        "_ensureProcessHints",
        "_enqueueKwinCommand", "_sendKwinCommand", "_subscribeKwin",
        "switchDesktop", "windowById", "windowsForApp", "thumbnailUrl",
        "requestThumbnail", "activateWindow", "minimizeWindow", "closeWindow",
        "toggleShowDesktop"];
    const names = [...source.matchAll(/^    function (\w+)\(/gm)]
        .map(m => m[1]).filter(name => !skip.includes(name));
    assert.ok(names.includes("_rebuild"), "_rebuild must exist in WindowService.qml");
    const functions = names.map(name => {
        const match = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, "m"));
        assert.ok(match, name);
        return match[0];
    }).join("\n");
    let writes = 0;
    const rows = [];
    const windowModel = {
        get count() { return rows.length; },
        get: i => rows[i],
        append: row => { writes++; rows.push(row); },
        remove: i => { writes++; rows.splice(i, 1); },
        setProperty: (i, key, value) => { writes++; rows[i][key] = value; },
    };
    const svc = { records: [], _kwinWindows: [], _nextWindowNumber: 1,
        revision: 0, placementRevision: 0, _recordsById: {}, _lastActivatedAt: {},
        // Process probes are QML runtime objects; placement tests provide the
        // caches but never spawn a real probe while rebuilding synthetic records.
        _processHintsByPid: {}, _processProbeByPid: {}, _ensureProcessHints() {},
        // Thumbnail state the service keeps keyed by KWin handle. `_rebuild` sweeps
        // it, so the mock has to carry the same shape or the sweep reads undefined.
        thumbnailRevision: 0, _thumbnailUrlsByHandle: {},
        _thumbnailPendingByHandle: {}};
    const context = vm.createContext({ svc, windowModel, WindowRecordIndex,
        PayloadArray,
        _collectToplevels: () => [],
        AppIdentityService: { resolve: id => ({ desktopId: id, rawAppId: id, iconSource: id }) },
    });
    vm.runInContext(functions, context);
    for (const name of names) svc[name] = context[name];
    // Process probing is asynchronous QML runtime integration. This test covers
    // record and placement updates, so keep identity hints empty and synchronous.
    svc._ensureProcessHints = () => {};
    const window = id => ({ id, appId: id, title: id, desktops: ["desktop-1"],
        geometry: { x: 0, y: 0, width: 100, height: 100 }, visible: true });
    svc._kwinWindows = [window("one"), window("two")];
    svc._rebuild();
    assert.equal(svc.revision, 1);
    assert.equal(svc.placementRevision, 1);
    assert.deepEqual(Object.keys(svc._lastActivatedAt), [], "inactive windows have no MRU stamp");
    const records = svc.records;
    const record = records[0];
    const byId = svc._recordsById;
    writes = 0;
    // All placement-only fields, including geometry loss and restoration.
    for (const patch of [
        { geometry: { x: 500, y: 20, width: 90, height: 80 } },
        { outputName: "DP-2" }, { maximized: true }, { visible: false },
        { geometry: null }, { geometry: { x: 0, y: 0, width: 100, height: 100 } },
    ]) {
        svc._kwinWindows[0] = { ...svc._kwinWindows[0], ...patch };
        const previous = svc.placementRevision;
        svc._rebuild();
        assert.equal(svc.placementRevision, previous + 1);
        assert.equal(svc.revision, 1);
        assert.equal(svc.records, records);
        assert.equal(svc.records[0], record);
        assert.equal(svc._recordsById, byId);
        assert.equal(writes, 0);
    }
    assert.equal(record.geometry.x, 0);
    assert.equal(record.screenName, "DP-2");
    assert.equal(record.toplevel.outputName, "DP-2");
    assert.equal(record.isVisible, false);
    const unchanged = svc.placementRevision;
    svc._rebuild();
    assert.equal(svc.placementRevision, unchanged);
    // Each presentation field must still wake both presentation and collision.
    // `iconPath` is deliberately absent: presentation now derives the icon from the
    // shared themed source (`_presentationEqual` compares `iconSource`), and KWin's
    // absolute `iconPath` is only consulted when theme lookup finds nothing. The
    // mock resolver always answers, so a bare `iconPath` change moves `iconSource`
    // not at all and must not wake either lane.
    for (const patch of [{ title: "renamed" }, { activated: true }, { minimized: true },
        { fullscreen: true }, { urgent: true }, { desktops: ["desktop-2"] },
        { onAllDesktops: true }, { appId: "new-app" }, { pid: 123 }]) {
        const revision = svc.revision, placement = svc.placementRevision;
        svc._kwinWindows[0] = { ...svc._kwinWindows[0], ...patch };
        svc._rebuild();
        assert.equal(svc.revision, revision + 1);
        assert.equal(svc.placementRevision, placement + 1);
    }
    // Earlier placement differences must not hide a later presentation change.
    svc._kwinWindows[0] = { ...svc._kwinWindows[0], geometry: null };
    svc._kwinWindows[1] = { ...svc._kwinWindows[1], title: "second changed" };
    let revision = svc.revision;
    svc._rebuild();
    assert.equal(svc.revision, revision + 1);
    assert.equal(rows[1].title, "second changed");
    const firstId = svc.records[0].windowId;
    svc._kwinWindows.reverse();
    svc._rebuild();
    assert.equal(svc.records[1].windowId, firstId);
    svc._kwinWindows = [];
    svc._rebuild();
    assert.equal(rows.length, 0);
    assert.equal(svc.activeWindowId, "");
    // Provider-owned foreign objects are read-only; placement updates cannot
    // assign to them. Their normalized record still receives the new placement.
    const foreign = { provider: "foreign", toplevel: Object.freeze({ visible: true }) };
    svc._updatePlacement(foreign, { geometry: null, screenName: "", isMaximized: false,
        isVisible: false, toplevel: { visible: false } });
    assert.equal(foreign.toplevel.visible, true);
    assert.equal(foreign.isVisible, false);
    for (const file of ["DockAutoHideController.qml", "../bar/BarAutoHideController.qml"]) {
        const controller = readFileSync(new URL(file, new URL("../../shell/desktop/modules/dock/", import.meta.url)), "utf8");
        assert.match(controller, /function onPlacementRevisionChanged\(\)/);
        assert.match(controller, /function onCurrentDesktopIdChanged\(\)/);
    }
    console.log("window placement updates: passed");
});

test("window transport fallback", async () => {
    const source = readFileSync(new URL("../../shell/desktop/modules/dock/WindowService.qml", import.meta.url), "utf8");
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
});

test("payload array", async () => {
    //
    // The interesting case is the array-like object: a QV4 sequence (Qt 6.12)
    // reports typeof "object" with a numeric length but fails Array.isArray,
    // which is what previously made WindowService drop every KWin snapshot.
    let errors = 0;
    function check(desc, actual, expected) {
        const a = JSON.stringify(actual);
        const e = JSON.stringify(expected);
        if (a === e) {
            console.log("OK:   " + desc + " -> " + a);
        } else {
            errors++;
            console.log("FAIL: " + desc + " -> " + a + " (expected " + e + ")");
        }
    }

    // Genuine arrays pass through untouched (same identity, not a copy).
    const real = [1, 2, 3];
    check("real array identity", toArray(real) === real, true);

    // QV4 sequence shape: object with numeric length and indexed entries.
    const sequence = { length: 3, 0: "a", 1: "b", 2: "c" };
    check("array-like sequence", toArray(sequence), ["a", "b", "c"]);
    check("empty sequence", toArray({ length: 0 }), []);
    check("sequence keeps null holes", toArray({ length: 1 }), [undefined]);

    // Not array-like: every other shape must stay null so "missing list" and
    // "empty list" remain distinguishable.
    check("null", toArray(null), null);
    check("undefined", toArray(undefined), null);
    check("object", toArray({ a: 1 }), null);
    check("string is not an array", toArray("abc"), null);
    check("number", toArray(5), null);
    check("boolean", toArray(true), null);
    check("function", toArray(function () {}), null);

    console.log(errors ? "\n" + errors + " FAILED" : "\nAll 11 passed");
    assert.equal(errors, 0, "all checks in this scenario must pass");
});

test("timed lyrics", async () => {
    assert.deepEqual(parse('plain lyrics\nsecond line'), []);
    assert.deepEqual(parse('[ar:Artist]\n[00:05]one\n[00:10.25][00:20.250]repeat\n[00:15.000]'), [
        {time:5,text:'one'}, {time:10.25,text:'repeat'}, {time:15,text:''}, {time:20.25,text:'repeat'}]);
    assert.deepEqual(parse('[00:02.5] a\r\n[offset:+500]'), [{time:2,text:'a'}]);
    assert.deepEqual(parse('[offset:-500]\n[00:02]a'), [{time:2.5,text:'a'}]);
    assert.deepEqual(parse('[00:99]invalid'), []);
    const lines=parse('[00:20]last\n[00:01]first\n[00:10]');
    for (const [position,expected] of [[0,-1],[1,0],[15,1],[21,2],[2,0],[10,1],[NaN,-1]])
        assert.equal(indexAt(lines,position),expected);
    assert.equal(indexAt([],100),-1);
    console.log('Timed lyrics: timestamps, repeats, offsets, interludes and seeks passed');
});

test("window cycle: multi-window dock activation", async () => {
    const win1 = { windowId: "win-1", toplevel: { activated: false } };
    const win2 = { windowId: "win-2", toplevel: { activated: false } };
    const win3 = { windowId: "win-3", toplevel: { activated: false } };
    const windows = [win1, win2, win3];

    const timestamps = { "win-1": 1000, "win-2": 2000, "win-3": 500 };
    const lastActivatedAt = id => timestamps[id] || 0;

    // 1. App not in foreground: activates MRU window (win-2 has highest timestamp)
    assert.equal(nextWindowToActivate(windows, null, lastActivatedAt), win2);

    // 2. Cycle through all 3 windows in sequence when already active
    // When win-1 is active -> next is win-2
    win1.toplevel.activated = true;
    win2.toplevel.activated = false;
    win3.toplevel.activated = false;
    assert.equal(nextWindowToActivate(windows, "win-1", lastActivatedAt), win2);

    // When win-2 is active -> next is win-3 (MUST NOT bounce back to win-1!)
    win1.toplevel.activated = false;
    win2.toplevel.activated = true;
    win3.toplevel.activated = false;
    assert.equal(nextWindowToActivate(windows, "win-2", lastActivatedAt), win3);

    // When win-3 is active -> wraps around to win-1
    win1.toplevel.activated = false;
    win2.toplevel.activated = false;
    win3.toplevel.activated = true;
    assert.equal(nextWindowToActivate(windows, "win-3", lastActivatedAt), win1);

    // 3. Rapid click lag guard: pending target advances even before compositor reports focus change
    // Suppose win-1 is still reported active by compositor, but we just clicked to win-2
    win1.toplevel.activated = true;
    win2.toplevel.activated = false;
    win3.toplevel.activated = false;
    assert.equal(nextWindowToActivate(windows, "win-1", lastActivatedAt, "win-2", 50), win3);

    // And next rapid click from win-2 to win-3 advances to win-1
    assert.equal(nextWindowToActivate(windows, "win-1", lastActivatedAt, "win-3", 100), win1);

    // When pending age exceeds TTL (>800ms), it expires and relies on compositor active state
    assert.equal(nextWindowToActivate(windows, "win-1", lastActivatedAt, "win-2", 900), win2);

    // 4. Single window returns that window
    assert.equal(nextWindowToActivate([win1], null, lastActivatedAt), win1);

    // 5. Empty window list returns null
    assert.equal(nextWindowToActivate([], null, lastActivatedAt), null);
    assert.equal(nextWindowToActivate(null, null, lastActivatedAt), null);
});

