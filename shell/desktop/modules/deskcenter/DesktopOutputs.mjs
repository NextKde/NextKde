// Output names come from the current compositor/Qt screen list, never from
// stored coordinates or a machine-specific connector preference.
export function outputNames(screens) {
    const names = [];
    for (const screen of screens || []) {
        const name = String(screen?.name || "");
        if (name && Number(screen.width) > 0 && Number(screen.height) > 0
                && names.indexOf(name) < 0)
            names.push(name);
    }
    return names;
}

export function entriesForOutput(entries, output, outputs, defaultOutput) {
    if (!output || outputs.indexOf(output) < 0)
        return [];
    const fallback = outputs.indexOf(defaultOutput) >= 0 ? defaultOutput : outputs[0];
    return (entries || []).filter(function(entry) {
        const owner = outputs.indexOf(entry.output) >= 0 ? entry.output : fallback;
        return owner === output;
    });
}

export function localPaths(urls) {
    const paths = [];
    for (const url of urls || []) {
        const match = /^file:\/\/(?:localhost)?(\/.*)$/.exec(String(url));
        if (!match)
            continue;
        try {
            const path = decodeURIComponent(match[1]);
            if (path.indexOf("\u0000") < 0 && paths.indexOf(path) < 0)
                paths.push(path);
        } catch (_) {}
    }
    return paths;
}

export function isDesktopPath(path, directory) {
    const prefix = directory.replace(/\/+$/, "") + "/";
    if (!directory || !path.startsWith(prefix))
        return false;
    const name = path.slice(prefix.length);
    return name.length > 0 && name.indexOf("/") < 0 && name !== "." && name !== "..";
}
