#pragma once
#include <QJsonDocument>
#include <QJsonArray>
#include <QVariantMap>

namespace listenfree::online {
inline bool isScriptTrack(const QVariantMap &track) {
    return track.value("originKind").toString() == "lx";
}
inline QString scriptTrackKey(const QVariantMap &track) {
    if (!isScriptTrack(track)) return {};
    // A structured tuple avoids collisions when script/provider IDs contain ':'
    // and remains stable through playlist and queue JSON round trips.
    return "lx:" + QString::fromLatin1(QJsonDocument(QJsonArray{
        track.value("originSourceId").toString(), track.value("source").toString(),
        track.value("rid").toString()}).toJson(QJsonDocument::Compact).toBase64(QByteArray::Base64UrlEncoding));
}
}
