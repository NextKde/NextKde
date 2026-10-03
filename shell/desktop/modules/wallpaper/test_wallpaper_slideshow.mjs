import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("./WallpaperService.qml", import.meta.url), "utf8");
const functions = source.slice(source.indexOf("    function setSlideshow("),
    source.indexOf("    property Timer slideshowTimer:"));
const selected = [];
const config = {
    slideshowEnabled: false,
    slideshowIntervalMinutes: 15,
    slideshowJson: "[]",
    takeoverEnabled: false,
    sync() {},
};
const context = vm.createContext({
    config,
    wallpaperUrl: "/wallpapers/other.jpg",
    slideshowImages: [],
    takeoverPending: false,
    localPath: value => String(value).startsWith("/") ? String(value) : "",
    chooseImage: (path, userSelected) => selected.push({ path, userSelected }),
});
vm.runInContext(functions, context);

assert.equal(context.setSlideshow(true, 15, '["/wallpapers/one.jpg"]'), false);
assert.equal(config.slideshowEnabled, false,
    "a single image must never start a repeating timer");
assert.equal(context.setSlideshow(true, 7,
    '["/wallpapers/one.jpg","/wallpapers/two.jpg"]'), false);

assert.equal(context.setSlideshow(true, 15, JSON.stringify([
    "/wallpapers/one.jpg", "/wallpapers/two.jpg", "/wallpapers/one.jpg",
])), true);
assert.equal(config.slideshowEnabled, true);
assert.equal(config.takeoverEnabled, true);
assert.deepEqual(JSON.parse(config.slideshowJson), [
    "/wallpapers/one.jpg", "/wallpapers/two.jpg",
]);
assert.deepEqual(selected.at(-1), {
    path: "/wallpapers/one.jpg", userSelected: false,
});

context.slideshowImages = JSON.parse(config.slideshowJson);
context.wallpaperUrl = "/wallpapers/one.jpg";
context.advanceSlideshow();
assert.deepEqual(selected.at(-1), {
    path: "/wallpapers/two.jpg", userSelected: false,
});

assert.equal(context.setSlideshow(false, 60, "[]"), true);
assert.equal(config.slideshowEnabled, false);
assert.equal(config.slideshowIntervalMinutes, 60);
assert.equal(context.setSlideshow(false, 60,
    '["/wallpapers/folder-a.jpg","/wallpapers/folder-b.jpg"]'), true);
assert.deepEqual(JSON.parse(config.slideshowJson),
    ['/wallpapers/folder-a.jpg', '/wallpapers/folder-b.jpg'],
    'selecting a folder while disabled must remember it for later');

console.log("wallpaper slideshow contracts: passed");
