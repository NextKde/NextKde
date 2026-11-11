import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Keep the production bindings, handlers and timers intact. Only singleton
// names are redirected to fixture objects; the real QML engine delivers the
// desktop and placement changes.
const stage = new URL("../../shell/desktop/modules/stage/", import.meta.url);
const sidebar = readFileSync(new URL("StageSidebarWindow.qml", stage), "utf8");
function section(start, end) {
    const first = sidebar.indexOf(start);
    const last = sidebar.indexOf(end, first);
    assert.ok(first >= 0 && last > first, `production section moved: ${start}`);
    return sidebar.slice(first, last);
}
const production = [
    section("    property var _fullscreenOverride:", "    property bool _drawerPeek:"),
    section("    readonly property bool drawerRetracted:", "    NumberAnimation {\n        id: retractMotion"),
    section("    readonly property real _yieldEngage:", "    // ── 滚动状态"),
].join("\n").replaceAll("WindowService.", "windowService.")
    .replaceAll("ConfigService.", "configService.");
const directory = mkdtempSync(join(tmpdir(), "kos-stage-visibility-"));
try {
    copyFileSync(new URL("../../shared/qml/foundation/MotionTokens.qml", import.meta.url), join(directory, "MotionTokens.qml"));
    writeFileSync(join(directory, "AppearanceTokens.qml"), `pragma Singleton
import QtQuick
QtObject { readonly property MotionTokens motion: MotionTokens {} }
`);
    writeFileSync(join(directory, "qmldir"), "singleton AppearanceTokens 1.0 AppearanceTokens.qml\n");
    copyFileSync(new URL("stage-groups.mjs", stage), join(directory, "stage-groups.mjs"));
    copyFileSync(new URL("StageDesktopTransition.qml", stage), join(directory, "StageDesktopTransition.qml"));
    copyFileSync(new URL("tst_transition.qml", import.meta.url), join(directory, "tst_transition.qml"));
    const transition = section("    property bool _committingDesktop:", "    // ── 卡片堆叠区")
        .replaceAll("WindowService.", "windowService.");
    const retract = section("    NumberAnimation {\n        id: retractMotion", "    on_RetractPxChanged:");
    const staticFixture = readFileSync(new URL("tst_static_sidebar.qml.in", import.meta.url), "utf8");
    writeFileSync(join(directory, "tst_static_sidebar.qml"), staticFixture
        .replace("// PRODUCTION_TRANSITION", transition)
        .replace("// PRODUCTION_RETRACT", retract));
    const fixture = readFileSync(new URL("tst_visibility.qml.in", import.meta.url), "utf8");
    assert.ok(fixture.includes("// PRODUCTION_DRAWER"));
    writeFileSync(join(directory, "tst_visibility.qml"),
        fixture.replace("// PRODUCTION_DRAWER", production));
    const result = spawnSync(process.argv[2] || "qmltestrunner", ["-input", directory], {
        encoding: "utf8", timeout: 20000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            WAYLAND_DISPLAY: "", DISPLAY: "" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL!|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
