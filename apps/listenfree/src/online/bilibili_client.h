#pragma once
#include <QCache>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QVariantMap>
#include <functional>
#include <memory>

namespace listenfree::online {
QString bilibiliMixinKey(const QJsonObject& nav);
QUrl bilibiliSignedUrl(const QString& path, const QMap<QString, QString>& params, const QString& key);

// One native catalog/resolver, shared by discovery, collections and SourceController.
// Returned IDs are cancellable; callbacks are never synchronous with creation.
class BilibiliClient final : public QObject {
public:
    using Done = std::function<void(QVariantMap, QString)>;
    explicit BilibiliClient(QObject* parent = nullptr, QNetworkAccessManager* network = nullptr);
    ~BilibiliClient() override;
    void setCookie(const QByteArray& cookie);
    QString search(const QString& query, int page, const QString& category, QObject* context, Done done);
    QString detail(const QString& bvid, QObject* context, Done done);
    QString audio(const QVariantMap& track, const QString& quality, QObject* context, Done done);
    bool cancel(const QString& id);
    static QVariantMap collectionFromView(const QJsonObject& view);
    static QVariantMap trackFromPage(const QJsonObject& view, const QJsonObject& page);
    static QVariantMap audioFromPlayInfo(const QJsonObject& data, const QString& quality, const QString& bvid);
    static QVariantMap videoFromPlayInfo(const QJsonObject& data);
private:
    struct Job;
    struct CacheEntry { qint64 time; QVariantMap data; };
    using Task = std::shared_ptr<Job>;
    Task create(QObject* context, Done done);
    void finish(const Task& job, QVariantMap data = {}, QString error = {});
    void get(const Task& job, const QUrl& url, std::function<void(QJsonObject, QString)> done);
    void prepare(const Task& job, std::function<void()> ready);
    void searchViews(const Task& job);
    void requestAudio(const Task& job, const QVariantMap& track, const QString& quality);
    QNetworkAccessManager ownedNetwork_;
    QNetworkAccessManager* network_;
    QByteArray accountCookie_, visitorCookie_;
    QString mixin_;
    qint64 keyTime_{0};
    QHash<QString, Task> jobs_;
    QCache<QString, CacheEntry> searchCache_{8};
};
}
