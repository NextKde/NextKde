import assert from "node:assert/strict";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
    rmSync } from "node:fs";
import { inflateSync } from "node:zlib";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads SquircleMask.qml under a real Quickshell, offscreen.
//
// The tree is copied into a scratch directory with the same relative layout the
// component expects (modules/common next to shaders), because SquircleMask
// resolves its fragment shader with Qt.resolvedUrl("../../shaders/...").
const shaderBinary = new URL("../../shell/desktop/shaders/squircle.frag.qsb",
    import.meta.url);
assert.ok(existsSync(shaderBinary),
    "shell/desktop/shaders/squircle.frag.qsb is missing; "
    + "run shell/desktop/shaders/compile.sh after editing squircle.frag");

// A .qsb is a 4-byte big-endian length followed by a single zlib stream, so the
// baked GLSL can be read back without any graphics context.
//
// The target set is checked because it is load bearing rather than cosmetic:
// this effect declares no vertexShader, so it is linked against Qt's built-in
// one, which only carries 100/120/150. Bake with anything wider and on a
// desktop GL context the fragment gets served as #version 440 -- with an
// explicit `layout(location = 0) in vec2 qt_TexCoord0` -- while the vertex side
// falls back to #version 150, whose varyings have no explicit location. The
// link fails with "fragment shader input `qt_TexCoord0' with explicit location
// has no matching output" and the layer draws nothing at all.
const baked = readFileSync(shaderBinary);
const bakedSource = inflateSync(baked.subarray(4)).toString("latin1");
const glslVersions = [...new Set((bakedSource.match(/#version \d+/g) || [])
        .map((line) => Number(line.slice("#version ".length))))]
    .sort((a, b) => a - b);
assert.deepEqual(glslVersions, [100, 120, 150],
    "squircle.frag.qsb must stay on the --qt6 target set that Qt Quick bakes "
    + "its own shaders with; found #version " + glslVersions.join(", ")
    + ". See shell/desktop/shaders/compile.sh.");

const directory = mkdtempSync(join(tmpdir(), "kos-squircle-mask-"));
try {
    mkdirSync(join(directory, "modules", "common"), { recursive: true });
    mkdirSync(join(directory, "shaders"), { recursive: true });
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    copyFileSync(new URL("../../shell/desktop/modules/common/SquircleMask.qml",
        import.meta.url), join(directory, "modules", "common", "SquircleMask.qml"));
    copyFileSync(shaderBinary, join(directory, "shaders", "squircle.frag.qsb"));

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 10000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /SQUIRCLE_MASK_PASS/);
    // QML resolves component types and property names at load time, so this
    // catches the mask drifting away from its call sites or from the
    // registration in modules/common/qmldir. It does NOT catch a shader uniform
    // that no QML property feeds: that check lives in the pipeline creation,
    // which needs a working graphics context. See the note in shell.qml.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|ShaderEffect/,
        output);
    console.log("SquircleMask offscreen: component, layer wiring and .qsb loaded");
} finally {
    rmSync(directory, { recursive: true, force: true });
}
