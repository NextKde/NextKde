export function toList(value) {
    if (value == null || typeof value === "string" || typeof value.length !== "number")
        return [];
    return Array.prototype.slice.call(value);
}

export function friendlyReason(code, rawReason) {
    switch (String(code ?? "")) {
    case "sdk-too-old":
        return "该插件版本过旧，已不再受当前系统支持（请更新插件）";
    case "sdk-too-new":
        return "该插件面向更新版本的桌面系统，当前系统暂不支持";
    case "api-too-old":
        return "该插件需要更高版本的系统能力，请先升级系统";
    case "missing-entry":
        return "插件缺少入口文件（Widget.qml / Snapshot.qml）或使用了不允许的外部软链";
    case "invalid-json":
        return "metadata.json 存在语法错误，无法解析";
    case "missing-metadata":
        return "插件缺少有效的 metadata.json 描述文件";
    case "broken-root":
        return "插件目录损坏或符号链接无效";
    case "invalid-id":
        return "插件目录名称不符合反向域名 ID 规范（如 com.example.widget）";
    case "invalid-metadata":
        return "metadata.json 必填字段缺失或格式不正确";
    default:
        return String(rawReason || "插件校验未通过");
    }
}

export function collectUnavailableDesktopInstances(
    retiredRecords,
    catalog,
    activeStyle,
    invalidPackages,
    trippedPackages
) {
    const retired = toList(retiredRecords);
    if (retired.length === 0) return [];
    const catalogList = toList(catalog);
    const invalidList = toList(invalidPackages);
    const trippedList = toList(trippedPackages);
    const out = [];

    for (const record of retired) {
        if (!record || !record.id || !record.packageId) continue;
        const pkgId = String(record.packageId);
        const entry = catalogList.find(item => item && String(item.id ?? "") === pkgId);
        // Valid packages parked solely because the user switched between
        // Material and macOS styles are not broken or unavailable.
        if (entry && entry.available === true && String(entry.style ?? "") !== String(activeStyle ?? ""))
            continue;

        const invalid = invalidList.find(item => item && String(item.id ?? "") === pkgId);
        if (invalid) {
            out.push({
                id: String(record.id),
                packageId: pkgId,
                code: String(invalid.code ?? "invalid"),
                summary: friendlyReason(invalid.code, invalid.reason)
            });
            continue;
        }

        const tripped = trippedList.find(item => item && String(item.id ?? "") === pkgId);
        if (tripped) {
            out.push({
                id: String(record.id),
                packageId: pkgId,
                code: "crashed",
                summary: "上次加载时导致桌面崩溃，已自动暂停"
            });
            continue;
        }

        out.push({
            id: String(record.id),
            packageId: pkgId,
            code: "missing",
            summary: "本地未找到该插件（可能已被卸载或移出目录）"
        });
    }
    return out;
}
