#pragma once

#include "online/track_origin.h"
#include "platform/file_paths.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace listenfree::online {
// Track identity describes ownership, never the expiring playback URL or title.
// Script IDs are scoped to their script: they need not be platform catalog IDs.
inline QString trackUid(const QVariantMap& track) {
    QJsonArray key;
    const auto path = track.value("localPath").toString();
    const auto source = track.value("source").toString().trimmed().toLower();
    const auto rid = track.value("rid").toString();
    if (!path.isEmpty())
        key = {"local", platform::filePathKey(QDir::cleanPath(QFileInfo(path).absoluteFilePath()))};
    else if (isScriptTrack(track))
        key = {"script", track.value("originSourceId").toString(), track.value("source").toString(), rid};
    else if (!track.value("radioId").toString().isEmpty())
        key = {"radio", track.value("radioProvider").toString(), track.value("radioId").toString()};
    else if (!source.isEmpty() && !rid.isEmpty())
        key = {"platform", source, rid};
    else if (!track.value("remoteUrl").toString().isEmpty())
        key = {"url", QUrl(track.value("remoteUrl").toString()).toString(QUrl::NormalizePathSegments)};
    else if (!track.value("trackId").toString().isEmpty())
        key = {"legacy", source, track.value("trackId").toString()};
    else return {};
    return "track:v1:" + QString::fromLatin1(QCryptographicHash::hash(
        QJsonDocument(key).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
}
inline QVariantMap identifiedTrack(QVariantMap track) {
    if (!track.value("localPath").toString().isEmpty()) track["source"] = "local";
    else if (track.contains("source") && !isScriptTrack(track)) track["source"] = track.value("source").toString().trimmed().toLower();
    track["trackUid"] = trackUid(track);
    return track;
}
inline QVariantList identifiedTracks(QVariantList tracks) {
    for (auto& value : tracks) value = identifiedTrack(value.toMap());
    return tracks;
}
}
