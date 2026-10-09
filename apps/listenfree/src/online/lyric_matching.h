#pragma once
#include <QVariantMap>
#include <QRegularExpression>
#include <QHash>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include "online/kuwo_lyrics.h"
#include <cmath>
#include <algorithm>

namespace listenfree::online {
// Adapt the existing WY word tuples to the LX format consumed by parseTimedLyrics.
inline QString neteaseWordLyrics(const QString& source) {
    static const QRegularExpression lineStamp(R"(^\[(\d+),\d+\])");
    static const QRegularExpression wordStamp(R"(\((\d+),(\d+),\d+\))");
    QStringList lines;
    for(const auto& line:source.split('\n')) {
        const auto stamp=lineStamp.match(line);if(!stamp.hasMatch())continue;
        const qint64 start=stamp.captured(1).toLongLong();
        QString body=line.mid(stamp.capturedLength());
        auto tokens=wordStamp.globalMatch(body);QString converted;qsizetype cursor=0;
        while(tokens.hasNext()) {
            const auto token=tokens.next();converted+=body.mid(cursor,token.capturedStart()-cursor);
            converted+=QString("<%1,%2>").arg(qMax(qint64(0),token.captured(1).toLongLong()-start)).arg(token.captured(2));
            cursor=token.capturedEnd();
        }
        converted+=body.mid(cursor);
        lines.append(QString("[%1:%2.%3]%4").arg(start/60000,2,10,QChar('0')).arg(start/1000%60,2,10,QChar('0')).arg(start%1000,3,10,QChar('0')).arg(converted));
    }
    return lines.join('\n');
}
inline QString packLyricTracks(const QString& lrc, const QString& words, const QString& translation, const QString& romanization) {
    if(words.isEmpty() && translation.isEmpty() && romanization.isEmpty())return lrc;
    if(lrc.isEmpty()&&words.isEmpty())return {};
    QStringList tracks;
    for(const auto& pair:{qMakePair(QString("awlrc"),words),qMakePair(QString("lrc"),lrc),qMakePair(QString("tlrc"),translation),qMakePair(QString("rlrc"),romanization)})
        if(!pair.second.isEmpty())tracks.append(pair.first+":"+QString::fromLatin1(pair.second.toUtf8().toBase64()));
    return "[awlrc:"+tracks.join(',')+"]\n"+lrc;
}
inline QString matchedLyricBundle(const QJsonObject& data) {
    const auto track=[&](const QString& key){return data.value(key).toObject().value("lyric").toString().trimmed();};
    const auto lrc=track("lrc"),words=neteaseWordLyrics(track("yrc"));
    const auto translation=!words.isEmpty()&&!track("ytlrc").isEmpty()?track("ytlrc"):track("tlyric");
    const auto romanization=!words.isEmpty()&&!track("yromalrc").isEmpty()?track("yromalrc"):track("romalrc");
    return packLyricTracks(lrc,words,translation,romanization);
}
inline QStringList matchedLyricFeatures(const QString& text) {
    const auto rows=parseTimedLyrics(text);bool words=false,translation=false,romanization=false;
    for(const auto& value:rows) {
        const auto row=value.toMap();words|=!row.value("words").toList().isEmpty();
        translation|=!row.value("translation").toString().trimmed().isEmpty();
        romanization|=!row.value("romanization").toString().trimmed().isEmpty();
    }
    QStringList features;
    features.append(text.isEmpty()?"无歌词":words?"逐字":rows.isEmpty()?"纯文本":"逐行");
    if(translation)features.append("翻译");
    if(romanization)features.append("罗马音");
    return features;
}
// Provider responses can contain timestamps but only an instrumental/no-lyrics
// notice, or just credits. They are not usable lyrics to offer for matching.
inline bool hasUsableMatchedLyrics(const QString& text) {
    static const QRegularExpression bodyCharacter("[\\p{L}\\p{N}]");
    static const QRegularExpression metadata(R"(^\[[A-Za-z]+:.*\]$)");
    static const QRegularExpression credits(
        R"(^(?:作词|作曲|编曲|词|曲|演唱|歌手|制作人|制作|监制|出品|发行|词曲|lyrics?(?:\s+by)?|composer|artist|title|album|written\s+by)\s*[:：])",
        QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression missing(
        R"(^(?:(?:纯音乐|此歌曲为没有填词的纯音乐|此歌曲为纯音乐|暂无歌词|暂时没有歌词|暂无滚动歌词|没有歌词|歌词暂缺|无歌词|未找到歌词|歌词不存在)(?:[，,\s]*(?:请欣赏|请您欣赏))?|instrumental(?:\s+only)?|no\s+lyrics(?:\s+(?:available|found))?|lyrics\s+(?:not\s+(?:found|available)|unavailable))\s*[。.!！]?$)",
        QRegularExpression::CaseInsensitiveOption);
    const auto usable=[&](QString line) {
        line=line.trimmed();
        return line.contains(bodyCharacter)&&!metadata.match(line).hasMatch()
            &&!credits.match(line).hasMatch()&&!missing.match(line).hasMatch();
    };
    const auto rows=parseTimedLyrics(text);
    if(!rows.isEmpty()) {
        for(const auto& row:rows)if(usable(row.toMap().value("text").toString()))return true;
        return false;
    }
    for(const auto& line:text.split('\n'))if(usable(line))return true;
    return false;
}
inline QString matchedLyricIdentity(const QString& text) {
    const auto rows=parseTimedLyrics(text);
    // Ignore file headers/album credits when the actual timed content is equal,
    // while preserving distinct translations, word timings and romanization.
    if(!rows.isEmpty())return QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(rows)).toJson(QJsonDocument::Compact));
    QStringList lines;
    for(const auto& line:text.split('\n'))if(!line.trimmed().isEmpty())lines.append(line.trimmed());
    return lines.join('\n');
}
// Narrow port of lx-ta-v2.1-release/services/localLyrics/matching.ts.
inline QString normalizedLyricTitle(QString value) {
    value=value.normalized(QString::NormalizationForm_KC).toCaseFolded();
    value.remove(QRegularExpression("[’'`]"));
    value.replace(QRegularExpression("[\\s\\p{P}\\p{S}]+")," ");
    return value.trimmed();
}
inline double lyricTextSimilarity(QString a,QString b) {
    a=normalizedLyricTitle(a);b=normalizedLyricTitle(b);
    if(a==b)return 1;
    a.remove(' ');b.remove(' ');
    if(a.isEmpty() || b.isEmpty())return 0;
    QHash<QString,int> counts;
    const int an=std::max(1,int(a.size())-1),bn=std::max(1,int(b.size())-1);
    for(int i=0;i<an;++i)++counts[a.mid(i,2)];
    int matches=0;
    for(int i=0;i<bn;++i){auto& n=counts[b.mid(i,2)];if(n>0){--n;++matches;}}
    return 2.0*matches/(an+bn);
}
inline double lyricTitleSimilarity(const QString& left, const QString& right) {
    static const QRegularExpression versions(
        "\\b(live|remaster(?:ed)?|instrumental|karaoke|acoustic|mono|stereo|radio edit|extended|mix|version|ver\\.?|伴奏|纯音乐|现场|重制)\\b",
        QRegularExpression::CaseInsensitiveOption | QRegularExpression::UseUnicodePropertiesOption);
    auto a=normalizedLyricTitle(left), b=normalizedLyricTitle(right);
    const auto versionWords=[&](const QString& text) {
        QStringList words;
        auto matches=versions.globalMatch(text);
        while(matches.hasNext()) words.append(matches.next().captured());
        words.sort();
        return words;
    };
    const auto penalty=versionWords(a)==versionWords(b)?0.0:.18;
    const auto base=lyricTextSimilarity(a,b);
    a.remove(versions);b.remove(versions);
    return std::max(base,lyricTextSimilarity(a,b)-penalty);
}
inline int lyricCandidateScore(const QVariantMap& query,const QVariantMap& candidate) {
    const double title=lyricTitleSimilarity(query.value("title").toString(),candidate.value("title").toString());
    const double artist=query.value("artist").toString().isEmpty() || candidate.value("artist").toString().isEmpty()? .55:lyricTextSimilarity(query.value("artist").toString(),candidate.value("artist").toString());
    const double album=query.value("album").toString().isEmpty() || candidate.value("album").toString().isEmpty()? .55:lyricTextSimilarity(query.value("album").toString(),candidate.value("album").toString());
    const double left=query.value("durationMs").toDouble()/1000,right=candidate.value("durationMs").toDouble()/1000,diff=std::abs(left-right);
    const double duration=!left||!right?.55:diff<=2?1:diff<=5?.9:diff<=10?.7:diff<=20?.35:std::max(0.0,1-diff/std::max(left,right)*3);
    return int(std::round(title*45+artist*25+duration*22+album*8));
}
inline bool manualLyricQuery(const QVariantMap& track, const QString& query) {
    const auto term = normalizedLyricTitle(query);
    const auto title = normalizedLyricTitle(track.value("title").toString());
    const auto artist = normalizedLyricTitle(track.value("artist").toString());
    return track.value("queryFromFilename").toBool() || (term != title
        && term != (title+' '+artist).trimmed() && term != (artist+' '+title).trimmed());
}
inline QStringList lyricSearchQueries(const QVariantMap& track, const QString& query) {
    QStringList queries{query.simplified()};
    if(!manualLyricQuery(track, query)) {
        const auto title = track.value("title").toString().simplified();
        if(!title.isEmpty() && !queries.contains(title, Qt::CaseInsensitive)) queries.append(title);
    }
    // An empty/transient first response can succeed on the same keyword too.
    // Keep this to one retry, not an unbounded auto-retry loop.
    if(queries.size() == 1) queries.append(queries.first());
    return queries;
}
inline QVariantList rankLyricCandidates(const QVariantMap& track, const QString& query, const QVariantList& rows) {
    const bool manual = manualLyricQuery(track, query);
    QVariantList ranked;
    for(const auto& value : rows) {
        auto row = value.toMap();
        auto title = row.value("title").toString();
        // Community entries may carry localized/alternative song names.
        const auto target = manual ? query : track.value("title").toString();
        for(const auto& alias : row.value("titleAliases").toStringList())
            if(lyricTitleSimilarity(target, alias) > lyricTitleSimilarity(target, title)) title = alias;
        row["title"] = title;
        const double textMatch = qMax(lyricTextSimilarity(query, title),
            qMax(lyricTextSimilarity(query, title+' '+row.value("artist").toString()),
                 lyricTextSimilarity(query, row.value("artist").toString()+' '+title)));
        const auto titleMatch = lyricTitleSimilarity(track.value("title").toString(), title);
        const int score = manual ? qRound(100*textMatch) : lyricCandidateScore(track, row);
        if(manual ? textMatch < .45 : (titleMatch < .55 || score < 55)) continue;
        const auto wantedArtist = normalizedLyricTitle(track.value("artist").toString());
        const auto foundArtist = normalizedLyricTitle(row.value("artist").toString());
        if(!manual && !wantedArtist.isEmpty() && !foundArtist.isEmpty()) {
            // Same-name songs by different artists are not alternative lyrics
            // for the current recording. Preserve missing artist metadata and
            // collaborations (e.g. "Artist / Guest") without accepting Muse's
            // "Animals" when matching the Maroon 5 recording.
            const auto containsArtist = (' '+foundArtist+' ').contains(' '+wantedArtist+' ')
                || (' '+wantedArtist+' ').contains(' '+foundArtist+' ');
            if(!containsArtist && lyricTextSimilarity(wantedArtist, foundArtist) < .3) continue;
        }
        const auto left = track.value("durationMs").toLongLong(), right = row.value("durationMs").toLongLong();
        if(!manual && left > 0 && right > 0 && qAbs(left-right) > qMax(qint64(20000), left/10)) continue;
        row["score"] = score;
        ranked.append(row);
    }
    // Rank each provider independently: a well-tagged reissue on one service
    // must not discard the correct recording with sparse metadata elsewhere.
    std::stable_sort(ranked.begin(), ranked.end(), [](const auto& a, const auto& b) {
        return a.toMap().value("score").toInt() > b.toMap().value("score").toInt();
    });
    return ranked;
}
}
