import assert from "node:assert/strict";
import {
    buildRows,
    deskCenterWidgetIds,
    isHidden,
    isKnownDeskCenterWidget,
    isKnownStatusCell,
    normalizeHiddenIds,
    statusCellIds,
    withVisibility,
} from "./VisibilityPolicy.mjs";

// ── id validation ───────────────────────────────────────────────────────────

assert.equal(isKnownDeskCenterWidget("clock"), true, "clock is a known widget");
assert.equal(isKnownDeskCenterWidget("music"), true, "music is a known widget");
assert.equal(isKnownDeskCenterWidget("nope"), false, "unknown widget rejected");
assert.equal(isKnownStatusCell("battery"), true, "battery is a known cell");
assert.equal(isKnownStatusCell("clock"), false, "a widget id is not a cell id");

// ── normalisation ───────────────────────────────────────────────────────────

// A file written by a newer build, or edited by hand, must not be able to hide
// a surface that no longer exists.
assert.deepEqual(
    normalizeHiddenIds(["clock", "ghost"], deskCenterWidgetIds),
    ["clock"],
    "unknown ids are dropped",
);
assert.deepEqual(
    normalizeHiddenIds(["clock", "clock"], deskCenterWidgetIds),
    ["clock"],
    "duplicates collapse",
);
assert.deepEqual(
    normalizeHiddenIds(null, deskCenterWidgetIds),
    [],
    "a missing key means everything visible",
);
assert.deepEqual(
    normalizeHiddenIds("clock", deskCenterWidgetIds),
    [],
    "a non-array is not interpreted as a single id",
);
// The Control Center is the anchor every other panel positions against.
assert.deepEqual(
    normalizeHiddenIds(["controlcenter", "network"], statusCellIds),
    ["network"],
    "the required anchor cannot be hidden",
);

// ── withVisibility ──────────────────────────────────────────────────────────

assert.deepEqual(
    withVisibility([], "clock", false, deskCenterWidgetIds),
    ["clock"],
    "hiding appends the id",
);
assert.deepEqual(
    withVisibility(["clock", "weather"], "clock", true, deskCenterWidgetIds),
    ["weather"],
    "showing removes only that id",
);
assert.equal(
    withVisibility(["clock"], "clock", false, deskCenterWidgetIds),
    null,
    "no write when the state already matches",
);
assert.equal(
    withVisibility([], "ghost", false, deskCenterWidgetIds),
    null,
    "an unknown id is refused",
);
assert.equal(
    withVisibility([], "controlcenter", false, statusCellIds),
    null,
    "the required anchor is refused even directly",
);
// Round-tripping through both directions must land on the starting set.
const toggled = withVisibility([], "todo", false, deskCenterWidgetIds);
assert.deepEqual(
    withVisibility(toggled, "todo", true, deskCenterWidgetIds),
    [],
    "hide then show restores the original set",
);

// ── isHidden ────────────────────────────────────────────────────────────────

assert.equal(isHidden(["clock"], "clock"), true, "a listed id is hidden");
assert.equal(isHidden(["clock"], "weather"), false, "an absent id is visible");
assert.equal(isHidden(undefined, "clock"), false, "an unset list hides nothing");

// ── buildRows ───────────────────────────────────────────────────────────────

const rows = buildRows(statusCellIds, ["battery"], { battery: "电池" });
assert.equal(rows.length, statusCellIds.length, "one row per known cell");
assert.deepEqual(
    rows.find(row => row.id === "battery"),
    { id: "battery", label: "电池", visible: false },
    "a hidden cell is unchecked and labelled",
);
assert.deepEqual(
    rows.find(row => row.id === "network"),
    { id: "network", label: "network", visible: true },
    "an unknown label falls back to the id rather than going blank",
);

console.log("visibility policy: all validation and toggle tests passed");
