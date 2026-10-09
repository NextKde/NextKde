#include "online/apple_dynamic_artwork_provider.h"

#include "online/apple_music_token.h"

#include <QDateTime>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QPointer>
#include <QTimer>
#include <QUrlQuery>

#include <algorithm>
#include <vector>

Q_LOGGING_CATEGORY(lcAppleCover, "listenfree.appleDynamicCover", QtInfoMsg)

namespace listenfree::online {

struct AppleDynamicArtworkProvider::SearchSong {
    QString id;
    QString resourceType; // "song" | "album"
    QString storefront;
    QString name;
    QString artistName;
    QString albumName;
    QString albumId;
};

// One in-flight request: pipeline state shared across the staged network hops.
struct AppleDynamicArtworkProvider::RequestState {
    QString token;
    AppleDynamicCoverQuery query;
    QString term;
    int storefrontIndex{0};
    std::vector<SearchSong> searchList;
    QString albumId;
    QString preferredStorefront;
    QString editorialVideoUrl;
    QString posterUrl;
};

namespace {

const QStringList kStorefronts{QStringLiteral("cn"), QStringLiteral("hk"), QStringLiteral("tw"),
                               QStringLiteral("us"), QStringLiteral("gb"), QStringLiteral("jp"),
                               QStringLiteral("de"), QStringLiteral("fr")};
// Motion field priority in the editorialVideo object: prefer 1:1 square covers
// because they match album artwork presentation.
const QStringList kMotionKeys{QStringLiteral("motionDetailSquare"), QStringLiteral("motionSquareVideo1x1"),
                              QStringLiteral("motionDetailTall")};
constexpr int kClassicMaxEdge = 640;
constexpr int kImmersiveMaxEdge = 1080;
constexpr int kPixelMaxEdge = 1080;
constexpr int kAmpApiSearchLimit = 10;
constexpr qsizetype kMaxCacheSize = 50;
const QString kAmpApiBase = QStringLiteral("https://amp-api.music.apple.com/v1/catalog");
const QString kUserAgent =
    QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36");

QNetworkRequest makeRequest(const QUrl& url, const QString& token) {
    QUrl resource=url;
    if(resource.host()=="amp-api.music.apple.com") { QUrlQuery query(resource);query.addQueryItem("platform","web");resource.setQuery(query); }
    QNetworkRequest request(resource);
    request.setTransferTimeout(10000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setRawHeader(QByteArrayLiteral("user-agent"), kUserAgent.toUtf8());
    request.setRawHeader(QByteArrayLiteral("accept"), QByteArrayLiteral("application/json"));
    if (!token.isEmpty()) {
        request.setRawHeader(QByteArrayLiteral("authorization"), "Bearer " + token.toUtf8());
        request.setRawHeader(QByteArrayLiteral("origin"), QByteArrayLiteral("https://music.apple.com"));
    }
    return request;
}

QString cacheKey(const AppleDynamicCoverQuery& info) {
    return QStringList{info.name.trimmed(), info.singer.trimmed(), info.album.trimmed()}.join(QLatin1Char('|'));
}

QString normalize(const QString& text) {
    QString normalized = text.toLower();
    static const QRegularExpression brackets(QStringLiteral("（.*?）|\\(.*?\\)|【.*?】|\\[.*?]"));
    normalized.remove(brackets);
    normalized.remove(QRegularExpression(QStringLiteral(u"[（）【】\\[\\]()]")));
    normalized.remove(QRegularExpression(QStringLiteral("[\\x{200b}\\x{00ad}]")));
    normalized.replace(QRegularExpression(QStringLiteral("\\s+")), QStringLiteral(" "));
    return normalized.trimmed();
}

double lcsSimilarity(const QString& left, const QString& right) {
    if (left.isEmpty() || right.isEmpty()) return 0;
    if (left == right) return 1;
    const qsizetype maxLen = std::max(left.size(), right.size());
    // LCS edit-distance-lite of the original implementation.
    std::vector<qsizetype> previous(right.size() + 1, 0);
    std::vector<qsizetype> current(right.size() + 1, 0);
    for (qsizetype i = 1; i <= left.size(); ++i) {
        for (qsizetype j = 1; j <= right.size(); ++j) {
            current[j] = left[i - 1] == right[j - 1] ? previous[j - 1] + 1 : std::max(previous[j], current[j - 1]);
        }
        std::copy(current.begin(), current.end(), previous.begin());
    }
    return static_cast<double>(previous[right.size()]) / static_cast<double>(maxLen);
}

std::optional<AppleDynamicArtworkProvider::SearchSong> pickBestSearch(
    const std::vector<AppleDynamicArtworkProvider::SearchSong>& list, const AppleDynamicCoverQuery& query) {
    if (list.empty()) return std::nullopt;
    const QString title = normalize(query.name);
    const QString artist = normalize(query.singer);
    const QString album = normalize(query.album);

    std::optional<AppleDynamicArtworkProvider::SearchSong> best;
    double bestScore = 0;
    for (const auto& item : list) {
        double score = 0;
        const QString itemTitle = normalize(item.name);
        const QString itemArtist = normalize(item.artistName);
        const QString itemAlbum = normalize(item.albumName);
        if (!title.isEmpty() && !itemTitle.isEmpty()) {
            if (item.name.trimmed().compare(query.name.trimmed(), Qt::CaseInsensitive) == 0) score += 50;
            else if (itemTitle == title) score += 6;
            else score += lcsSimilarity(itemTitle, title) * 3;
        }
        if (!artist.isEmpty() && !itemArtist.isEmpty()) {
            if (itemArtist == artist) score += 4;
            else if (itemArtist.contains(artist) || artist.contains(itemArtist)) score += 3;
            else score += lcsSimilarity(itemArtist, artist) * 2;
        }
        if (!album.isEmpty() && !itemAlbum.isEmpty()) {
            if (itemAlbum == album) score += 3;
            else if (itemAlbum.contains(album) || album.contains(itemAlbum)) score += 2;
            else score += lcsSimilarity(itemAlbum, album);
        }
        if (item.albumId.isEmpty()) score *= 0.8;
        if (score > bestScore) {
            bestScore = score;
            best = item;
        }
    }
    if (bestScore >= 2) return best;
    const auto fallback =
        std::find_if(list.begin(), list.end(), [](const AppleDynamicArtworkProvider::SearchSong& item) {
            return !item.albumId.isEmpty();
        });
    if (fallback != list.end()) return *fallback;
    return std::nullopt;
}

} // namespace

AppleDynamicArtworkProvider::AppleDynamicArtworkProvider(QObject* parent)
    : QObject(parent), network_(new QNetworkAccessManager(this)), token_(new AppleMusicWebToken(this)) {}

QString AppleDynamicArtworkProvider::normalizeText(const QString& text) { return normalize(text); }

double AppleDynamicArtworkProvider::similarity(const QString& rawLeft, const QString& rawRight) {
    return lcsSimilarity(normalize(rawLeft), normalize(rawRight));
}

void AppleDynamicArtworkProvider::clearCache() { cache_.clear(); artistCache_.clear(); }

void AppleDynamicArtworkProvider::fetch(const AppleDynamicCoverQuery& query, const Done& callback) {
    const QString key = cacheKey(query);
    for (const auto& entry : cache_) {
        if (cacheKey(entry.key) == key && entry.value) {
            callback(entry.value);
            return;
        }
    }
    for (int index = 0; index < pending_.size(); ++index) {
        if (cacheKey(pending_.at(index).key) == key) {
            pending_[index].callbacks.push_back(callback);
            return;
        }
    }
    pending_.push_back({query, {callback}});
    queue_.push_back([this, key] {
        for (int index = 0; index < pending_.size(); ++index) {
            if (cacheKey(pending_.at(index).key) != key) continue;
            auto callbacks = pending_.at(index).callbacks;
            auto target = pending_.at(index).key;
            pending_.removeAt(index);
            runFetch(target, [callbacks](std::optional<AppleDynamicCoverResult> result) {
                for (const auto& callback : callbacks) callback(result);
            });
            return;
        }
        nextQueued();
    });
    if (!jobRunning_) nextQueued();
}

void AppleDynamicArtworkProvider::nextQueued() {
    if (jobRunning_ || queue_.isEmpty()) return;
    jobRunning_ = true;
    const auto job = queue_.takeFirst();
    job();
}

void AppleDynamicArtworkProvider::runFetch(const AppleDynamicCoverQuery& query, const Done& callback) {
    // Mirrors the original getAppleDynamicCover async chain; a failure never
    // throws, it degrades to nullopt so callers fall back to static artwork.
    const auto state = std::make_shared<RequestState>();
    state->query = query;
    state->term = QStringList{query.name.trimmed(), query.singer.trimmed()}.join(QLatin1Char(' ')).trimmed();
    if (state->term.isEmpty()) {
        qCInfo(lcAppleCover) << "[appleDynamicCover] get dynamic cover failed: empty query";
        jobRunning_ = false;
        callback(std::nullopt);
        nextQueued();
        return;
    }
    token_->fetch([this, callback, state](const QString& token) mutable {
        if (token.isEmpty()) {
            jobRunning_ = false;
            callback(std::nullopt);
            nextQueued();
            return;
        }
        state->token = token;
        searchNextStorefront(callback, state);
    });
}

void AppleDynamicArtworkProvider::searchNextStorefront(const Done& done,
                                                       const std::shared_ptr<RequestState>& state) {
    if (state->storefrontIndex >= kStorefronts.size()) {
        jobRunning_ = false;
        qCInfo(lcAppleCover) << "[appleDynamicCover] get dynamic cover failed: no search results";
        done(std::nullopt);
        nextQueued();
        return;
    }
    const QString storefront = kStorefronts.at(state->storefrontIndex);
    const QUrl url = QUrl(QStringLiteral("%1/%2/search?term=%3&types=albums,songs&limit=%4")
                              .arg(kAmpApiBase, storefront, QString::fromUtf8(QUrl::toPercentEncoding(state->term)))
                              .arg(kAmpApiSearchLimit));
    connect(network_, &QNetworkAccessManager::finished, this,
            [this, done, state, storefront](QNetworkReply* reply) mutable {
                reply->deleteLater();
                disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
                const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                if (status == 401 || status == 403) {
                    token_->clearCachedToken();
                    jobRunning_ = false;
                    qCInfo(lcAppleCover) << "[appleDynamicCover] apple api auth failed:" << status;
                    done(std::nullopt);
                    nextQueued();
                    return;
                }
                if (reply->error() == QNetworkReply::NoError && status >= 200 && status < 300) {
                    const QJsonDocument document = QJsonDocument::fromJson(reply->readAll());
                    const QJsonObject results = document.object().value(QStringLiteral("results")).toObject();
                    const auto albums =
                        results.value(QStringLiteral("albums")).toObject().value(QStringLiteral("data")).toArray();
                    const auto songs =
                        results.value(QStringLiteral("songs")).toObject().value(QStringLiteral("data")).toArray();
                    // Album results first (higher hit rate for editorialVideo),
                    // then songs, matching the original list order.
                    QHash<QString, QString> albumNames;
                    for (const auto& albumValue : albums) {
                        const QJsonObject albumObject = albumValue.toObject();
                        const QJsonObject attributes = albumObject.value(QStringLiteral("attributes")).toObject();
                        const QString id = albumObject.value(QStringLiteral("id")).toString();
                        albumNames.insert(id, attributes.value(QStringLiteral("name")).toString());
                        state->searchList.push_back({id, QStringLiteral("album"), storefront,
                                                     attributes.value(QStringLiteral("name")).toString(),
                                                     attributes.value(QStringLiteral("artistName")).toString(),
                                                     attributes.value(QStringLiteral("name")).toString(), id});
                    }
                    for (const auto& songValue : songs) {
                        const QJsonObject songObject = songValue.toObject();
                        const QJsonObject attributes = songObject.value(QStringLiteral("attributes")).toObject();
                        QString albumId;
                        const auto albumRelationship =
                            songObject.value(QStringLiteral("relationships")).toObject()
                                .value(QStringLiteral("albums")).toObject().value(QStringLiteral("data")).toArray();
                        if (!albumRelationship.isEmpty())
                            albumId = albumRelationship.first().toObject().value(QStringLiteral("id")).toString();
                        QString albumName = attributes.value(QStringLiteral("albumName")).toString();
                        if (albumName.isEmpty()) albumName = albumNames.value(albumId);
                        state->searchList.push_back({songObject.value(QStringLiteral("id")).toString(),
                                                     QStringLiteral("song"), storefront,
                                                     attributes.value(QStringLiteral("name")).toString(),
                                                     attributes.value(QStringLiteral("artistName")).toString(),
                                                     albumName, albumId});
                    }
                } else {
                    qCInfo(lcAppleCover) << "[appleDynamicCover] search failed" << storefront << status;
                }
                const auto best = pickBestSearch(state->searchList, state->query);
                if (!best) {
                    ++state->storefrontIndex;
                    searchNextStorefront(done, state);
                    return;
                }
                qCInfo(lcAppleCover) << "[appleDynamicCover] matched" << best->resourceType << best->name
                                     << "in storefront" << best->storefront;
                resolveAlbumReference(done, state, *best);
            });
    network_->get(makeRequest(url, state->token));
}

void AppleDynamicArtworkProvider::resolveAlbumReference(const Done& done,
                                                        const std::shared_ptr<RequestState>& state,
                                                        const SearchSong& match) {
    if (match.resourceType == QStringLiteral("album") || !match.albumId.isEmpty()) {
        state->albumId = match.resourceType == QStringLiteral("album") ? match.id : match.albumId;
        state->preferredStorefront = match.storefront;
        fetchEditorialVideo(done, state);
        return;
    }
    const QUrl url = QUrl(QStringLiteral("%1/%2/songs/%3?include=albums").arg(kAmpApiBase, match.storefront, match.id));
    connect(network_, &QNetworkAccessManager::finished, this,
            [this, done, state, match](QNetworkReply* reply) mutable {
                reply->deleteLater();
                disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
                if (reply->error() != QNetworkReply::NoError) {
                    qCInfo(lcAppleCover) << "[appleDynamicCover] song album relationship failed" << match.storefront;
                    ++state->storefrontIndex;
                    searchNextStorefront(done, state);
                    return;
                }
                const QJsonDocument document = QJsonDocument::fromJson(reply->readAll());
                const auto albumRelationship =
                    document.object().value(QStringLiteral("data")).toArray().first().toObject()
                        .value(QStringLiteral("relationships")).toObject()
                        .value(QStringLiteral("albums")).toObject().value(QStringLiteral("data")).toArray();
                if (albumRelationship.isEmpty()) {
                    ++state->storefrontIndex;
                    searchNextStorefront(done, state);
                    return;
                }
                state->albumId = albumRelationship.first().toObject().value(QStringLiteral("id")).toString();
                state->preferredStorefront = match.storefront;
                fetchEditorialVideo(done, state);
            });
    network_->get(makeRequest(url, state->token));
}

void AppleDynamicArtworkProvider::fetchEditorialVideo(const Done& done,
                                                      const std::shared_ptr<RequestState>& state) {
    QStringList storefrontOrder{state->preferredStorefront};
    for (const QString& storefront : kStorefronts) {
        if (storefront != state->preferredStorefront) storefrontOrder.push_back(storefront);
    }
    const auto attempt = std::make_shared<int>(-1);
    const auto nextAttempt = std::make_shared<std::function<void()>>();
    *nextAttempt = [this, done, state, storefrontOrder, attempt, nextAttempt]() mutable {
        ++*attempt;
        if (*attempt >= storefrontOrder.size()) {
            jobRunning_ = false;
            qCInfo(lcAppleCover) << "[appleDynamicCover] get dynamic cover failed: no editorialVideo";
            done(std::nullopt);
            nextQueued();
            return;
        }
        const QString storefront = storefrontOrder.at(*attempt);
        const QUrl url = QUrl(QStringLiteral("%1/%2/albums/%3?extend=editorialVideo")
                                  .arg(kAmpApiBase, storefront, state->albumId));
        connect(network_, &QNetworkAccessManager::finished, this,
                [this, done, state, nextAttempt](QNetworkReply* reply) mutable {
                    reply->deleteLater();
                    disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
                    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    if (status == 401 || status == 403) {
                        token_->clearCachedToken();
                        jobRunning_ = false;
                        qCInfo(lcAppleCover) << "[appleDynamicCover] apple api auth failed:" << status;
                        done(std::nullopt);
                        nextQueued();
                        return;
                    }
                    if (!(reply->error() == QNetworkReply::NoError && status >= 200 && status < 300)) {
                        (*nextAttempt)();
                        return;
                    }
                    const QJsonDocument document = QJsonDocument::fromJson(reply->readAll());
                    const QJsonObject attributes =
                        document.object().value(QStringLiteral("data")).toArray().first().toObject()
                            .value(QStringLiteral("attributes")).toObject();
                    const QJsonObject editorialVideo = attributes.value(QStringLiteral("editorialVideo")).toObject();
                    if (editorialVideo.isEmpty()) {
                        (*nextAttempt)();
                        return;
                    }
                    for (const QString& key : kMotionKeys) {
                        const QJsonObject motion = editorialVideo.value(key).toObject();
                        const QString video = motion.value(QStringLiteral("video")).toString();
                        if (video.isEmpty()) continue;
                        QString poster = motion.value(QStringLiteral("previewFrame")).toObject()
                                             .value(QStringLiteral("url")).toString();
                        if (!poster.isEmpty()) poster.replace(QStringLiteral("{w}x{h}"), QStringLiteral("600x600"));
                        state->editorialVideoUrl = video;
                        state->posterUrl = poster;
                        qCInfo(lcAppleCover) << "[appleDynamicCover] editorialVideo found via" << key;
                        resolvePlayableUrls(done, state);
                        return;
                    }
                    (*nextAttempt)();
                });
        network_->get(makeRequest(url, state->token));
    };
    (*nextAttempt)();
}

void AppleDynamicArtworkProvider::resolvePlayableUrls(const Done& done,
                                                      const std::shared_ptr<RequestState>& state) {
    connect(network_, &QNetworkAccessManager::finished, this,
            [this, done, state](QNetworkReply* reply) mutable {
                reply->deleteLater();
                disconnect(network_, &QNetworkAccessManager::finished, nullptr, nullptr);
                AppleDynamicCoverResult result;
                result.albumId = state->albumId;
                result.storefront = state->preferredStorefront;
                result.posterUrl = state->posterUrl;
                result.videoUrl = state->editorialVideoUrl;
                result.videoUrlImmersive = state->editorialVideoUrl;
                result.videoUrlPixel = state->editorialVideoUrl;
                if (reply->error() == QNetworkReply::NoError) {
                    const QString master = QString::fromUtf8(reply->readAll());
                    if (master.contains(QStringLiteral("#EXT-X-STREAM-INF"))) {
                        const auto pick = [&](int maxEdge) {
                            const apple_hls::HlsVariant variant =
                                apple_hls::pickBestVariant(master, state->editorialVideoUrl, maxEdge);
                            return variant.uri.isEmpty()
                                       ? state->editorialVideoUrl
                                       : apple_hls::resolveUrl(variant.uri, state->editorialVideoUrl);
                        };
                        result.videoUrl = pick(kClassicMaxEdge);
                        result.videoUrlImmersive = pick(kImmersiveMaxEdge);
                        result.videoUrlPixel = pick(kPixelMaxEdge);
                    }
                } else {
                    qCInfo(lcAppleCover) << "[appleDynamicCover] resolve hls failed, use master directly:"
                                         << reply->errorString();
                }
                qCInfo(lcAppleCover) << "[appleDynamicCover] resolved album" << result.albumId
                                     << "classic" << result.videoUrl;
                // Cache a bounded number of entries, evicting oldest first.
                cache_.push_back({state->query, result, QDateTime::currentMSecsSinceEpoch()});
                while (cache_.size() > kMaxCacheSize) cache_.removeFirst();
                jobRunning_ = false;
                done(result);
                nextQueued();
            });
    network_->get(makeRequest(QUrl(state->editorialVideoUrl), QString{}));
}

} // namespace listenfree::online

namespace listenfree::online {
namespace {
QString artistImage(const QJsonObject& artwork, int width, int height, bool transparent = false) {
    const auto originalWidth=artwork.value("width").toDouble();
    const auto originalHeight=artwork.value("height").toDouble();
    if(originalWidth>0 && originalHeight>0) {
        const auto scale=std::min({1.0,width/originalWidth,height/originalHeight});
        width=std::max(1,qRound(originalWidth*scale));
        height=std::max(1,qRound(originalHeight*scale));
    }
    QString url = artwork.value("url").toString();
    url.replace("{w}", QString::number(width)).replace("{h}", QString::number(height));
    url.replace("{f}", transparent ? "png" : "jpg").replace("{c}", "bb");
    // Editorial logos currently arrive with a fixed .jpg suffix, not {f}.
    if (transparent) url.replace(QRegularExpression("\\.(jpg|jpeg|webp)(?=\\?|$)"), ".png");
    return QUrl(url).scheme() == "https" ? url : QString{};
}

QVariantMap appleArtistVisual(const QJsonObject& row) {
    const auto attributes = row.value("attributes").toObject();
    QVariantMap result{{"id", row.value("id").toString()},
                       {"name", attributes.value("name").toString()},
                       {"source", "apple"}, {"pageUrl", attributes.value("url").toString()}};
    result["hero"] = artistImage(attributes.value("artwork").toObject(), 1600, 1600);
    const auto editorial = attributes.value("editorialArtwork").toObject();
    for (const auto* key : {"centeredFullscreenBackground", "artistHero", "superWide", "vipSquare", "storeFlowcase"}) {
        const auto url = artistImage(editorial.value(key).toObject(), 1600, 800);
        if (!url.isEmpty()) { result["hero"] = url; result["heroKind"] = key; break; }
    }
    for (const auto* key : {"musicContentColorLogoTrimmed", "artistLogo", "signature", "artistSignature"}) {
        const auto url = artistImage(editorial.value(key).toObject(), 900, 260, true);
        if (!url.isEmpty()) { result["signature"] = url; result["signatureKind"] = key; break; }
    }
    return result;
}
}

struct AppleDynamicArtworkProvider::ArtistRequest {
    QString name;
    QString key;
    bool chinese{false};
    bool fallback{false};
    bool finished{false};
    bool refreshedToken{false};
    QVariantMap appleFallback;
    QPointer<QNetworkAccessManager> network;
    QPointer<QNetworkReply> reply;
    QList<std::function<void(QVariantMap)>> callbacks;
};

void AppleDynamicArtworkProvider::fetchArtist(const QString& name, std::function<void(QVariantMap)> done) {
    const QString key = normalize(name);
    if (key.isEmpty()) { done({}); return; }
    const auto cached = artistCache_.constFind(key);
    if (cached != artistCache_.cend() && cached->expiresAt > QDateTime::currentMSecsSinceEpoch()) {
        done(cached->result); return;
    }
    if (artistPending_.contains(key)) { artistPending_[key]->callbacks.append(done); return; }
    // Fast navigation cannot create an unbounded fan-out of background requests.
    if (artistPending_.size() >= 4) { done({}); return; }
    auto state = std::make_shared<ArtistRequest>();
    state->name = name.trimmed(); state->key = key;
    state->chinese = QRegularExpression("[\\x{3400}-\\x{9fff}]").match(name).hasMatch();
    state->network = new QNetworkAccessManager(this);
    state->callbacks.append(done);
    artistPending_.insert(key, state);
    QTimer::singleShot(18000, state->network, [this, state] {
        if (!state->finished && !state->fallback) fetchArtistFallback(state);
    });
    QTimer::singleShot(28000, state->network, [this, state] {
        if (!state->finished) finishArtist(state, {});
    });
    token_->fetch([this, state](const QString& token) {
        if (state->finished || state->fallback) return;
        if (token.isEmpty()) fetchArtistFallback(state);
        else searchArtist(state, token);
    });
}

void AppleDynamicArtworkProvider::searchArtist(const std::shared_ptr<ArtistRequest>& state, const QString& token) {
    const QString store = state->chinese ? "cn" : "us";
    QUrl url(kAmpApiBase + "/" + store + "/search");
    QUrlQuery query;
    query.addQueryItem("term", state->name);
    query.addQueryItem("types", "artists"); query.addQueryItem("limit", "5");
    query.addQueryItem("l", state->chinese ? "zh-Hans-CN" : "en-US");
    query.addQueryItem("extend", "editorialArtwork"); url.setQuery(query);
    auto* reply = state->network->get(makeRequest(url, token)); state->reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, state, reply, store, token] {
        reply->deleteLater();
        if (state->finished || state->fallback) return;
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if ((status == 401 || status == 403) && !state->refreshedToken) {
            state->refreshedToken = true; token_->clearCachedToken();
            token_->fetch([this, state](const QString& refreshed) {
                if (state->finished || state->fallback) return;
                if (refreshed.isEmpty()) fetchArtistFallback(state); else searchArtist(state, refreshed);
            });
            return;
        }
        const auto artists = QJsonDocument::fromJson(reply->readAll()).object().value("results")
                                 .toObject().value("artists").toObject().value("data").toArray();
        if (reply->error() == QNetworkReply::NoError) for (const auto& value : artists) {
            const auto row = value.toObject();
            if (similarity(state->name, row.value("attributes").toObject().value("name").toString()) < .88) continue;
            auto visual = appleArtistVisual(row);
            state->appleFallback = visual;
            if (!visual.value("heroKind").toString().isEmpty() && !visual.value("signature").toString().isEmpty()) { finishArtist(state, visual); return; }
            const auto id = row.value("id").toString();
            if (id.isEmpty()) break;
            QUrl detail(kAmpApiBase + "/" + store + "/artists/" + id);
            QUrlQuery parameters;
            parameters.addQueryItem("extend", "editorialArtwork");
            parameters.addQueryItem("l", state->chinese ? "zh-Hans-CN" : "en-US"); detail.setQuery(parameters);
            auto* artist = state->network->get(makeRequest(detail, token)); state->reply = artist;
            connect(artist, &QNetworkReply::finished, this, [this, state, artist] {
                artist->deleteLater();
                if (state->finished || state->fallback) return;
                const auto data = QJsonDocument::fromJson(artist->readAll()).object().value("data").toArray();
                const auto visual = data.isEmpty() ? QVariantMap{} : appleArtistVisual(data.first().toObject());
                if (artist->error() == QNetworkReply::NoError && !visual.value("hero").toString().isEmpty())
                    finishArtist(state, visual);
                else fetchArtistFallback(state);
            });
            return;
        }
        fetchArtistFallback(state);
    });
}

void AppleDynamicArtworkProvider::fetchArtistFallback(const std::shared_ptr<ArtistRequest>& state) {
    if (state->finished || state->fallback) return;
    if (!state->appleFallback.value("hero").toString().isEmpty()) { finishArtist(state, state->appleFallback); return; }
    state->fallback = true;
    if (state->reply && state->reply->isRunning()) state->reply->abort();
    // Exact title with MediaWiki's own redirect/Chinese-variant resolution,
    // rather than taking the first arbitrary image search hit for a person.
    const QString language = state->chinese ? "zh" : "en";
    QUrl url("https://" + language + ".wikipedia.org/api/rest_v1/page/summary/" +
             QString::fromUtf8(QUrl::toPercentEncoding(state->name)));
    auto request = makeRequest(url, {});
    request.setRawHeader("user-agent", "ListenFree/0.2 (https://github.com/Tabris-Ayanami/ListenFree-desktop; artist artwork)");
    auto* reply = state->network->get(request); state->reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, state, reply] {
        reply->deleteLater(); if (state->finished) return;
        const auto page = QJsonDocument::fromJson(reply->readAll()).object();
        // Exclude disambiguation and non-musical namesakes. Redirect aliases
        // are allowed, so Chinese traditional/simplified names still resolve.
        static const QRegularExpression musician(
            "singer|musician|rapper|songwriter|composer|band|orchestra|musical|music duo|歌手|歌唱|音乐|音樂|乐团|樂團|藝人|艺人|演員|演员",
            QRegularExpression::CaseInsensitiveOption);
        const auto description = page.value("description").toString();
        QVariantMap result;
        if (reply->error() == QNetworkReply::NoError && page.value("type").toString() == "standard" &&
            musician.match(description).hasMatch()) {
            QString image = page.value("originalimage").toObject().value("source").toString();
            if (image.isEmpty()) image = page.value("thumbnail").toObject().value("source").toString();
            const QUrl source(image);
            if (source.scheme() == "https" && source.host() == "upload.wikimedia.org") {
                result = {{"id", page.value("wikibase_item").toString()},
                          {"name", page.value("title").toString()}, {"hero", image}, {"source", "wikipedia"},
                          {"pageUrl", page.value("content_urls").toObject().value("desktop").toObject().value("page").toString()}};
            }
        }
        finishArtist(state, result);
    });
}

void AppleDynamicArtworkProvider::finishArtist(const std::shared_ptr<ArtistRequest>& state, const QVariantMap& result) {
    if (state->finished) return;
    state->finished = true;
    artistPending_.remove(state->key);
    if (artistCache_.size() >= 24 && !artistCache_.contains(state->key)) artistCache_.erase(artistCache_.begin());
    artistCache_.insert(state->key, {result, QDateTime::currentMSecsSinceEpoch() + (result.value("source") == "apple" ? 86400000 : 60000)});
    if (state->reply && state->reply->isRunning()) state->reply->abort();
    if (state->network) state->network->deleteLater();
    auto callbacks = std::move(state->callbacks);
    for (const auto& callback : callbacks) callback(result);
}
}
