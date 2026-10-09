#pragma once
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QVariantList>

namespace listenfree::online {
// Narrow adaptations of LX musicSdk/{kw,kg,tx,wy,mg}; identities survive every
// UI/queue/download round trip, and signed playback URLs are never persisted.
QNetworkReply *platformRequest(QNetworkAccessManager &network,
                               const QString &platform,
                               const QString &operation, const QString &text,
                               const QString &order = "hot", int page = 1,
                               int pageSize = 30);
QVariantList platformSearchRows(const QString &platform, const QString &category,
                               const QJsonObject &object);
int platformSearchTotal(const QString &platform, const QString &category,
                        const QJsonObject &object);
QVariantList platformAlbumSongs(const QString &platform, const QJsonObject &object);
QJsonObject platformJson(QByteArray bytes);
QVariantList platformSongs(const QString &platform, const QJsonObject &object);
QStringList platformSuggestions(const QString &platform,
                                const QJsonObject &object);
QVariantList platformPlaylists(const QString &platform,
                               const QJsonObject &object);
QVariantMap platformDetail(const QString &platform, const QJsonObject &object);
QVariantMap sourceMusicInfo(const QVariantMap &track);
} // namespace listenfree::online
