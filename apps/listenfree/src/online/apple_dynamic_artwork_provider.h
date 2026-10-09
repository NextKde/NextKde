// Ported from the old project's src/renderer/utils/appleDynamicCover/index.ts:
// resolves the Apple Music animated artwork (editorialVideo) for a track.
// 1. amp-api search across storefronts to find the album id.
// 2. albums/{id}?extend=editorialVideo gives the motion-detail m3u8.
// 3. The HLS master list is parsed and AVC variants are preferred (hls.ts).
// Requests are serialized and results cached to stay under risk-control limits.

#pragma once

#include "online/apple_hls.h"

#include <QElapsedTimer>
#include <QHash>
#include <QObject>

#include <functional>
#include <optional>
#include <QString>
#include <QVariantMap>
#include <memory>

class QNetworkAccessManager;

namespace listenfree::online {

class AppleMusicWebToken;

struct AppleDynamicCoverQuery {
    QString name;
    QString singer;
    QString album;
};

struct AppleDynamicCoverResult {
    // Per-scene variant URLs: classic detail cover, immersive background and
    // pixel layout use different resolution caps (640 / 1080 / 1080).
    QString videoUrl;
    QString videoUrlImmersive;
    QString videoUrlPixel;
    QString posterUrl;
    QString albumId;
    QString storefront;
};

class AppleDynamicArtworkProvider : public QObject {
    Q_OBJECT

public:
    using Done = std::function<void(std::optional<AppleDynamicCoverResult>)>;

    explicit AppleDynamicArtworkProvider(QObject* parent = nullptr);

    // Asynchronously resolves the dynamic cover; a nullopt means "not found or
    // unavailable" and must degrade to the static artwork without an error UI.
    void fetch(const AppleDynamicCoverQuery& query, const Done& callback);
    void clearCache();
    void fetchArtist(const QString& name, std::function<void(QVariantMap)> done);

    // Visible for tests: title/artist normalization and LCS similarity.
    static QString normalizeText(const QString& text);
    static double similarity(const QString& rawLeft, const QString& rawRight);

public:
    struct SearchSong;
    struct RequestState;

private:

    void nextQueued();
    void runFetch(const AppleDynamicCoverQuery& query, const Done& callback);
    void searchNextStorefront(const Done& done, const std::shared_ptr<RequestState>& state);
    void resolveAlbumReference(const Done& done, const std::shared_ptr<RequestState>& state, const SearchSong& match);
    void fetchEditorialVideo(const Done& done, const std::shared_ptr<RequestState>& state);
    void resolvePlayableUrls(const Done& done, const std::shared_ptr<RequestState>& state);

    struct ArtistRequest;
    void searchArtist(const std::shared_ptr<ArtistRequest>& state, const QString& token);
    void fetchArtistFallback(const std::shared_ptr<ArtistRequest>& state);
    void finishArtist(const std::shared_ptr<ArtistRequest>& state, const QVariantMap& result);
    struct ArtistCacheEntry {
        QVariantMap result;
        qint64 expiresAt{0};
    };
    QHash<QString, std::shared_ptr<ArtistRequest>> artistPending_;
    QHash<QString, ArtistCacheEntry> artistCache_;

    QNetworkAccessManager* network_;
    AppleMusicWebToken* token_;
    // Serialized job queue mirroring the original requestQueue promise chain.
    QList<std::function<void()>> queue_;
    bool jobRunning_{false};

    struct CacheEntry {
        AppleDynamicCoverQuery key;
        std::optional<AppleDynamicCoverResult> value;
        qint64 storedAtMs{0};
    };
    QList<CacheEntry> cache_; // FIFO with bounded size, matches cacheSet semantics
    struct Pending {
        AppleDynamicCoverQuery key;
        QList<Done> callbacks;
    };
    QList<Pending> pending_;
};

} // namespace listenfree::online
