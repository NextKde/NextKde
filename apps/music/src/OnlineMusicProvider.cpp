#include "OnlineMusicProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrlQuery>

#include <algorithm>
#include <utility>

namespace {

QString joinedArtists(const QJsonArray &artists)
{
    QStringList names;
    for (const QJsonValue &value : artists) {
        const QString name = value.toObject().value(QStringLiteral("name")).toString();
        if (!name.isEmpty())
            names.append(name);
    }
    return names.join(QStringLiteral(" / "));
}

void setOutputError(QString *target, const QString &message)
{
    if (target)
        *target = message;
}

int searchMatchScore(const TrackRecord &track, const QStringList &terms)
{
    int score = 0;
    const QStringList artists = track.artist.split(QStringLiteral(" / "),
                                                   Qt::SkipEmptyParts);
    for (const QString &term : terms) {
        if (track.title.compare(term, Qt::CaseInsensitive) == 0)
            score += 12;
        else if (track.title.contains(term, Qt::CaseInsensitive))
            score += 5;

        bool exactArtist = false;
        for (const QString &artist : artists) {
            if (artist.compare(term, Qt::CaseInsensitive) == 0) {
                exactArtist = true;
                break;
            }
        }
        if (exactArtist)
            score += 12;
        else if (track.artist.contains(term, Qt::CaseInsensitive))
            score += 6;
        if (track.album.contains(term, Qt::CaseInsensitive))
            score += 1;
    }
    return score;
}

} // namespace

OnlineMusicProvider::OnlineMusicProvider(QObject *parent)
    : QObject(parent)
{
}

bool OnlineMusicProvider::searching() const { return m_searching; }
QString OnlineMusicProvider::errorMessage() const { return m_errorMessage; }

void OnlineMusicProvider::search(const QString &query, int limit)
{
    const QString cleaned = query.trimmed();
    ++m_generation;
    if (QNetworkReply *reply = std::exchange(m_reply, nullptr)) {
        reply->abort();
        reply->deleteLater();
    }
    if (cleaned.isEmpty()) {
        setSearching(false);
        setError({});
        emit resultsReady({});
        return;
    }

    setSearching(true);
    setError({});
    QNetworkRequest request(QUrl(QStringLiteral("https://music.163.com/api/search/get/web")));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    request.setRawHeader("Referer", "https://music.163.com/");
    request.setRawHeader("User-Agent", "Mozilla/5.0 KOS-Music/1.0");
    request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    QUrlQuery form;
    form.addQueryItem(QStringLiteral("s"), cleaned);
    form.addQueryItem(QStringLiteral("type"), QStringLiteral("1"));
    form.addQueryItem(QStringLiteral("offset"), QStringLiteral("0"));
    form.addQueryItem(QStringLiteral("total"), QStringLiteral("true"));
    form.addQueryItem(QStringLiteral("limit"), QString::number(std::clamp(limit, 1, 50)));
    const quint64 generation = m_generation;
    QNetworkReply *reply = m_network.post(
        request, form.toString(QUrl::FullyEncoded).toUtf8());
    m_reply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, cleaned, generation, reply] {
        if (m_reply == reply)
            m_reply = nullptr;
        if (generation != m_generation) {
            reply->deleteLater();
            return;
        }
        setSearching(false);
        if (reply->error() != QNetworkReply::NoError) {
            setError(tr("Online search failed: %1").arg(reply->errorString()));
            emit resultsReady({});
            reply->deleteLater();
            return;
        }
        QString parseError;
        const QList<TrackRecord> tracks =
            parseNeteaseSearch(reply->readAll(), &parseError, cleaned);
        setError(parseError);
        emit resultsReady(tracks);
        reply->deleteLater();
    });
}

QList<TrackRecord> OnlineMusicProvider::parseNeteaseSearch(const QByteArray &payload,
                                                            QString *errorMessage,
                                                            const QString &query)
{
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setOutputError(errorMessage, QObject::tr("The search service returned invalid data"));
        return {};
    }
    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("code")).toInt(200) != 200) {
        setOutputError(errorMessage, QObject::tr("The search service rejected the request"));
        return {};
    }

    QList<TrackRecord> tracks;
    const QJsonArray songs = root.value(QStringLiteral("result")).toObject()
                                 .value(QStringLiteral("songs")).toArray();
    tracks.reserve(songs.size());
    for (const QJsonValue &value : songs) {
        const QJsonObject song = value.toObject();
        const QString providerId = QString::number(song.value(QStringLiteral("id")).toVariant()
                                                       .toLongLong());
        if (providerId == QLatin1String("0") || providerId.isEmpty())
            continue;
        const QJsonObject album = song.value(QStringLiteral("album")).toObject();
        const QString artist = joinedArtists(song.value(QStringLiteral("artists")).toArray());
        TrackRecord track;
        track.id = -1;
        track.source = QStringLiteral("wy");
        track.providerId = providerId;
        track.path = QStringLiteral("lx://wy/%1").arg(providerId);
        track.title = song.value(QStringLiteral("name")).toString();
        track.artist = artist;
        track.albumArtist = artist;
        track.album = album.value(QStringLiteral("name")).toString();
        track.artworkUrl = album.value(QStringLiteral("picUrl")).toString();
        track.durationMs = song.value(QStringLiteral("duration")).toVariant().toLongLong();
        if (track.durationMs <= 0)
            track.durationMs = song.value(QStringLiteral("dt")).toVariant().toLongLong();

        const qint64 totalSeconds = std::max<qint64>(0, track.durationMs / 1000);
        const QString interval = QStringLiteral("%1:%2")
                                     .arg(totalSeconds / 60, 2, 10, QLatin1Char('0'))
                                     .arg(totalSeconds % 60, 2, 10, QLatin1Char('0'));

        QJsonArray qualitys;
        QJsonObject legacyQualitys;
        const auto addQuality = [&song, &qualitys, &legacyQualitys](
                                    const QString &field, const QString &type) {
            const QJsonObject audio = song.value(field).toObject();
            if (audio.isEmpty() || legacyQualitys.contains(type))
                return;
            const qint64 size = audio.value(QStringLiteral("size")).toVariant().toLongLong();
            QJsonObject quality{{QStringLiteral("type"), type}};
            QJsonObject details;
            if (size > 0) {
                quality.insert(QStringLiteral("size"), QString::number(size));
                details.insert(QStringLiteral("size"), QString::number(size));
            }
            qualitys.append(quality);
            legacyQualitys.insert(type, details);
        };
        addQuality(QStringLiteral("lMusic"), QStringLiteral("128k"));
        addQuality(QStringLiteral("bMusic"), QStringLiteral("128k"));
        addQuality(QStringLiteral("mMusic"), QStringLiteral("128k"));
        addQuality(QStringLiteral("hMusic"), QStringLiteral("320k"));
        if (qualitys.isEmpty()) {
            qualitys.append(QJsonObject{{QStringLiteral("type"), QStringLiteral("128k")}});
            legacyQualitys.insert(QStringLiteral("128k"), QJsonObject{});
        }

        QJsonObject sourceData{
            {QStringLiteral("id"), providerId},
            {QStringLiteral("songmid"), providerId},
            {QStringLiteral("songId"), providerId},
            {QStringLiteral("name"), track.title},
            {QStringLiteral("singer"), track.artist},
            {QStringLiteral("source"), track.source},
            {QStringLiteral("interval"), interval},
            {QStringLiteral("img"), track.artworkUrl},
            {QStringLiteral("albumId"), QString::number(
                 album.value(QStringLiteral("id")).toVariant().toLongLong())},
            {QStringLiteral("albumName"), track.album},
            {QStringLiteral("types"), qualitys},
            {QStringLiteral("_types"), legacyQualitys},
            {QStringLiteral("typeUrl"), QJsonObject{}},
            {QStringLiteral("meta"), QJsonObject{
                 {QStringLiteral("songId"), providerId},
                 {QStringLiteral("albumName"), track.album},
                 {QStringLiteral("albumId"), QString::number(
                      album.value(QStringLiteral("id")).toVariant().toLongLong())},
                 {QStringLiteral("picUrl"), track.artworkUrl},
                 {QStringLiteral("qualitys"), qualitys},
                 {QStringLiteral("_qualitys"), legacyQualitys},
             }},
        };
        track.sourceData = QString::fromUtf8(
            QJsonDocument(sourceData).toJson(QJsonDocument::Compact));
        tracks.append(track);
    }
    const QStringList terms = query.split(QRegularExpression(QStringLiteral("\\s+")),
                                          Qt::SkipEmptyParts);
    if (!terms.isEmpty()) {
        std::stable_sort(tracks.begin(), tracks.end(), [&terms](const TrackRecord &left,
                                                                const TrackRecord &right) {
            return searchMatchScore(left, terms) > searchMatchScore(right, terms);
        });
    }
    if (tracks.isEmpty())
        setOutputError(errorMessage, QObject::tr("No matching songs were found"));
    else
        setOutputError(errorMessage, {});
    return tracks;
}

void OnlineMusicProvider::setSearching(bool searching)
{
    if (m_searching == searching)
        return;
    m_searching = searching;
    emit searchingChanged();
}

void OnlineMusicProvider::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}
