import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:net";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Usage: node tests/dock/runtime.mjs <case> [quickshell-or-qmltestrunner]
// Each selected case retains its own scratch configuration and cleanup.
const cases = {
    "native-target": async () => {
        // Load the production service and native delegates. Only the external
        // task protocol and daemon are mocked; no desktop session is touched.
        const directory = mkdtempSync(join(tmpdir(), "kos-native-target-"));
        try {
            const source = new URL("../../shell/desktop/modules/dock/", import.meta.url);
            const service = readFileSync(new URL("DockWindowAnimationTargetService.qml", source), "utf8")
                .replace("import qs.desktop.modules.common", 'import "."')
                .replace("import qs.desktop.modules.platform", 'import "."')
                .replace("import org.kde.taskmanager as TaskManager", 'import "." as TaskManager');
            writeFileSync(join(directory, "DockWindowAnimationTargetService.qml"), service);
            copyFileSync(new URL("NativeMinimizeTarget.mjs", source), join(directory, "NativeMinimizeTarget.mjs"));
            copyFileSync(new URL("native-target.qml", import.meta.url), join(directory, "tst_native_target.qml"));
            writeFileSync(join(directory, "qmldir"), `singleton DockWindowAnimationTargetService 1.0 DockWindowAnimationTargetService.qml
singleton WindowService 1.0 WindowService.qml
singleton PlatformClient 1.0 PlatformClient.qml
TasksModel 1.0 TasksModel.qml
`);
            writeFileSync(join(directory, "WindowService.qml"), `pragma Singleton
import QtQuick
QtObject { property var records: [] }
`);
            writeFileSync(join(directory, "PlatformClient.qml"), `pragma Singleton
import QtQuick
QtObject {
    property int calls: 0
    signal eventReceived(string eventName, var payload)
    function request(op, payload, callback) { calls++; callback({ ok: false }) }
}
`);
            writeFileSync(join(directory, "TasksModel.qml"), `import QtQuick
ListModel {
    dynamicRoles: true
    enum GroupMode { GroupDisabled }
    enum SortMode { SortDisabled }
    property int groupMode: 0
    property int sortMode: 0
    property var requests: []
    function makeModelIndex(row) { return row }
    function requestPublishDelegateGeometry(row, geometry, item) {
        requests = requests.concat([{ row, parent: item.parent,
            x: item.x, y: item.y, width: item.width, height: item.height }])
    }
}
`);
            const result = spawnSync(process.argv[3] || "qmltestrunner", ["-input", directory], {
                encoding: "utf8", timeout: 15000,
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
    },
    "builtins": async () => {
        // Run the real configuration service and JSON transport across three starts. Only the
        // platform's state storage is replaced, so this never writes user settings.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const directory = mkdtempSync(join(tmpdir(), "kos-dock-builtins-"));
        const socket = join(directory, "platform.sock");
        const saved = new Map();
        const server = createServer((connection) => {
            let pending = "";
            connection.on("data", (chunk) => {
                pending += chunk;
                let newline;
                while ((newline = pending.indexOf("\n")) >= 0) {
                    const request = JSON.parse(pending.slice(0, newline));
                    pending = pending.slice(newline + 1);
                    const payload = request.payload ?? {};
                    const key = `${payload.dir}/${payload.file}`;
                    let result = {};
                    if (request.operation === "state.write")
                        saved.set(key, payload.data);
                    if (request.operation === "state.read")
                        result = { exists: saved.has(key), data: saved.get(key) ?? "" };
                    connection.write(JSON.stringify({ version: 1, requestId: request.requestId, ok: true, result }) + "\n");
                }
            });
        });

        async function run(reload) {
            const child = spawn(process.argv[3] || "quickshell", ["-p", directory], {
                env: {
                    ...process.env,
                    QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
                    XDG_CONFIG_HOME: join(directory, "config"),
                    XDG_STATE_HOME: join(directory, "state"),
                    KOS_PLATFORM_SOCKET: socket,
                    KOS_DATA_SOCKET: join(directory, "absent-data.sock"),
                    KOS_TEST_RELOAD: String(reload),
                    WAYLAND_DISPLAY: "", DISPLAY: "",
                },
            });
            let output = "";
            child.stdout.on("data", (chunk) => { output += chunk; });
            child.stderr.on("data", (chunk) => { output += chunk; });
            const timeout = setTimeout(() => child.kill("SIGKILL"), 10000);
            try {
                const status = await new Promise((resolve, reject) => {
                    child.on("error", reject);
                    child.on("exit", resolve);
                });
                assert.equal(status, 0, output);
                assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop/);
                assert.ok(output.includes(reload === 2 ? "DOCK_BUILTINS_DEFAULT_RELOAD_PASS"
                    : reload === 1 ? "DOCK_BUILTINS_RELOAD_PASS"
                    : "DOCK_BUILTINS_SAVE_PASS"), output);
            } finally {
                clearTimeout(timeout);
                child.kill();
            }
        }

        try {
            copyFileSync(new URL("./builtins.qml", import.meta.url), join(directory, "shell.qml"));
            symlinkSync(join(repository, "shell/desktop"), join(directory, "desktop"), "dir");
            symlinkSync(join(repository, "shell/shared"), join(directory, "shared"), "dir");
            symlinkSync(join(repository, "shell/Kos"), join(directory, "Kos"), "dir");
            mkdirSync(join(directory, "config"));
            await new Promise((resolve) => server.listen(socket, resolve));
            await run(0);
            assert.ok([...saved.values()].some((data) => {
                const value = JSON.parse(data);
                return value.showLauncher === false && value.showTrash === false;
            }), "visibility booleans must be serialized");
            await run(1);
            assert.ok([...saved.values()].some((data) => {
                const value = JSON.parse(data);
                return value.showLauncher === true && value.showTrash === true;
            }), "restoring defaults must also persist");
            await run(2);
            console.log("Dock built-ins: defaults, validation, independent toggles, persistence and restart passed");
        } finally {
            server.close();
            rmSync(directory, { recursive: true, force: true });
        }
    },
    "highlight": async () => {
        // Test the shipping paint-only component without importing the Dock's
        // Quickshell-only service registry into a plain Qt Quick Test process.
        const directory = mkdtempSync(join(tmpdir(), "kos-dock-highlight-"));
        try {
            copyFileSync(new URL("../../shared/qml/controls/SelectionHighlight.qml", import.meta.url),
                join(directory, "SelectionHighlight.qml"));
            const dockWrapper = readFileSync(new URL("../../shell/desktop/modules/dock/DockIconHighlight.qml", import.meta.url), "utf8")
                .replace('import "../../../Kos/Ui"', 'import "."');
            writeFileSync(join(directory, "DockIconHighlight.qml"), dockWrapper);
            const fixture = readFileSync(new URL("./highlight.qml", import.meta.url), "utf8")
                .replace('import "../../shell/desktop/modules/dock" as Dock', 'import "." as Dock');
            writeFileSync(join(directory, "tst_highlight.qml"), fixture);
            const result = spawnSync(process.argv[3] || "qmltestrunner", ["-input", directory], {
                encoding: "utf8",
                timeout: 15000,
                env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
            });
            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error) + "\n" + output);
            assert.equal(result.status, 0, output);
            assert.doesNotMatch(output, /FAIL!|ReferenceError|TypeError|Binding loop/);
            console.log(output.trim());
        } finally {
            rmSync(directory, { recursive: true, force: true });
        }
    },
    "hover-hit": async () => {
        // Loads the shipping DockIcon under a real Quickshell, offscreen, and drives its
        // `magnificationPointer` by hand (a pointer never enters an offscreen window).
        //
        // What this pins: `_hovering` must be a pure function of the pointer against the
        // icon's *untransformed* slot. It used to be `_mouseArea.containsMouse`, and
        // that MouseArea is anchored to the icon, so it moved with the hover lift/scale
        // it drove -- with the cursor parked on the slot's bottom edge the icon lifted
        // out from under it, the hover cleared, the icon dropped back and the cycle
        // repeated. That is an endless jitter, and no other test in the suite looks at
        // where the Dock decides an icon is hovered.
        //
        // The fixture also reports the width of the band where the old
        // transformed-rect test disagrees with the slot test, so the size of the
        // removed defect is visible in the log rather than asserted.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const shell = join(repository, "shell");

        const directory = mkdtempSync(join(tmpdir(), "kos-dock-hover-hit-"));
        try {
            copyFileSync(new URL("./hover-hit.qml", import.meta.url),
                join(directory, "shell.qml"));
            // Quickshell resolves "qs.desktop.modules.*" against the config directory,
            // and AppearanceTokens reaches the shared library through the Kos/Ui alias
            // with a path relative to its own file.
            symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
            symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
            symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

            // The magnification tokens (and therefore the hover lift this test is about)
            // only switch on for the macOS shell style, which is also the default. An
            // empty config home guarantees that default instead of inheriting whatever
            // the machine running the test has selected.
            const configHome = join(directory, "config");
            mkdirSync(configHome, { recursive: true });

            const result = spawnSync(process.argv[3] || "quickshell",
                ["-p", directory], {
                    encoding: "utf8",
                    timeout: 20000,
                    env: {
                        ...process.env,
                        QT_QPA_PLATFORM: "offscreen",
                        QT_QUICK_BACKEND: "software",
                        XDG_CONFIG_HOME: configHome,
                    },
                });

            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error));
            assert.equal(result.status, 0, output);
            assert.match(output, /DOCK_HOVER_HIT_PASS/);
            // QML resolves types and property names at load time, so this catches
            // DockIcon drifting away from its own module registration.
            assert.doesNotMatch(output,
                /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop/,
                output);
            // A binding loop between the hover test and the lift it drives is the whole
            // defect; QML reports it, and the fixture must never accept it.
            assert.doesNotMatch(output, /FAIL /, output);

            for (const line of output.split("\n"))
                if (line.includes("REPORT ")) console.log(line.slice(line.indexOf("REPORT ")));
            console.log("DockIcon hover: resolved against the untransformed slot on both axes");
        } finally {
            // The scratch tree is nothing but symlinks, and some sandboxes route rm
            // through a trash directory the process cannot write. Cleanup failing says
            // nothing about the Dock, so it must not be able to fail the test.
            try {
                rmSync(directory, { recursive: true, force: true });
            } catch {
                console.error(`left ${directory} for the system temp reaper`);
            }
        }
    },
    "launch-feedback": async () => {
        // Runs the shipping DockIcon through boundary, entry, tracking and exit probes.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const shell = join(repository, "shell");

        const directory = mkdtempSync(join(tmpdir(), "kos-dock-launch-feedback-"));
        try {
            copyFileSync(new URL("./launch-feedback.qml", import.meta.url),
                join(directory, "shell.qml"));
            // Quickshell resolves "qs.desktop.modules.*" against the config directory,
            // and AppearanceTokens reaches the shared library through the Kos/Ui alias
            // with a path relative to its own file.
            symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
            symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
            symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

            // The magnification tokens (and therefore the hover lift this test is about)
            // only switch on for the macOS shell style, which is also the default. An
            // empty config home guarantees that default instead of inheriting whatever
            // the machine running the test has selected.
            const configHome = join(directory, "config");
            mkdirSync(configHome, { recursive: true });

            const runtimeDir = join(directory, "runtime");
            mkdirSync(runtimeDir, { mode: 0o700 });
            const result = spawnSync(process.argv[3] || "quickshell",
                ["-p", directory], {
                    encoding: "utf8",
                    timeout: 20000,
                    env: {
                        ...process.env,
                        QT_QPA_PLATFORM: "offscreen",
                        QT_QUICK_BACKEND: "software",
                        QT_LOGGING_RULES: "qml.debug=true",
                        XDG_CONFIG_HOME: configHome,
                        XDG_STATE_HOME: join(directory, "state"),
                        XDG_RUNTIME_DIR: runtimeDir,
                        WAYLAND_DISPLAY: "", DISPLAY: "",
                        DBUS_SESSION_BUS_ADDRESS: "unix:path=" + join(runtimeDir, "no-bus"),
                    },
                });

            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error) + output);
            assert.equal(result.status, 0, output);
            assert.match(output, /DOCK_LAUNCH_FEEDBACK_PASS/);
            // Existing singleton teardown clears ConfigService before its delegates.
            // Ignore only those known bool-binding warnings after successful completion;
            // the same warning during the probe, and every other QML error, still fail.
            const completedAt = output.indexOf("DOCK_LAUNCH_FEEDBACK_PASS");
            const checkedOutput = output.slice(0, completedAt)
                + output.slice(completedAt).replace(
                    /^.*WARN scene: @desktop\/modules\/dock\/DockIcon.qml\[\d+:\d+\]: Unable to assign \[undefined\] to bool\r?\n/gm, "");
            // QML resolves types and property names at load time, so this catches
            // DockIcon drifting away from its own module registration.
            assert.doesNotMatch(checkedOutput,
                /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop/,
                output);
            // The fixture reports visual and temporal regressions as explicit failures.
            assert.doesNotMatch(output, /FAIL /, output);

            for (const line of output.split("\n"))
                if (line.includes("REPORT ")) console.log(line.slice(line.indexOf("REPORT ")));
            console.log("Dock launch feedback: readiness, failure, expiry, landing and label tracking on all edges");
        } finally {
            // The scratch tree is nothing but symlinks, and some sandboxes route rm
            // through a trash directory the process cannot write. Cleanup failing says
            // nothing about the Dock, so it must not be able to fail the test.
            try {
                rmSync(directory, { recursive: true, force: true });
            } catch {
                console.error(`left ${directory} for the system temp reaper`);
            }
        }
    },
    "magnification": async () => {
        // Runs the shipping DockIcon through boundary, entry, tracking and exit probes.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const shell = join(repository, "shell");

        const directory = mkdtempSync(join(tmpdir(), "kos-dock-magnification-"));
        try {
            copyFileSync(new URL("./magnification.qml", import.meta.url),
                join(directory, "shell.qml"));
            // Quickshell resolves "qs.desktop.modules.*" against the config directory,
            // and AppearanceTokens reaches the shared library through the Kos/Ui alias
            // with a path relative to its own file.
            symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
            symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
            symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

            // The magnification tokens (and therefore the hover lift this test is about)
            // only switch on for the macOS shell style, which is also the default. An
            // empty config home guarantees that default instead of inheriting whatever
            // the machine running the test has selected.
            const configHome = join(directory, "config");
            mkdirSync(configHome, { recursive: true });

            const runtimeDir = join(directory, "runtime");
            mkdirSync(runtimeDir, { mode: 0o700 });
            const result = spawnSync(process.argv[3] || "quickshell",
                ["-p", directory], {
                    encoding: "utf8",
                    timeout: 20000,
                    env: {
                        ...process.env,
                        QT_QPA_PLATFORM: "offscreen",
                        QT_QUICK_BACKEND: "software",
                        QT_LOGGING_RULES: "qml.debug=true",
                        XDG_CONFIG_HOME: configHome,
                        XDG_STATE_HOME: join(directory, "state"),
                        XDG_RUNTIME_DIR: runtimeDir,
                        WAYLAND_DISPLAY: "", DISPLAY: "",
                        DBUS_SESSION_BUS_ADDRESS: "unix:path=" + join(runtimeDir, "no-bus"),
                    },
                });

            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error));
            assert.equal(result.status, 0, output);
            assert.match(output, /DOCK_MAGNIFICATION_PASS/);
            // Existing singleton teardown clears ConfigService before its delegates.
            // Ignore only those known bool-binding warnings after successful completion;
            // the same warning during the probe, and every other QML error, still fail.
            const completedAt = output.indexOf("DOCK_MAGNIFICATION_PASS");
            const checkedOutput = output.slice(0, completedAt)
                + output.slice(completedAt).replace(
                    /^.*WARN scene: @desktop\/modules\/dock\/DockIcon.qml\[\d+:\d+\]: Unable to assign \[undefined\] to bool\r?\n/gm, "");
            // QML resolves types and property names at load time, so this catches
            // DockIcon drifting away from its own module registration.
            assert.doesNotMatch(checkedOutput,
                /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop/,
                output);
            // The fixture reports visual and temporal regressions as explicit failures.
            assert.doesNotMatch(output, /FAIL /, output);

            for (const line of output.split("\n"))
                if (line.includes("REPORT ")) console.log(line.slice(line.indexOf("REPORT ")));
            console.log("Dock magnification: continuous boundaries, synchronized motion and idle settlement on all edges");
        } finally {
            // The scratch tree is nothing but symlinks, and some sandboxes route rm
            // through a trash directory the process cannot write. Cleanup failing says
            // nothing about the Dock, so it must not be able to fail the test.
            try {
                rmSync(directory, { recursive: true, force: true });
            } catch {
                console.error(`left ${directory} for the system temp reaper`);
            }
        }
    },
    "reveal": async () => {
        // Exercise the shipping handle, controller, geometry and timing code with
        // synthetic Qt events in an offscreen QQuickWindow. Service state and the glass
        // renderer are stubbed; no event reaches the user's compositor or pointer.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const directory = mkdtempSync(join(tmpdir(), 'kos-dock-reveal-'));
        try {
            const dock = join(directory, 'desktop/modules/dock');
            const common = join(directory, 'desktop/modules/common');
            for (const path of [dock, common, join(directory, 'config'), join(directory, 'state'), join(directory, 'runtime')])
                mkdirSync(path, { recursive: true, mode: 0o700 });
            for (const name of ['DockRevealHandle.qml', 'DockRevealGeometry.mjs',
                'DockAutoHideController.qml', 'DockAutoHideMath.mjs', 'DockAnimation.qml'])
                symlinkSync(join(repository, 'shell/desktop/modules/dock', name), join(dock, name));
            copyFileSync(new URL("./fixtures/WindowService.qml", import.meta.url), join(dock, 'WindowService.qml'));
            for (const name of ['LiquidGlassPanel.qml', 'AppearanceTokens.qml'])
                copyFileSync(new URL(`fixtures/${name}`, import.meta.url), join(common, name));
            writeFileSync(join(dock, 'ConfigService.qml'), `pragma Singleton
import QtQuick
QtObject { readonly property real effectiveHoverScale: 1.1 }
`);
            writeFileSync(join(dock, 'qmldir'), `module qs.desktop.modules.dock
        DockRevealHandle 1.0 DockRevealHandle.qml
        DockAutoHideController 1.0 DockAutoHideController.qml
        singleton DockAnimation 1.0 DockAnimation.qml
        singleton ConfigService 1.0 ConfigService.qml
        singleton WindowService 1.0 WindowService.qml
        `);
            writeFileSync(join(common, 'qmldir'), `module qs.desktop.modules.common
        LiquidGlassPanel 1.0 LiquidGlassPanel.qml
        singleton AppearanceTokens 1.0 AppearanceTokens.qml
        `);
            copyFileSync(new URL("./reveal.qml", import.meta.url), join(directory, 'shell.qml'));
            const result = spawnSync(process.argv[3] || 'quickshell', ['-p', directory], {
                encoding: 'utf8', timeout: 22000,
                env: { ...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
                    WAYLAND_DISPLAY: '', DISPLAY: '',
                    XDG_CONFIG_HOME: join(directory, 'config'), XDG_STATE_HOME: join(directory, 'state'),
                    XDG_RUNTIME_DIR: join(directory, 'runtime'),
                    KOS_PLATFORM_SOCKET: join(directory, 'absent-platform.sock'),
                    KOS_DATA_SOCKET: join(directory, 'absent-data.sock') },
            });
            const output = (result.stdout || '') + (result.stderr || '');
            assert.equal(result.error, undefined, String(result.error));
            assert.equal(result.status, 0, output);
            assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop|is not a type|is not a function|Cannot assign|Unable to assign/, output);
            assert.match(output, /DOCK_REVEAL_RUNTIME_PASS/, output);
            console.log('Dock reveal: real HoverHandler input, delayed/cancelled entry, slow gap hand-off, hide reset, dynamic span, legacy default, mode switching and disabled mode passed offscreen');
        } finally {
            rmSync(directory, { recursive: true, force: true });
        }
    },
    "reveal-indicator": async () => {
        // Run the real configuration service and JSON transport twice. Only the
        // platform's state storage is replaced, so this never writes user settings.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const directory = mkdtempSync(join(tmpdir(), "kos-dock-reveal-indicator-"));
        const socket = join(directory, "platform.sock");
        const saved = new Map();
        const server = createServer((connection) => {
            let pending = "";
            connection.on("data", (chunk) => {
                pending += chunk;
                let newline;
                while ((newline = pending.indexOf("\n")) >= 0) {
                    const request = JSON.parse(pending.slice(0, newline));
                    pending = pending.slice(newline + 1);
                    const payload = request.payload ?? {};
                    const key = `${payload.dir}/${payload.file}`;
                    let result = {};
                    if (request.operation === "state.write")
                        saved.set(key, payload.data);
                    if (request.operation === "state.read")
                        result = { exists: saved.has(key), data: saved.get(key) ?? "" };
                    connection.write(JSON.stringify({ version: 1, requestId: request.requestId, ok: true, result }) + "\n");
                }
            });
        });

        async function run(reload) {
            const child = spawn(process.argv[3] || "quickshell", ["-p", directory], {
                env: {
                    ...process.env,
                    QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
                    XDG_CONFIG_HOME: join(directory, "config"),
                    XDG_STATE_HOME: join(directory, "state"),
                    KOS_PLATFORM_SOCKET: socket,
                    KOS_DATA_SOCKET: join(directory, "absent-data.sock"),
                    KOS_TEST_RELOAD: reload ? "1" : "0",
                },
            });
            let output = "";
            child.stdout.on("data", (chunk) => { output += chunk; });
            child.stderr.on("data", (chunk) => { output += chunk; });
            const timeout = setTimeout(() => child.kill("SIGKILL"), 10000);
            try {
                const status = await new Promise((resolve, reject) => {
                    child.on("error", reject);
                    child.on("exit", resolve);
                });
                assert.equal(status, 0, output);
                assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop/);
                assert.ok(output.includes(reload ? "DOCK_REVEAL_INDICATOR_RELOAD_PASS"
                    : "DOCK_REVEAL_INDICATOR_SAVE_PASS"), output);
            } finally {
                clearTimeout(timeout);
                child.kill();
            }
        }

        try {
            copyFileSync(new URL("./reveal-indicator.qml", import.meta.url), join(directory, "shell.qml"));
            symlinkSync(join(repository, "shell/desktop"), join(directory, "desktop"), "dir");
            symlinkSync(join(repository, "shell/shared"), join(directory, "shared"), "dir");
            symlinkSync(join(repository, "shell/Kos"), join(directory, "Kos"), "dir");
            mkdirSync(join(directory, "config"));
            await new Promise((resolve) => server.listen(socket, resolve));
            await run(false);
            assert.ok([...saved.values()].some((data) => {
                const value = JSON.parse(data);
                return value.showRevealIndicator === false;
            }), "indicator visibility must be serialized as a boolean");
            await run(true);
            console.log("Dock reveal indicator: defaults, rendering, hit target, persistence and restart passed");
        } finally {
            server.close();
            rmSync(directory, { recursive: true, force: true });
        }
    },
    "startup": async () => {
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
            copyFileSync(new URL("./startup.qml", import.meta.url), join(directory, "shell.qml"));
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
                    const result = spawnSync(process.argv[3] || "quickshell", ["-p", directory], {
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
    },
    "surface": async () => {
        // Exercise DockWindow's shipping bindings offscreen. Replace only the
        // layer-shell boundary with a QQuickWindow; the geometry, region aggregation,
        // glass visibility and input mask remain the actual source. This checks what
        // we submit to the compositor, not KWin's rendering of the submitted regions.
        const repository = fileURLToPath(new URL("../..", import.meta.url));
        const directory = mkdtempSync(join(tmpdir(), "kos-dock-surface-"));
        function module(name, files) {
            const path = join(directory, "desktop/modules", name);
            mkdirSync(path, { recursive: true });
            const entries = [`module qs.desktop.modules.${name}`];
            for (const [type, body] of Object.entries(files)) {
                const singleton = body.startsWith("pragma Singleton");
                writeFileSync(join(path, `${type}.qml`), body);
                entries.push(`${singleton ? "singleton " : ""}${type} 1.0 ${type}.qml`);
            }
            writeFileSync(join(path, "qmldir"), entries.join("\n") + "\n");
        }
        const object = body => `pragma Singleton\nimport QtQuick\nQtObject { ${body} }\n`;
        try {
            const source = readFileSync(join(repository, "shell/desktop/modules/dock/DockWindow.qml"), "utf8");
            const window = source.replace('import "../../../Kos/Ui"', "import QtQuick.Window")
                .replace(/^import qs\.desktop\.modules\.(deskcenter|platform)\n/gm, "")
                .replace("PanelWindow {", "Window {")
                .replace(/^    WlrLayershell\.namespace:.*\n/m, "")
                .replace(/^    exclusionMode:.*\n/m, "")
                .replace(/^    WlrLayershell\.layer:[\s\S]*?WlrLayer\.Top\n/m, "")
                .replace(/^    WlrLayershell\.keyboardFocus:[\s\S]*?: WlrKeyboardFocus\.None\n/m, "")
                .replace("    anchors: ({", "    property var testAnchors: ({")
                .replace(/^    margins \{.*\}\n/m, "")
                .replace("    exclusiveZone:", "    property real exclusiveZone:")
                .replace("    implicitWidth:", "    property real implicitWidth:")
                .replace("    implicitHeight:", "    property real implicitHeight:")
                .replace("    BackgroundEffect.blurRegion:", "    property var testBlurRegion:")
                .replace("    mask: Region {", "    property Region testMask: Region {")
                .replace("    id: root", `    id: root
            width: vertical ? implicitWidth : 1000
            height: vertical ? 1000 : implicitHeight
            readonly property alias testContainer: dockContainer
            readonly property alias testController: hide
            readonly property alias testPill: pill
            readonly property alias testHandle: revealHandle
            readonly property alias testRegions: dockBlurRegionHolder`);
            module("dock", {
                DockWindow: window,
                ConfigService: object(`property string dockStyle: "floating"; property string visibilityMode: "always"
                    property bool showRevealIndicator: true; property real effectiveHoverScale: 1
                    property real effectiveHoverLift: 0
                    property bool ready: true; property int barHeight: 35`),
                DockContainer: `import QtQuick
        Item {
            property var targetScreen; property real surfaceOriginX; property real surfaceOriginY
            property Component leadingAccessory; property Component trailingAccessory
            property bool clockInInfoCarousel; property bool pointerInside: false; property bool editMode: false
            property bool launchAnimationVisible; property Item nameLabelHost; property bool nameLabelsEnabled
            property Item pointerInputItem; property Item pointerEventRoot
            property bool statusCollectionExpanded: false; property bool statusDragActive: false
            property bool accessoryInteractionActive: false
            property real iconSize: 44; property real activeBackgroundGap: 4
            property real magnificationRadius: 60; property real hoverGlassShift: 0
            readonly property real computedDockHeight: Math.min(width, height)
            readonly property real restingComputedWidth: width
            function closeStatusCollectionOutside(x, y) {}
            property var draggedPinnedLoader: null; property real pillRadius: 28
            readonly property real surfaceRadius: ConfigService.dockStyle === "taskbar" ? 0 : pillRadius
            width: 56; height: 900
        }`,
                DockAutoHideController: `import QtQuick
        Item {
            property string mode; property bool configReady; property bool windowDataReady
            property string position; property var targetScreen
            property real dockWidth; property real dockHeight; property real edgeMargin
            property bool pointerInsideDock; property bool editing; property bool dragging
            property bool popupOpen; property bool launcherOpen
            property real revealProgress: 1; property real offsetX: 0; property real offsetY: 0
            property real dockOpacity: 1; property real dockScale: 1; property real handleOpacity: 0
            property bool handleActive: false; property string phase: "Shown"
            function handleEntered() {} function handleExited() {} function handleClicked() {}
            function requestReveal(reason, duration) {}
        }`,
                DockModelService: object("property var activeDockPopup: null; signal urgentWindowAppeared()"),
                WindowService: object("property bool providerReady: true"),
                DockAnimation: object(`property int smartHideUrgentRevealMs: 2200
                    property real launchBounceHeightRatio: 0.5; property real nameLabelGap: 8
                    property real nameLabelMaximumWidth: 160; property real nameLabelMaximumHeight: 24`),
                ThemeService: object('property color backgroundColor: "black"'),
                DockRevealHandle: readFileSync(join(repository, "shell/desktop/modules/dock/DockRevealHandle.qml"), "utf8"),
            });
            copyFileSync(join(repository, "shell/desktop/modules/dock/DockRevealGeometry.mjs"),
                join(directory, "desktop/modules/dock/DockRevealGeometry.mjs"));
            copyFileSync(join(repository, "shell/desktop/modules/dock/DockMagnification.mjs"),
                join(directory, "desktop/modules/dock/DockMagnification.mjs"));
            const glass = readFileSync(join(repository, "tests/dock/fixtures/LiquidGlassPanel.qml"), "utf8")
                .replace("import QtQuick", "import QtQuick\nimport Quickshell")
                .replace("property var blurRegion: null", "property Region blurRegion: Region {}");
            module("common", {
                LiquidGlassPanel: glass,
                AppearanceTokens: object(`property var surface: ({ usesKwinBlur: true, usesBackdrop: true })
                    property var glass: ({ ambientMultiplier: 1 })`),
                AppearanceConfigService: object(`property real effectiveDockBlur: 1
                    property real effectiveDockLiquid: 1; property bool barIntegratedWithDock: false`),
                WorkspaceLayoutService: object("function updateDock(screen, position, rect, margin) {}"),
            });
            module("applauncher", {
                AppLauncherService: object("property bool open: false"),
                AppLauncherConfigService: object('property string displayMode: "bottom"'),
            });
            module("wallpaper", {
                WallpaperColorSource: object('property color primary: "black"; property color secondary: "black"'),
                ThemeWallpaperService: object("property bool active: false; function setDockRect(screen, rect) {}"),
            });
            copyFileSync(new URL("./surface.qml", import.meta.url), join(directory, "shell.qml"));
            const result = spawnSync(process.argv[3] || "quickshell", ["-p", directory], {
                encoding: "utf8", timeout: 6000,
                env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
                    WAYLAND_DISPLAY: "", DISPLAY: "" },
            });
            const output = (result.stdout || "") + (result.stderr || "");
            assert.equal(result.error, undefined, String(result.error));
            assert.equal(result.status, 0, output);
            assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop|is not a type|Cannot assign|Unable to assign/, output);
            assert.match(output, /DOCK_SURFACE_PASS/, output);
            console.log("Dock surface: proportional side margins, workspace reservation and hidden/shown glass declarations passed");
        } finally {
            rmSync(directory, { recursive: true, force: true });
        }
    },
    "lyrics": async () => {
        const dir=mkdtempSync(join(tmpdir(),'kos-lyrics-'));
        try {
            const source=new URL('../../shell/desktop/modules/dock/',import.meta.url);
            // Keep the production service and timers, replace only the D-Bus model
            // and the deskcenter module import (stubbed locally below).
            writeFileSync(join(dir,'DockMprisService.qml'),readFileSync(new URL('DockMprisService.qml',source),'utf8')
                .replace('import Quickshell.Services.Mpris','import "."')
                .replace("import qs.desktop.modules.deskcenter\n",""));
            copyFileSync(new URL('TimedLyrics.mjs',source),join(dir,'TimedLyrics.mjs'));
            copyFileSync(new URL('lyrics.qml',import.meta.url),join(dir,'tst_lyrics.qml'));
            writeFileSync(join(dir,'qmldir'),'singleton DockMprisService 1.0 DockMprisService.qml\nsingleton DeskCenterConfigService 1.0 DeskCenterConfigService.qml\nsingleton Mpris 1.0 Mpris.qml\nsingleton MprisPlaybackState 1.0 MprisPlaybackState.qml\nMprisPlayer 1.0 MprisPlayer.qml\n');
            writeFileSync(join(dir,'DeskCenterConfigService.qml'),'pragma Singleton\nimport QtQuick\nQtObject { readonly property bool desktopLyricsActive: true }\n');
            writeFileSync(join(dir,'Mpris.qml'),'pragma Singleton\nimport QtQuick\nQtObject { property var players: [] }\n');
            writeFileSync(join(dir,'MprisPlaybackState.qml'),'pragma Singleton\nimport QtQuick\nQtObject { readonly property int paused: 2; enum State { Stopped, Playing, Paused } }\n');
            writeFileSync(join(dir,'MprisPlayer.qml'),`import QtQuick
        QtObject {
            property string dbusName: ""
            property var metadata: ({})
            property bool isPlaying: false
            property bool positionSupported: true
            property int playbackState: 0
            property real position: 0
            property string trackArtUrl: ""
            property string trackTitle: ""
            property string trackArtist: ""
        }`);
            const result=spawnSync(process.argv[3]||'qmltestrunner',['-input',dir],{encoding:'utf8',timeout:10000,
                env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software'}});
            const output=result.stdout+result.stderr;
            assert.equal(result.status,0,output);
            assert.doesNotMatch(output,/TypeError|ReferenceError/);
            console.log(output);
        } finally {rmSync(dir,{recursive:true,force:true});}
    },
};
const selected = process.argv[2];
assert.ok(Object.hasOwn(cases, selected),
    `Choose a Dock runtime case: ${Object.keys(cases).join(', ')}`);
await cases[selected]();
