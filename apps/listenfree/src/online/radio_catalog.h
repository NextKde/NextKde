#pragma once
#include <QJsonObject>
#include <QVariantMap>
#include <QVector>

namespace listenfree::online {
// Compact directory records stay in C++; only a page crosses the QML boundary.
struct RadioStation {
    QString id, title, subtitle, url, artwork, tags, codec;
    int bitrate{};
};
QVector<RadioStation> icecastStations(const QByteArray& xml, QString* error = nullptr);
QVariantList radioBrowserStations(const QByteArray& json);
QVariantList neteaseBroadcastStations(const QJsonObject& data);
QVariantList neteasePodcasts(const QJsonObject& root);
QVariantList neteasePrograms(const QJsonObject& root);
QVariantMap radioTrack(const RadioStation& station, const QString& provider);
bool radioHttpUrl(const QString& url);
QString radioProgramTitle(const QString& metadata);
}
