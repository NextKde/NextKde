#include "automatic_lyrics.h"
#include "online/track_origin.h"
#include "online/lyric_matching.h"
#include "platform/file_paths.h"
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>

namespace listenfree::qmlbridge {
AutomaticLyrics::AutomaticLyrics(infrastructure::database::Database& db, QNetworkAccessManager& network,
                                 QObject* parent, int timeoutMs)
    : QObject(parent), database_(db), search_(network, nullptr, qMin(8000, timeoutMs), timeoutMs) {
    connect(&search_, &online::LyricSearch::changed, this, &AutomaticLyrics::finish);
}
QString AutomaticLyrics::identity(const QVariantMap& track) {
    if (online::isScriptTrack(track)) return online::scriptTrackKey(track);
    const auto path = track.value("localPath").toString();
    if (!path.isEmpty()) return "local:" + platform::filePathKey(path);
    const auto id = track.value("rid", track.value("trackId")).toString();
    return id.isEmpty() ? QString{} : track.value("source").toString() + ":" + id;
}
void AutomaticLyrics::cancel() {
    active_ = false;
    key_.clear();
    search_.release();
}
void AutomaticLyrics::request(const QVariantMap& track, const QVariantMap& seed) {
    const auto key = identity(track);
    if (key.isEmpty() || (active_ && key_ == key)) return;
    cancel();
    if (seed.value("title").toString().trimmed().isEmpty()) return;
    key_ = key; seed_ = seed;
    fingerprint_ = QString::fromUtf8(QJsonDocument(QJsonArray{
        online::normalizedLyricTitle(seed.value("title").toString()),
        online::normalizedLyricTitle(seed.value("artist").toString()),
        seed.value("durationMs").toLongLong()}).toJson(QJsonDocument::Compact));
    const auto setting = "lyrics.auto." + QString::fromLatin1(key.toUtf8().toBase64(QByteArray::Base64UrlEncoding));
    const auto cached = QJsonDocument::fromJson(QByteArray::fromStdString(database_.getSetting(setting).value_or("{}"))).object();
    const auto text = cached.value("lyrics").toString();
    if (cached.value("fingerprint").toString() == fingerprint_ && online::hasUsableMatchedLyrics(text)
        && !online::parseTimedLyrics(text).isEmpty()) {
        emit resolved(key, text);
        return;
    }
    const auto now = QDateTime::currentMSecsSinceEpoch();
    if (const auto* retry = retryAfter_.object(key); retry && *retry > now) return;
    retryAfter_.insert(key, new qint64(now + 10 * 60 * 1000));
    active_ = true;
    search_.search(seed, (seed.value("title").toString() + " " + seed.value("artist").toString()).trimmed());
    finish(); // A provider cache may have completed synchronously.
}
void AutomaticLyrics::finish() {
    if (!active_ || search_.busy()) return;
    active_ = false;
    const auto rows = search_.results();
    for (int i = 0; i < rows.size(); ++i) {
        const auto row = rows[i].toMap();
        const auto title = online::lyricTitleSimilarity(seed_.value("title").toString(), row.value("title").toString());
        const auto artist = seed_.value("artist").toString();
        if (title < .85 || online::lyricCandidateScore(seed_, row) < 82) continue;
        if (!artist.isEmpty()) {
            if (online::lyricTextSimilarity(artist, row.value("artist").toString()) < .75) continue;
        } else {
            const auto duration = seed_.value("durationMs").toLongLong();
            const auto other = row.value("durationMs").toLongLong();
            if (title < .98 || duration <= 0 || other <= 0 || qAbs(duration - other) > 5000) continue;
        }
        const auto text = search_.lyrics(i);
        if (text.size() > 1024 * 1024 || !online::hasUsableMatchedLyrics(text) || online::parseTimedLyrics(text).isEmpty()) continue;
        const auto setting = "lyrics.auto." + QString::fromLatin1(key_.toUtf8().toBase64(QByteArray::Base64UrlEncoding));
        database_.setSetting(setting, QString::fromUtf8(QJsonDocument(QJsonObject{
            {"fingerprint", fingerprint_}, {"lyrics", text}}).toJson(QJsonDocument::Compact)));
        emit resolved(key_, text);
        break;
    }
    search_.release();
}
}
