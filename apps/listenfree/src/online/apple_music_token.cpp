#include "online/apple_music_token.h"

#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>

Q_LOGGING_CATEGORY(lcAppleToken, "listenfree.appleDynamicCover.token", QtInfoMsg)

namespace listenfree::online {
namespace {

constexpr auto kTokenHeaderKid = "WebPlayKid"; // documented JWT header kid
const QString kAlbumPageUrl = QStringLiteral("https://music.apple.com/us/album/positions-deluxe-edition/1553944254");
const QString kUserAgent =
    QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36");

QByteArray decodeBase64Url(const QString& segment) {
    return QByteArray::fromBase64Encoding(segment.toUtf8(), QByteArray::Base64UrlEncoding | QByteArray::AbortOnBase64DecodingErrors).decoded;
}

QJsonObject decodeJwtSegment(const QString& segment) {
    const QByteArray json = decodeBase64Url(segment);
    return QJsonDocument::fromJson(json).object();
}

QNetworkRequest makeRequest(const QUrl& url) {
    QNetworkRequest request(url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader(QByteArrayLiteral("user-agent"), kUserAgent.toUtf8());
    return request;
}

} // namespace

AppleMusicWebToken::AppleMusicWebToken(QObject* parent) : QObject(parent), network_(new QNetworkAccessManager(this)) {}

std::optional<QString> AppleMusicWebToken::extractWebPlayKidJwt(const QString& javaScript) {
    // Same shape as the original matcher: JWT candidate runs, filtered by
    // header kid == WebPlayKid so unrelated tokens in the bundle are ignored.
    static const QRegularExpression jwtPattern(
        QStringLiteral("e[yw][A-Za-z0-9\\-_]+\\.[A-Za-z0-9\\-_]*\\.[A-Za-z0-9\\-_]{2,}(?:(?:\\.[A-Za-z0-9\\-_]{2,}){2})?"));
    auto matches = jwtPattern.globalMatch(javaScript);
    while (matches.hasNext()) {
        const QString candidate = matches.next().captured(0);
        const QStringList segments = candidate.split(QLatin1Char('.'));
        if (segments.isEmpty()) continue;
        const QJsonObject header = decodeJwtSegment(segments.first());
        if (header.value(QStringLiteral("kid")).toString() == QLatin1String(kTokenHeaderKid)) return candidate;
    }
    return std::nullopt;
}

qint64 AppleMusicWebToken::tokenExpiryEpochMs(const QString& jwt) {
    const QStringList segments = jwt.split(QLatin1Char('.'));
    if (segments.size() < 2) return 0;
    const QJsonObject payload = decodeJwtSegment(segments.at(1));
    const qint64 expirySeconds = static_cast<qint64>(payload.value(QStringLiteral("exp")).toDouble());
    if (expirySeconds <= 0) return 0;
    // Treat tokens as stale 10 minutes early, like the original cache.
    return expirySeconds * 1000 - 10 * 60 * 1000;
}

void AppleMusicWebToken::fetch(const std::function<void(const QString&)>& callback) {
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (cachedToken_ && cachedExpiryMs_ > now) {
        callback(*cachedToken_);
        return;
    }
    pending_.push_back(callback);
    if (inFlight_) return;
    inFlight_ = true;
    fetchFreshToken();
}

void AppleMusicWebToken::clearCachedToken() {
    cachedToken_.reset();
    cachedExpiryMs_ = 0;
}

void AppleMusicWebToken::deliver(const QString& token) {
    inFlight_ = false;
    QList<std::function<void(const QString&)>> callbacks = std::move(pending_);
    pending_.clear();
    for (const auto& callback : callbacks) callback(token);
}

void AppleMusicWebToken::fail(const QString& reason) {
    qCWarning(lcAppleToken) << "[appleDynamicCover] token fetch failed:" << reason;
    deliver({});
}

void AppleMusicWebToken::fetchFreshToken() {
    qCInfo(lcAppleToken) << "[appleDynamicCover] fetching fresh WebPlayKid token";
    connect(network_, &QNetworkAccessManager::finished, this, [this](QNetworkReply* reply) {
        reply->deleteLater();
        disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
        if (reply->error() != QNetworkReply::NoError) {
            fail(QStringLiteral("album page fetch error: %1").arg(reply->errorString()));
            return;
        }
        const QString page = QString::fromUtf8(reply->readAll());
        static const QRegularExpression assetPattern(QStringLiteral("crossorigin src=\"(/assets/index.+?\\.js)\""));
        const QString assetPath = assetPattern.match(page).captured(1);
        if (assetPath.isEmpty()) {
            fail(QStringLiteral("apple music page asset not found"));
            return;
        }
        network_->get(makeRequest(QUrl(QStringLiteral("https://music.apple.com%1").arg(assetPath))));
        connect(network_, &QNetworkAccessManager::finished, this, [this](QNetworkReply* bundleReply) {
            bundleReply->deleteLater();
            disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
            if (bundleReply->error() != QNetworkReply::NoError) {
                fail(QStringLiteral("bundle fetch error: %1").arg(bundleReply->errorString()));
                return;
            }
            const QString bundle = QString::fromUtf8(bundleReply->readAll());
            const auto token = extractWebPlayKidJwt(bundle);
            if (!token) {
                fail(QStringLiteral("WebPlayKid token not found in bundle"));
                return;
            }
            cachedToken_ = *token;
            cachedExpiryMs_ = tokenExpiryEpochMs(*token);
            if (cachedExpiryMs_ <= 0) cachedExpiryMs_ = QDateTime::currentMSecsSinceEpoch() + 6 * 60 * 60 * 1000;
            qCInfo(lcAppleToken) << "[appleDynamicCover] WebPlayKid token acquired, valid until"
                                 << QDateTime::fromMSecsSinceEpoch(cachedExpiryMs_).toString(Qt::ISODate);
            deliver(*token);
        });
    });
    network_->get(makeRequest(QUrl(kAlbumPageUrl)));
}

} // namespace listenfree::online
