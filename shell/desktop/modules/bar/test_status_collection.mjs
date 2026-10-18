import assert from "node:assert/strict";
import { test } from "node:test";
import { visibleKeys, sections, previewOrder, dropPlan, mergeOrder, toggleKey, popupGeometry, gridOrigin } from "./StatusCollection.mjs";

const app = "tray:music", other = "tray:chat", network = "cell:network", cc = "cell:controlcenter";

test("the disclosure stays first and opening never adds collected icons to the strip", () => {
    assert.deepEqual(visibleKeys([app, network, cc], []), [toggleKey, app, network, cc]);
    assert.deepEqual(visibleKeys([app, network, cc], [app, cc]), [toggleKey, network, cc]);
    // A formerly persisted/forwarded expanded flag cannot put anything before it.
    assert.deepEqual(visibleKeys([app, network, cc], [app], true), [toggleKey, network, cc]);
    assert.deepEqual(sections([app, network, cc], [app, cc]), { strip: [network, cc], collection: [app] });
});

test("a native drop into an empty popup collects without changing the input arrays", () => {
    const keys = [app, network, cc], collected = [];
    assert.deepEqual(dropPlan(keys, collected, app, "collection", 0), { collected: true, keys: [app] });
    assert.deepEqual(keys, [app, network, cc]);
    assert.deepEqual(collected, []);
});

test("a drop back on the strip restores a permanent item and retains the fixed Control Center", () => {
    assert.deepEqual(dropPlan([app, other, network, cc], [app], app, "strip", 4),
        { collected: false, keys: [other, app, network, cc] });
    assert.equal(dropPlan([app, cc], [], cc, "collection", 0), null);
    assert.deepEqual(previewOrder([toggleKey, app, other, cc], other, 0), [toggleKey, other, app, cc]);
});

test("cancelled or foreign drops have no persistence plan", () => {
    const keys = [app, other, network, cc];
    assert.equal(dropPlan(keys, [], app, "", 0), null);
    assert.equal(dropPlan(keys, [], app, "strip", -1), null);
    assert.equal(dropPlan(keys, [], "tray:disconnected", "strip", 0), null);
    assert.deepEqual(previewOrder(keys, app, -1), keys);
});

test("section reordering preserves absent applications and v2 preferences", () => {
    const saved = [app, "tray:offline", other, network, cc];
    assert.deepEqual(mergeOrder(saved, [other, app]), [other, "tray:offline", app, network, cc]);
    assert.deepEqual(mergeOrder(saved, [network, "cell:battery", cc]),
        [app, "tray:offline", other, network, "cell:battery", cc]);
    const reloaded = JSON.parse(JSON.stringify({version: 2, order: saved, collectedKeys: [app]}));
    assert.deepEqual(visibleKeys(reloaded.order, reloaded.collectedKeys),
        [toggleKey, "tray:offline", other, network, cc]);
});

test("the popup is always 300px wide, grows by rows, then leaves a scrollable viewport", () => {
    const empty = popupGeometry(0, 700), one = popupGeometry(1, 700);
    const wrapped = popupGeometry(7, 700), many = popupGeometry(200, 300);
    assert.equal(empty.width, 300);
    assert.equal(one.height, empty.height);
    assert.equal(wrapped.width, 300);
    assert.equal(wrapped.height, one.height + one.cellSize + one.spacing);
    assert.equal(many.width, 300);
    assert.equal(many.height, 300);
    assert.ok(many.contentHeight > many.viewportHeight);
    assert.ok(popupGeometry(20, 96).viewportHeight > 0);
});

test("popup slots wrap without pushing icons or the disclosure along the Bar", () => {
    const layout = popupGeometry(7, 700);
    const last = gridOrigin(layout.columns - 1, layout.columns, layout.cellSize, layout.spacing);
    const next = gridOrigin(layout.columns, layout.columns, layout.cellSize, layout.spacing);
    assert.ok(last.x + layout.cellSize <= layout.width - 2 * layout.padding);
    assert.deepEqual(next, {x: 0, y: layout.cellSize + layout.spacing});
    assert.deepEqual(visibleKeys([app, other, network, cc], [app, other]), [toggleKey, network, cc]);
});
