import assert from "node:assert/strict";
import { test } from "node:test";
import { visibleKeys, previewOrder, destinationSection, mergeOrder, toggleKey, pointInSlot } from "./StatusCollection.mjs";

const app = "tray:music", other = "tray:chat", network = "cell:network", cc = "cell:controlcenter";

test("existing configurations start unfolded and the required control remains visible", () => {
    assert.deepEqual(visibleKeys([app, network, cc], [], false), [toggleKey, app, network, cc]);
    assert.deepEqual(visibleKeys([app, network, cc], [app, cc], false), [toggleKey, network, cc]);
    assert.deepEqual(visibleKeys([app, network, cc], [app], true), [app, toggleKey, network, cc]);

});

test("dragging into a closed collection previews the drop without modifying configuration", () => {
    const keys = [toggleKey, app, network, cc];
    const preview = previewOrder(keys, app, 0);
    assert.deepEqual(keys, [toggleKey, app, network, cc]);
    assert.deepEqual(destinationSection(preview, app), { collected: true, keys: [app] });
});

test("dragging out restores a permanent item without moving the Control Center anchor", () => {
    const keys = [app, toggleKey, other, network, cc];
    const preview = previewOrder(keys, app, 4);
    assert.equal(preview.at(-1), cc);
    assert.deepEqual(destinationSection(preview, app), { collected: false, keys: [other, app, network, cc] });
    assert.deepEqual(previewOrder(keys, cc, 0), keys);
});

test("cancelled and out-of-strip drops do not change order or collection", () => {
    const keys = [app, toggleKey, other, network, cc];
    assert.deepEqual(previewOrder(keys, app, -1), keys);
    assert.deepEqual(previewOrder(keys, "tray:disconnected", 0), keys);
});

test("reordering one section retains absent applications and the other section", () => {
    const saved = [app, "tray:offline", other, network, cc];
    assert.deepEqual(mergeOrder(saved, [other, app]), [other, "tray:offline", app, network, cc]);
    assert.deepEqual(mergeOrder(saved, [network, "cell:battery", cc]),
        [app, "tray:offline", other, network, "cell:battery", cc]);
    const reloaded = JSON.parse(JSON.stringify({version: 2, order: saved, collectedKeys: [app]}));
    assert.deepEqual(visibleKeys(reloaded.order, reloaded.collectedKeys, false),
        [toggleKey, "tray:offline", other, network, cc]);
});

test("collection target only covers its own cell in a two-row Dock", () => {
    assert.equal(pointInSlot({x: 10, y: 10}, {x: 0, y: 0}, 26), true);
    assert.equal(pointInSlot({x: 10, y: 39}, {x: 0, y: 0}, 26), false);
    assert.equal(pointInSlot({x: 10, y: 39}, {x: 0, y: 26}, 26), true);
    assert.equal(pointInSlot({x: 40, y: 10}, {x: 0, y: 0}, 26), false);
});
