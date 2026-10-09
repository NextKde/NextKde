#include "online/lyric_sources.h"
#include "online/lyric_matching.h"
#include "online/platform_catalog.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrlQuery>
#include <QTextDocumentFragment>
#include <QXmlStreamReader>
namespace qqlyrics {
#include "third_party/qqmusic_des/des.h"
}

namespace listenfree::online {
namespace {
QString stamp(qint64 ms) { return QString("[%1:%2.%3]").arg(ms/60000,2,10,QChar('0')).arg(ms/1000%60,2,10,QChar('0')).arg(ms%1000,3,10,QChar('0')); }
QString inflateLyrics(const QByteArray& bytes) {
    if(bytes.isEmpty() || bytes.size()>2*1024*1024)return {};
    QByteArray output(8*1024*1024,Qt::Uninitialized);uLongf size=static_cast<uLongf>(output.size());
    if(uncompress(reinterpret_cast<Bytef*>(output.data()),&size,reinterpret_cast<const Bytef*>(bytes.constData()),static_cast<uLong>(bytes.size()))!=Z_OK)return {};
    return QString::fromUtf8(output.constData(),static_cast<qsizetype>(size));
}
QString plainTrack(const QString& text) { auto out=text;out.remove(QRegularExpression(R"(<\d+,\d+>)"));return out; }
QNetworkReply* request(QNetworkAccessManager& network,const QUrl& url,const QJsonObject& body={}) {
    QNetworkRequest req(url);req.setTransferTimeout(15000);
    req.setRawHeader("User-Agent","ListenFree/0.3.0 (desktop lyric matching)");
    if(url.host().endsWith("qq.com"))req.setRawHeader("Referer","https://y.qq.com/");
    req.setHeader(QNetworkRequest::ContentTypeHeader,"application/json");
    auto* reply=body.isEmpty()?network.get(req):network.post(req,QJsonDocument(body).toJson(QJsonDocument::Compact));
    QObject::connect(reply,&QIODevice::readyRead,reply,[reply]{if(reply->bytesAvailable()>2*1024*1024)reply->abort();});
    return reply;
}
QUrl queryUrl(const QString& base,const QList<QPair<QString,QString>>& params) { QUrl url(base);QUrlQuery query;query.setQueryItems(params);url.setQuery(query);return url; }
}
QString lyricSourceName(const QString& source) {
    return QMap<QString,QString>{{"wy","网易云音乐"},{"tx","QQ 音乐"},{"kg","酷狗音乐"},{"kw","酷我音乐"},{"mg","咪咕音乐"},{"lrclib","LRCLIB"},{"amll","AMLL TTML"}}.value(source,source);
}
QNetworkReply* lyricSearchRequest(QNetworkAccessManager& network,const QString& source,const QVariantMap& track,const QString& query) {
    if(source=="wy"||source=="tx"||source=="mg")return platformRequest(network,source,"search",query);
    if(source=="amll" || source=="lrclib") {
        const bool structured = !manualLyricQuery(track,query) && !track.value("title").toString().isEmpty();
        QList<QPair<QString,QString>> params;
        if(structured) {
            params.append({source=="amll"?"musicName":"track_name",track.value("title").toString()});
            if(normalizedLyricTitle(query)!=normalizedLyricTitle(track.value("title").toString()) && !track.value("artist").toString().isEmpty())
                params.append({source=="amll"?"artistName":"artist_name",track.value("artist").toString()});
        } else params.append({"q",query});
        if(source=="amll")params.emplaceBack("pageSize","30");
        return request(network,queryUrl(source=="amll"?"https://api.amll.dev/v1/lyrics/search":"https://lrclib.net/api/search",params));
    }
    if(source=="kg")return request(network,queryUrl("https://lyrics.kugou.com/search",{{"ver","1"},{"man","yes"},{"client","pc"},{"keyword",query},{"duration",manualLyricQuery(track,query)?QString("0"):track.value("durationMs",0).toString()}}));
    // The legacy defaults rank partial matches/remixes ahead of the requested
    // recording. Use the mobile search contract also used by musicdl; include
    // catalog entries independently of their audio playback availability.
    if(source=="kw")return request(network,queryUrl("https://search.kuwo.cn/r.s",{{"encoding","utf8"},{"rformat","json"},
        {"client","kt"},{"all",query},{"pn","0"},{"rn","30"},{"ft","music"},{"vipver","1"},
        {"cluster","0"},{"strategy","2012"},{"mobi","1"},{"issubtitle","1"},{"show_copyright_off","1"}}));
    return nullptr;
}
QVariantList lyricSearchResults(const QString& source,const QByteArray& response) {
    QVariantList rows;
    if(source=="wy"||source=="tx"||source=="mg")rows=platformSongs(source,platformJson(response));
    else if(source=="amll") {
        const auto object=platformJson(response);
        if(object.value("status").toInt()!=200)return {};
        for(const auto& item:object.value("data").toObject().value("items").toArray()) {
            const auto value=item.toObject();
            const auto strings=[&](const char* key) { QStringList result;for(const auto& text:value.value(key).toArray())if(text.isString())result.append(text.toString());return result; };
            const auto titles=strings("musicNames");
            if(titles.isEmpty() || !value.contains("id"))continue;
            const auto filename=value.value("filename").toString();
            rows.append(QVariantMap{{"rid",value.value("id").toVariant().toString()},{"title",titles.first()},
                {"titleAliases",titles},{"artist",strings("artistNames").join(" / ")},{"album",strings("albumNames").join(" / ")},
                {"creator",strings("authorUsernames").join(" / ")},{"filename",filename},
                {"sourceUrl","https://github.com/amll-dev/amll-ttml-db/blob/main/raw-lyrics/"+QString::fromLatin1(QUrl::toPercentEncoding(filename))}});
        }
    }
    else {
        const auto object=platformJson(response);
        const auto array=source=="lrclib"?QJsonDocument::fromJson(response).array():object.value(source=="kg"?"candidates":"abslist").toArray();
        for(const auto& item:array) {
            const auto value=item.toObject();QVariantMap row;
            if(source=="lrclib") {
                if(value.value("instrumental").toBool())continue;
                const auto text=value.value("syncedLyrics").toString().trimmed().isEmpty()?value.value("plainLyrics").toString():value.value("syncedLyrics").toString();
                if(text.trimmed().isEmpty())continue;
                row={{"rid",value.value("id").toVariant().toString()},{"title",value.value("trackName").toString()},{"artist",value.value("artistName").toString()},{"album",value.value("albumName").toString()},{"durationMs",qRound64(value.value("duration").toDouble()*1000)},{"lyricsText",text}};
            } else if(source=="kg") {
                row={{"rid",value.value("id").toVariant().toString()},{"accesskey",value.value("accesskey").toString()},{"title",value.value("song").toString()},{"artist",value.value("singer").toString()},{"durationMs",value.value("duration").toVariant()},{"creator",value.value("nickname").toString()}};
            } else {
                auto id=value.value("MUSICRID").toString();id.remove("MUSIC_");
                row={{"rid",id},{"title",QTextDocumentFragment::fromHtml(value.value("SONGNAME").toString(value.value("NAME").toString())).toPlainText()},{"artist",QTextDocumentFragment::fromHtml(value.value("ARTIST").toString()).toPlainText()},{"album",QTextDocumentFragment::fromHtml(value.value("ALBUM").toString()).toPlainText()},{"durationMs",value.value("DURATION").toVariant().toLongLong()*1000}};
            }
            if(row.value("rid").toString().isEmpty())continue;
            const auto ms=row.value("durationMs").toLongLong();row["duration"]=QString("%1:%2").arg(ms/60000,2,10,QChar('0')).arg(ms/1000%60,2,10,QChar('0'));
            rows.append(row);
        }
    }
    for(auto& item:rows) {
        auto row=item.toMap();row["lyricSource"]=source;row["sourceLabel"]=lyricSourceName(source);
        item=row;
    }
    return rows;
}
QNetworkReply* lyricFetchRequest(QNetworkAccessManager& network,const QString& source,const QVariantMap& candidate) {
    const auto id=candidate.value("rid").toString();
    if(source=="wy")return platformRequest(network,"wy","lyrics",id);
    if(source=="amll" && QRegularExpression("^[0-9]+$").match(id).hasMatch())
        return request(network,queryUrl("https://api.amll.dev/v1/lyrics/get",{{"id",id}}));
    if(source=="mg") {
        auto url=QUrl(candidate.value("lrcUrl").toString());
        if(url.scheme()=="http")url.setScheme("https");
        if(url.scheme()=="https" && (url.host()=="migu.cn" || url.host().endsWith(".migu.cn")))return request(network,url);
        return nullptr;
    }
    if(source=="kg")return request(network,queryUrl("https://lyrics.kugou.com/download",{{"ver","1"},{"client","pc"},{"id",id},{"accesskey",candidate.value("accesskey").toString()},{"fmt","krc"},{"charset","utf8"}}));
    if(source=="kw") {
        const auto data=kuwoXor("user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_"+id.toLatin1()+"&lrcx=1").toBase64();
        return request(network,QUrl("https://newlyric.kuwo.cn/newlyric.lrc?"+QString::fromLatin1(data)));
    }
    if(source=="tx") {
        const auto encode=[&](const char* key){return QString::fromLatin1(candidate.value(key).toString().toUtf8().toBase64());};
        const QJsonObject param{{"albumName",encode("album")},{"crypt",1},{"ct",19},{"cv",2111},{"interval",candidate.value("durationMs").toLongLong()/1000},{"lrc_t",0},{"qrc",1},{"qrc_t",0},{"roma",1},{"roma_t",0},{"singerName",encode("artist")},{"songID",candidate.value("songId").toLongLong()},{"songName",encode("title")},{"trans",1},{"trans_t",0},{"type",0}};
        return request(network,QUrl("https://u.y.qq.com/cgi-bin/musicu.fcg"),{{"comm",QJsonObject{{"ct",11},{"cv",1003006},{"v",1003006},{"tmeAppID","qqmusic"}}},{"req",QJsonObject{{"module","music.musichallSong.PlayLyricInfo"},{"method","GetPlayLyricInfo"},{"param",param}}}});
    }
    return nullptr;
}
QString decodeQrc(const QString& hex) {
    // Cloud QRC envelope from LDDC; QQ's modified DES is the upstream MIT core.
    if(hex.size()>4*1024*1024 || !QRegularExpression("^[a-fA-F0-9]+$").match(hex).hasMatch())return {};
    const auto bytes=QByteArray::fromHex(hex.toLatin1());if(bytes.isEmpty()||bytes.size()%8)return {};
    QByteArray decoded(bytes.size(),Qt::Uninitialized);
    static const auto schedule=[] {
        struct Keys { qqlyrics::BYTE value[3][16][6]; } keys{};
        const qqlyrics::BYTE key[]="!@#)(*$%123ZXC!@!@#)(NHL";
        qqlyrics::three_des_key_setup(key,keys.value,qqlyrics::DES_DECRYPT);return keys;
    }();
    for(qsizetype i=0;i<bytes.size();i+=8)qqlyrics::three_des_crypt(reinterpret_cast<const qqlyrics::BYTE*>(bytes.constData()+i),reinterpret_cast<qqlyrics::BYTE*>(decoded.data()+i),schedule.value);
    return inflateLyrics(decoded);
}
QString qrcWordLyrics(const QString& text) {
    const auto match=QRegularExpression(R"qrc(<Lyric_1\b[^>]*LyricContent="(.*?)"\s*/>)qrc",QRegularExpression::DotMatchesEverythingOption).match(text);
    if(!match.hasMatch())return text;
    const auto content=match.captured(1);QStringList lines;
    static const QRegularExpression linePattern(R"(^\[(\d+),\d+\](.*)$)"),wordPattern(R"((.*?)\((\d+),(\d+)\))");
    for(const auto& line:content.split('\n')) {
        const auto lm=linePattern.match(line.trimmed());if(!lm.hasMatch())continue;
        const auto start=lm.captured(1).toLongLong();auto words=wordPattern.globalMatch(lm.captured(2));QString body;
        while(words.hasNext()) { const auto word=words.next();body+=QString("<%1,%2>%3").arg(qMax(qint64(0),word.captured(2).toLongLong()-start)).arg(word.captured(3),word.captured(1)); }
        lines.append(stamp(start)+(body.isEmpty()?lm.captured(2):body));
    }
    return lines.join('\n');
}
QString krcLyricBundle(const QByteArray& bytes) {
    if(!bytes.startsWith("krc1"))return {};
    QByteArray compressed=bytes.mid(4);constexpr unsigned char key[]{0x40,0x47,0x61,0x77,0x5e,0x32,0x74,0x47,0x51,0x36,0x31,0x2d,0xce,0xd2,0x6e,0x69};
    for(qsizetype i=0;i<compressed.size();++i)compressed[i]=char(static_cast<unsigned char>(compressed[i])^key[i%16]);
    const auto text=inflateLyrics(compressed);QStringList words,translations,romans;QJsonArray languages;
    const auto language=QRegularExpression(R"(\[language:([^\]]+)\])").match(text);
    if(language.hasMatch())languages=QJsonDocument::fromJson(QByteArray::fromBase64(language.captured(1).toLatin1())).object().value("content").toArray();
    static const QRegularExpression linePattern(R"(^\[(\d+),\d+\](.*)$)");
    int index=0,romanIndex=0;
    for(const auto& line:text.split('\n')) {
        const auto match=linePattern.match(line.trimmed());if(!match.hasMatch())continue;
        const auto prefix=stamp(match.captured(1).toLongLong());
        auto body=match.captured(2);body.replace(QRegularExpression(R"(<(\d+,\d+),\d+>)"),"<\\1>");words.append(prefix+body);
        const bool hasText=!plainTrack(body).trimmed().isEmpty();
        for(const auto& value:languages) {
            const auto lang=value.toObject();const auto rows=lang.value("lyricContent").toArray();const int type=lang.value("type").toInt(-1),i=type==0?romanIndex:index;
            if(i>=rows.size()||(type==0&&!hasText))continue;
            QString valueText;for(const auto& part:rows[i].toArray())valueText+=part.toString();
            if(type==0)romans.append(prefix+valueText);else if(type==1)translations.append(prefix+valueText);
        }
        ++index;if(hasText)++romanIndex;
    }
    const auto timed=words.join('\n');return packLyricTracks(plainTrack(timed),timed,translations.join('\n'),romans.join('\n'));
}
namespace {
// Narrow adaptation of AMLL TTMLParser's timed spans, role separation and
// iTunes text@for sidecars. Qt parses XML; no DOM/runtime enters the UI.
struct TtmlNode { QString name,text;QHash<QString,QString> attributes;QList<TtmlNode> children; };
TtmlNode readTtmlNode(QXmlStreamReader& xml,int depth=0) {
    TtmlNode node;node.name=xml.name().toString();
    if(depth>64){xml.raiseError("TTML nesting too deep");return node;}
    for(const auto& attr:xml.attributes())node.attributes[attr.name().toString()]=attr.value().toString();
    while(!xml.atEnd()) {
        xml.readNext();
        if(xml.isStartElement())node.children.append(readTtmlNode(xml,depth+1));
        else if(xml.isCharacters())node.children.append(TtmlNode{{},xml.text().toString(),{}, {}});
        else if(xml.isEndElement())break;
    }
    return node;
}
qint64 ttmlTime(QString value) {
    value=value.trimmed();if(value.endsWith("ms"))return qRound64(value.chopped(2).toDouble());
    if(value.endsWith('s'))return qRound64(value.chopped(1).toDouble()*1000);
    double seconds=0;for(const auto& part:value.split(':'))seconds=seconds*60+part.toDouble();
    return qMax(qint64(0),qRound64(seconds*1000));
}
QString ttmlText(const TtmlNode& node) {
    const auto ruby=node.attributes.value("ruby");
    if(ruby=="text"||ruby=="textContainer"||node.attributes.value("role")=="x-bg")return {};
    QString text=node.text;for(const auto& child:node.children)text+=ttmlText(child);
    text.replace(QRegularExpression("\\s+")," ");return text;
}
}
QString ttmlLyricBundle(const QByteArray& bytes) {
    if(bytes.isEmpty()||bytes.size()>2*1024*1024)return {};
    QXmlStreamReader xml(bytes);if(!xml.readNextStartElement()||xml.name()!=QStringLiteral("tt"))return {};
    const auto root=readTtmlNode(xml);if(xml.hasError())return {};
    QHash<QString,QString> sideTranslations,sideRomans;
    QSet<QString> chineseTranslations;
    const auto head=[&](auto&& self,const TtmlNode& node,QString type=QString{},QString language=QString{}) -> void {
        if(node.name=="body")return;
        if(node.name=="translation"||node.name=="transliteration")type=node.name;
        if(node.attributes.contains("lang"))language=node.attributes.value("lang");
        if(node.name=="text"&&node.attributes.contains("for")) {
            auto& values=type=="translation"?sideTranslations:sideRomans;
            const auto id=node.attributes.value("for");const bool preferred=type=="translation"&&language.startsWith("zh");
            if(!values.contains(id)||(preferred&&!chineseTranslations.contains(id)))values[id]=ttmlText(node).trimmed();
            if(preferred)chineseTranslations.insert(id);
        }
        for(const auto& child:node.children)self(self,child,type,language);
    };head(head,root);
    QStringList originals,words,translations,romans;
    const auto visit=[&](auto&& self,const TtmlNode& node) -> void {
        if(node.name=="head")return;
        if(node.name!="p") { for(const auto& child:node.children)self(self,child);return; }
        qint64 start=ttmlTime(node.attributes.value("begin"));
        QString body,translation=sideTranslations.value(node.attributes.value("key")),roman=sideRomans.value(node.attributes.value("key"));
        bool chinese=chineseTranslations.contains(node.attributes.value("key"));
        const auto spans=[&](auto&& parse,const TtmlNode& span) -> void {
            const auto role=span.attributes.value("role"),ruby=span.attributes.value("ruby");
            if(role=="x-translation") {
                const bool preferred=span.attributes.value("lang").startsWith("zh");
                if(translation.isEmpty()||(preferred&&!chinese))translation=ttmlText(span).trimmed();
                chinese|=preferred;return;
            }
            if(role=="x-roman") { if(roman.isEmpty())roman=ttmlText(span).trimmed();return; }
            if(role=="x-bg"||ruby=="textContainer"||ruby=="text")return;
            if(span.attributes.contains("begin")&&span.attributes.contains("end")) {
                const auto from=ttmlTime(span.attributes.value("begin")),to=ttmlTime(span.attributes.value("end"));
                const auto text=ttmlText(span);
                if(!text.isEmpty())body+=QString("<%1,%2>%3").arg(qMax(qint64(0),from-start)).arg(qMax(qint64(0),to-from)).arg(text);
            } else {
                auto text=span.text;text.replace(QRegularExpression("\\s+")," ");body+=text;
                for(const auto& child:span.children)parse(parse,child);
            }
        };
        for(const auto& child:node.children)spans(spans,child);
        if(plainTrack(body).trimmed().isEmpty())return;
        originals.append(stamp(start)+plainTrack(body).trimmed());words.append(stamp(start)+body.trimmed());
        if(!translation.isEmpty())translations.append(stamp(start)+translation);
        if(!roman.isEmpty())romans.append(stamp(start)+roman);
    };visit(visit,root);
    return packLyricTracks(originals.join('\n'),words.join('\n'),translations.join('\n'),romans.join('\n'));
}
QString lyricResponse(const QString& source,const QByteArray& response) {
    if(source=="wy")return matchedLyricBundle(platformJson(response));
    if(source=="kw")return decodeKuwoLyrics(response);
    if(source=="amll") {
        if(response.trimmed().startsWith('<'))return ttmlLyricBundle(response);
        return ttmlLyricBundle(platformJson(response).value("data").toObject().value("lyrics").toString().toUtf8());
    }
    if(source=="mg") {
        const auto text=QString::fromUtf8(response);
        return parseTimedLyrics(text).isEmpty()?QString{}:text;
    }
    if(source=="kg") {
        const auto object=platformJson(response);const auto data=QByteArray::fromBase64(object.value("content").toString().toLatin1());
        return object.value("contenttype").toInt()==2?QString::fromUtf8(data):krcLyricBundle(data);
    }
    if(source=="tx") {
        const auto data=platformJson(response).value("req").toObject().value("data").toObject();
        const auto words=qrcWordLyrics(decodeQrc(data.value("lyric").toString()));
        const auto translation=plainTrack(qrcWordLyrics(decodeQrc(data.value("trans").toString())));
        const auto roman=plainTrack(qrcWordLyrics(decodeQrc(data.value("roma").toString())));
        return packLyricTracks(plainTrack(words),words,translation,roman);
    }
    return {};
}
}
