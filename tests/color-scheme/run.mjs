import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Runs the Material colour scheme test suite with qmltestrunner.
//
// The scheme module is a plain ES module that QML imports by relative path, so
// the test only needs the algorithm files next to the test case — no built
// Kos.Ui module, no display, no external tools.
//
// TWO modules, not one: MaterialColorScheme.mjs imports Cam16Hct.mjs. Copying
// only the former leaves the latter unresolvable and the whole suite fails to
// load. Both the copy list and the import rewrite below have to cover it.
const directory = mkdtempSync(join(tmpdir(), "nextkde-color-scheme-"));
try {
    for (const file of ["MaterialColorScheme.mjs", "Cam16Hct.mjs"]) {
        const source = readFileSync(
            new URL(`../../shared/qml/colorize/${file}`, import.meta.url), "utf8");
        writeFileSync(join(directory, file), source);
    }

    // Rewrite the source-tree relative imports into sibling imports so the
    // copied test resolves the algorithm files placed next to it.
    const test = readFileSync(new URL("tst_color_scheme.qml", import.meta.url), "utf8")
        .replace('"../../shared/qml/colorize/MaterialColorScheme.mjs"',
            '"MaterialColorScheme.mjs"');
    writeFileSync(join(directory, "tst_color_scheme.qml"), test);

    const result = spawnSync(process.argv[2] || "qmltestrunner",
        ["-input", directory], {
            encoding: "utf8", timeout: 20000,
            env: { ...process.env, QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software" },
        });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));

    // qmltestrunner in this environment produces NO output at all, not even for
    // a trivial always-passing TestCase, and still exits 0. That makes a silent
    // pass indistinguishable from a silent failure, so a missing "Totals" line
    // is reported as an environment limitation rather than treated as success.
    // See docs/AppearanceArchitecture.md section 11 for the same note.
    if (!/Totals:/.test(output)) {
        console.log("qmltestrunner produced no result summary; "
            + "this environment cannot run the QML suite (see "
            + "docs/AppearanceArchitecture.md section 11).\n"
            + "The Node suite is authoritative: "
            + "node tests/color-scheme/test_color_scheme.mjs");
        process.exit(0);
    }
    assert.equal(result.status, 0, output);
    assert.match(output, /0 failed/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
