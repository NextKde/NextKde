import assert from "node:assert/strict";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repo = fileURLToPath(new URL("../..", import.meta.url));
const scratch = mkdtempSync(join(tmpdir(), "kos-selection-"));
function run(executable, args, env) {
    const result = spawnSync(executable, args, {
        encoding: "utf8", timeout: 15000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", QT_LOGGING_RULES: "qml.debug=true", ...env },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL[! ]|ReferenceError|TypeError|Binding loop|is not a type|Cannot assign|Unable to assign/, output);
    return output;
}
try {
    const controls = join(scratch, "controls");
    mkdirSync(controls);
    copyFileSync(join(repo, "shared/qml/controls/SelectionHighlight.qml"), join(controls, "SelectionHighlight.qml"));
    const adapter = readFileSync(join(repo, "shell/desktop/modules/bar/ControlCenterSelection.qml"), "utf8")
        .replace('import qs.desktop.modules.common', '')
        .replace('import "../../../Kos/Ui"', 'import "."');
    writeFileSync(join(controls, "ControlCenterSelection.qml"), adapter);
    writeFileSync(join(controls, "AppearanceTokens.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool isDarkTheme: true
    property QtObject surface: QtObject { property string selectionHighlightStyle: "glass" }
}
`);
    writeFileSync(join(controls, "qmldir"), `module SelectionFixture
SelectionHighlight 1.0 SelectionHighlight.qml
ControlCenterSelection 1.0 ControlCenterSelection.qml
singleton AppearanceTokens 1.0 AppearanceTokens.qml
`);
    copyFileSync(new URL("tst_controls.qml", import.meta.url), join(controls, "tst_controls.qml"));
    console.log(run(process.argv[2] || "qmltestrunner", ["-input", controls]).trim());

    const runtime = join(scratch, "shell");
    mkdirSync(runtime);
    for (const name of ["desktop", "Kos", "shared"])
        symlinkSync(join(repo, "shell", name), join(runtime, name), "dir");
    for (const name of ["config", "state", "runtime"])
        mkdirSync(join(runtime, name), { mode: 0o700 });
    copyFileSync(new URL("shell.qml", import.meta.url), join(runtime, "shell.qml"));
    const display = process.env.WAYLAND_DISPLAY;
    const socket = display && (isAbsolute(display) ? display : join(process.env.XDG_RUNTIME_DIR || "", display));
    if (!socket || !existsSync(socket)) {
        console.log("SKIP: unmapped shipping-surface checks require a Wayland compositor");
    } else {
        // Both production windows stay unmapped. Connect only for PanelWindow's
        // backend; no pointer/keyboard events or desktop actions are synthesized.
        symlinkSync(socket, join(runtime, "runtime", basename(display)));
        const output = run(process.argv[3] || "quickshell", ["-p", runtime, "--no-color"], {
            XDG_CONFIG_HOME: join(runtime, "config"), XDG_STATE_HOME: join(runtime, "state"),
            XDG_RUNTIME_DIR: join(runtime, "runtime"), WAYLAND_DISPLAY: basename(display),
            QT_QPA_PLATFORM: "wayland",
            DBUS_SESSION_BUS_ADDRESS: "unix:path=" + join(runtime, "runtime/no-bus"),
        });
        assert.match(output, /SELECTION_SURFACES_PASS/, output);
        console.log("Selection surfaces: shipping launcher apps/folders/keyboard/edit/merge and Control Center bindings passed");
    }
} finally {
    rmSync(scratch, { recursive: true, force: true });
}
