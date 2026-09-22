import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Boots the whole shipping shell -- shell/shell.qml, not a fixture -- on a
// headless Wayland compositor and waits for Quickshell's "Configuration
// Loaded" line. The offscreen fixtures under tests/static-work, squircle-mask
// and liquid-glass-panel load isolated QML; this is the only check that the
// real configuration and its module graph come up on a live compositor.
//
// argv[2] quickshell, argv[3] weston (both default to what is on PATH).
const quickshell = process.argv[2] || "quickshell";
const weston = process.argv[3] || "weston";
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-shell-startup-"));
const runtime = join(directory, "runtime");
mkdirSync(runtime, { mode: 0o700 });
const display = "wayland-kos-shell-test";

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForFile(path, process_, deadlineMs) {
    const deadline = Date.now() + deadlineMs;
    while (Date.now() < deadline) {
        if (existsSync(path))
            return true;
        if (process_.exitCode !== null || process_.signalCode !== null)
            return false;
        await sleep(100);
    }
    return false;
}

async function stop(process_) {
    if (!process_ || process_.exitCode !== null || process_.signalCode !== null)
        return;
    process_.kill("SIGTERM");
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline && process_.exitCode === null
            && process_.signalCode === null)
        await sleep(100);
    if (process_.exitCode === null && process_.signalCode === null)
        process_.kill("SIGKILL");
}

async function main() {
    // A headless compositor with the software renderer: CI containers have no
    // GPU at all, and the GL renderer aborts before the shell can connect.
    const help = spawnSync(weston, ["--help"], { encoding: "utf8" });
    const helpText = (help.stdout || "") + (help.stderr || "");
    const renderer = helpText.includes("--renderer=pixman") ? "--renderer=pixman"
        : helpText.includes("--use-pixman") ? "--use-pixman" : null;

    const westonArguments = ["--backend=headless", `--socket=${display}`];
    if (renderer)
        westonArguments.push(renderer);
    console.log(`weston: ${westonArguments.join(" ")}`);

    const westonProcess = spawn(weston, westonArguments, {
        env: { ...process.env, XDG_RUNTIME_DIR: runtime },
        stdio: ["ignore", "pipe", "pipe"],
    });
    let westonOutput = "";
    westonProcess.stdout.on("data", (chunk) => { westonOutput += chunk; });
    westonProcess.stderr.on("data", (chunk) => { westonOutput += chunk; });

    const socketPath = join(runtime, display);
    if (!await waitForFile(socketPath, westonProcess, 15000)) {
        console.error(`weston never created ${socketPath}\n${westonOutput}`);
        await stop(westonProcess);
        return 1;
    }

    const shellProcess = spawn(quickshell, ["-p", shell], {
        env: {
            ...process.env,
            XDG_RUNTIME_DIR: runtime,
            WAYLAND_DISPLAY: display,
            QT_QPA_PLATFORM: "wayland",
            QT_QUICK_BACKEND: "software",
        },
        stdio: ["ignore", "pipe", "pipe"],
    });
    let shellOutput = "";
    shellProcess.stdout.on("data", (chunk) => { shellOutput += chunk; });
    shellProcess.stderr.on("data", (chunk) => { shellOutput += chunk; });

    // "Configuration Loaded" is Quickshell's own success line: printed once
    // the whole configuration has been parsed and the object tree built.
    let loaded = false;
    const deadline = Date.now() + 45000;
    while (Date.now() < deadline && !loaded) {
        if (shellOutput.includes("Configuration Loaded"))
            loaded = true;
        else if (shellProcess.exitCode !== null
                || shellProcess.signalCode !== null)
            break;
        else
            await sleep(250);
    }
    if (!loaded) {
        console.error(`no "Configuration Loaded" from quickshell\n${shellOutput}`);
        await stop(shellProcess);
        await stop(westonProcess);
        return 1;
    }

    // A configuration that loads and then dies a moment later is still a
    // broken shell, so hold the session open and re-check before passing.
    await sleep(4000);
    if (shellProcess.exitCode !== null || shellProcess.signalCode !== null) {
        console.error(`quickshell died right after loading\n${shellOutput}`);
        await stop(westonProcess);
        return 1;
    }
    console.log("shell.qml loaded and stayed alive on headless weston");
    await stop(shellProcess);
    await stop(westonProcess);
    return 0;
}

let exitCode = 1;
try {
    exitCode = await main();
} catch (error) {
    console.error(String((error && error.stack) || error));
} finally {
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
process.exit(exitCode);
