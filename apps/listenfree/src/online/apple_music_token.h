// Ported from the old project's src/renderer/utils/appleDynamicCover/token.ts:
// amp-api.music.apple.com needs `authorization: Bearer <jwt>` where the JWT
// header kid is WebPlayKid. The token is embedded in the main JS bundle that
// music.apple.com loads, so it can be scraped without an Apple developer
// account. Tokens are cached until shortly before expiry.

#pragma once

#include <QObject>
#include <QPointer>

#include <functional>
#include <optional>
#include <QString>

class QNetworkAccessManager;

namespace listenfree::online {

class AppleMusicWebToken : public QObject {
    Q_OBJECT

public:
    explicit AppleMusicWebToken(QObject* parent = nullptr);

    // Asynchronously resolves a valid WebPlayKid JWT; errors are reported as
    // an empty string through `callback`. Requests are coalesced while one is
    // in flight, mirroring the original tokenPromise behaviour.
    void fetch(const std::function<void(const QString&)>& callback);
    void clearCachedToken();

    // Visible for tests: extracts the first JWT whose header kid is WebPlayKid.
    static std::optional<QString> extractWebPlayKidJwt(const QString& javaScript);
    // Visible for tests: decodes the JWT payload "exp" (seconds), 0 on failure.
    static qint64 tokenExpiryEpochMs(const QString& jwt);

private:
    void fetchFreshToken();
    void deliver(const QString& token);
    void fail(const QString& reason);

    QNetworkAccessManager* network_;
    std::optional<QString> cachedToken_;
    qint64 cachedExpiryMs_{0};
    bool inFlight_{false};
    QList<std::function<void(const QString&)>> pending_;
};

} // namespace listenfree::online
