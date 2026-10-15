import assert from "node:assert/strict";
import { columnsForWidth, dragDestination, cardWidth, spacing, margin } from "../../shell/desktop/modules/bar/StatusAreaLayout.mjs";
import { empty, append } from "../../shell/desktop/modules/bar/NetworkTrafficHistory.mjs";

for (const width of [320, 400, 600, 780, 804, 1280]) {
    const columns = columnsForWidth(width, 8);
    assert(columns * cardWidth + (columns - 1) * spacing + 2 * margin <= width);
    assert(columns >= 1 && columns <= 8);
}
assert.equal(columnsForWidth(804, 8), 8);
assert.equal(columnsForWidth(600, 8), 5);
assert.equal(dragDestination(1, 0, 74, 3, 8), 4);
assert.equal(dragDestination(4, 98, -74, 3, 8), 2);
assert.equal(dragDestination(1, -999, -999, 3, 8), 0);
assert.equal(dragDestination(1, 999, 999, 3, 8), 6);

let history = empty("eth0");
for (let i = 0; i < 65; i++) history = append(history, "eth0", i, 2 * i);
assert.deepEqual(history.download, Array.from({ length: 60 }, (_, i) => i + 5));
assert.equal(history.upload.at(-1), 128);
assert.equal(append(history, "eth0", NaN, 1), history);
assert.equal(append(history, "eth0", 1, Infinity), history);
assert.equal(append(history, "", 1, 2), history);
history = append(history, "wlan0", -10, 20);
assert.deepEqual(history, { device: "wlan0", download: [0], upload: [20] });
console.log("Status area: constrained layout, cross-row drag and bounded per-interface history passed");
