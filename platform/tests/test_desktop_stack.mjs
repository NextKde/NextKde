// Run in the test VM: node platform/tests/test_desktop_stack.mjs
// Exercise the actual KWin script with synchronous signals, including KWin's
// partial publication of per-window stackingOrder numbers during a restack.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const bridge = readFileSync(new URL("../../kwin/window-bridge.js", import.meta.url), "utf8");
const source = bridge.slice(0, bridge.indexOf("// Runtime-dependent bridge helpers"))
    + "\ninstallDesktopStack(workspace);";
let checks = 0;

class Signal {
    listeners = [];
    connect(listener) { this.listeners.push(listener); }
    emit(...args) { for (const listener of this.listeners) listener(...args); }
}

function surface(id, role, overrides = {}) {
    const properties = {
        id, resourceClass: "quickshell", layer: 1,
        windowType: role === "strip" ? 0 : 1,
        wantsInput: role === "widgets", stackingOrderChanged: new Signal(),
        ...overrides,
    };
    // A stack manager must not hide/reopen a surface or repair its desktop
    // membership. Fail even if a forbidden write would leave the same value.
    for (const [key, value] of Object.entries({ visible: true, onAllDesktops: true, desktops: [] }))
        Object.defineProperty(properties, key, {
            get: () => value,
            set: () => { throw new Error(`Forbidden ${key} write on ${id}`); },
        });
    return properties;
}

function workspaceFor(initial) {
    const workspace = {
        stackingOrder: initial.slice().sort((a, b) => a.layer - b.layer),
        windowAdded: new Signal(),
        raised: [],
        publish() {
            const order = this.stackingOrder.slice();
            for (let i = 0; i < order.length; ++i) {
                // Later windows still have stale values when this signal fires.
                order[i].stackingOrder = i;
                order[i].stackingOrderChanged.emit();
            }
        },
        raiseWindow(window) {
            assert(this.stackingOrder.includes(window), "cannot raise a removed window");
            assert(this.raised.length < 100, "restacking must converge without a signal loop");
            this.raised.push(window.id);
            this.stackingOrder = this.stackingOrder.filter(w => w !== window).concat(window)
                .sort((a, b) => a.layer - b.layer);
            this.publish();
        },
        add(window) {
            this.stackingOrder.push(window);
            this.stackingOrder.sort((a, b) => a.layer - b.layer);
            this.windowAdded.emit(window);
            this.publish();
        },
    };
    return workspace;
}

function load(workspace) {
    vm.runInNewContext(source, { workspace }, { timeout: 1000 });
}

function expectOrder(workspace, wallpapers, widgets, strips = []) {
    const position = w => workspace.stackingOrder.indexOf(w);
    for (const wallpaper of wallpapers)
        for (const widget of widgets)
            assert(position(wallpaper) < position(widget), "wallpaper covers a desktop surface");
    for (const widget of widgets)
        for (const strip of strips)
            assert(position(widget) < position(strip), "desktop covers the Stage strip");
    checks++;
}

function* permutations(items) {
    if (items.length === 0) { yield []; return; }
    for (let i = 0; i < items.length; ++i)
        for (const rest of permutations(items.filter((_, j) => i !== j)))
            yield [items[i], ...rest];
}

// Every initial mapping order across two outputs, including the real regression
// (widgets mapped before their wallpapers) and a strip mapped before widgets.
for (const arrangement of permutations(["p0", "p1", "w0", "w1", "s"])) {
    const byId = Object.fromEntries(arrangement.map(id => [id,
        surface(id, id.startsWith("p") ? "wallpaper" : id === "s" ? "strip" : "widgets")]));
    const plasma = surface("plasma", "wallpaper", { resourceClass: "plasmashell", layer: 0 });
    const app = surface("app", "widgets", { resourceClass: "editor", layer: 2, windowType: 0 });
    const workspace = workspaceFor([plasma, ...arrangement.map(id => byId[id]), app]);
    load(workspace);
    expectOrder(workspace, [byId.p0, byId.p1], [byId.w0, byId.w1], [byId.s]);
    assert.equal(workspace.stackingOrder.at(-1), app, "ordinary apps stay above the desktop");
    assert(workspace.raised.every(id => id.startsWith("w") || id === "s"),
        "must not reorder wallpapers, Plasma, or application windows directly");
    const count = workspace.raised.length;
    workspace.publish();
    assert.equal(workspace.raised.length, count, "an ordered stack must be a no-op");
}

// Desktop ordering remains active with Stage disabled and tolerates outputs
// that temporarily have only a wallpaper or only a widget surface.
for (const arrangement of [["widgets", "wallpaper"], ["wallpaper"], ["widgets"]]) {
    const windows = arrangement.map(role => surface(role, role));
    const workspace = workspaceFor(windows);
    load(workspace);
    expectOrder(workspace, windows.filter(w => !w.wantsInput), windows.filter(w => w.wantsInput));
}

{
    const wallpaper = surface("wallpaper", "wallpaper");
    const widgets = surface("widgets", "widgets");
    const strip = surface("strip", "strip");
    const workspace = workspaceFor([wallpaper, widgets, strip]);
    load(workspace);
    assert.equal(workspace.raised.length, 0, "initially correct order needs no changes");
    workspace.raiseWindow(widgets); // User focuses the desktop.
    expectOrder(workspace, [wallpaper], [widgets], [strip]);
    const lateWallpaper = surface("late-wallpaper", "wallpaper");
    workspace.add(lateWallpaper); // Wallpaper surface is remapped after widgets.
    expectOrder(workspace, [wallpaper, lateWallpaper], [widgets], [strip]);
    workspace.stackingOrder = workspace.stackingOrder.filter(w => w !== widgets);
    const remappedWidgets = surface("remapped-widgets", "widgets");
    workspace.add(remappedWidgets); // A real output reconnect replaces its surface.
    expectOrder(workspace, [wallpaper, lateWallpaper], [remappedWidgets], [strip]);
}

{
    const widgets = surface("widgets", "widgets", { resourceClass: "org.quickshell" });
    const wallpaper = surface("wallpaper", "wallpaper", { resourceClass: "org.quickshell" });
    const otherApp = surface("other-app", "widgets", { windowType: 0 });
    const overlay = surface("overlay", "strip", { layer: 3 });
    const workspace = workspaceFor([widgets, otherApp, wallpaper, overlay]);
    load(workspace);
    expectOrder(workspace, [wallpaper], [widgets]);
    assert(workspace.raised.every(id => id === "widgets"), "ignore other windows and shell overlays");
}

console.log(`DESKTOP_STACK_PASS: ${checks} ordering scenarios`);
