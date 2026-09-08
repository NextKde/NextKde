// Build once per snapshot. Keep providers separate and preserve the first
// match, just like the old linear lookup (including duplicate provider IDs).
export function indexWindowRecords(records) {
    const kwin = new Map();
    const foreign = new Map();
    for (const record of records) {
        const index = record.provider === "kwin" ? kwin
            : record.provider === "foreign" ? foreign : null;
        if (!index)
            continue;
        const key = record.provider === "kwin" ? record.handleId : record.toplevel;
        if (!index.has(key))
            index.set(key, record);
    }
    return { kwin, foreign };
}
