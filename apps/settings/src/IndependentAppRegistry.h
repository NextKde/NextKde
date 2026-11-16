#pragma once
#include "AppCatalog.h"
#include <optional>

// Compatibility facade for the Flatpak adapter. Catalog entries and source trust
// are shared with Settings, the CLI and the background updater.
namespace IndependentAppRegistry {
struct App {
    QString key, appId, executable, desktop, repository, manifest;
    QVariantMap entry;
};
inline App convert(const QVariantMap& entry)
{
    const auto id = entry.value("appId").toString();
    return {entry.value("key").toString(), id, {}, id + ".desktop",
        entry.value("repository").toString(), entry.value("manifest").toString(), entry};
}
inline QList<App> apps()
{
    QList<App> result;
    for (const auto& item : AppCatalog::apps()) {
        const auto entry = item.toMap();
        if (entry.value("format").toString() == "flatpak") result.append(convert(entry));
    }
    return result;
}
inline std::optional<App> find(const QString& id)
{
    const auto entry = AppCatalog::find(id);
    if (entry.isEmpty() || entry.value("format").toString() != "flatpak") return std::nullopt;
    return convert(entry);
}
}
