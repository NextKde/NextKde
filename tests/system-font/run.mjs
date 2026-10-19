import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

// 使用系统字体, read where the shell actually resolves it.
//
// The option is a chain of four links -- AppearanceConfigService.useSystemFont →
// SystemFontService (kdeglobals) → AppearanceTokens.typography.* → the string
// each Text item binds -- and every link fails *silently*: a Text that keeps its
// designed family still renders a plausible interface, just not the user's font.
// This fixture loads the shipping modules and reads the resolved `font.family`
// off representative Text items in both states of the option, so the chain is
// exercised the way the shell evaluates it.
//
// It needs the real module tree (the singletons reach across qs.desktop.modules.*
// and Kos.Ui), so it symlinks it instead of copying, the way tests/glass-ink does.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-system-font-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");
    symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
    mkdirSync(join(directory, "config"));
    mkdirSync(join(directory, "state"));
    mkdirSync(join(directory, "runtime"));
    // The family the fixture asserts on. Written as KDE 6 writes it, so the
    // parser is exercised against the real shape -- including the comma and the
    // point size the shell deliberately does not take.
    writeFileSync(join(directory, "config/kdeglobals"),
        "[General]\nfont=Maple Mono NF CN,10\n");

    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
        encoding: "utf8",
        timeout: 25000,
        env: {
            ...process.env,
            QT_QPA_PLATFORM: "offscreen",
            QT_QUICK_BACKEND: "software",
            WAYLAND_DISPLAY: "",
            DISPLAY: "",
            XDG_CONFIG_HOME: join(directory, "config"),
            XDG_STATE_HOME: join(directory, "state"),
            XDG_RUNTIME_DIR: join(directory, "runtime"),
            QML2_IMPORT_PATH: directory,
        },
    });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    // Markers go to stderr: the shell's logging setup filters console.log.
    assert.doesNotMatch(output, /FONT_FAIL/, output);
    assert.match(output, /FONT_PASS/, output);
    // A role the module no longer registers surfaces as a load-time warning
    // rather than a wrong family, so those are checked too.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError/,
        output);
    console.log("system font: off keeps the designed families, on resolves every "
        + "surface to the family kdeglobals names");
} finally {
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
