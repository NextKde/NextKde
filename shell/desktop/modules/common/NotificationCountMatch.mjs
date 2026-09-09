export function groupMatches(group, appId, appName, normalize) {
    const id = normalize(appId);
    const name = normalize(appName);
    if (!id && !name)
        return false;
    const key = normalize(group?.groupKey);
    const groupName = normalize(group?.appName);
    const keyMatches = key && (key === id || key === name);
    const nameIsFallback = !key || key === groupName;
    return keyMatches || (nameIsFallback && groupName
        && (groupName === id || groupName === name));
}

export function countForApp(groups, appId, appName, normalize) {
    let total = 0;
    for (let i = 0; i < groups.length; i++) {
        if (groupMatches(groups[i], appId, appName, normalize))
            total += Math.max(0, Math.floor(Number(groups[i]?.count) || 0));
    }
    return total;
}

export function reportedCount(summary, body, hints) {
    const values = hints && typeof hints === "object" ? hints : {};
    for (const key of ["x-kde-unread-count", "unread-count",
                       "badge-count", "message-count"]) {
        const value = Math.floor(Number(values[key]));
        if (Number.isFinite(value) && value >= 0)
            return value;
    }
    const text = String(summary || "") + "\n" + String(body || "");
    const chinese = text.match(/(?:^|\D)(\d{1,4})\s*(?:条|个)?\s*(?:未读|新)?消息/);
    if (chinese)
        return Number(chinese[1]);
    const english = text.match(/(?:^|\D)(\d{1,4})\s+(?:unread|new)\s+messages?/i);
    return english ? Number(english[1]) : null;
}

export function recordNotification(groups, notification) {
    const key = String(notification?.desktopEntry
        || notification?.appName || "unknown").trim();
    const appName = String(notification?.appName || "").trim();
    const next = groups.map(group => ({
        groupKey: group.groupKey,
        appName: group.appName,
        count: group.count
    }));
    let index = next.findIndex(group => group.groupKey === key);
    if (index < 0) {
        index = next.length;
        next.push({ groupKey: key, appName: appName, count: 0 });
    }
    const explicit = reportedCount(notification?.summary,
        notification?.body, notification?.hints);
    next[index].appName = appName || next[index].appName;
    next[index].count = explicit === null
        ? next[index].count + 1 : Math.max(0, Math.floor(explicit));
    return next.filter(group => group.count > 0);
}

export function clearForApp(groups, appId, appName, normalize) {
    return groups.filter(group => !groupMatches(group,
        appId, appName, normalize));
}

export function clearGroup(groups, groupKey) {
    const key = String(groupKey || "").trim();
    return groups.filter(group => group.groupKey !== key);
}
