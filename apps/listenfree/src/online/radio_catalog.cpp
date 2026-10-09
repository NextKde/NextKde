#include "radio_catalog.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QMap>
#include <QRegularExpression>
#include <QSet>
#include <QUrl>
#include <QXmlStreamReader>
#include <algorithm>

namespace listenfree::online {
QString radioProgramTitle(const QString& metadata) {
    const auto input = metadata.trimmed();
    // Qmmp extracts StreamTitle, but iHeart also places quoted attributes inside
    // that value. Present its text/title/song, never the tracking fields.
    static const QRegularExpression structured(R"(^[A-Za-z][A-Za-z0-9_-]*\s*=)");
    if (!structured.match(input).hasMatch()) return input;
    static const QRegularExpression field(R"meta(([A-Za-z][A-Za-z0-9_-]*)\s*=\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'))meta");
    static const QRegularExpression escapedQuote(R"meta(\\(["'\\]))meta");
    QMap<QString, QString> fields;
    qsizetype position = 0;
    while (position < input.size()) {
        while (position < input.size() && (input[position].isSpace() || input[position] == ';' || input[position] == ',')) ++position;
        if (position == input.size()) break;
        const auto match = field.match(input, position);
        if (!match.hasMatch() || match.capturedStart() != position) return {};
        auto value = match.captured(match.capturedStart(2) >= 0 ? 2 : 3);
        value.replace(escapedQuote, QStringLiteral("\\1"));
        fields[match.captured(1).toLower()] = value.trimmed();
        position = match.capturedEnd();
    }
    QString title;
    for (const auto* key : {"text", "title", "song"}) {
        title = fields.value(QLatin1String(key));
        if (!title.isEmpty()) break;
    }
    if (title.isEmpty()) return {};
    const auto artist = fields.value("artist");
    return artist.isEmpty() || title.startsWith(artist + " - ") ? title : artist + " - " + title;
}
bool radioHttpUrl(const QString& value) {
    const QUrl url(value);
    return url.isValid() && !url.host().isEmpty() && (url.scheme()=="http" || url.scheme()=="https");
}
QVariantMap radioTrack(const RadioStation& s, const QString& provider) {
    return {{"trackId",provider+":"+s.id},{"radioId",s.id},{"radioProvider",provider},
            {"title",s.title},{"artist",s.subtitle},{"album",s.tags},{"tags",s.tags},
            {"remoteUrl",s.url},{"artwork",s.artwork},{"codec",s.codec},{"bitrate",s.bitrate},
            {"isLive",true},{"durationMs",0},{"duration",QStringLiteral("直播")}};
}
QVector<RadioStation> icecastStations(const QByteArray& bytes, QString* error) {
    QVector<RadioStation> result;
    QXmlStreamReader xml(bytes);
    QSet<QString> seen;
    while (!xml.atEnd()) {
        xml.readNext();
        if (!xml.isStartElement() || xml.name()!=u"entry") continue;
        RadioStation station;
        while(xml.readNextStartElement()) {
            const auto name=xml.name().toString();
            const auto value=xml.readElementText(QXmlStreamReader::SkipChildElements).trimmed();
            if(name=="server_name") station.title=value.left(240);
            else if(name=="listen_url") station.url=value;
            else if(name=="genre") station.tags=value.left(300);
            else if(name=="server_type") station.codec=value;
            else if(name=="bitrate") station.bitrate=value.toInt();
        }
        if(!radioHttpUrl(station.url) || station.title.isEmpty() || seen.contains(station.url)) continue;
        seen.insert(station.url); station.id=station.url;
        station.subtitle=QStringLiteral("Icecast · %1").arg(station.tags.isEmpty()?QStringLiteral("网络广播"):station.tags);
        result.append(std::move(station));
    }
    if(xml.hasError()) { if(error)*error=QStringLiteral("Icecast 目录格式无效，请重试"); return {}; }
    std::sort(result.begin(),result.end(),[](const auto& a,const auto& b) {return a.title.compare(b.title,Qt::CaseInsensitive)<0;});
    return result;
}
QVariantList radioBrowserStations(const QByteArray& bytes) {
    QVariantList result;
    for(const auto& value:QJsonDocument::fromJson(bytes).array()) {
        const auto row=value.toObject();
        RadioStation s;
        s.id=row.value("stationuuid").toString(); s.title=row.value("name").toString().trimmed();
        s.url=row.value("url_resolved").toString(row.value("url").toString());
        if(s.id.isEmpty() || !radioHttpUrl(s.url))continue;
        s.tags=row.value("tags").toString();s.codec=row.value("codec").toString();s.bitrate=row.value("bitrate").toInt();
        s.artwork=row.value("favicon").toString();
        if(!radioHttpUrl(s.artwork))s.artwork.clear();
        s.subtitle=QStringList{row.value("country").toString(),row.value("language").toString()}.join(" · ");
        auto station=radioTrack(s,"radiobrowser");station["radioHls"]=row.value("hls").toInt()!=0;
        result.append(station);
    }
    return result;
}
QVariantList neteaseBroadcastStations(const QJsonObject& data) {
    QVariantList result;
    for(const auto& value:data.value("list").toArray()) {
        const auto row=value.toObject();
        RadioStation s; s.id=row.value("id").toVariant().toString();s.title=row.value("name").toString();
        s.subtitle=row.value("regionName").toString();s.artwork=row.value("coverUrl").toString();
        auto station=radioTrack(s,"netease-broadcast");station["score"]=row.value("score").toVariant();
        result.append(station);
    }
    return result;
}
QVariantList neteasePodcasts(const QJsonObject& root) {
    auto rows=root.value("djRadios").toArray();
    if(rows.isEmpty())rows=root.value("result").toObject().value("djRadios").toArray();
    QVariantList result;
    for(const auto& v:rows) {
        const auto row=v.toObject(); const auto dj=row.value("dj").toObject();
        result.append(QVariantMap{{"radioId",row.value("id").toVariant().toString()},
            {"title",row.value("name").toString()},{"artist",dj.value("nickname").toString()},
            {"artwork",row.value("picUrl").toString()},{"tags",row.value("category").toString()},
            {"subtitle",row.value("desc").toString()},{"programCount",row.value("programCount").toInt()},
            {"kind","podcast"},{"radioProvider","netease-podcast"}});
    }
    return result;
}
QVariantList neteasePrograms(const QJsonObject& root) {
    QVariantList result;
    for(const auto& v:root.value("programs").toArray()) {
        const auto row=v.toObject();const auto song=row.value("mainSong").toObject();
        const auto id=row.value("mainTrackId").toVariant().toString();
        const qint64 ms=row.value("duration").toVariant().toLongLong();
        result.append(QVariantMap{{"trackId","netease-program:"+id},{"radioId",id},{"radioProvider","netease-program"},
            {"title",row.value("name").toString()},{"artist",row.value("dj").toObject().value("nickname").toString()},
            {"album",row.value("radio").toObject().value("name").toString()},
            {"artwork",row.value("coverUrl").toString()},{"remoteUrl",song.value("mp3Url").toString()},
            {"durationMs",ms},{"duration",QString("%1:%2").arg(ms/60000).arg(ms/1000%60,2,10,QChar('0'))},
            {"isLive",false}});
    }
    return result;
}
}
