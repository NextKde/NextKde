import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

// Run the shipping Dock.qml and its position-specific Loader. Only its input
// services and DockWindow are replaced: the window double records when Dock
// asks it to become visible and which mode/edge that first exposure receives.
// This checks the pre-map boundary without a compositor or any user settings;
// it does not simulate KWin's handling of a layer surface's exclusive zone.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const directory = mkdtempSync(join(tmpdir(), "kos-dock-startup-"));

try {
    const dock = join(directory, "desktop/modules/dock");
    const common = join(directory, "desktop/modules/common");
    mkdirSync(dock, { recursive: true });
    mkdirSync(common, { recursive: true });
    mkdirSync(join(directory, "config"));
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    copyFileSync(join(repository, "shell/desktop/modules/dock/Dock.qml"),
        join(dock, "Dock.qml"));
    writeFileSync(join(dock, "qmldir"), `module qs.desktop.modules.dock
singleton ConfigService 1.0 ConfigService.qml
Dock 1.0 Dock.qml
DockWindow 1.0 DockWindow.qml
`);
    writeFileSync(join(dock, "ConfigService.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool ready: false
    property string position: "bottom"
    property string visibilityMode: "always"
    property int creations: 0
    property int shows: 0
    property bool dockVisible: false
    property string exposedMode: ""
    property string exposedPosition: ""
}
`);
    writeFileSync(join(dock, "DockWindow.qml"), `import QtQuick
Item {
    property string position: "bottom"
    property var screen: null
    property Component leadingAccessory: null
    property Component trailingAccessory: null
    property bool clockInInfoCarousel: false
    property bool completed: false
    function recordVisibility() {
        ConfigService.dockVisible = visible
        if (visible) {
            ConfigService.shows++
            ConfigService.exposedMode = ConfigService.visibilityMode
            ConfigService.exposedPosition = position
        }
    }
    onVisibleChanged: if (completed) recordVisibility()
    Component.onCompleted: {
        ConfigService.creations++
        completed = true
        recordVisibility()
    }
}
`);
    writeFileSync(join(common, "qmldir"), `module qs.desktop.modules.common
singleton ScreenLifecycle 1.0 ScreenLifecycle.qml
`);
    writeFileSync(join(common, "ScreenLifecycle.qml"), `pragma Singleton
import QtQuick
QtObject {
    property var activeScreen: ({ name: "test", width: 1920, height: 1080 })
    property bool outputAvailable: true
}
`);

    for (const mode of ["smart", "persistent", "always"]) {
        for (const position of ["bottom", "left", "right"]) {
            const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
                encoding: "utf8",
                timeout: 5000,
                env: {
                    ...process.env,
                    QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
                    XDG_CONFIG_HOME: join(directory, "config"),
                    XDG_STATE_HOME: join(directory, "state"),
                    KOS_TEST_MODE: mode, KOS_TEST_POSITION: position,
                },
            });
            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error) + "\n" + output);
            assert.equal(result.status, 0, output);
            assert.doesNotMatch(output,
                /FAIL |ReferenceError|TypeError|Binding loop|is not a type|Cannot assign|Unable to assign/);
            assert.match(output, /DOCK_STARTUP_PASS/);
            console.log(`Dock startup: ${mode}/${position} passed`);
        }
    }
} finally {
    rmSync(directory, { recursive: true, force: true });
}
