import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// The wallpaper colour source now lives in the shared Kos.Ui layer.
const wallpaper = readFileSync(
    new URL("../../../../shared/qml/colorize/WallpaperColorSource.qml", import.meta.url), "utf8");
const parser = wallpaper.slice(wallpaper.indexOf("    function _readWallpaperText("),
    wallpaper.indexOf("    function refresh()"));
const resolved = [];
const cleared = [];
const context = vm.createContext({
    preferredScreen: 1, configuredWallpaperUrl: "", wallpaperUrl: "",
    _resolveWallpaperUrl: url => resolved.push(url),
    paletteCleared: () => cleared.push(true),
    console: { warn() {} },
});
vm.runInContext(parser, context);
const config = "[Containments][1]\nlastScreen=0\n"
    + "[Containments][1][Wallpaper][org.kde.image][General]\nImage=file:///first.png\n"
    + "[Containments][2]\nlastScreen=1\n"
    + "[Containments][2][Wallpaper][org.kde.image][General]\nImage=file:///second.png\n";
context._readWallpaperText(config);
context._readWallpaperText(config);
assert.deepEqual(resolved, ["file:///second.png"]);
context._readWallpaperText(config.replace("second.png", "replacement.png"));
assert.equal(resolved.at(-1), "file:///replacement.png");
context.preferredScreen = 9;
context._readWallpaperText(config);
assert.equal(resolved.at(-1), "file:///first.png");
context._readWallpaperText("");
assert.equal(context.configuredWallpaperUrl, "");
assert.equal(context.wallpaperUrl, "");
assert.equal(cleared.length, 1, "clearing the wallpaper must notify the shell adapter");
// The shared layer must not reach back into shell modules.
assert.doesNotMatch(wallpaper, /import qs\.desktop/);
assert.doesNotMatch(wallpaper, /AppearanceConfigService/);
assert.match(wallpaper, /interval: 3000/);
assert.match(wallpaper, /function refresh\(\)\s*\{\s*_configFile\.reload\(\)/);
assert.doesNotMatch(wallpaper, /wallpaper-palette-read|_refreshProcess/);
console.log("wallpaper contracts: passed");
