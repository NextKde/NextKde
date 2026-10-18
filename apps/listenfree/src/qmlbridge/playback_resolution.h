#pragma once
#include "online/track_origin.h"
#include <QList>
#include <QPair>
#include <QStringList>

namespace listenfree::qmlbridge {
inline constexpr int PlaybackResolutionBudgetMs = 240000;
inline constexpr int PlaybackResolutionMaxAttempts = 24;
using PlaybackAttempts = QList<QPair<QString, QString>>;
inline PlaybackAttempts playbackAttempts(const QVariantMap& track, const QVariantList& sources,
                                         const QString& activeId, const QString& preferredQuality) {
    QStringList ids;
    const auto provider = track.value("source").toString();
    if (online::isScriptTrack(track)) ids.append(track.value("originSourceId").toString());
    else if (provider == "bili") ids.append("bili");
    else {
        if (!activeId.isEmpty()) ids.append(activeId);
        for (const auto& value : sources) {
            const auto source = value.toMap();
            if (!source.value("enabled", true).toBool() || !source.value("removable").toBool()) continue;
            const auto capabilities = source.value("capabilities").toMap();
            if (!capabilities.isEmpty() && !capabilities.contains(provider)) continue;
            const auto id = source.value("id").toString();
            if (!id.isEmpty() && !ids.contains(id)) ids.append(id);
        }
    }
    QStringList qualities{preferredQuality.isEmpty() ? QStringLiteral("128k") : preferredQuality};
    if (qualities.first().startsWith("flac")) qualities.append("320k");
    if (!qualities.contains("128k")) qualities.append("128k");
    PlaybackAttempts attempts;
    // Try every source before repeating transient failures. Never search by title
    // or move a script-specific ID into another script's namespace.
    for (int round = 0; round < 2; ++round)
        for (const auto& id : ids)
            for (const auto& quality : qualities) {
                if (attempts.size() == PlaybackResolutionMaxAttempts) return attempts;
                attempts.append({id, quality});
            }
    return attempts;
}
}
