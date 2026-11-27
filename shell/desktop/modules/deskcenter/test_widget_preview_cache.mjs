import assert from "node:assert/strict";
import {
    buildCacheFileName,
    buildSlotKey,
    buildThemeKey,
    commitEntry,
    createQueueState,
    enqueueRender,
    invalidateSlotFile,
    isRenderActive,
    parseIndex,
    pruneForCatalog,
    releaseRender,
    resolveSlot,
    safeFileName,
    touchEntry,
} from "./WidgetPreviewCacheLogic.mjs";

// 1. Safe filename check & deterministic cache key generation
assert.equal(safeFileName("org.example.clock-2x2-0123456789abcdef.png"), true);
assert.equal(safeFileName("../evil.png"), false);
assert.equal(safeFileName("dir/evil.png"), false);
assert.equal(safeFileName("evil.sh"), false);

const themeLight = buildThemeKey({ style: "material", isDark: false, transparent: false, locale: "zh-CN", palette: { primary: "#112233", surface: "#ffffff", onSurface: "#000000" } }, true, "#fafafa", 2);
const themeDark = buildThemeKey({ style: "material", isDark: true, transparent: false, locale: "zh-CN", palette: { primary: "#112233", surface: "#111111", onSurface: "#ffffff" } }, true, "#181818", 2);
assert.notEqual(themeLight, themeDark);

const f1 = buildCacheFileName("org.nextkde.example.clock", "rev1", "2x2", themeLight);
const f1Again = buildCacheFileName("org.nextkde.example.clock", "rev1", "2x2", themeLight);
const f1NewRev = buildCacheFileName("org.nextkde.example.clock", "rev2", "2x2", themeLight);
assert.equal(f1, f1Again);
assert.notEqual(f1, f1NewRev);
assert.equal(safeFileName(f1), true);

// 2. Miss -> Commit -> Hit -> Stale retained fallback -> Commit supersedes old file
let index = parseIndex("{bad json");
assert.deepEqual(Object.keys(index), []);

const slot = buildSlotKey("org.nextkde.example.clock", "2x2");
assert.equal(resolveSlot(index, slot, f1).status, "miss");

let commitRes = commitEntry(index, {
    widgetId: "org.nextkde.example.clock",
    packageId: "org.nextkde.example.clock",
    sizeValue: "2x2",
    isDefaultSize: true,
    fileName: f1,
    revision: "rev1",
    themeKey: themeLight,
    lastUsedMs: 1000,
});
index = commitRes.entries;
assert.deepEqual(commitRes.removedFiles, []);
assert.equal(resolveSlot(index, slot, f1).status, "hit");

// Revision bump returns stale with fallbackUrl pointing to f1
const staleRes = resolveSlot(index, slot, f1NewRev);
assert.equal(staleRes.status, "stale");
assert.equal(staleRes.fallbackFileName, f1);

// Committing new revision returns old file in removedFiles
commitRes = commitEntry(index, {
    widgetId: "org.nextkde.example.clock",
    packageId: "org.nextkde.example.clock",
    sizeValue: "2x2",
    isDefaultSize: true,
    fileName: f1NewRev,
    revision: "rev2",
    themeKey: themeLight,
    lastUsedMs: 2000,
});
index = commitRes.entries;
assert.deepEqual(commitRes.removedFiles, [f1]);

// 3. Eviction prioritizes non-default sizes before default sizes, and oldest LRU first
const f2Def = buildCacheFileName("pkg.a", "r1", "2x2", themeLight);
const f3NonDefOld = buildCacheFileName("pkg.b", "r1", "3x2", themeLight);
const f4NonDefNew = buildCacheFileName("pkg.b", "r1", "4x2", themeLight);

let evictIndex = Object.create(null);
evictIndex = commitEntry(evictIndex, { widgetId: "pkg.a", sizeValue: "2x2", isDefaultSize: true, fileName: f2Def, lastUsedMs: 100 }, 10).entries;
evictIndex = commitEntry(evictIndex, { widgetId: "pkg.b", sizeValue: "3x2", isDefaultSize: false, fileName: f3NonDefOld, lastUsedMs: 200 }, 10).entries;
const evictStep = commitEntry(evictIndex, { widgetId: "pkg.b", sizeValue: "4x2", isDefaultSize: false, fileName: f4NonDefNew, lastUsedMs: 300 }, 2);
// Non-default pkg.b@3x2 (ts=200) must be evicted instead of default pkg.a@2x2 (ts=100)
assert.equal(evictStep.entries["pkg.a@2x2"].fileName, f2Def);
assert.equal(evictStep.entries["pkg.b@4x2"].fileName, f4NonDefNew);
assert.equal(evictStep.entries["pkg.b@3x2"], undefined);
assert.deepEqual(evictStep.removedFiles, [f3NonDefOld]);

// 4. Touch, invalidate corrupt file, and catalog/crash prune
const touched = touchEntry(evictStep.entries, "pkg.a@2x2", 999);
assert.equal(touched.changed, true);
assert.equal(touched.entries["pkg.a@2x2"].lastUsedMs, 999);

const parsed = parseIndex(JSON.stringify(Object.assign({ corrupt: { widgetId: "x", sizeValue: "1x1", fileName: "../bad.png" } }, touched.entries)));
assert.equal(parsed.corrupt, undefined);
assert.equal(parsed["pkg.a@2x2"].lastUsedMs, 999);

const inv = invalidateSlotFile(parsed, "pkg.a@2x2", "wrong.png");
assert.equal(inv.changed, false);
const inv2 = invalidateSlotFile(parsed, "pkg.a@2x2", f2Def);
assert.equal(inv2.changed, true);
assert.equal(inv2.entries["pkg.a@2x2"], undefined);

// Prune uninstalled and crash-blocked packages
let pruneMap = Object.create(null);
pruneMap = commitEntry(pruneMap, { widgetId: "pkg.keep", packageId: "pkg.keep", sizeValue: "2x2", isDefaultSize: true, fileName: f1, lastUsedMs: 1 }, 10).entries;
pruneMap = commitEntry(pruneMap, { widgetId: "pkg.gone", packageId: "pkg.gone", sizeValue: "2x2", isDefaultSize: true, fileName: f2Def, lastUsedMs: 2 }, 10).entries;
pruneMap = commitEntry(pruneMap, { widgetId: "pkg.multi.sub", packageId: "pkg.multi", sizeValue: "2x2", isDefaultSize: true, fileName: f3NonDefOld, lastUsedMs: 3 }, 10).entries;

const pruned = pruneForCatalog(pruneMap, ["pkg.keep", "pkg.multi.sub"], ["pkg.multi"]);
assert.equal(pruned.changed, true);
assert.ok(pruned.entries["pkg.keep@2x2"]);
assert.equal(pruned.entries["pkg.gone@2x2"], undefined);
assert.equal(pruned.entries["pkg.multi.sub@2x2"], undefined);
assert.deepEqual(pruned.removedFiles.sort(), [f2Def, f3NonDefOld].sort());

// 5. Render queue limits concurrency & prioritizes default sizes
let q = createQueueState();
q = enqueueRender(q, { slotKey: "a@2x2", fileName: f1, isDefaultSize: true }, 2);
q = enqueueRender(q, { slotKey: "b@3x2", fileName: f2Def, isDefaultSize: false }, 2);
q = enqueueRender(q, { slotKey: "c@3x2", fileName: f3NonDefOld, isDefaultSize: false }, 2);
q = enqueueRender(q, { slotKey: "d@2x2", fileName: f4NonDefNew, isDefaultSize: true }, 2);

assert.equal(isRenderActive(q, "a@2x2", f1), true);
assert.equal(isRenderActive(q, "b@3x2", f2Def), true);
assert.equal(isRenderActive(q, "c@3x2", f3NonDefOld), false);
assert.equal(isRenderActive(q, "d@2x2", f4NonDefNew), false);

// Releasing one slot must promote d@2x2 (default size) before c@3x2 (non-default size)
q = releaseRender(q, "a@2x2", 2);
assert.equal(isRenderActive(q, "d@2x2", f4NonDefNew), true);
assert.equal(isRenderActive(q, "c@3x2", f3NonDefOld), false);

q = releaseRender(q, "b@3x2", 2);
assert.equal(isRenderActive(q, "c@3x2", f3NonDefOld), true);

console.log("test_widget_preview_cache: all checks passed");
