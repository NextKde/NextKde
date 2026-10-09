#include "online/lyric_search.h"
#include "online/lyric_sources.h"
#include "online/lyric_matching.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonDocument>
#include <QSignalBlocker>
#include <algorithm>
#include <utility>

namespace listenfree::online {
namespace {
constexpr int versionsPerSource = 3;
QString rowKey(const QVariantMap& row) {
    return row.value("lyricSource").toString() + ':' + row.value("rid").toString();
}
QString contextKey(const QVariantMap& track, const QString& query) {
    QJsonArray fields{normalizedLyricTitle(query), normalizedLyricTitle(track.value("title").toString()),
        normalizedLyricTitle(track.value("artist").toString()), normalizedLyricTitle(track.value("album").toString()),
        track.value("durationMs").toLongLong(), track.value("queryFromFilename").toBool()};
    return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(fields).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
}
int matchCost(const QVariantMap& row, const QString& text) {
    return 1 + int((QJsonDocument::fromVariant(row).toJson(QJsonDocument::Compact).size()*2 + text.size()*2 + 256)/1024);
}
}
LyricSearch::LyricSearch(QNetworkAccessManager& network, QObject* parent, int requestMs, int totalMs)
    : QObject(parent), network_(network), requestTimeoutMs_(requestMs), totalTimeoutMs_(totalMs) {
    deadline_.setSingleShot(true);
    connect(&deadline_, &QTimer::timeout, this, [this] { stop(true); });
}
LyricSearch::~LyricSearch() { blockSignals(true); stop(false); }
void LyricSearch::cancel() { stop(false); }
void LyricSearch::release() {
    {
        const QSignalBlocker blocker(this);
        stop(false);
    }
    providers_.clear(); sourceOrder_.clear(); results_.clear(); texts_.clear();
    track_.clear(); query_.clear(); searchKey_.clear();
    emit changed();
}
void LyricSearch::stop(bool timedOut) {
    deadline_.stop();
    ++generation_; // Invalidate before abort(): finished may be emitted synchronously.
    for(auto& provider : providers_) {
        const auto reply = provider.reply;
        provider.reply = nullptr;
        if(!provider.done) {
            provider.done = true;
            provider.state = timedOut ? "超时" : "已停止";
            provider.failed |= timedOut;
            provider.pending.clear();
        }
        if(reply) { reply->abort(); reply->deleteLater(); }
    }
    const bool wasBusy = std::exchange(busy_, false);
    if(wasBusy) emit changed();
}
void LyricSearch::search(const QVariantMap& track, const QString& query, const QString& source) {
    const auto term = query.simplified();
    const auto key = contextKey(track, term) + ':' + source;
    if(busy_ && searchKey_ == key) return; // Enter/repeated clicks do not restart the same work.
    stop(false);
    track_ = track; query_ = term; searchKey_ = key;
    providers_.clear(); results_.clear(); texts_.clear();
    sourceOrder_ = source == "all" ? QStringList{"wy","tx","kg","kw","mg","lrclib","amll"} : QStringList{source};
    if(term.isEmpty()) { sourceOrder_.clear(); emit changed(); return; }
    const auto now = QDateTime::currentMSecsSinceEpoch();
    for(const auto& id : sourceOrder_) {
        Provider provider;
        provider.queries = lyricSearchQueries(track_, term);
        provider.cacheKey = id + ':' + contextKey(track_, term);
        if(auto* cached = cache_.object(provider.cacheKey); cached && cached->expires > now) {
            provider.matches = cached->matches;
            provider.done = true; provider.state = "已缓存";
        } else if(retryAfter_.value(id) > now) {
            provider.done = true; provider.failed = true; provider.state = "稍后重试";
            provider.detail = QString("来源限流，约 %1 秒后可重试").arg((retryAfter_.value(id)-now+999)/1000);
        }
        providers_.insert(id, provider);
    }
    busy_ = true; elapsed_.start(); deadline_.start(totalTimeoutMs_);
    publish();
    for(const auto& id : sourceOrder_) advance(id);
}
void LyricSearch::advance(const QString& source) {
    auto& provider = providers_[source];
    if(!busy_ || provider.done || provider.reply) return;
    while(!provider.pending.isEmpty() && provider.matches.size() < versionsPerSource) {
        auto row = provider.pending.takeFirst().toMap();
        const auto embedded = row.take("lyricsText").toString();
        if(!embedded.isEmpty()) { accept(source, row, embedded); continue; }
        if(const auto* cached = lyricCache_.object(rowKey(row))) { accept(source, row, cached->text); continue; }
        provider.state = "验证中";
        if(auto* reply = lyricFetchRequest(network_, source, row)) { watchReply(source, reply, row); return; }
    }
    if(provider.matches.size() >= versionsPerSource || !provider.matches.isEmpty()) { finishProvider(source); return; }
    if(provider.nextQuery < provider.queries.size() && !provider.failed) {
        const auto term = provider.queries[provider.nextQuery++];
        provider.state = provider.nextQuery > 1 ? "放宽搜索" : "搜索中";
        if(auto* reply = lyricSearchRequest(network_, source, track_, term)) { watchReply(source, reply); return; }
        provider.failed = true; provider.detail = "来源暂不支持搜索";
    }
    finishProvider(source);
}
void LyricSearch::watchReply(const QString& source, QNetworkReply* reply, const QVariantMap& candidate) {
    providers_[source].reply = reply;
    const auto generation = generation_;
    // QNetworkRequest::transferTimeout only measures inactivity. This deadline
    // includes DNS, queued requests, and trickling responses as well.
    auto* timeout = new QTimer(reply);
    timeout->setSingleShot(true);
    connect(timeout, &QTimer::timeout, reply, [reply] { reply->setProperty("lyricDeadline", true); reply->abort(); });
    timeout->start(requestTimeoutMs_);
    connect(reply, &QIODevice::readyRead, reply, [reply] { if(reply->bytesAvailable() > 2*1024*1024) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, timeout, generation, source, candidate] {
        timeout->stop(); reply->deleteLater();
        if(generation != generation_ || !busy_ || providers_[source].reply != reply) return;
        auto& provider = providers_[source]; provider.reply = nullptr;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if(reply->error() != QNetworkReply::NoError) {
            if(status == 429) {
                bool secondsValid{};
                auto seconds = reply->rawHeader("Retry-After").toLongLong(&secondsValid);
                if(!secondsValid) {
                    const auto date = QDateTime::fromString(QString::fromLatin1(reply->rawHeader("Retry-After")), Qt::RFC2822Date);
                    seconds = date.isValid() ? QDateTime::currentDateTimeUtc().secsTo(date) : 5;
                }
                retryAfter_[source] = QDateTime::currentMSecsSinceEpoch() + qBound(qint64(1), seconds, qint64(86400))*1000;
                provider.failed = true; provider.detail = "来源请求过于频繁，请稍后重试";
                provider.pending.clear();
            } else if(candidate.isEmpty() || status != 404) {
                provider.detail = reply->property("lyricDeadline").toBool() ? "请求超时" : "网络请求失败";
                // Search failures get one simpler query retry; a broken download
                // must not generate a burst over the rest of the same provider.
                if(!candidate.isEmpty()) { provider.failed = true; provider.pending.clear(); }
            }
            qWarning().noquote() << "[lyric-search]" << source << (candidate.isEmpty()?"search":"fetch")
                << "http" << status << "network" << int(reply->error()) << "elapsedMs" << elapsed_.elapsed();
        } else if(candidate.isEmpty()) {
            auto rows = rankLyricCandidates(track_, query_, lyricSearchResults(source, reply->readAll()));
            for(const auto& item : rows) {
                const auto key = rowKey(item.toMap());
                if(provider.seen.contains(key)) continue;
                provider.seen.insert(key); provider.pending.append(item);
                if(provider.pending.size() >= 10) break;
            }
        } else accept(source, candidate, lyricResponse(source, reply->readAll()));
        const auto delay = candidate.isEmpty() && provider.pending.isEmpty() ? 250 : 0;
        QTimer::singleShot(delay, this, [this, generation, source] { if(generation == generation_) advance(source); });
        emit changed();
    });
    emit changed();
}
void LyricSearch::accept(const QString& source, QVariantMap row, const QString& text) {
    if(!hasUsableMatchedLyrics(text)) return;
    auto& provider = providers_[source];
    const auto identity = QCryptographicHash::hash(matchedLyricIdentity(text).toUtf8(), QCryptographicHash::Sha256);
    for(const auto& match : provider.matches) if(match.identity == identity) return;
    row["key"] = rowKey(row); row["features"] = matchedLyricFeatures(text);
    const Match match{row, text, identity};
    provider.matches.append(match);
    lyricCache_.insert(rowKey(row), new Match(match), matchCost(row, text));
    publish();
}
void LyricSearch::finishProvider(const QString& source) {
    auto& provider = providers_[source];
    provider.done = true; provider.pending.clear();
    if(provider.matches.isEmpty() && !provider.detail.isEmpty())provider.failed = true;
    if(!provider.matches.isEmpty() && !provider.failed)provider.detail.clear();
    provider.state = provider.failed ? "暂不可用" : provider.matches.isEmpty() ? "无匹配" : "已完成";
    if(!provider.matches.isEmpty() && !provider.failed) {
        int cost = 1;
        for(const auto& match : provider.matches) cost += matchCost(match.row, match.text);
        cache_.insert(provider.cacheKey, new CachedMatches{provider.matches, QDateTime::currentMSecsSinceEpoch()+5*60*1000}, cost);
    }
    publish();
}
void LyricSearch::publish() {
    QVariantList rows;
    texts_.clear();
    bool pending = false;
    for(const auto& source : sourceOrder_) {
        const auto& provider = providers_[source]; pending |= !provider.done;
        for(const auto& match : provider.matches) { rows.append(match.row); texts_.insert(rowKey(match.row), match.text); }
    }
    std::stable_sort(rows.begin(), rows.end(), [](const auto& a, const auto& b) { return a.toMap().value("score").toInt() > b.toMap().value("score").toInt(); });
    results_ = rows;
    if(!pending) { busy_ = false; deadline_.stop(); }
    emit changed();
}
QVariantList LyricSearch::sources() const {
    QVariantList result;
    for(const auto& id : sourceOrder_) {
        const auto& p = providers_[id];
        result.append(QVariantMap{{"id", id}, {"label", lyricSourceName(id)}, {"state", p.state},
            {"count", p.matches.size()}, {"detail", p.detail}, {"done", p.done}});
    }
    return result;
}
QString LyricSearch::message() const {
    if(query_.isEmpty()) return "请输入歌曲或艺术家";
    if(busy_) return results_.isEmpty() ? "正在搜索与验证，结果会陆续显示" : "已找到可用歌词，可以立即预览和使用；其他来源仍在搜索";
    QStringList failures;
    for(const auto& id : sourceOrder_) if(providers_[id].failed || !providers_[id].detail.isEmpty()) failures.append(lyricSourceName(id));
    if(!failures.isEmpty()) return failures.join("、") + " 暂不可用，已保留成功结果，可重新搜索";
    return results_.isEmpty() ? "未找到可用歌词，试试只搜歌名或调整关键词" : QString{};
}
QString LyricSearch::lyrics(int index) const {
    return index >= 0 && index < results_.size() ? texts_.value(rowKey(results_[index].toMap())) : QString{};
}
}
