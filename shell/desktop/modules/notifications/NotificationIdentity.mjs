// Distinct prefixes keep name-only sources separate from desktop identities.
export function sourceKey(notification) {
    const desktop = String(notification.desktopEntry || "").trim().replace(/\.desktop$/i, "").toLowerCase();
    return desktop ? "desktop:" + desktop
        : "name:" + String(notification.appName || "其他").trim();
}
