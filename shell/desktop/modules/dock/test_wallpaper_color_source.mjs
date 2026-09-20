import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// The wallpaper colour source now lives in the shared Kos.Ui layer.
const wallpaper = readFileSync(
    new URL("../../../../shared/qml/colorize/WallpaperColorSource.qml", import.meta.url), "utf8");
// Half the file's parsing side, from the first helper to `refresh`.
// `_readWallpaperText` delegates to two pure helpers, so slicing it alone
// would evaluate a body whose callees are undefined. The trio stays adjacent
// and in this order in the source; that adjacency is what this slice relies on.
const parser = wallpaper.slice(wallpaper.indexOf("    function _parseWallpaperConfig("),
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

// Plasma keeps one `[Wallpaper][<plugin>][General]` block per plugin that has
// ever been configured, and retired ones keep their keys. image comes first,
// then the others:
//
//   [Containments][5][Wallpaper][org.kde.image][General]
//   Image=file:///real.png
//   [Containments][5][Wallpaper][org.kde.potd][General]
//   [Containments][5][Wallpaper][org.kde.slideshow][General]
//   Image=file:///stale.jpg
//
// A cursor that is not reset on the headers it does not recognise leaves the
// image block's id in place, so that stray slideshow Image lands on it and
// overwrites the real wallpaper. That shipped: the URL never moved, the seed
// was never re-sampled, and all three colour sources froze after a wallpaper
// change — the symptom a user reports as "the colours no longer follow my
// wallpaper". Real configs carry the same shape.
const noisy = "[Containments][5]\nlastScreen=1\nwallpaperplugin=org.kde.image\n"
    + "[Containments][5][Wallpaper][org.kde.image][General]\nImage=file:///real.png\n"
    + "SlidePaths=/usr/share/wallpapers/\n"
    + "[Containments][5][Wallpaper][org.kde.potd][General]\nFillMode=1\n"
    + "[Containments][5][Wallpaper][org.kde.slideshow][General]\nImage=file:///stale.jpg\n";
context.preferredScreen = 1;
context._readWallpaperText(noisy);
assert.equal(resolved.at(-1), "file:///real.png",
    "a retired plugin block must not overwrite the active wallpaper");
context._readWallpaperText(noisy.replace("real.png", "changed.png"));
assert.equal(resolved.at(-1), "file:///changed.png",
    "changing the active wallpaper must change the resolved URL");
// The active plugin decides, rather than the image plugin being hardcoded.
context._readWallpaperText(noisy.replace("wallpaperplugin=org.kde.image",
    "wallpaperplugin=org.kde.slideshow"));
assert.equal(resolved.at(-1), "file:///stale.jpg",
    "an active slideshow plugin must resolve to its own image");

// The applets config Plasma writes is named after the shell package the session
// runs: `plasmashellrc [Shell] ShellPackage` -> `plasma-<package>-appletsrc`.
// KOS's lock-screen install points that key at its own package, so the desktop
// wallpapers land in `plasma-org.kos.desktop-appletsrc` while a hardcoded KDE
// filename reads a file Plasma has stopped writing. Same symptom as the parser
// bug above and for the same reason: a wallpaper URL that never moves.
const shellPackageSource = wallpaper.slice(
    wallpaper.indexOf("    function _parseShellPackage("),
    wallpaper.indexOf("    property FileView _shellConfigFile:"));
const svcContext = vm.createContext({
    svc: {
        configDirectory: "/home/user/.config",
        defaultConfigPath: "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
        configCandidates: ["/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc"],
        configCandidateIndex: 0,
        configPath: "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
    },
    console: { warn() {} },
});
vm.runInContext(shellPackageSource, svcContext);
// QML resolves the helper names through the object's scope; evaluated as plain
// script they are plain function declarations on the context global, so they are
// called through the context while the state stays on `svc`.
const svc = svcContext.svc;

assert.equal(svcContext._parseShellPackage("[Shell]\nShellPackage=org.kos.desktop\n"),
    "org.kos.desktop");
assert.equal(svcContext._parseShellPackage(
    "[KDE]\nShellPackage=org.kde.plasma.desktop\n"), "",
    "only the [Shell] group names the shell package");
assert.equal(svcContext._parseShellPackage("[Shell]\nLockScreen=kscreenlocker\n"), "");
assert.equal(svcContext._parseShellPackage(""), "");

svcContext._applyShellPackage("org.kos.desktop");
assert.equal(svc.configPath, "/home/user/.config/plasma-org.kos.desktop-appletsrc",
    "the session's shell package must win over the hardcoded KDE filename");
// Spread into host arrays: the candidates are built inside the vm context, so
// their prototype is that realm's Array and deepStrictEqual would reject them.
assert.deepEqual([...svc.configCandidates], [
    "/home/user/.config/plasma-org.kos.desktop-appletsrc",
    "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc",
]);
// A named file that Plasma has not written yet must fall through instead of
// leaving the shell with no wallpaper at all.
svcContext._fallBackToNextConfig("no such file");
assert.equal(svc.configPath, "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc");
assert.equal(svc.configCandidateIndex, 1);
// Lock screen uninstalled: kosctl deletes the key and the KDE file takes over.
svcContext._applyShellPackage("");
assert.equal(svc.configPath, "/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc");
assert.deepEqual([...svc.configCandidates],
    ["/home/user/.config/plasma-org.kde.plasma.desktop-appletsrc"]);

const refreshBody = wallpaper.slice(wallpaper.indexOf("    function refresh()"),
    wallpaper.indexOf("    function _parseShellPackage("));
assert.match(refreshBody, /_shellConfigFile\.reload\(\)/,
    "the shell package is re-read on the same timer, or the config can move");
assert.match(refreshBody, /_configFile\.reload\(\)/);

// The shared layer must not reach back into shell modules.
assert.doesNotMatch(wallpaper, /import qs\.desktop/);
assert.doesNotMatch(wallpaper, /AppearanceConfigService/);
assert.match(wallpaper, /interval: 3000/);
assert.match(wallpaper, /shellConfigPath: configDirectory \+ "\/plasmashellrc"/);
assert.doesNotMatch(wallpaper, /wallpaper-palette-read|_refreshProcess/);
console.log("wallpaper contracts: passed");
