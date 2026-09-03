import assert from "node:assert/strict";
import { packWidgets, sizeOrder, spanFor } from "./WidgetLayout.mjs";

const ids = ["clock", "weather", "calendar", "todo", "system", "activity", "music"];

for (const id of ids) {
    for (const size of sizeOrder) {
        const [columns, rows] = spanFor(id, size);
        assert.ok(columns >= 1 && columns <= 3, `${id}/${size} columns`);
        assert.ok(rows >= 1 && rows <= 2, `${id}/${size} rows`);
    }
}

for (const size of sizeOrder) {
    const definitions = ids.map((id, index) => {
        const [columns, rows] = spanFor(id, size);
        return { id, columns, rows, priority: 100 - index };
    });
    const placements = packWidgets(definitions, 4, 8);
    assert.equal(placements.length, ids.length, `${size} widgets all fit`);
    const cells = new Set();
    for (const placement of placements) {
        for (let row = placement.row; row < placement.row + placement.rows; row++) {
            for (let column = placement.column;
                 column < placement.column + placement.columns; column++) {
                assert.ok(column < 4 && row < 8, `${placement.id} remains in bounds`);
                const key = `${column}:${row}`;
                assert.ok(!cells.has(key), `${placement.id} does not overlap`);
                cells.add(key);
            }
        }
    }
}

const constrained = ids.map((id, index) => {
    const [columns, rows] = spanFor(id, "large");
    return { id, columns, rows, priority: 100 - index };
});
const visible = packWidgets(constrained, 4, 3);
assert.ok(visible.length < ids.length, "short screens drop lower priority widgets");
assert.equal(visible[0].id, "clock", "highest priority widget remains first");

console.log("DeskCenter widget layout: all size and packing tests passed");
