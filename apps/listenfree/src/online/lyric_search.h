#pragma once
#include <QCache>
#include <QElapsedTimer>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QSet>
#include <QTimer>
#include <QVariantList>

namespace listenfree::online {
// A search is a set of independent provider pipelines. Only verified lyrics are
// published; a slow provider never gates preview, selection or other providers.
class LyricSearch final : public QObject {
    Q_OBJECT
public:
    explicit LyricSearch(QNetworkAccessManager& network, QObject* parent = nullptr,
                         int requestTimeoutMs = 8000, int totalTimeoutMs = 24000);
    ~LyricSearch() override;
    void search(const QVariantMap& track, const QString& query, const QString& source = "all");
    void cancel();
    // End the preview session; successful bounded caches and backoff survive.
    void release();
    bool busy() const { return busy_; }
    QVariantList results() const { return results_; }
    QVariantList sources() const;
    QString message() const;
    QString lyrics(int index) const;
signals:
    void changed();
private:
    struct Match { QVariantMap row; QString text; QByteArray identity; };
    struct CachedMatches { QList<Match> matches; qint64 expires; };
    struct Provider {
        QStringList queries;
        int nextQuery{};
        QVariantList pending;
        QSet<QString> seen;
        QList<Match> matches;
        QPointer<QNetworkReply> reply;
        QString state{"搜索中"}, detail, cacheKey;
        bool done{}, failed{};
    };
    QNetworkAccessManager& network_;
    QMap<QString, Provider> providers_;
    QStringList sourceOrder_;
    QVariantMap track_;
    QString query_, searchKey_;
    QVariantList results_;
    QHash<QString, QString> texts_;
    QHash<QString, qint64> retryAfter_;
    QCache<QString, CachedMatches> cache_{2048}; // KiB, successful results only.
    QCache<QString, Match> lyricCache_{2048};
    QTimer deadline_;
    QElapsedTimer elapsed_;
    quint64 generation_{};
    int requestTimeoutMs_, totalTimeoutMs_;
    bool busy_{};
    void advance(const QString& source);
    void watchReply(const QString& source, QNetworkReply* reply, const QVariantMap& candidate = {});
    void accept(const QString& source, QVariantMap row, const QString& text);
    void finishProvider(const QString& source);
    void publish();
    void stop(bool timedOut);
};
}
