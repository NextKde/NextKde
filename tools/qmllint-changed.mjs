#!/usr/bin/env node
// Lint every QML file changed in the working tree, filtering qmllint's false
// positives.
//
// Why this exists: qmllint cannot parse optional chaining (`?.`) or nullish
// coalescing (`??`) -- it flags even a three-line file using them with
// "Unexpected token `.`". This project uses both across pre-existing, working
// shell code, so a raw `qmllint` sweep produces mostly noise, and the noise
// makes it easy to miss a genuine error sitting in the middle of it.
//
// That is exactly what happened: a mangled line
//     ColorScheme.color("error", dark) : Qt.rgba(0.73, 0.10, 0.12, 1))
// sat in AppearanceTokens.qml and only surfaced when QuickShell refused to
// load. The linter had flagged it; it was buried among ~40 `?.` reports.
//
// This script reports only errors whose preceding lines contain neither `?.`
// nor `??`, then prints the offending source line so it can be judged.
//
// Usage:
//   node tools/qmllint-changed.mjs          # changed files only
//   node tools/qmllint-changed.mjs --all    # every .qml in shell/ shared/ apps/

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

// Optional chaining / nullish coalescing: qmllint misparses these.
//
// The window is deliberately wide (and biased backwards). qmllint does not
// report an error ON the `?.` line -- it loses sync and then emits a cascade
// of bogus "Unexpected token" errors on the lines that FOLLOW, sometimes many
// lines later. A real example: `implicitWidth: screen?.width ?? 1920` at line
// 35 produced errors at 35, 36 and again at 41 ("Expected token `:'"). A
// 4-line lookback reported line 41 as a genuine fault; 12 lines back plus 2
// forward is what it actually takes to attribute the cascade to its cause.
const MODERN_JS = /\?\.|\?\?/;
const LOOKBACK = 12;
const LOOKAHEAD = 2;

function changedFiles() {
    return execFileSync("git", ["status", "--porcelain"], { encoding: "utf8" })
        .split("\n")
        .map(line => line.slice(3).trim())
        .filter(f => f.endsWith(".qml"));
}

function allFiles() {
    return execFileSync(
        "git", ["ls-files", "shell", "shared", "apps"], { encoding: "utf8" })
        .split("\n")
        .filter(f => f.endsWith(".qml"));
}

const all = process.argv.includes("--all");
const files = all ? allFiles() : changedFiles();
const roots = ["-I", "shared/qml", "-I", "shell", "-I", "."];

let broken = 0;
let skippedOptChain = 0;

for (const file of files) {
    let out = "";
    try {
        out = execFileSync("qmllint", [...roots, file],
            { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) {
        // qmllint exits non-zero when it finds problems; stdout/stderr still
        // carry the report.
        out = (e.stdout || "") + (e.stderr || "");
    }
    if (!out.trim()) continue;

    let src;
    try {
        src = readFileSync(file, "utf8").split("\n");
    } catch {
        continue; // Deleted or moved file in the porcelain listing.
    }

    const flagged = new Set();
    for (const m of out.matchAll(/:(\d+) : /g)) flagged.add(parseInt(m[1], 10));

    const suspicious = [];
    for (const line of flagged) {
        // The construct may span lines, so look back a little before judging.
        const from = Math.max(0, line - 1 - LOOKBACK);
        const to = Math.min(src.length, line + LOOKAHEAD);
        if (MODERN_JS.test(src.slice(from, to).join("\n"))) {
            skippedOptChain++;
            continue;
        }
        suspicious.push(line);
    }

    if (!suspicious.length) continue;
    broken++;
    console.log(`\n${file}  ->  真实错误行: ${suspicious.join(", ")}`);
    for (const line of suspicious) {
        const text = src[line - 1] ?? "<越界>";
        console.log(`  ${String(line).padStart(5)}: ${text}`);
    }
}

if (all && skippedOptChain) {
    console.log(`\n（已忽略 ${skippedOptChain} 处 qmllint 对可选链的误报）`);
}

if (broken === 0) {
    console.log(`\n无真实语法错误（共检查 ${files.length} 个文件，`
        + `忽略 ${skippedOptChain} 处 ?./?? 误报）`);
} else {
    console.log(`\n共 ${broken} 个文件存在真实错误`);
    process.exitCode = 1;
}
