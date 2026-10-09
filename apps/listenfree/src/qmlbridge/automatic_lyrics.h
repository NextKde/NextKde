#pragma once
#include "infrastructure/database/database.h"
#include "online/lyric_search.h"
#include <QCache>

namespace listenfree::qmlbridge {
// Missing-lyrics fallback. Its cache belongs to the app, never to audio tags.
class AutomaticLyrics final : public QObject {
    Q_OBJECT
public:
    AutomaticLyrics(infrastructure::database::Database& database, QNetworkAccessManager& network,
                    QObject* parent = nullptr, int timeoutMs = 24000);
    void request(const QVariantMap& track, const QVariantMap& seed);
    void cancel();
    static QString identity(const QVariantMap& track);
signals:
    void resolved(const QString& identity, const QString& lyrics);
private:
    infrastructure::database::Database& database_;
    online::LyricSearch search_;
    QVariantMap seed_;
    QString key_, fingerprint_;
    QCache<QString, qint64> retryAfter_{128};
    bool active_{};
    void finish();
};
}
