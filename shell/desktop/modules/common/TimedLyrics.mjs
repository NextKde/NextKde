// LRC timestamps are seconds; a positive offset advances the lyrics.
export function parse(source) {
    const lines = [];
    const text = String(source ?? "");
    const offsetPattern = /\[offset:([+-]?\d+)\]/gi;
    let offset = 0, offsetMatch;
    while ((offsetMatch = offsetPattern.exec(text)))
        offset = Number(offsetMatch[1]) / 1000;
    for (const raw of text.split(/\r?\n/)) {
        let rest = raw.trim();
        const times = [];
        let match;
        while ((match = rest.match(/^\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]/))) {
            if (Number(match[2]) < 60)
                times.push(Number(match[1]) * 60 + Number(match[2])
                    + Number("0." + (match[3] || "0")) - offset);
            rest = rest.slice(match[0].length);
        }
        for (const time of times)
            lines.push({ time, text: rest.trim() });
    }
    return lines.sort((a, b) => a.time - b.time);
}

export function indexAt(lines, position) {
    if (!Number.isFinite(position)) return -1;
    let low = 0, high = lines.length;
    while (low < high) {
        const mid = (low + high) >>> 1;
        if (lines[mid].time <= position) low = mid + 1;
        else high = mid;
    }
    return low - 1;
}
