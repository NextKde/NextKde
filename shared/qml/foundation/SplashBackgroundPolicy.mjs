// Pure rules for the login splash's optional background picture.
//
// The splash is a separate Quickshell instance that runs before the desktop
// tree, so it reads its two appearance fields from config.json itself instead
// of going through AppearanceConfigService. The Shell writes validated values,
// the splash validates what is actually in the file before handing it to
// Image.source, and Settings shares the same mode validator. Keeping this file
// in shared/qml lets every caller resolve it without mounting shell/splash.

// "solid" is the light/dark surface the splash has always drawn. "image"
// paints the chosen picture full screen behind a scrim so the spinner and the
// signature stay legible on any photo.
export const backgroundModes = ["solid", "image"];

export function isValidBackgroundMode(value) {
    return backgroundModes.indexOf(String(value)) >= 0;
}

// True only for a non-empty local absolute path. A relative path would
// silently resolve against the splash's own directory, and a network-style
// path would stop being a local file. A path whose file has since disappeared
// stays valid here: Image reports its own error and the splash keeps the solid
// background. Control characters are rejected because Image.source and QUrl
// would otherwise reinterpret the value.
export function normalizeImagePath(value) {
    const path = String(value ?? "").trim();
    if (!path.startsWith("/") || path.startsWith("//"))
        return "";
    if (/[\u0000-\u001f\u007f]/.test(path))
        return "";
    return path;
}

// Read and migrate the two persisted fields together. "canonical" is false
// for files written before schema 36 (both fields absent) and for values that
// need trimming or validation, so the config service knows to write the
// normalized pair back once.
export function resolveBackground(rawMode, rawPath) {
    const validMode = isValidBackgroundMode(rawMode);
    const image = normalizeImagePath(rawPath);
    return {
        mode: validMode ? String(rawMode) : "solid",
        image,
        canonical: validMode && typeof rawPath === "string"
            && rawPath === image,
    };
}

// The local picture the splash should paint, or "" for the solid surface.
// Used by tests and by callers that need the persisted path.
export function activeImage(mode, path) {
    return isValidBackgroundMode(mode) && String(mode) === "image"
        ? normalizeImagePath(path) : "";
}

function encodePath(path) {
    return path.split("/").map((segment, index) =>
        index === 0 ? "" : encodeURIComponent(segment)).join("/");
}

// Image.source is a URL. Encode each path segment so characters such as '#',
// '?', '%' and spaces remain part of the selected filename instead of being
// interpreted as URL syntax.
export function imageSource(mode, path) {
    const local = activeImage(mode, path);
    if (local === "")
        return "";
    try {
        return "file://" + encodePath(local);
    } catch (_) {
        // A hand-edited JSON string can contain an unpaired surrogate, which
        // encodeURIComponent rejects. Keep the solid surface instead of
        // breaking the splash's source binding.
        return "";
    }
}
