import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Which QML tree the Settings window runs is decided by the session it serves,
// and both directions matter:
//
//   * a Shell started from a checkout (`kosctl dev` -> `qs -p <checkout>/shell`)
//     must make the window load that checkout's own pages. The binary is the
//     installed one in that mode -- `dev` builds no apps -- so without this the
//     window would silently show the installed copy and QML edits would need a
//     `kosctl install` each time, which is the whole thing `dev` exists to avoid;
//   * an ordinary launch must keep loading the copy beside the binary, even on a
//     machine that happens to have a checkout lying around.
//
// Choosing wrong is invisible: every candidate renders the same UI, so the only
// evidence is the line the binary logs while choosing. That line is what this
// asserts on. `KOS_SHELL_DIR` is passed exactly as the platform daemon passes it
// -- an absolute path to the session's Shell directory -- and the checkout is
// built here, one level up from it, because that is the layout the window
// derives the pages from.

const binary = process.argv[2];
assert.ok(binary, "usage: run.mjs <kos-settings binary>");

const scratch = mkdtempSync(join(tmpdir(), "kos-settings-dev-session-"));
const checkout = join(scratch, "checkout");
const page = join(checkout, "apps/settings/main.qml");
mkdirSync(join(checkout, "shell"), { recursive: true });
mkdirSync(join(checkout, "apps/settings"), { recursive: true });
writeFileSync(join(checkout, "shell/shell.qml"),
    "import QtQuick\nimport Quickshell\nShellRoot {}\n");
// Deliberately nothing like the real pages: this asserts which file was picked,
// not that the real one still loads (the smoke test above covers that).
writeFileSync(page,
    "import QtQuick\nimport QtQuick.Controls\nApplicationWindow { visible: true }\n");

function launch(shellDir) {
    const env = {
        ...process.env,
        QT_QPA_PLATFORM: "offscreen",
        QT_QUICK_BACKEND: "software",
        QSG_RHI_BACKEND: "software",
        // Without this the application's log lines do not reach stderr, and the
        // line under test is the only observable difference between the trees.
        QT_FORCE_STDERR_LOGGING: "1",
    };
    if (shellDir === null)
        delete env.KOS_SHELL_DIR;
    else
        env.KOS_SHELL_DIR = shellDir;

    const run = spawnSync(binary, ["--smoke-test"], { encoding: "utf8", env });
    return `${run.stdout ?? ""}${run.stderr ?? ""}`;
}

let checks = 0;
function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

try {
    const development = launch(join(checkout, "shell"));
    check(development.includes(`loading QML from ${page}`),
        `a checkout session must load the checkout's own pages:\n${development}`);
    check(development.includes("session checkout"),
        `the log has to name the checkout as the source:\n${development}`);
    check(development.includes("reloads on change"),
        `a checkout session must watch its pages, not only load them once:\n${development}`);

    const installed = launch(null);
    check(!installed.includes(page),
        `a launch with no session must not pick up a checkout:\n${installed}`);
    check(!installed.includes("reloads on change"),
        `only a checkout session may reload; the installed copy must not:\n${installed}`);
    check(/loading QML from .+ \((installed copy|build tree)\)/.test(installed),
        `a launch with no session has to name the installed copy or the build tree:\n${installed}`);

    console.log(`settings dev-session entry point: ${checks} checks passed`);
} finally {
    rmSync(scratch, { recursive: true, force: true });
}
