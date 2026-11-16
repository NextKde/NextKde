// Display-name resolution for PipeWire audio sinks.
//
// `pactl --format=json list sinks` (which the platform service parses) returns
// the literal string "(null)" as `description` for a non-ASCII sink name —
// a Chinese/Japanese/Russian device label turns into "(null)" in the UI even
// though the running PipeWire node still carries the original UTF-8 text.
// Quickshell's PipeWire service exposes that original text, so the name is
// resolved here, in a pure function the shell and its tests share.

function usable(value) {
    if (typeof value !== "string")
        return false;
    const trimmed = value.trim();
    return trimmed.length > 0 && trimmed.toLowerCase() !== "(null)"
        && trimmed.toLowerCase() !== "null";
}

/**
 * @param nodes   Quickshell `Pipewire.nodes.values` (live node list)
 * @param output  platform reply entry: { name, description, isDefault }
 * @param fallbackLabel translated last-resort label
 */
export function resolveAudioOutputName(nodes, output, fallbackLabel) {
    const name = output?.name ?? "";
    const node = (nodes || []).find(item => item && item.isSink && item.name === name);
    const candidates = [node?.description, node?.nickname, output?.description, name];
    return candidates.find(usable) ?? fallbackLabel;
}
