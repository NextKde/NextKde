import assert from "node:assert/strict";
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads LiquidGlassPanel.qml under a real Quickshell, offscreen.
//
// This fixture cannot copy the component into a scratch tree the way the
// SquircleMask one does. LiquidGlassPanel sits on LiquidGlassSurface, which
// sits on AppearanceTokens, which reaches through the Kos/Ui alias into
// shared/qml; reproducing that layout by hand would mean a second copy of the
// module tree, quietly drifting from the real one. Quickshell instead resolves
// "qs.desktop.modules.*" against the config directory, so a single "desktop"
// symlink is enough -- and the fixture then exercises the shipping files rather
// than copies of them.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const shaderBinary = join(shell, "desktop", "shaders", "squircle.frag.qsb");
assert.ok(existsSync(shaderBinary),
    "shell/desktop/shaders/squircle.frag.qsb is missing; "
    + "run shell/desktop/shaders/compile.sh after editing squircle.frag");

// DockWindow is a PanelWindow, so it needs a Wayland session and cannot be
// loaded here. Its base pill is nevertheless the reason the panel exists and
// the one consumer whose regression no other test would notice, so read its
// shape out of the source: the Dock's base pill must carry its own capsule
// corner profile while KWin remains the sole glass renderer.
const dockWindow = readFileSync(
    join(shell, "desktop", "modules", "dock", "DockWindow.qml"), "utf8");
const dockPill = dockWindow.match(
    /LiquidGlassPanel \{\n\s*id: pill\n([\s\S]*?)\n {8}\}/);
assert.ok(dockPill, "the Dock's base pill is a LiquidGlassPanel named pill");
assert.match(dockPill[1], /\n\s*radius: dockContainer\.pillRadius/,
    "the Dock pill keeps its own radius");
assert.match(dockPill[1],
    /\n\s*cornerExponent: 2\.35/,
    "the Dock pill keeps its capsule corner profile");
assert.doesNotMatch(dockPill[1], /\n\s*(blurEnabled|blurStrength|liquidStrength):/,
    "the Dock pill does not own compositor glass settings");
console.log("Dock pill: shape only; KWin owns the glass finish");

const directory = mkdtempSync(join(tmpdir(), "kos-liquid-glass-panel-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    // Quickshell resolves "qs.desktop.modules.*" against the config directory,
    // and AppearanceTokens reaches the shared library through the Kos/Ui alias
    // with a path relative to its own file. Both names have to exist in the
    // scratch directory for the tree to resolve exactly as it does in a live
    // session; without the second one the failure is a bare "module
    // ../../../Kos/Ui is not installed" six frames down the type chain.
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 12000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /LIQUID_GLASS_PANEL_PASS/);
    assert.doesNotMatch(output, /LIQUID_GLASS_PANEL_FAIL/, output);
    // QML resolves types and property names at load time, so this catches the
    // panel drifting away from the body it forwards to, from SquircleMask, or
    // from its own registration in modules/common/qmldir.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|ShaderEffect/,
        output);
    console.log("LiquidGlassPanel offscreen: shape switch, forwarding and "
        + "content alias all resolve");
} finally {
    // The scratch tree is nothing but symlinks, and some sandboxes route rm
    // through a trash directory the process cannot write. Cleanup failing says
    // nothing about the panel, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
