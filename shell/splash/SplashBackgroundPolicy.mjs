// Pure rules for the login splash's optional background picture.
//
// The splash is a separate Quickshell instance that runs before the desktop
// tree, so it reads its two appearance fields from config.json itself instead
// of going through AppearanceConfigService. Both sides apply the rules here:
// the writer validates what Settings sends, and the reader validates what is
// actually in the file before handing it to Image.source. That keeps a
// hand-edited config from turning into a remote URL or a QML resource path.

// "solid" is the light/dark surface the splash has always drawn. "image"
// paints the chosen picture full screen behind a scrim so the spinner and the
// signature stay legible on any photo.
export const backgroundModes = ["solid", "image"];

export function isValidBackgroundMode(value) {
    return backgroundModes.indexOf(String(value)) >= 0;
}

// True only for a non-empty absolute path. A relative path would silently
// resolve against the splash's own directory, and the splash never loads
// remote images. A path whose file has since disappeared stays valid here:
// Image reports its own error and the splash keeps the solid background.
export function normalizeImagePath(value) {
    const path = String(value ?? "").trim();
    return path.startsWith("/") && path.indexOf("\n") < 0 ? path : "";
}

// The picture the splash should paint, or "" for the solid surface. Used by
// the splash's binding and by the tests that pin the fallback rules.
export function activeImage(mode, path) {
    return isValidBackgroundMode(mode) && String(mode) === "image"
        ? normalizeImagePath(path) : "";
}
