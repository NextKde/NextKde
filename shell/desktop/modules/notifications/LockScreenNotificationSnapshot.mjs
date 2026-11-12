// A deliberately lossy projection: never read summary/body/actions, even when
// desktop previews are enabled. Consumers must render appName as PlainText.
export function snapshot(history, policy) {
    if (!policy.ready || !policy.historyEnabled || policy.doNotDisturbEnabled)
        return [];
    const result = [];
    for (let i = 0; i < history.count && result.length < 4; ++i) {
        const row = history.get(i);
        if (policy.isKeyBlocked(row.sourceKey)) continue;
        const createdAt = Number(row.timestamp);
        if (!Number.isSafeInteger(createdAt) || createdAt <= 0) continue;
        const icon = String(row.appIcon || "");
        result.push({
            id: String(row.historyKey),
            appName: String(row.appName || "").replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 256),
            // Theme names only: never make the greeter fetch notification URLs
            // or load arbitrary local files, image providers or QML resources.
            appIcon: /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(icon) ? icon : "",
            createdAt,
            summary: "",
            body: ""
        });
    }
    return result;
}
