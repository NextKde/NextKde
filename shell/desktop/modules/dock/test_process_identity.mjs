import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

import { matchEntryByHints, parseProbeOutput, probeCommand }
    from "./ProcessIdentity.mjs";

// The normaliser is shared with the rest of the shell, so the test runs the real
// implementation rather than a copy that could drift away from it.
const presentation = readFileSync(
    new URL("../common/AppPresentationService.qml", import.meta.url), "utf8");
const normalizerSource = presentation.slice(
    presentation.indexOf("    function normalize(value) {"),
    presentation.indexOf("    // QtObject has no default child property"));
assert.ok(normalizerSource.includes("function normalize"),
    "AppPresentationService.normalize moved; update this slice");
const context = vm.createContext({});
vm.runInContext(normalizerSource, context);
const normalize = context.normalize;
assert.equal(normalize("yeshayun-4.0.11-linux-amd64.desktop"),
    "yeshayun4011linuxamd64");

// ── probeCommand ──
const probe = probeCommand(4242);
assert.equal(probe[0], "sh");
assert.equal(probe[1], "-c");
assert.equal(probe.at(-2), "kos-window-identity");
assert.equal(probe.at(-1), "4242");
// The PID reaches a shell, so anything that is not an integer is discarded
// instead of being interpolated.
assert.equal(probeCommand("12; touch /tmp/pwned").at(-1), "0");
assert.equal(probeCommand(-5).at(-1), "0");
assert.equal(probeCommand(undefined).at(-1), "0");
// Every source prints one line, so a failed read cannot shift the later hints
// into the wrong slot.
assert.equal((probe[2].match(/printf/g) || []).length, 3);

// ── parseProbeOutput ──
// A real AppImage launch: the runtime exports the file it was started from, the
// executable lives in the mount directory, and argv[0] names the binary again.
// The launcher path is kept first because external installers (including
// ~/Downloads/install-appimage) name the desktop file after it.
const appImageProbe = [
    "/home/amao/Applications/yeshayun-4.0.11-linux-amd64.appimage",
    "/tmp/.mount_yeshaABCDEF/yeshayun",
    "./yeshayun",
].join("\n");
assert.deepEqual(parseProbeOutput(appImageProbe),
    ["yeshayun-4.0.11-linux-amd64", "yeshayun"]);

// The same binary without the AppImage wrapper still yields its own name.
assert.deepEqual(parseProbeOutput("\n/usr/lib/firefox/firefox\n/usr/bin/firefox"),
    ["firefox"]);

// A missing source leaves an empty line rather than shifting the later ones.
assert.deepEqual(parseProbeOutput("\n/usr/bin/hplip\nhplip"), ["hplip"]);

// Runtimes and wrappers name the toolkit or the launcher, never the app, so a
// match on one of them would identify the wrong entry.
assert.deepEqual(parseProbeOutput("\n/usr/lib/electron/electron\nelectron"), []);
assert.deepEqual(parseProbeOutput("\n/bin/sh\nsh"), []);
assert.deepEqual(parseProbeOutput("\n/usr/bin/appimage/apprun\napprun"), []);
assert.deepEqual(parseProbeOutput("\n/sbin/init\n/sbin/init"), []);
assert.deepEqual(parseProbeOutput("\n/usr/bin/kdeinit6\nkdeinit6"), []);

// Too short to be evidence.
assert.deepEqual(parseProbeOutput("\n/usr/bin/qs\nqs"), []);

// Nothing readable at all.
assert.deepEqual(parseProbeOutput(""), []);
assert.deepEqual(parseProbeOutput(undefined), []);

// ── matchEntryByHints ──
function entry(id, icon = "app-icon") {
    return { id, icon, name: id };
}
const hasIcon = app => !!app.icon;
const catalogue = [
    entry("firefox.desktop"),
    entry("yeshayun-4.0.11-linux-amd64.desktop",
        "/home/amao/.local/share/icons/yeshayun-4.0.11-linux-amd64.png"),
    entry("code.desktop"),
];

// The window reports `com.yesha.net`, which no entry carries, but the AppImage
// the process was launched from is named exactly like the desktop file.
assert.equal(
    matchEntryByHints(catalogue,
        ["yeshayun-4.0.11-linux-amd64", "yeshayun"], normalize, hasIcon)?.id,
    "yeshayun-4.0.11-linux-amd64.desktop");

// The bare binary name is enough on its own: exactly one id contains it.
assert.equal(
    matchEntryByHints(catalogue, ["yeshayun"], normalize, hasIcon)?.id,
    "yeshayun-4.0.11-linux-amd64.desktop");

// Quickshell does not guarantee the `.desktop` suffix on `entry.id`; the shared
// normaliser strips it either way.
assert.equal(
    matchEntryByHints([entry("yeshayun-4.0.11-linux-amd64")], ["yeshayun"],
        normalize, hasIcon)?.id, "yeshayun-4.0.11-linux-amd64");

// An id that normalises to the hint exactly beats a longer id containing it.
assert.equal(
    matchEntryByHints([entry("firefox-esr.desktop"), entry("firefox.desktop")],
        ["firefox"], normalize, hasIcon)?.id, "firefox.desktop");

// A hint shared by several entries proves nothing. The generic icon is a better
// answer than another application's icon.
assert.equal(
    matchEntryByHints([entry("yesha-one.desktop"), entry("yesha-two.desktop")],
        ["yesha"], normalize, hasIcon), null);

// Two ids that normalise identically are the same app to this lookup; prefer
// the one that can actually supply an icon.
assert.equal(
    matchEntryByHints([entry("foo-bar.desktop", ""), entry("foo_bar.desktop")],
        ["foo-bar"], normalize, hasIcon)?.id, "foo_bar.desktop");

// No evidence, no answer. This is also what keeps every app that already
// resolves through its app id completely untouched by the fallback.
assert.equal(matchEntryByHints(catalogue, [], normalize, hasIcon), null);
assert.equal(matchEntryByHints([], ["firefox"], normalize, hasIcon), null);
assert.equal(matchEntryByHints(catalogue, ["firefox"], null, hasIcon), null);
assert.equal(matchEntryByHints(catalogue, ["redshift"], normalize, hasIcon), null);
assert.equal(matchEntryByHints(catalogue, ["yeshayun", "redshift"],
    normalize, hasIcon)?.id, "yeshayun-4.0.11-linux-amd64.desktop");

// ── The QML boundary ──
// This is the shape that shipped broken: QML hands `list<T>` to JavaScript as a
// V4Sequence, where `Array.isArray` is false even though length and indexing
// work. An array-only guard disabled the entire fallback inside the shell while
// every assertion above kept passing, because Node only ever passes real
// Arrays. Same evidence, both container shapes, identical answer.
function sequenceLike(items) {
    const sequence = { length: items.length };
    for (let i = 0; i < items.length; i++)
        sequence[i] = items[i];
    return sequence;
}

const arrayLikeCatalogue = sequenceLike(catalogue);
assert.equal(Object.prototype.toString.call(arrayLikeCatalogue),
    "[object Object]", "the fixture must not accidentally be an Array");

assert.equal(
    matchEntryByHints(arrayLikeCatalogue,
        sequenceLike(["yeshayun-4.0.11-linux-amd64"]), normalize, hasIcon)?.id,
    "yeshayun-4.0.11-linux-amd64.desktop",
    "array-like entries and hints must match exactly like real Arrays");
assert.equal(
    matchEntryByHints(arrayLikeCatalogue, ["yeshayun"], normalize, hasIcon)?.id,
    "yeshayun-4.0.11-linux-amd64.desktop");
assert.equal(
    matchEntryByHints(arrayLikeCatalogue, ["yesha"], normalize, hasIcon)?.id,
    matchEntryByHints(catalogue, ["yesha"], normalize, hasIcon)?.id,
    "array-like and real-Array input must reach the same verdict");
assert.equal(
    matchEntryByHints(
        sequenceLike([entry("yesha-one.desktop"), entry("yesha-two.desktop")]),
        sequenceLike(["yesha"]), normalize, hasIcon), null,
    "the uniqueness guard must hold for array-like input too");

console.log("process identity: ok");
