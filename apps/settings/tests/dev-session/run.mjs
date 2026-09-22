import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import {
    chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync,
} from "node:fs";
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
//   * an ordinary launch must keep loading the copy beside the binary, and must
//     not watch it: that copy is a destination, not an edit surface.
//
// Choosing wrong is invisible: every candidate renders the same UI, so the only
// evidence is the line the binary logs while choosing. That line is what this
// asserts on, plus the absence of reloads on the side that must never reload.
// `KOS_SHELL_DIR` is passed exactly as the platform daemon passes it -- an
// absolute path to the session's Shell directory -- and the checkout is built
// here, one level up from it, because that is the layout the window derives the
// pages from.

const binary = process.argv[2];
assert.ok(binary, "usage: run.mjs <kos-settings binary>");

const scratch = mkdtempSync(join(tmpdir(), "kos-settings-dev-session-"));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function environmental(shellDir) {
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
    return env;
}

function page(marker) {
    // Deliberately nothing like the real pages: this asserts which file was
    // picked, not that the real one still loads (the smoke test covers that).
    // It does read the bridge, because the banner condition is the other half of
    // the same decision -- see the source-text checks at the end.
    return `import QtQuick
import QtQuick.Controls

ApplicationWindow {
    visible: true
    width: 320
    height: 200
    Text { text: "${marker}" }
    Component.onCompleted: console.log("BANNER-" + (typeof settingsBridge !== "undefined"
        ? settingsBridge.sourceTreeEntry : "no-bridge"))
}
`;
}

function loadOnce(binary, shellDir) {
    const run = spawnSync(binary, ["--smoke-test"],
        { encoding: "utf8", env: environmental(shellDir) });
    return `${run.stdout ?? ""}${run.stderr ?? ""}`;
}

// Runs the window, edits the page under it, and reports whether it rebuilt
// itself. The edit writes the same bytes: a new timestamp is all a file watcher
// sees when an editor saves.
async function editWhileRunning(binary, shellDir, pagePath) {
    const child = spawn(binary, [], { env: environmental(shellDir) });
    let log = "";
    for (const stream of [child.stdout, child.stderr])
        stream.on("data", (chunk) => { log += chunk; });
    await sleep(1500);
    writeFileSync(pagePath, readFileSync(pagePath));
    await sleep(2500);
    child.kill("SIGKILL");
    await sleep(200);
    return log;
}

let checks = 0;
function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

try {
    // 1. A checkout session: the checkout's pages, and they are watched.
    const checkout = join(scratch, "checkout");
    const pagePath = join(checkout, "apps/settings/main.qml");
    mkdirSync(join(checkout, "shell"), { recursive: true });
    mkdirSync(join(checkout, "apps/settings"), { recursive: true });
    writeFileSync(join(checkout, "shell/shell.qml"),
        "import QtQuick\nimport Quickshell\nShellRoot {}\n");
    writeFileSync(pagePath, page("CHECKOUT"));

    const development = loadOnce(binary, join(checkout, "shell"));
    check(development.includes(`loading QML from ${pagePath}`),
        `a checkout session must load the checkout's own pages:\n${development}`);
    check(development.includes("session checkout"),
        `the log has to name the checkout as the source:\n${development}`);
    check(development.includes("reloads on change"),
        `a checkout session must watch its pages, not only load them once:\n${development}`);
    check(development.includes("BANNER-true"),
        `a checkout entry has to report itself as one, or its banner never shows:\n${development}`);

    // 2. No session at all: the installed copy beside the binary, and no
    //    watcher -- reloading a window because someone installed over it is the
    //    surprise the shell's own install path already avoids.
    const layout = join(scratch, "installed");
    const layoutBinary = join(layout, "bin/kos-settings");
    const layoutPage = join(layout, "share/kos/settings/main.qml");
    mkdirSync(join(layout, "bin"), { recursive: true });
    mkdirSync(join(layout, "share/kos/settings"), { recursive: true });
    copyFileSync(binary, layoutBinary);
    chmodSync(layoutBinary, 0o755);
    writeFileSync(layoutPage, page("INSTALLED"));

    const installed = loadOnce(layoutBinary, null);
    check(installed.includes(`loading QML from ${layoutPage}`),
        `a launch with no session must load the copy beside the binary:\n${installed}`);
    check(!installed.includes(pagePath),
        `a launch with no session must not pick up a checkout:\n${installed}`);
    check(!installed.includes("reloads on change"),
        `the installed copy must not claim to reload:\n${installed}`);
    check(installed.includes("BANNER-false"),
        `the installed copy must not claim a checkout entry, or the banner lies:\n${installed}`);

    const installedEdited = await editWhileRunning(layoutBinary, null, layoutPage);
    check(!installedEdited.includes("reloaded"),
        `the installed copy must not be watched:\n${installedEdited}`);
    check(installedEdited.includes("installed copy"),
        `the edit run has to be the installed-copy branch:\n${installedEdited}`);

    // 3. The banner condition belongs to the same decision, and it has to follow
    //    the entry point rather than the session: a window opened from the app
    //    grid loads the installed copy and only then talks to a checkout Shell,
    //    so keying the banner off the session would announce hot reloading on a
    //    window that has none. Asserted on the source text, because both
    //    spellings render perfectly -- only the file says which one shipped.
    const pages = readFileSync(join(import.meta.dirname, "../../main.qml"), "utf8");
    check(/visible:\s*window\.developmentBannerVisible/.test(pages),
        "the banner must be shown from the entry point, not from the session");
    check(/developmentBannerVisible:\s*window\.sourceTreeEntry[\s\S]{0,200}?settingsBridge\.developmentBannerDismissed/
        .test(pages),
        "the banner condition must be the entry point AND the dismissal, nothing else");
    check(!/visible:\s*window\.developmentSession/.test(pages),
        "the banner must not be driven by the session it happens to reach");
    check(/settingsBridge\.developmentBannerDismissed = true/.test(pages),
        "the close control has to dismiss the banner on the bridge, so a reload cannot resurrect it");

    console.log(`settings dev-session entry point: ${checks} checks passed`);
} finally {
    rmSync(scratch, { recursive: true, force: true });
}
