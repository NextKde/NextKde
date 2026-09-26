#include "LyricsService.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrlQuery>

#include <algorithm>
#include <utility>

LyricsService::LyricsService(QString cachePath, QObject *parent)
    : QObject(parent)
    , m_cachePath(std::move(cachePath))
    , m_network(this)
{
    QDir().mkpath(m_cachePath);
}

QVariantList LyricsService::lines() const { return m_lines; }
int LyricsService::currentLineIndex() const { return m_currentLineIndex; }
qint64 LyricsService::loadedTrackId() const { return m_loadedTrackId; }
bool LyricsService::loading() const { return m_loading; }
QString LyricsService::errorMessage() const { return m_errorMessage; }

void LyricsService::load(const TrackRecord &track)
{
    ++m_generation;
    m_loadedTrackId = track.id;
    if (QNetworkReply *reply = std::exchange(m_reply, nullptr)) {
        // abort() may emit finished synchronously. Keep the cancelled reply
        // independent of the member that the completion handler updates.
        reply->abort();
        reply->deleteLater();
    }
    m_lines.clear();
    m_currentLineIndex = -1;
    emit lyricsChanged();
    emit currentLineChanged();
    setError({});
    setLoading(false);

    if (track.source == QLatin1String("local")) {
        const QFileInfo audio(track.path);
        const QStringList candidates{
            QDir(audio.absolutePath()).filePath(audio.completeBaseName() + QStringLiteral(".lrc")),
            QDir(audio.absolutePath()).filePath(audio.completeBaseName() + QStringLiteral(".LRC")),
        };
        for (const QString &candidate : candidates) {
            QFile file(candidate);
            if (file.open(QIODevice::ReadOnly)) {
                applyLyrics(QString::fromUtf8(file.readAll()));
                return;
            }
        }
        setError(tr("No sidecar lyrics found"));
        return;
    }
    if (track.source == QLatin1String("wy") && !track.providerId.isEmpty()) {
        loadOnline(track);
        return;
    }
    setError(tr("Lyrics are not available for this source"));
}

void LyricsService::setPositionMs(qint64 positionMs)
{
    int nextIndex = -1;
    for (qsizetype index = 0; index < m_lines.size(); ++index) {
        if (m_lines.at(index).toMap().value(QStringLiteral("timeMs")).toLongLong()
            > positionMs) {
            break;
        }
        nextIndex = static_cast<int>(index);
    }
    if (nextIndex == m_currentLineIndex)
        return;
    m_currentLineIndex = nextIndex;
    emit currentLineChanged();
}

QVariantList LyricsService::parseLrc(const QString &text)
{
    struct Line {
        qint64 timeMs = 0;
        QString text;
    };
    QList<Line> parsed;
    const QRegularExpression timestamp(
        QStringLiteral(R"(\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\])"));
    const QStringList sourceLines = text.split(QRegularExpression(QStringLiteral("\r?\n")));
    for (const QString &sourceLine : sourceLines) {
        QRegularExpressionMatchIterator matches = timestamp.globalMatch(sourceLine);
        QList<qint64> times;
        qsizetype lyricStart = 0;
        while (matches.hasNext()) {
            const QRegularExpressionMatch match = matches.next();
            const qint64 minutes = match.captured(1).toLongLong();
            const qint64 seconds = match.captured(2).toLongLong();
            QString fraction = match.captured(3);
            qint64 milliseconds = 0;
            if (!fraction.isEmpty()) {
                if (fraction.size() == 1)
                    milliseconds = fraction.toLongLong() * 100;
                else if (fraction.size() == 2)
                    milliseconds = fraction.toLongLong() * 10;
                else
                    milliseconds = fraction.left(3).toLongLong();
            }
            times.append((minutes * 60 + seconds) * 1000 + milliseconds);
            lyricStart = match.capturedEnd();
        }
        if (times.isEmpty())
            continue;
        const QString lyric = sourceLine.mid(lyricStart).trimmed();
        if (lyric.isEmpty())
            continue;
        for (qint64 time : std::as_const(times))
            parsed.append(Line{time, lyric});
    }
    std::stable_sort(parsed.begin(), parsed.end(), [](const Line &left, const Line &right) {
        return left.timeMs < right.timeMs;
    });
    QVariantList result;
    result.reserve(parsed.size());
    for (const Line &line : std::as_const(parsed)) {
        result.append(QVariantMap{{QStringLiteral("timeMs"), line.timeMs},
                                  {QStringLiteral("text"), line.text}});
    }
    return result;
}

void LyricsService::loadOnline(const TrackRecord &track)
{
    QFile cached(cacheFile(track));
    if (cached.open(QIODevice::ReadOnly)) {
        const QString text = QString::fromUtf8(cached.readAll());
        if (!parseLrc(text).isEmpty()) {
            applyLyrics(text);
            return;
        }
    }

    setLoading(true);
    QUrl url(QStringLiteral("https://music.163.com/api/song/lyric"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("id"), track.providerId);
    query.addQueryItem(QStringLiteral("lv"), QStringLiteral("-1"));
    query.addQueryItem(QStringLiteral("kv"), QStringLiteral("-1"));
    query.addQueryItem(QStringLiteral("tv"), QStringLiteral("-1"));
    url.setQuery(query);
    QNetworkRequest request(url);
    request.setTransferTimeout(12000);
    request.setRawHeader("Referer", "https://music.163.com/");
    request.setRawHeader("User-Agent", "Mozilla/5.0 KOS-Music/1.0");
    const quint64 generation = m_generation;
    const QString target = cacheFile(track);
    QNetworkReply *reply = m_network.get(request);
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, generation, target, reply] {
        if (m_reply == reply)
            m_reply = nullptr;
        if (generation != m_generation) {
            reply->deleteLater();
            return;
        }
        setLoading(false);
        if (reply->error() != QNetworkReply::NoError) {
            applyLyrics({}, tr("Unable to load lyrics: %1").arg(reply->errorString()));
            reply->deleteLater();
            return;
        }
        const QJsonObject root = QJsonDocument::fromJson(reply->readAll()).object();
        const QString original = root.value(QStringLiteral("lrc")).toObject()
                                     .value(QStringLiteral("lyric")).toString();
        const QString translated = root.value(QStringLiteral("tlyric")).toObject()
                                       .value(QStringLiteral("lyric")).toString();
        QString combined = original;
        if (combined.isEmpty())
            combined = translated;
        if (parseLrc(combined).isEmpty()) {
            applyLyrics({}, tr("No synchronized lyrics were returned"));
        } else {
            QSaveFile file(target);
            if (file.open(QIODevice::WriteOnly)) {
                file.write(combined.toUtf8());
                file.commit();
            }
            applyLyrics(combined);
        }
        reply->deleteLater();
    });
}

void LyricsService::applyLyrics(const QString &text, const QString &error)
{
    m_lines = parseLrc(text);
    m_currentLineIndex = -1;
    setError(error);
    emit lyricsChanged();
    emit currentLineChanged();
}

void LyricsService::setLoading(bool loading)
{
    if (m_loading == loading)
        return;
    m_loading = loading;
    emit loadingChanged();
}

void LyricsService::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

QString LyricsService::cacheFile(const TrackRecord &track) const
{
    return QDir(m_cachePath).filePath(
        QStringLiteral("%1-%2.lrc").arg(track.source, track.providerId));
}
