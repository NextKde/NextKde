import assert from "node:assert/strict";
import { test } from "node:test";
import { selectTarget, surfaceRect, windowKey } from "../../shell/desktop/modules/dock/NativeMinimizeTarget.mjs";

const launcher = { target: { appId: "org.kde.kate.desktop", windowId: "" } };
const first = { target: { appId: "org.kde.kate.desktop", windowId: "aaaa-bbbb" } };
const second = { target: { appId: "org.kde.kate.desktop", windowId: "cccc-dddd" } };

test("exact KWin UUID wins over a grouped launcher and other window icons", () => {
    assert.equal(selectTarget([launcher, second, first], "{AAAA-BBBB}", ["org.kde.kate"]), first);
    assert.equal(selectTarget([first, launcher], "cccc-dddd", ["org.kde.kate"]), launcher);
    assert.equal(selectTarget([first, second], "eeee-ffff", ["org.kde.kate"]), null);
    assert.equal(selectTarget([first], "window-1", ["org.kde.kate"]), null);
    assert.equal(windowKey("{AAAA-BBBB}"), "aaaa-bbbb");
});

test("canonical and raw app ids reach the same grouped launcher", () => {
    assert.equal(selectTarget([launcher], "aaaa-bbbb", ["kate", "org.kde.kate.desktop"]), launcher);
    assert.equal(selectTarget([launcher], "aaaa-bbbb", ["org.kde.dolphin"]), null);
    assert.equal(selectTarget([{ target: { appId: "github-desktop", windowId: "" } }],
        "aaaa-bbbb", ["GitHub Desktop.desktop"])?.target.appId, "github-desktop");
});

test("secondary outputs and fractional scaling publish surface-local logical pixels", () => {
    const rect = { x: 2080.5, y: 1010.25, width: 44.5, height: 44.5 };
    assert.deepEqual(surfaceRect(rect, 1920, 950), { x: 160, y: 60, width: 45, height: 45 });
    assert.deepEqual(surfaceRect({ ...rect, x: -1759.5 }, -1920, 950),
        { x: 160, y: 60, width: 45, height: 45 });
    assert.deepEqual(surfaceRect({ x: 8, y: 140, width: 44, height: 44 }, 0, 100),
        { x: 8, y: 40, width: 44, height: 44 });
});

test("removed, invalid and off-surface targets cannot wrap unsigned Wayland coordinates", () => {
    assert.equal(selectTarget([], "aaaa-bbbb", ["org.kde.kate"]), null);
    assert.equal(surfaceRect({ x: 0, y: 0, width: 0, height: 44 }, 0, 0), null);
    assert.equal(surfaceRect({ x: NaN, y: 0, width: 44, height: 44 }, 0, 0), null);
    assert.equal(surfaceRect({ x: -1, y: 0, width: 44, height: 44 }, 0, 0), null);
});
