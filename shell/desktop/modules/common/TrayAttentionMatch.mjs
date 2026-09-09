export function collectAttentionKeys(items, needsAttentionStatus, normalize) {
    const keys = [];
    for (const item of items) {
        if (!item || item.status !== needsAttentionStatus)
            continue;
        for (const candidate of [item.id, item.title]) {
            const key = normalize(candidate);
            if (key && keys.indexOf(key) < 0)
                keys.push(key);
        }
    }
    return keys;
}

export function matchesAttention(keys, appId, appName, normalize) {
    const id = normalize(appId);
    const name = normalize(appName);
    return (id && keys.indexOf(id) >= 0)
        || (name && keys.indexOf(name) >= 0);
}
