// test_inputmethod_placement.mjs — Unit test for InputMethodPlacement.mjs
import assert from "node:assert/strict";
import {
    parseCandidateText,
    parseKimpanelProperty,
    resolveGlobalSpotRect,
    placeCandidatePopup
} from "./InputMethodPlacement.mjs";

console.log("Running input method placement unit tests...");

// 1. Candidate text parsing (Rime & Pinyin comments)
assert.deepEqual(parseCandidateText("你好"), { text: "你好", comment: "" });
assert.deepEqual(parseCandidateText("测试 ce shi"), { text: "测试", comment: "ce shi" });
assert.deepEqual(parseCandidateText("中州韵\trime"), { text: "中州韵", comment: "rime" });
assert.deepEqual(parseCandidateText(""), { text: "", comment: "" });

// 2. Kimpanel property parsing
const p1 = parseKimpanelProperty("/Fcitx/im:中:fcitx-rime:中州韵:menu");
assert.equal(p1.id, "/Fcitx/im");
assert.equal(p1.key, "im");
assert.equal(p1.shortText, "中");
assert.equal(p1.icon, "fcitx-rime");
assert.equal(p1.label, "中州韵");
assert.equal(p1.isMenu, true);

const p2 = parseKimpanelProperty("/Fcitx/rime-deploy::system-run:重新部署:");
assert.equal(p2.key, "rime-deploy");
assert.equal(p2.shortText, "");
assert.equal(p2.label, "重新部署");
assert.equal(p2.isMenu, false);

// 3. Resolve global spot rect
// 3a. KWin Caret Priority (Wayland text-input-v3: VS Code / Obsidian / Antigravity)
const kwinCaret = { available: true, source: "caret", x: 450, y: 320, width: 2, height: 22 };
const resCaret = resolveGlobalSpotRect({ x: 0, y: 0, mode: "absolute" }, null, kwinCaret);
assert.equal(resCaret.source, "kwin-caret");
assert.equal(resCaret.x, 450);
assert.equal(resCaret.y, 320);

// 3b. Wayland relative spot (Konsole / Firefox)
const activeWin = { contentGeometry: { x: 100, y: 150, width: 800, height: 600 } };
const spotRel = { mode: "relative", x: 50, y: 80, width: 10, height: 20, scale: 2.0 };
const resRel = resolveGlobalSpotRect(spotRel, activeWin, { available: false });
assert.equal(resRel.source, "window-relative");
assert.equal(resRel.x, 125); // 100 + 50 / 2
assert.equal(resRel.y, 190); // 150 + 80 / 2
assert.equal(resRel.width, 5);
assert.equal(resRel.height, 10);

// 3c. XWayland absolute spot
const spotAbs = { mode: "absolute", x: 720, y: 600, width: 15, height: 25 };
const resAbs = resolveGlobalSpotRect(spotAbs, null, null);
assert.equal(resAbs.source, "absolute");
assert.equal(resAbs.x, 720);
assert.equal(resAbs.y, 600);

// 3d. KWin pointer anchor fallback when spot coordinates are zero
const spotZero = { mode: "relative", x: 0, y: 0 };
const kwinPointer = { available: true, source: "pointer", x: 2117, y: 1019, width: 0, height: 0 };
const resPointer = resolveGlobalSpotRect(spotZero, null, kwinPointer);
assert.equal(resPointer.source, "kwin-pointer");
assert.equal(resPointer.x, 2117);
assert.equal(resPointer.y, 1019);

// 4. Candidate popup placement & Boundary clamping
const safeBounds = { x: 0, y: 35, width: 1920, height: 1045 }; // top bar reserved 35px

// 4a. Normal placement (below caret)
const normalPlacement = placeCandidatePopup(safeBounds, { x: 200, y: 300, width: 2, height: 20 }, 300, 50, 8);
assert.equal(normalPlacement.x, 200);
assert.equal(normalPlacement.y, 328); // 300 + 20 + 8

// 4b. Flip above caret when near screen bottom
const nearBottomPlacement = placeCandidatePopup(safeBounds, { x: 200, y: 1050, width: 2, height: 20 }, 300, 60, 8);
assert.equal(nearBottomPlacement.x, 200);
assert.equal(nearBottomPlacement.y, 1050 - 8 - 60); // 982

// 4c. Horizontal clamp on right edge
const nearRightPlacement = placeCandidatePopup(safeBounds, { x: 1800, y: 400, width: 2, height: 20 }, 300, 50, 8);
assert.equal(nearRightPlacement.x, 1920 - 300); // 1620
assert.equal(nearRightPlacement.y, 428);

// 4d. Negative offset screen (multi-display / external DP)
const negativeScreenSafe = { x: -1920, y: 0, width: 1920, height: 1080 };
const negPlacement = placeCandidatePopup(negativeScreenSafe, { x: -1000, y: 500, width: 2, height: 20 }, 250, 40, 8);
assert.equal(negPlacement.x, -1000);
assert.equal(negPlacement.y, 528);

console.log("All input method placement unit tests passed successfully!");
