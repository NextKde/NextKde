#include "AboutCache.h"
#include "CacheMaintenance.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
constexpr qint64 maximumResponseBytes = 2 * 1024 * 1024;
constexpr qint64 retryInterval = 15 * 60;
constexpr qint64 listLifetime = 24 * 60 * 60;
constexpr qint64 avatarLifetime = 7 * listLifetime;

QUrl localAvatarUrl(const QString &path)
{
    QUrl url = QUrl::fromLocalFile(path);
    // Change the QML image-cache key when a background refresh replaces a file.
    url.setFragment(QString::number(QFileInfo(path).lastModified().toMSecsSinceEpoch()));
    return url;
}
}

AboutCache::AboutCache(QObject *parent)
    : QObject(parent)
    , m_directory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                  + QStringLiteral("/about"))
{
    QDir().mkpath(m_directory);
    CacheMaintenance::schedule(m_directory, 16 * 1024 * 1024, 500);
}

QString AboutCache::pagePath(int page) const
{
    return m_directory + QStringLiteral("/contributors-%1.json").arg(page);
}

QString AboutCache::readPage(int page) const
{
    if (page < 1) return {};
    QFile file(pagePath(page));
    if (!file.open(QIODevice::ReadOnly) || file.size() > maximumResponseBytes) return {};
    const QByteArray bytes = file.readAll();
    const QJsonDocument document = QJsonDocument::fromJson(bytes);
    return document.isArray() ? QString::fromUtf8(bytes) : QString();
}

bool AboutCache::pageNeedsRefresh(int page)
{
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const QFileInfo file(pagePath(page));
    if (file.exists() && file.lastModified().secsTo(now) < listLifetime) return false;
    if (m_pageRefreshes.contains(page)
        && m_pageRefreshes.value(page).secsTo(now) < retryInterval) return false;
    m_pageRefreshes.insert(page, now);
    return true;
}

void AboutCache::savePage(int page, const QString &json)
{
    const QByteArray bytes = json.toUtf8();
    if (page < 1 || bytes.size() > maximumResponseBytes
        || !QJsonDocument::fromJson(bytes).isArray()) return;
    QSaveFile file(pagePath(page));
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size()
        || !file.commit()) return;
    // A fresh first page invalidates the old pagination snapshot. Never remove
    // the previous snapshot on a failed network request or failed disk write.
    if (page == 1) {
        const QDir directory(m_directory);
        for (const auto &name : directory.entryList({QStringLiteral("contributors-*.json")}, QDir::Files)) {
            if (name != QStringLiteral("contributors-1.json"))
                QFile::remove(directory.filePath(name));
        }
    }
    CacheMaintenance::schedule(m_directory, 16 * 1024 * 1024, 500);
}

QUrl AboutCache::avatar(const QString &remote)
{
    const QUrl url(remote);
    if (url.scheme() != QLatin1String("https")
        || url.host() != QLatin1String("avatars.githubusercontent.com")
        || !url.userInfo().isEmpty() || url.port(-1) != -1) return {};
    const QString path = m_directory + QLatin1Char('/')
        + QString::fromLatin1(QCryptographicHash::hash(remote.toUtf8(), QCryptographicHash::Sha256).toHex())
        + QStringLiteral(".png");
    const QFileInfo fileInfo(path);
    QUrl local = m_avatars.value(remote);
    if (!fileInfo.exists()) {
        local = QUrl();
        m_avatars.remove(remote);
    } else if (local.isEmpty()) {
        // Discard truncated/corrupt cache files so the next request repairs them.
        const QImage cached(path);
        if (!cached.isNull()) {
            local = localAvatarUrl(path);
            m_avatars.insert(remote, local);
        } else {
            QFile::remove(path);
        }
    }
    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (!local.isEmpty() && fileInfo.lastModified().secsTo(now) < avatarLifetime) return local;
    if (m_pending.contains(remote)
        || (m_failed.contains(remote) && m_failed.value(remote).secsTo(now) < retryInterval)) return local;
    m_pending.insert(remote);
    QNetworkRequest request(url);
    request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::readyRead, reply, [reply] {
        if (reply->bytesAvailable() > maximumResponseBytes) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, remote, path] {
        m_pending.remove(remote);
        bool saved = false;
        if (reply->error() == QNetworkReply::NoError
            && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 200
            && reply->bytesAvailable() <= maximumResponseBytes) {
            const QImage image = QImage::fromData(reply->readAll());
            if (!image.isNull()) {
                QSaveFile file(path);
                saved = file.open(QIODevice::WriteOnly)
                    && image.scaled(72, 72, Qt::KeepAspectRatio, Qt::SmoothTransformation).save(&file, "PNG")
                    && file.commit();
            }
        }
        if (saved) {
            m_avatars.insert(remote, localAvatarUrl(path));
            m_failed.remove(remote);
            CacheMaintenance::schedule(m_directory, 16 * 1024 * 1024, 500);
        } else {
            m_failed.insert(remote, QDateTime::currentDateTimeUtc());
        }
        reply->deleteLater();
        ++m_revision;
        emit avatarsChanged();
    });
    return local;
}
