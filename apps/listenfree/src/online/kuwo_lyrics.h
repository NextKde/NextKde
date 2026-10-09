#pragma once
#include <QByteArray>
#include <QRegularExpression>
#include <QVariantList>
#include <QMap>
#include <zlib.h>
#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif
namespace listenfree::online {
// Narrow native adaptation of LX musicSdk/kw/lyric.js, util.js and kw_decodeLyric.ts.
inline QByteArray kuwoXor(QByteArray bytes) {
    constexpr char key[]="yeelion";
    for (qsizetype i=0;i<bytes.size();++i) bytes[i]=char(bytes.at(i)^key[i%7]);
    return bytes;
}
inline QString decodeKuwoLyrics(const QByteArray& response) {
    const auto boundary=response.indexOf("\r\n\r\n");
    if (!response.startsWith("tp=content") || boundary<0 || response.size()>2*1024*1024) return {};
    QByteArray decoded(8*1024*1024,Qt::Uninitialized);
    uLongf length=static_cast<uLongf>(decoded.size());
    if (uncompress(reinterpret_cast<Bytef*>(decoded.data()),&length,
        reinterpret_cast<const Bytef*>(response.constData()+boundary+4),static_cast<uLong>(response.size()-boundary-4))!=Z_OK) return {};
    decoded.resize(static_cast<qsizetype>(length));
    if (response.left(boundary).contains("lrcx=1")) {
        auto result=QByteArray::fromBase64Encoding(decoded,QByteArray::AbortOnBase64DecodingErrors);
        if (!result) return {};
        decoded=kuwoXor(result.decoded);
    }
#ifdef Q_OS_WIN
    const int size=MultiByteToWideChar(54936,0,decoded.data(),int(decoded.size()),nullptr,0);
    if (size<=0) return {};
    std::wstring wide(size,L'\0');
    MultiByteToWideChar(54936,0,decoded.data(),int(decoded.size()),wide.data(),size);
    return QString::fromStdWString(wide);
#else
    return QString::fromUtf8(decoded);
#endif
}
inline QVariantList parseTimedLyrics(const QString& raw) {
    // LX embeds independent base64 tracks in one comma-separated awlrc tag.
    // Its word tuples are offset,duration; Kuwo's encrypted tuples are different.
    static const QRegularExpression embedded(R"(\[awlrc:([^\]]+)\])");
    const auto bundle = embedded.match(raw);
    if (bundle.hasMatch()) {
        QMap<QString, QString> tracks;
        for (const auto& part : bundle.captured(1).split(',')) {
            const auto colon = part.indexOf(':');
            if (colon < 0) continue;
            const auto decoded = QByteArray::fromBase64Encoding(part.mid(colon+1).toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
            if (decoded && decoded.decoded.size() <= 2*1024*1024)
                tracks[part.left(colon)] = QString::fromUtf8(decoded.decoded);
        }
        auto rows = parseTimedLyrics(tracks.value("awlrc", tracks.value("lrc", QString(raw).remove(embedded))));
        for (const auto& pair : {qMakePair(QString("tlrc"),QString("translation")),qMakePair(QString("rlrc"),QString("romanization"))}) {
            QMap<qint64,QString> secondary;
            for (const auto& v : parseTimedLyrics(tracks.value(pair.first))) {
                const auto row=v.toMap(); secondary[row.value("timeMs").toLongLong()]=row.value("text").toString();
            }
            for (auto& v : rows) { auto row=v.toMap();row[pair.second]=secondary.value(row.value("timeMs").toLongLong());v=row; }
        }
        return rows;
    }
    static const QRegularExpression stamp(R"(\[(\d+):(\d+(?:\.\d+)?)\])");
    static const QRegularExpression tag(R"(\[kuwo:([0-7]+)\])");
    static const QRegularExpression wordTag(R"(<(-?\d+),(-?\d+)(?:,-?\d+)?>)");
    const auto encoding=tag.match(raw);
    const int code=encoding.hasMatch()?encoding.captured(1).toInt(nullptr,8):11;
    const double divisor1=2.0*(code/10), divisor2=2.0*(code%10);
    QMap<qint64,QVariantMap> lines;
    for (const auto& line:raw.split('\n')) {
        auto times=stamp.globalMatch(line);
        if (!times.hasNext()) continue;
        const QString body=QString(line).remove(stamp).trimmed();
        const QString text=QString(body).remove(wordTag).trimmed();
        while (times.hasNext()) {
            const auto time=times.next();
            const qint64 start=qRound64((time.captured(1).toInt()*60+time.captured(2).toDouble())*1000);
            if (lines.contains(start)) {
                if (text!=lines[start].value("text").toString()) lines[start]["translation"]=text;
                continue;
            }
            QVariantList words;
            if (divisor1>0 && divisor2>0) {
                auto matches=wordTag.globalMatch(body);
                QList<QRegularExpressionMatch> tags;
                while (matches.hasNext()) tags.push_back(matches.next());
                for (qsizetype i=0;i<tags.size();++i) {
                    const auto& token=tags[i];
                    const double a=token.captured(1).toDouble(), b=token.captured(2).toDouble();
                    const qint64 wordStart=start+qRound64(encoding.hasMatch()?std::abs((a+b)/divisor1):std::max(0.0,a));
                    const qint64 wordEnd=wordStart+qRound64(encoding.hasMatch()?std::abs((a-b)/divisor2):std::max(0.0,b));
                    const auto textEnd=i+1<tags.size()?tags[i+1].capturedStart():body.size();
                    const auto word=body.mid(token.capturedEnd(),textEnd-token.capturedEnd());
                    if (word.isEmpty()) continue;
                    if (!words.isEmpty()) {
                        auto previous=words.last().toMap();
                        previous["endMs"]=std::max(previous.value("startMs").toLongLong(),std::min(previous.value("endMs").toLongLong(),wordStart));
                        words.last()=previous;
                    }
                    words.append(QVariantMap{{"text",word},{"startMs",wordStart},{"endMs",wordEnd}});
                }
            }
            lines.insert(start,{{"timeMs",start},{"text",text},{"translation",""},{"words",words}});
        }
    }
    QVariantList result;
    for (auto i=lines.cbegin();i!=lines.cend();++i) {
        auto row=i.value(); const auto next=std::next(i);
        row["endMs"]=next==lines.cend()?i.key()+10000:next.key(); result.append(row);
    }
    return result;
}
}
