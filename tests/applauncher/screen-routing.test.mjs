import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

// Exercise the shipping service methods without requiring a compositor.
function launcher() {
    const source = readFileSync(new URL("../../shell/desktop/modules/applauncher/AppLauncherService.qml", import.meta.url), "utf8");
    const methods = source.slice(source.indexOf("    function show("), source.lastIndexOf("}"));
    const service = { open: false, triggerScreen: null };
    const context = vm.createContext({ service, dockWidth: 0, dockHeight: 0, console });
    vm.runInContext(methods, context);
    for (const name of ["show", "hide", "toggle"])
        service[name] = context[name];
    return service;
}

const primary = { name: "primary", isPlaceholder: false };
const secondary = { name: "secondary", isPlaceholder: false };

test("each Dock opening uses the clicked output", () => {
    const service = launcher();
    service.toggle(secondary);
    assert.equal(service.open, true);
    assert.equal(service.triggerScreen, secondary);
    service.toggle(primary);
    assert.equal(service.open, false);
    assert.equal(service.triggerScreen, secondary, "closing must not move the exit animation");
    service.toggle(primary);
    assert.equal(service.open, true);
    assert.equal(service.triggerScreen, primary);
});

test("show and toggle without an output forget the previous Dock screen", () => {
    for (const method of ["show", "toggle"]) {
        const service = launcher();
        service.show(secondary);
        service.hide();
        service[method]();
        assert.equal(service.open, true);
        assert.equal(service.triggerScreen, null, `${method} should use the active output`);
    }
});

test("an explicit show replaces screen routing even while open", () => {
    const service = launcher();
    service.show(secondary);
    service.show();
    assert.equal(service.open, true);
    assert.equal(service.triggerScreen, null);
});

test("missing and placeholder outputs fall back to the active output", () => {
    for (const screen of [null, undefined, { name: "placeholder", isPlaceholder: true }]) {
        const service = launcher();
        service.show(secondary);
        service.hide();
        service.show(screen);
        assert.equal(service.triggerScreen, null);
    }
});
