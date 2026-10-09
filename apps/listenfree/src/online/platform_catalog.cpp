#include "platform_catalog.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSet>
#include <QTextDocumentFragment>
#include <QUrlQuery>
#include <functional>

namespace listenfree::online {
namespace {
QString str(const QJsonValue &v) { return v.toVariant().toString(); }
QString clean(const QJsonValue &v) {
  auto text = str(v);
  // Kuwo album fields sometimes contain another escaped Unicode layer.
  // Decode only complete code units, without evaluating provider text.
  static const QRegularExpression escaped("\\\\u([0-9a-fA-F]{4})");
  auto matches = escaped.globalMatch(text);
  QString decoded; qsizetype cursor = 0;
  while (matches.hasNext()) {
    const auto match = matches.next();
    decoded += text.mid(cursor,match.capturedStart()-cursor);
    decoded += QChar(match.captured(1).toUShort(nullptr,16));
    cursor = match.capturedEnd();
  }
  decoded += text.mid(cursor);
  return QTextDocumentFragment::fromHtml(decoded).toPlainText();
}
QString singers(const QJsonArray &a) {
  QStringList n;
  for (const auto &v : a)
    n << v.toObject().value("name").toString();
  return n.join("、");
}
QJsonObject qq(const QString &module, const QString &method,
               const QJsonObject &param) {
  return {
      {"comm", QJsonObject{{"ct", "11"},
                           {"cv", "14090508"},
                           {"v", "14090508"},
                           {"tmeAppID", "qqmusic"},
                           {"phonetype", "EBG-AN10"},
                           {"os_ver", "12"},
                           {"QIMEI36", "0"}}},
      {"req",
       QJsonObject{{"module", module}, {"method", method}, {"param", param}}}};
}
QVariantMap song(const QString &platform, QJsonObject o) {
  QString id, title, artist, album, cover;
  qint64 duration = 0;
  QVariantMap extra;
  if (platform == "wy") {
    if (o.contains("baseInfo"))
      o = o.value("baseInfo").toObject();
    const auto a = o.value(o.contains("al") ? "al" : "album").toObject();
    id = str(o.value("id"));
    title = clean(o.value("name"));
    artist = singers(o.value(o.contains("ar") ? "ar" : "artists").toArray());
    album = clean(a.value("name"));
    cover = a.value("picUrl").toString();
    duration =
        o.value(o.contains("dt") ? "dt" : "duration").toVariant().toLongLong();
    extra["albumId"] = a.value("id").toVariant();
  } else if (platform == "kg") {
    id = str(o.value(o.contains("Audioid") ? "Audioid" : "audio_id"));
    const auto hash =
        str(o.value(o.contains("FileHash") ? "FileHash" : "hash"));
    if (id.isEmpty())
      id = hash;
    title = clean(o.value("SongName"));
    artist = singers(o.value("Singers").toArray());
    if (title.isEmpty()) {
      const auto name = clean(o.value("filename"));
      const auto at = name.indexOf(" - ");
      artist = name.left(at);
      title = at < 0 ? name : name.mid(at + 3);
    }
    album = clean(o.value("AlbumName"));
    duration = o.value(o.contains("Duration") ? "Duration" : "duration")
                   .toVariant()
                   .toLongLong() *
               1000;
    cover = o.value("imgurl").toString();
    if (cover.isEmpty()) cover = o.value("AlbumImage").toString();
    if (cover.isEmpty()) cover = o.value("Image").toString();
    if (cover.isEmpty()) cover = o.value("trans_param").toObject().value("union_cover").toString();
    cover.replace("{size}", "400");
    extra["hash"] = hash;
    extra["albumId"] =
        o.value(o.contains("AlbumID") ? "AlbumID" : "album_id").toVariant();
    extra["albumAudioId"] = o.value(o.contains("MixSongID") ? "MixSongID" : "mixsongid").toVariant();
    QVariantMap types;
    for (const auto &pair :
         {qMakePair("128k", "FileHash"), qMakePair("320k", "HQFileHash"),
          qMakePair("flac", "SQFileHash"), qMakePair("flac24bit", "ResFileHash")}) {
      QString h = str(o.value(pair.second));
      if (h.isEmpty())
        h = str(o.value(QString(pair.first) == "flac24bit" ? "ResFileHash"
                        : QString(pair.first) == "flac"   ? "sqhash"
                        : QString(pair.first) == "320k" ? "320hash"
                                                        : "hash"));
      if (!h.isEmpty())
        types[pair.first] = QVariantMap{{"hash", h}};
    }
    extra["_types"] = types;
  } else if (platform == "tx") {
    const auto a = o.value("album").toObject();
    id = str(o.value("mid"));
    title = clean(o.value(o.contains("name") ? "name" : "title"));
    artist = singers(o.value("singer").toArray());
    album = clean(a.value("name"));
    duration = o.value("interval").toVariant().toLongLong() * 1000;
    const auto mid = str(a.value("mid"));
    cover = mid.isEmpty()
                ? QString()
                : "https://y.gtimg.cn/music/photo_new/T002R500x500M000" + mid +
                      ".jpg";
    extra["strMediaMid"] =
        o.value("file").toObject().value("media_mid").toString();
    extra["songId"] = o.value("id").toVariant();
    extra["albumMid"] = mid;
    QVariantMap types;
    const auto file = o.value("file").toObject();
    for (const auto &pair : {qMakePair("128k", "size_128mp3"), qMakePair("320k", "size_320mp3"),
                            qMakePair("flac", "size_flac"), qMakePair("flac24bit", "size_hires")})
      if (file.value(pair.second).toDouble() > 0)
        types[pair.first] = QVariantMap{{"size", file.value(pair.second).toVariant()}};
    extra["_types"] = types;
  } else if (platform == "mg") {
    id = str(o.value("songId"));
    if (id.isEmpty())
      id = str(o.value("id"));
    title = clean(o.value("name"));
    if (title.isEmpty())
      title = clean(o.value("songName"));
    artist = singers(o.value("singerList").toArray());
    if (artist.isEmpty())
      artist = clean(o.value("singerName"));
    album = clean(o.value("album"));
    duration = o.value("duration").toVariant().toLongLong() * 1000;
    cover = o.value("img3").toString(o.value("img2").toString(
        o.value("img1").toString(o.value("mediumPic").toString())));
    if (cover.startsWith('/'))
      cover = "https://d.musicapp.migu.cn" + cover;
    for (const auto *key : {"copyrightId", "lrcUrl", "albumId"})
      extra[key] = o.value(key).toVariant();
  }
  if (id.isEmpty())
    return {};
  extra.insert("trackId", platform + ":" + id);
  extra.insert("source", platform);
  extra.insert("songmid", id);
  extra.insert("rid", id);
  extra.insert("title", title);
  extra.insert("artist", artist);
  extra.insert("album", album);
  extra.insert("artwork", cover);
  extra.insert("durationMs", duration);
  extra.insert("duration",
               QString("%1:%2")
                   .arg(duration / 60000, 2, 10, QLatin1Char('0'))
                   .arg(duration / 1000 % 60, 2, 10, QLatin1Char('0')));
  return extra;
}
} // namespace
QJsonObject platformJson(QByteArray bytes) {
  auto obj = QJsonDocument::fromJson(bytes).object();
  if (!obj.isEmpty())
    return obj;
  // Kuwo legacy response uses single-quoted JSON strings; never evaluate it.
  QString raw = QString::fromUtf8(bytes), out;
  qsizetype pos = 0;
  static const QRegularExpression token("'((?:[^'\\\\]|\\\\.)*)'");
  auto matches = token.globalMatch(raw);
  while (matches.hasNext()) {
    auto m = matches.next();
    out += raw.mid(pos, m.capturedStart() - pos);
    auto body = m.captured(1);
    body.replace("\\'", "'");
    body.replace('"', "\\\"");
    out += '"' + body + '"';
    pos = m.capturedEnd();
  }
  out += raw.mid(pos);
  return QJsonDocument::fromJson(out.toUtf8()).object();
}
QNetworkReply *platformRequest(QNetworkAccessManager &network, const QString &p,
                               const QString &op, const QString &text,
                               const QString &order, int page, int pageSize) {
  page = qMax(1, page);
  pageSize = qBound(1, pageSize, 1000);
  const bool search = op == "search" || op == "searchPlaylists" || op == "searchAlbums";
  const bool albums = op == "searchAlbums";
  const bool playlists = op == "searchPlaylists";
  const auto paging = QString("&page=%1&pagesize=%2").arg(page).arg(pageSize);
  const auto e = QString::fromLatin1(QUrl::toPercentEncoding(text));
  QString url;
  QJsonObject body;
  QVariantMap headers;
  // The retired Migu web suggestion endpoint no longer completes TLS.
  // Use the same authenticated search contract and return actual song names.
  if (p == "mg" && op == "suggest")
    return platformRequest(network, p, "search", text, order);
  if (p == "wy") {
    headers["Referer"] = "https://music.163.com/";
    if (search)
      url = "https://music.163.com/api/search/get/web?s=" + e +
            QString("&type=%1&limit=%2&offset=%3").arg(albums ? 10 : playlists ? 1000 : 1).arg(pageSize).arg((page-1)*pageSize);
    else if (op == "album")
      url = "https://music.163.com/api/v1/album/" + e;
    else if (op == "song")
      url = "https://music.163.com/api/song/detail/?ids=[" + e + "]&id=" + e;
    else if (op == "songs")
      url = "https://music.163.com/api/song/detail/?ids=[" + e + "]";
    else if (op == "suggest")
      url = "https://music.163.com/api/search/suggest/web?s=" + e;
    else if (op == "lists")
      url = "https://music.163.com/api/playlist/list?limit=36&offset=0&order=" +
            order + "&cat=" +
            QString::fromLatin1(QUrl::toPercentEncoding(
                text.isEmpty() ? QStringLiteral("全部") : text));
    else if (op == "detail")
      url = "https://music.163.com/api/v6/playlist/detail?n=1000&s=0&id=" + e;
    else if (op == "lyrics")
      url = "https://music.163.com/api/song/lyric?id=" + e +
            "&lv=-1&tv=-1&rv=-1&yv=-1";
  } else if (p == "kg") {
    headers["Referer"] = "https://www.kugou.com/";
    headers["User-Agent"] =
        "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120.0.0.0 "
        "Mobile Safari/537.36";
    if (op == "search")
      url = "https://songsearch.kugou.com/song_search_v2?keyword=" + e +
            paging + "&userid=0&clientver=&platform=WebFilter&filter=2&iscorrection=1&privilege_filter=0&area_code=1";
    else if (search)
      url = "https://msearchretry.kugou.com/api/v3/search/" + QString(albums ? "album" : "special") +
            "?keyword=" + e + paging + "&showtype=10&filter=0&version=7910&sver=2";
    else if (op == "album")
      url = "https://mobiles.kugou.com/api/v3/album/song?albumid=" + e + paging + "&version=9108&plat=0&area_code=0&with_res_tag=0";
    else if (op == "suggest")
      url =
          "https://searchtip.kugou.com/getSearchTip?MusicTipCount=8&keyword=" +
          e;
    else if (op == "lists")
      url = "https://m.kugou.com/plist/index?json=true";
    else if (op == "detail")
      url = "https://m.kugou.com/plist/list/" + e + "/?json=true";
    else if (op == "playlistSongs")
      url = "https://mobiles.kugou.com/api/v3/special/song?specialid=" + e +
            paging + "&version=9108&plat=0&area_code=0&with_res_tag=0";
  } else if (p == "tx") {
    headers["Referer"] = "https://y.qq.com/";
    headers["User-Agent"] = "QQMusic 14090508(android 12)";
    if (op == "suggest")
      url = "https://c.y.qq.com/splcloud/fcgi-bin/"
            "smartbox_new.fcg?format=json&key=" +
            e;
    else {
      url = "https://u.y.qq.com/cgi-bin/musicu.fcg";
      if (search)
        body = qq("music.search.SearchCgiService", "DoSearchForQQMusicMobile",
                  {{"query", text},
                   {"search_type", albums ? 2 : playlists ? 3 : 0},
                   {"page_num", page},
                   {"num_per_page", pageSize},
                   {"highlight", 0},
                   {"nqc_flag", 0},
                   {"multi_zhida", 0},
                   {"cat", 2},
                   {"grp", 1},
                   {"sin", 0},
                   {"sem", 0}});
      else if (op == "album")
        body = qq("music.musichallAlbum.AlbumSongList", "GetAlbumSongList", {{"albumMid", text}, {"begin", (page-1)*pageSize}, {"num", pageSize}, {"order", 2}});
      else if (op == "lists")
        body = qq("playlist.PlayListPlazaServer", "get_playlist_by_tag",
                  {{"id", 10000000},
                   {"cur_page", 1},
                   {"sin", 0},
                   {"size", 36},
                   {"order", order == "new" ? 2 : 5}});
      else if (op == "detail") {
        body = qq("music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo",
                  {{"disstid", text.toLongLong()},
                   {"enc_host_uin", ""},
                   {"tag", 1},
                   {"userinfo", 1},
                   {"song_begin", 0},
                   {"song_num", 1000}});
        body["comm"] = QJsonObject{{"g_tk", 5381},
                                   {"uin", 0},
                                   {"format", "json"},
                                   {"ct", 24},
                                   {"cv", 0}};
      }
    }
  } else if (p == "mg") {
    headers["Referer"] = "https://music.migu.cn/";
    if (op == "suggest")
      url = "https://music.migu.cn/v3/api/search/suggest?keyword=" + e;
    else if (search) {
      const auto time = QString::number(QDateTime::currentMSecsSinceEpoch());
      const QString device = "963B7AA0D21511ED807EE5846EC87D20";
      headers["timestamp"] = time;
      headers["deviceId"] = device;
      headers["uiVersion"] = "A_music_3.6.1";
      headers["channel"] = "0146921";
      headers["sign"] = QString::fromLatin1(
          QCryptographicHash::hash((text +
                                    "6cdc72a439cef99a3418d2a78aa28c73yyapp2d161"
                                    "48780a1dcc7408e06336b98cfd50" +
                                    device + time)
                                       .toUtf8(),
                                   QCryptographicHash::Md5)
              .toHex());
      const auto category = albums ? "album" : playlists ? "songlist" : "song";
      const auto switches = QJsonDocument(QJsonObject{{category, 1}}).toJson(QJsonDocument::Compact);
      url = "https://jadeite.migu.cn/music_search/v3/search/searchAll?isCorrect=0&isCopyright=1&searchSwitch=" +
            QString::fromLatin1(QUrl::toPercentEncoding(QString::fromUtf8(switches))) +
            QString("&pageSize=%1&pageNo=%2&sort=0&sid=USS&text=").arg(pageSize).arg(page) + e;
    } else if (op == "lists")
      url = "https://app.c.nf.migu.cn/pc/bmw/page-data/"
            "playlist-square-recommend/v1.0?templateVersion=2&pageNo=1";
    else if (op == "album")
      url = "https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/queryAlbumSong?albumId=" + e + QString("&pageNo=%1&pageSize=%2").arg(page).arg(pageSize);
    else if (op == "detail")
      url = "https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/"
            "v2.0?pageNo=1&pageSize=1000&playlistId=" +
            e;
  } else if (p == "kw" && search)
    url = "https://search.kuwo.cn/r.s?all=" + e + QString("&pn=%1&rn=%2&ft=").arg(page-1).arg(pageSize) +
          (albums ? "album" : playlists ? "playlist" : "music") + "&rformat=json&encoding=utf8&client=kt";
  else if (p == "kw" && op == "album")
    url = "https://search.kuwo.cn/r.s?stype=albuminfo&albumid=" + e + QString("&pn=%1&rn=%2").arg(page-1).arg(pageSize) + "&rformat=json&encoding=utf8&vipver=MUSIC_9.1.0";
  else if (p == "kw" && op == "suggest")
    url = "https://search.kuwo.cn/r.s?all=" + e +
          "&ft=music&client=kt&pn=0&rn=8&rformat=json&encoding=utf8";
  if (url.isEmpty())
    return nullptr;
  QNetworkRequest request{QUrl(url)};
  request.setTransferTimeout(15000);
  request.setRawHeader("User-Agent", "Mozilla/5.0");
  for (auto it = headers.cbegin(); it != headers.cend(); ++it)
    request.setRawHeader(it.key().toUtf8(), it.value().toString().toUtf8());
  QNetworkReply *reply;
  if (body.isEmpty())
    reply = network.get(request);
  else {
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    reply = network.post(request,
                         QJsonDocument(body).toJson(QJsonDocument::Compact));
  }
  QObject::connect(reply, &QIODevice::readyRead, reply, [reply] {
    if (reply->bytesAvailable() > 8 * 1024 * 1024)
      reply->abort();
  });
  return reply;
}
QVariantList platformSongs(const QString &p, const QJsonObject &o) {
  QJsonArray array;
  if (p == "wy")
    array = o.contains("songs") ? o.value("songs").toArray()
            : o.contains("playlist")
                ? o.value("playlist").toObject().value("tracks").toArray()
                : o.value("result").toObject().value("songs").toArray();
  else if (p == "kg")
    array = o.contains("list")
                ? o.value("list")
                      .toObject()
                      .value("list")
                      .toObject()
                      .value("info")
                      .toArray()
                : o.value("data").toObject().value(
                      o.value("data").toObject().contains("info") ? "info" : "lists").toArray();
  else if (p == "tx") {
    const auto data = o.value("req").toObject().value("data").toObject();
    array = data.value("body")
                .toObject()
                .value("song")
                .toObject()
                .value("list")
                .toArray();
    if (array.isEmpty())
      array = data.value("body").toObject().value("item_song").toArray();
    if (array.isEmpty())
      array = data.value("item_song").toArray();
    if (array.isEmpty())
      array = data.value("songlist").toArray();
    if (o.contains("cdlist") && !o.value("cdlist").toArray().isEmpty())
      array = o.value("cdlist")
                  .toArray()
                  .first()
                  .toObject()
                  .value("songlist")
                  .toArray();
  } else if (p == "mg") {
    array = o.value("data").toObject().value("songList").toArray();
    if (array.isEmpty())
      for (const auto &group :
           o.value("songResultData").toObject().value("resultList").toArray())
        for (const auto &v : group.toArray())
          array.append(v);
  }
  QVariantList rows;
  for (const auto &v : array) {
    auto row = song(p, v.toObject());
    if (!row.isEmpty())
      rows.append(row);
  }
  return rows;
}
int platformSearchTotal(const QString &p, const QString &category, const QJsonObject &o) {
  QJsonValue total;
  if (p == "kw") total = o.value(category == "albums" ? "total" : "TOTAL");
  else if (p == "kg") total = o.value("data").toObject().value("total");
  else if (p == "wy") total = o.value("result").toObject().value(category == "albums" ? "albumCount" : category == "playlists" ? "playlistCount" : "songCount");
  else if (p == "tx") total = o.value("req").toObject().value("data").toObject().value("meta").toObject().value("estimate_sum");
  else if (p == "mg") total = o.value(category == "albums" ? "albumResultData" : category == "playlists" ? "songListResultData" : "songResultData").toObject().value("totalCount");
  return total.isUndefined() || total.isNull() ? -1 : qMax(0, total.toVariant().toInt());
}

QVariantList platformSearchRows(const QString &p, const QString &category, const QJsonObject &o) {
  if (category == "songs") {
    if (p == "mg") {
      // Migu returns alternate versions grouped under each result. The API's
      // page/count contract counts groups, so show its preferred version.
      QVariantList rows;
      for (const auto &group : o.value("songResultData").toObject().value("resultList").toArray()) {
        const auto variants = group.toArray();
        if (!variants.isEmpty()) { const auto row = song(p, variants.first().toObject()); if (!row.isEmpty()) rows.append(row); }
      }
      return rows;
    }
    if (p != "kw") return platformSongs(p, o);
    QVariantList rows;
    for (const auto &v : o.value("abslist").toArray()) {
      const auto r = v.toObject(); auto id = str(r.value("MUSICRID")); id.remove("MUSIC_");
      if (id.isEmpty()) continue;
      const auto ms = r.value("DURATION").toVariant().toLongLong()*1000;
      rows.append(QVariantMap{{"trackId", "kw:"+id}, {"rid", id}, {"source", p},
        {"title", clean(r.value(r.contains("SONGNAME") ? "SONGNAME" : "NAME"))},
        {"artist", clean(r.value("ARTIST"))}, {"album", clean(r.value("ALBUM"))}, {"albumId", r.value("ALBUMID").toVariant()},
        {"durationMs", ms}, {"duration", QString("%1:%2").arg(ms/60000,2,10,QChar('0')).arg(ms/1000%60,2,10,QChar('0'))}});
    }
    return rows;
  }
  const bool album = category == "albums";
  QJsonArray items;
  if (p == "kw") items = o.value(album ? "albumlist" : "abslist").toArray();
  else if (p == "kg") items = o.value("data").toObject().value("info").toArray();
  else if (p == "wy") items = o.value("result").toObject().value(album ? "albums" : "playlists").toArray();
  else if (p == "tx") items = o.value("req").toObject().value("data").toObject().value("body").toObject().value(album ? "item_album" : "item_songlist").toArray();
  else if (p == "mg") items = o.value(album ? "albumResultData" : "songListResultData").toObject().value("result").toArray();
  QVariantList rows;
  for (const auto &v : items) {
    const auto r = v.toObject(); QString id, title, artist, artwork; QJsonValue count;
    if (p == "kw") {
      id = str(r.value(album ? "albumid" : "playlistid")); title = clean(r.value("name"));
      artist = clean(r.value(album ? "artist" : "nickname")); artwork = str(r.value(album ? "img" : "pic")); count = r.value(album ? "musiccnt" : "songnum");
    } else if (p == "kg") {
      id = str(r.value(album ? "albumid" : "specialid")); title = clean(r.value(album ? "albumname" : "specialname"));
      artist = clean(r.value(album ? "singername" : "nickname")); artwork = str(r.value("imgurl")); count = r.value("songcount");
    } else if (p == "wy") {
      id = str(r.value("id")); title = clean(r.value("name")); artwork = str(r.value(album ? "picUrl" : "coverImgUrl"));
      artist = clean(r.value(album ? "artist" : "creator").toObject().value(album ? "name" : "nickname")); count = r.value(album ? "size" : "trackCount");
    } else if (p == "tx") {
      id = str(r.value(album ? "albummid" : "dissid")); title = clean(r.value(album ? "name" : "dissname"));
      artist = clean(r.value(album ? "singer" : "nickname")); artwork = str(r.value(album ? "pic" : "logo")); count = r.value(album ? "song_num" : "songnum");
    } else if (p == "mg") {
      id = str(r.value("id")); title = clean(r.value("name")); artist = clean(r.value(album ? "singer" : "userName"));
      const auto images = r.value("imgItems").toArray();
      artwork = album ? (images.isEmpty() ? QString{} : images.first().toObject().value("img").toString()) : r.value("musicListPicUrl").toString(); count = r.value("musicNum");
    }
    if (id.isEmpty()) continue;
    artwork.replace("{size}","400");
    QString subtitle = artist;
    if (!count.isUndefined()) subtitle += (subtitle.isEmpty() ? "" : " · ") + str(count) + " 首";
    rows.append(QVariantMap{{"id",id},{"source",p},{"kind",album ? "album" : "playlist"},{"title",title},{"artist",artist},{"artwork",artwork},{"subtitle",subtitle},{"total",count.toVariant()},{"color","#80868d"}});
  }
  return rows;
}

QVariantList platformAlbumSongs(const QString &p, const QJsonObject &o) {
  if (p == "wy" || p == "mg") return platformSongs(p, o);
  QJsonArray items;
  if (p == "kw") items = o.value("musiclist").toArray();
  else if (p == "kg") items = o.value("data").toObject().value("info").toArray();
  else if (p == "tx") items = o.value("req").toObject().value("data").toObject().value("songList").toArray();
  QVariantList rows;
  for (const auto &v : items) {
    auto r = v.toObject();
    if (p == "kw") {
      const auto id = str(r.value("id")); if(id.isEmpty()) continue;
      const auto ms = r.value("duration").toVariant().toLongLong()*1000;
      rows.append(QVariantMap{{"trackId","kw:"+id},{"rid",id},{"source",p},{"title",clean(r.value("name"))},
        {"artist",clean(r.value("artist"))},{"album",clean(r.value("album"))},{"durationMs",ms},
        {"duration",QString("%1:%2").arg(ms/60000,2,10,QChar('0')).arg(ms/1000%60,2,10,QChar('0'))}});
    } else {
      if(p=="tx") r=r.value("songInfo").toObject();
      if(p=="kg") r["imgurl"]=r.value("trans_param").toObject().value("union_cover");
      auto row=song(p,r);if(!row.isEmpty()) rows.append(row);
    }
  }
  return rows;
}

QStringList platformSuggestions(const QString &p, const QJsonObject &o) {
  QStringList rows;
  QJsonArray array;
  if (p == "mg") {
    for (const auto &v : platformSongs(p, o))
      rows << v.toMap().value("title").toString();
  } else if (p == "kw") {
    for (const auto &v : o.value("abslist").toArray())
      rows << clean(v.toObject().value("SONGNAME"));
  } else if (p == "kg") {
    const auto data = o.value("data").toArray();
    if (!data.isEmpty())
      for (const auto &v :
           data.first().toObject().value("RecordDatas").toArray())
        rows << v.toObject().value("HintInfo").toString();
  } else {
    if (p == "wy")
      array = o.value("result").toObject().value("songs").toArray();
    else if (p == "tx")
      array = o.value("data")
                  .toObject()
                  .value("song")
                  .toObject()
                  .value("itemlist")
                  .toArray();
    else
      array = o.value("songs").toArray();
    for (const auto &v : array)
      rows << clean(v.toObject().value("name"));
  }
  rows.removeAll({});
  rows.removeDuplicates();
  return rows.mid(0, 8);
}
QVariantMap sourceMusicInfo(const QVariantMap &track) {
  auto info = track;
  info["songmid"] = track.value("songmid", track.value("rid"));
  info["name"] = track.value("title", track.value("name"));
  info["singer"] = track.value("artist", track.value("singer"));
  info["albumName"] = track.value("album", track.value("albumName"));
  info["img"] = track.value("artwork", track.value("img"));
  info["interval"] = track.value("duration", track.value("interval"));
  if (track.value("source") == "tx") info["albumId"] = track.value("albumMid");
  if (!info.contains("types")) {
    QVariantList types;
    const auto mapped = track.value("_types").toMap();
    for (auto it = mapped.cbegin(); it != mapped.cend(); ++it) {
      auto item = it.value().toMap();
      item["type"] = it.key();
      types.append(item);
    }
    info["types"] = types;
  }
  if (!info.contains("typeUrl")) info["typeUrl"] = QVariantMap{};
  return info;
}
QVariantList platformPlaylists(const QString &p, const QJsonObject &object) {
  QJsonArray a;
  if (p == "wy")
    a = object.value("playlists").toArray();
  else if (p == "kg")
    a = object.value("plist")
            .toObject()
            .value("list")
            .toObject()
            .value("info")
            .toArray();
  else if (p == "tx") {
    const auto data = object.value("req").toObject().value("data").toObject();
    a = data.value("v_playlist").toArray();
    if (a.isEmpty())
      a = data.value("content").toArray();
  } else if (p == "mg") {
    std::function<void(QJsonValue)> visit = [&](QJsonValue v) {
      if (v.isArray()) {
        for (const auto &c : v.toArray())
          visit(c);
      } else if (v.isObject()) {
        const auto o = v.toObject();
        if (o.value("resType").toString() == "2021")
          a.append(o);
        visit(o.value("contents"));
      }
    };
    visit(object.value("data"));
  }
  QVariantList rows;
  QSet<QString> ids;
  for (const auto &v : a) {
    const auto o = v.toObject();
    QString id, title, cover, subtitle;
    if (p == "wy") {
      id = str(o.value("id"));
      title = clean(o.value("name"));
      cover = str(o.value("coverImgUrl"));
      subtitle = clean(o.value("creator").toObject().value("nickname"));
    }
    if (p == "kg") {
      id = str(o.value("specialid"));
      title = clean(o.value("specialname"));
      cover = str(o.value("imgurl")).replace("{size}", "400");
      subtitle = clean(o.value("nickname"));
    }
    if (p == "tx") {
      id = str(o.value("tid"));
      title = clean(o.value("title"));
      cover = str(o.value("cover_url_big"));
      if (cover.isEmpty())
        cover = str(o.value("cover_url_medium"));
    }
    if (p == "mg") {
      id = str(o.value("resId"));
      title = clean(o.value("txt"));
      cover = str(o.value("img"));
      subtitle = clean(o.value("txt2"));
    }
    if (id.isEmpty() || ids.contains(id))
      continue;
    ids.insert(id);
    rows.append(QVariantMap{{"id", id},
                            {"source", p},
                            {"title", title},
                            {"artwork", cover},
                            {"subtitle", subtitle},
                            {"kind", "playlist"},
                            {"color", "#5699c5"}});
  }
  return rows;
}
QVariantMap platformDetail(const QString &p, const QJsonObject &object) {
  auto rows = platformSongs(p, object);
  QVariantMap result{{"tracks", rows}, {"total", rows.size()}};
  if (p == "wy") {
    auto o = object.value("playlist").toObject();
    result["title"] = o.value("name").toString();
    result["artwork"] = o.value("coverImgUrl").toString();
    result["total"] = o.value("trackCount").toInt();
    result["playCount"] = o.value("playCount").toVariant();
  } else if (p == "kg") {
    const auto info = object.value("info").toObject().value("list").toObject();
    const auto list = object.value("list").toObject().value("list").toObject();
    result["title"] = clean(info.value("specialname"));
    result["artwork"] = info.value("imgurl").toString().replace("{size}", "400");
    result["playCount"] = info.value("playcount").toVariant();
    result["total"] = list.value("total").toVariant().toInt();
  }
  return result;
}
} // namespace listenfree::online
