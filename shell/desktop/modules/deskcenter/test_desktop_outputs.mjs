import assert from "node:assert/strict";
import { outputNames, entriesForOutput, localPaths, isDesktopPath } from "./DesktopOutputs.mjs";

const screens = [
    { name: "Portrait", x: -1080, y: -500, width: 1080, height: 1920, scale: 1.5 },
    { name: "Wide", x: 0, y: 0, width: 2560, height: 1440, scale: 1.25 },
    { name: "Internal", x: 200, y: 1440, width: 1536, height: 960, scale: 2 },
    { name: "", width: 800, height: 600 },
    { name: "Disabled", width: 0, height: 0 },
];
const outputs = outputNames(screens);
assert.deepEqual(outputs, ["Portrait", "Wide", "Internal"]);
assert.deepEqual(outputNames(screens.concat(screens)), outputs);
const entries = [
    { path: "/Desktop/new.txt" },
    { path: "/Desktop/App.desktop", output: "Wide" },
    { path: "/Desktop/Folder", output: "Portrait" },
    { path: "/Desktop/notes.txt", output: "Internal" },
    { path: "/Desktop/offline.txt", output: "Unplugged" },
];

function displayedOn(active, fallback) {
    const displayed = active.flatMap(output => entriesForOutput(entries, output, active, fallback));
    assert.equal(displayed.length, active.length ? entries.length : 0);
    assert.equal(new Set(displayed.map(entry => entry.path)).size, displayed.length,
        "each file must be visible on exactly one screen");
    return output => entriesForOutput(entries, output, active, fallback).map(entry => entry.path);
}
let files = displayedOn(outputs, "Portrait");
assert.deepEqual(files("Wide"), ["/Desktop/App.desktop"]);
assert.deepEqual(files("Portrait"), ["/Desktop/new.txt", "/Desktop/Folder", "/Desktop/offline.txt"]);
files = displayedOn(["Wide"], "Wide");
assert.equal(files("Wide").length, entries.length);
assert.deepEqual(files("Portrait"), []);
files = displayedOn(["Wide", "Internal"], "Wide");
assert.equal(files("Wide").length, 4);
files = displayedOn(outputs, "Portrait");
assert.deepEqual(files("Internal"), ["/Desktop/notes.txt"]);
displayedOn([], "");
displayedOn(["Replacement"], "Portrait");
displayedOn(outputs.slice().reverse(), "Internal");
// Topology changes are a display projection, not a rewrite of saved owners.
assert.equal(entries[2].output, "Portrait");
assert.equal(entries[4].output, "Unplugged");

assert.deepEqual(localPaths(["file:///Desktop/%E8%AF%B4%E6%98%8E.txt", "file://localhost/Desktop/App.desktop",
    "https://example.org/file", "file://remote/Desktop/wrong.txt", "file:///bad%escape", "file:///bad%00name"]),
    ["/Desktop/说明.txt", "/Desktop/App.desktop"]);
assert.equal(isDesktopPath("/Desktop/App.desktop", "/Desktop"), true);
assert.equal(isDesktopPath("/Desktop2/App.desktop", "/Desktop"), false);
assert.equal(isDesktopPath("/Desktop/subfolder/file.txt", "/Desktop"), false);
assert.equal(isDesktopPath("/Desktop/../secret.txt", "/Desktop"), false);
console.log("Desktop outputs: unique ownership, mixed layouts/scales, hotplug fallback and local drag paths passed.");
