#include "collection_service.h"
#include "online/platform_catalog.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDir>
#include <QCryptographicHash>
#include <QRegularExpression>
#include <QTextDocumentFragment>
#include <QUrlQuery>
#include <QUuid>

namespace listenfree::qmlbridge {
namespace {
constexpr int playlistPageSize = 100;
constexpr int playlistTrackLimit = 5000;
QString referenceKey(const QVariantMap& row) {
  return row.value("source","kw").toString()+":"+(row.value("kind")=="album" ? "album:" : "")+row.value("playlistId",row.value("id")).toString();
}
QString likedTrackKey(const QVariantMap& row) {
  const auto path = row.value("localPath").toString();
  if (!path.isEmpty()) return "local:" + QDir::fromNativeSeparators(path).toCaseFolded();
  const auto source = row.value("source").toString().toLower();
  const auto rid = row.value("rid").toString();
  return !source.isEmpty() && !rid.isEmpty() ? source + ":" + rid : row.value("trackId").toString();
}
QString clean(const QJsonValue &v) {
  return QTextDocumentFragment::fromHtml(v.toVariant().toString())
      .toPlainText();
}
QVariantMap song(const QJsonObject &o) {
  const auto id = o.value("id").toVariant().toString().remove("MUSIC_");
  const auto ms = o.value("duration").toVariant().toLongLong() * 1000;
  return {
      {"trackId", "kw:" + id},
      {"rid", id},
      {"source", "kw"},
      {"title", clean(o.value("name"))},
      {"artist", clean(o.value("artist"))},
      {"album", clean(o.value("album"))},
      {"durationMs", ms},
      {"duration",
       QString("%1:%2").arg(ms / 60000).arg(ms / 1000 % 60, 2, 10, QChar('0'))},
      {"artwork", o.value("albumpic").toString(o.value("pic").toString())}};
}
QVariantList safeTracks(const QVariantList &rows) {
  QVariantList result;
  for (const auto &value : rows) {
    auto row = value.toMap();
    if (row.value("localPath").toString().isEmpty() &&
        row.value("rid").toString().isEmpty())
      continue;
    row.remove("resolvedUrl");
    row.remove("remoteUrl");
    row.remove("entryId");
    result.append(row);
  }
  return result;
}
} // namespace
CollectionService::CollectionService(infrastructure::database::Database &db,
                                     QObject *parent, QNetworkAccessManager *network)
    : QObject(parent), db_(db), network_(network ? network : &ownedNetwork_) {
  get(QUrl("https://music.163.com/api/search/hot?type=1111"),[this](QJsonObject result,QString){
    for(const auto& v:result.value("result").toObject().value("hots").toArray()) { const auto term=v.toObject().value("first").toString();if(!term.isEmpty())hotSearches_.append(term); }
    emit discoverChanged();
  });
  lists_ = QJsonDocument::fromJson(
               QByteArray::fromStdString(
                   db_.getSetting("collections.v1").value_or("[]")))
               .array()
               .toVariantList();
  refreshLikedTrackIndex();
  const auto home = QJsonDocument::fromJson(QByteArray::fromStdString(db_.getSetting("discovery.home.v1").value_or("{}"))).object();
  homeRecommendations_=home.value("recommendations").toArray().toVariantList().mid(0,12);
  homeCharts_=home.value("charts").toArray().toVariantList();
  homePreviews_=home.value("previews").toArray().toVariantList();
  dailyTracks_=home.value("dailyTracks").toArray().toVariantList();
  dailySource_=home.value("dailySource").toString(QStringLiteral("网易云每日推荐"));
  homeFetchedAt_=QDateTime::fromString(home.value("fetchedAt").toString(),Qt::ISODate);
  if(homePreviews_.size()!=2) homePreviews_={
      QVariantMap{{"id","3779629"},{"title","新歌榜"},{"source","wy"},{"kind","playlist"},{"tracks",QVariantList{}}},
      QVariantMap{{"id","3778678"},{"title","热歌榜"},{"source","wy"},{"kind","playlist"},{"tracks",QVariantList{}}}};
}

void CollectionService::refreshHome(bool force) {
  if(homeBusy())return;
  const auto now=QDateTime::currentDateTime();
  if(!force && homeRecommendations_.size()==12 && homeFetchedAt_.date()==now.date() && homeFetchedAt_.secsTo(now)<1800)return;
  homeRequests_=5;homeSucceeded_=false;homeError_.clear();emit homeStateChanged();
  const auto listsFrom=[](const QJsonArray& input) {
    QJsonArray normalized;
    QHash<QString,QJsonObject> originals;
    for(const auto& value:input){auto row=value.toObject();row["coverImgUrl"]=row.value("coverImgUrl").toString(row.value("picUrl").toString());normalized.append(row);originals.insert(row.value("id").toVariant().toString(),row);}
    auto rows=online::platformPlaylists("wy",QJsonObject{{"playlists",normalized}});
    for(auto& value:rows){auto row=value.toMap();const auto raw=originals.value(row.value("id").toString());row["playCount"]=raw.value("playCount").toVariant();if(raw.contains("updateFrequency"))row["subtitle"]=raw.value("updateFrequency").toString();value=row;}
    return rows;
  };
  get(QUrl("https://music.163.com/api/personalized/playlist?limit=12&total=true&n=1000"),[this,listsFrom](QJsonObject obj,QString error){
    const auto rows=listsFrom(obj.value("result").toArray()).mid(0,12);
    if(error.isEmpty() && !rows.isEmpty()){homeRecommendations_=rows;homeSucceeded_=true;emit homeRecommendationsChanged();}
    else homeError_=QStringLiteral("部分推荐暂时无法更新，请稍后重试");
    finishHomeRequest();
  });
  get(QUrl("https://music.163.com/api/toplist"),[this,listsFrom](QJsonObject obj,QString error){
    const auto raw=obj.value("list").toArray();auto rows=listsFrom(raw);
    if(error.isEmpty() && !rows.isEmpty()){
      homeCharts_=rows;homeSucceeded_=true;emit homeChartsChanged();
    } else homeError_=QStringLiteral("部分榜单暂时无法更新，请稍后重试");
    finishHomeRequest();
  });
  for(int i=0;i<2;++i){
    const auto id=homePreviews_[i].toMap().value("id").toString();
    get(QUrl("https://music.163.com/api/v6/playlist/detail?n=5&s=0&id="+id),[this,i](QJsonObject obj,QString error){
      const auto rows=online::platformSongs("wy",obj).mid(0,5);
      if(error.isEmpty() && !rows.isEmpty()){
        auto preview=homePreviews_[i].toMap();preview["tracks"]=rows;
        preview["artwork"]=obj.value("playlist").toObject().value("coverImgUrl").toString();
        homePreviews_[i]=preview;homeSucceeded_=true;emit homePreviewsChanged();
      } else homeError_=QStringLiteral("部分榜单暂时无法更新，请稍后重试");
      finishHomeRequest();
    });
  }
  loadDailyTracks(false);
}

void CollectionService::loadDailyTracks(bool fallback) {
  const QUrl url(fallback ? "https://music.163.com/api/personalized/newsong?limit=30&type=recommend"
                         : "https://music.163.com/api/v3/discovery/recommend/songs");
  get(url,[this,fallback](QJsonObject obj,QString error){
    auto songs=obj.value("data").toObject().value("dailySongs").toArray();
    if(fallback)for(const auto& value:obj.value("result").toArray())songs.append(value.toObject().value("song"));
    const auto rows=online::platformSongs("wy",QJsonObject{{"songs",songs}}).mid(0,30);
    if(error.isEmpty() && !rows.isEmpty()){
      dailyTracks_=rows;dailySource_=fallback ? QStringLiteral("网易云推荐新歌") : QStringLiteral("网易云每日推荐");
      homeSucceeded_=true;emit dailyTracksChanged();
    } else if(!fallback){loadDailyTracks(true);return;}
    else homeError_=QStringLiteral("每日推荐暂时无法更新，请稍后重试");
    finishHomeRequest();
  });
}

void CollectionService::finishHomeRequest() {
  if(--homeRequests_==0 && homeSucceeded_){
    homeFetchedAt_=homeError_.isEmpty() ? QDateTime::currentDateTime() : QDateTime{};
    const QJsonObject snapshot{{"recommendations",QJsonArray::fromVariantList(homeRecommendations_)},
      {"charts",QJsonArray::fromVariantList(homeCharts_)},{"previews",QJsonArray::fromVariantList(homePreviews_)},
      {"dailyTracks",QJsonArray::fromVariantList(dailyTracks_)},{"dailySource",dailySource_},
      {"fetchedAt",homeFetchedAt_.toString(Qt::ISODate)}};
    db_.setSetting("discovery.home.v1",QString::fromUtf8(QJsonDocument(snapshot).toJson(QJsonDocument::Compact)));
  }
  emit homeStateChanged();
}
int CollectionService::index(const QString &id) const {
  for (int i = 0; i < lists_.size(); ++i)
    if (lists_[i].toMap().value("id") == id)
      return i;
  return -1;
}
bool CollectionService::save(const QVariantList &lists) {
  if (!db_.setSetting(
          "collections.v1",
          QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(lists))
                                .toJson(QJsonDocument::Compact)))) {
    emit notice("歌单保存失败，请检查数据目录");
    return false;
  }
  lists_ = lists;
  refreshLikedTrackIndex();
  emit playlistsChanged();
  return true;
}
QString CollectionService::create(const QString &name,
                                  const QVariantList &tracks) {
  if (name.trimmed().isEmpty())
    return {};
  const auto id = QUuid::createUuid().toString(QUuid::WithoutBraces);
  const auto rows = safeTracks(tracks);
  auto lists = lists_;
  lists.append(
      QVariantMap{{"id", id},
                  {"title", name.trimmed()},
                  {"kind", "Local"},
                  {"tracks", rows},
                  {"subtitle", QString::number(rows.size()) + " 首歌曲"},
                  {"color", "#5699c5"}});
  return save(lists) ? id : QString{};
}
void CollectionService::rename(const QString &id, const QString &name) {
  int i = index(id);
  if (i < 0 || name.trimmed().isEmpty())
    return;
  auto lists = lists_;
  auto row = lists[i].toMap();
  row["title"] = name.trimmed();
  lists[i] = row;
  save(lists);
}
void CollectionService::remove(const QString &id) {
  int i = index(id);
  if (i < 0)
    return;
  auto lists = lists_;
  lists.removeAt(i);
  save(lists);
}
void CollectionService::clear() { save({}); }
bool CollectionService::isTrackLiked(const QVariantMap &track) const {
  const auto key = likedTrackKey(track);
  return !key.isEmpty() && likedTrackKeys_.contains(key);
}
void CollectionService::refreshLikedTrackIndex() {
  QSet<QString> keys;
  const auto i = index("liked-tracks");
  if (i >= 0) {
    const auto rows = lists_[i].toMap().value("tracks").toList();
    keys.reserve(rows.size());
    for (const auto& value : rows) {
      auto key = likedTrackKey(value.toMap());
      if (!key.isEmpty()) keys.insert(std::move(key));
    }
  }
  // Metadata, ordering and unrelated playlists do not change membership.
  // Publish only after successful persistence, before notifying consumers.
  if (keys == likedTrackKeys_) return;
  likedTrackKeys_.swap(keys);
  ++likedTracksRevision_;
  emit likedTracksChanged();
}
void CollectionService::toggleTrackLiked(const QVariantMap &track) {
  const auto cleanRows = safeTracks({track});
  if (cleanRows.isEmpty() || likedTrackKey(track).isEmpty()) return;
  auto lists = lists_;
  auto i = index("liked-tracks");
  QVariantMap list = i < 0 ? QVariantMap{{"id", "liked-tracks"}, {"title", "我喜欢的音乐"}, {"kind", "Local"}} : lists[i].toMap();
  auto rows = list.value("tracks").toList();
  const auto key = likedTrackKey(track);
  bool removed = false;
  for (int j = rows.size() - 1; j >= 0; --j) {
    if (likedTrackKey(rows[j].toMap()) == key) { rows.removeAt(j); removed = true; }
  }
  if (!removed) rows.append(cleanRows.first());
  list["tracks"] = rows;
  list["subtitle"] = QString::number(rows.size()) + " 首歌曲";
  list["artwork"] = rows.isEmpty() ? QString{} : rows.first().toMap().value("artwork").toString();
  if (i < 0) lists.prepend(list); else lists[i] = list;
  save(lists);
}
bool CollectionService::isSaved(const QVariantMap &collection) const {
  for (const auto &v : lists_) {
    const auto row=v.toMap();
    if (referenceKey(row)==referenceKey(collection)) return true;
  }
  return false;
}
void CollectionService::toggleSaved(const QVariantMap &collection) {
  if(collection.value("id").toString().isEmpty() || collection.value("title").toString().trimmed().isEmpty()) return;
  auto rows=lists_;
  for(int i=0;i<rows.size();++i) {
    const auto row=rows[i].toMap();
    if(referenceKey(row)==referenceKey(collection)) { rows.removeAt(i);save(rows);return; }
  }
  auto reference=collection;
  if(reference.value("kind") != "Local") reference.remove("tracks");
  reference.remove("error");
  const auto provider=reference.value("source","kw").toString();reference["source"]=provider;
  reference["reference"]=reference.value("kind") != "Local";
  if(reference.value("reference").toBool()) {
    reference["playlistId"]=reference.value("playlistId",reference.value("id"));
    reference["id"]="online:"+provider+":"+(reference.value("kind")=="album" ? "album:" : "")+reference.value("playlistId").toString();
  }
  if(reference.value("reference").toBool()) {
    const auto id=reference.value("playlistId").toString();
    const QMap<QString,QString> links{{"kw","https://www.kuwo.cn/playlist_detail/"},
      {"wy","https://music.163.com/#/playlist?id="},{"tx","https://y.qq.com/n/ryqq/playlist/"},
      {"kg","https://www.kugou.com/yy/special/single/"},{"mg","https://music.migu.cn/v3/music/playlist/"}};
    if(reference.value("kind")!="album" && reference.value("url").toString().isEmpty()) reference["url"]=links.value(provider)+id;
    reference["subtitle"]="在线收藏 · 打开时更新";
  } else reference["subtitle"]="本地收藏 · "+QString::number(reference.value("tracks").toList().size())+" 首歌曲";
  rows.append(reference);save(rows);
}
void CollectionService::addTracks(const QString &id,
                                  const QVariantList &tracks) {
  int i = index(id);
  if (i < 0)
    return;
  auto lists = lists_;
  auto row = lists[i].toMap();
  if (row.value("reference").toBool()) {
    emit notice("在线收藏是原歌单的只读引用，请选择或新建本地歌单");
    return;
  }
  auto rows = row.value("tracks").toList();
  for (const auto &v : safeTracks(tracks)) {
    bool found = false;
    for (const auto &r : rows)
      if (r.toMap().value("trackId") == v.toMap().value("trackId")) {
        found = true;
        break;
      }
    if (!found)
      rows.append(v);
  }
  row["tracks"] = rows;
  row["subtitle"] = QString::number(rows.size()) + " 首歌曲";
  lists[i] = row;
  save(lists);
}
void CollectionService::removeTrack(const QString &id, int at) {
  int i = index(id);
  if (i < 0)
    return;
  auto lists = lists_;
  auto row = lists[i].toMap();
  auto rows = row.value("tracks").toList();
  if (at < 0 || at >= rows.size())
    return;
  rows.removeAt(at);
  row["tracks"] = rows;
  row["subtitle"] = QString::number(rows.size()) + " 首歌曲";
  lists[i] = row;
  save(lists);
}
QNetworkReply *
CollectionService::get(const QUrl &url,
                       std::function<void(QJsonObject, QString)> done) {
  QNetworkRequest request(url);
  request.setTransferTimeout(15000);
  request.setRawHeader("User-Agent", "Mozilla/5.0");
  if(url.host()=="music.163.com")request.setRawHeader("Referer","https://music.163.com/");
  auto *reply = network_->get(request);
  reply->setReadBufferSize(4 * 1024 * 1024 + 1);
  connect(reply, &QNetworkReply::readyRead, this, [reply] {
    if (reply->bytesAvailable() > 4 * 1024 * 1024)
      reply->abort();
  });
  connect(
      reply, &QNetworkReply::finished, this, [reply, done = std::move(done)] {
        const auto bytes = reply->isOpen() ? reply->readAll() : QByteArray{};
        const auto obj = QJsonDocument::fromJson(bytes).object();
        const auto err = reply->error() != QNetworkReply::NoError
                             ? QStringLiteral("网络请求失败，请重试")
                         : obj.isEmpty() ? QStringLiteral("服务返回了无效数据")
                                         : QString{};
        reply->deleteLater();
        done(obj, err);
      });
  return reply;
}
void CollectionService::refresh(const QString &order) {
  order_ = order == "new" ? "new" : "hot";
  const auto gen = ++discoveryGeneration_;
  if(platform_!="kw") {
    recommendations_.clear();charts_.clear();tags_.clear();tagIds_.clear();error_.clear();requests_=1;emit discoverChanged();
    const auto provider=platform_;auto* reply=online::platformRequest(*network_,provider,"lists",activeTag_,order_);
    if(!reply){requests_=0;emit discoverChanged();return;}
    connect(reply,&QNetworkReply::finished,this,[this,reply,provider,gen]{
      reply->deleteLater();
      if(gen!=discoveryGeneration_)return;
      requests_=0;
      const auto response=online::platformJson(reply->readAll());
      const bool networkOk=reply->error()==QNetworkReply::NoError;
      if(networkOk)recommendations_=online::platformPlaylists(provider,response);
      if(recommendations_.isEmpty()) {
        if(provider=="wy" && networkOk && response.value("code").toInt()==200) {
          error_=order_=="new" ? QStringLiteral("网易云暂未返回最新歌单，可切换“最热”查看")
                              : QStringLiteral("网易云暂未返回此分类的歌单，请稍后重试");
        } else error_=QStringLiteral("此平台歌单暂不可用，请稍后重试");
        qWarning().noquote()<<"Playlist catalog"<<provider<<"order"<<order_
            <<"HTTP"<<reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()
            <<"network"<<static_cast<int>(reply->error())<<"code"<<response.value("code").toVariant();
      }
      emit discoverChanged();
    });return;
  }
  requests_ = 3;
  error_.clear();
  emit discoverChanged();
  const auto endpoint = activeTag_.isEmpty()
                            ? "https://wapi.kuwo.cn/api/pc/classify/playlist/"
                              "getRcmPlayList?loginUid=0&loginSid=0&appUid="
                              "76039576&pn=1&rn=36&order=" +
                                  order_
                            : "https://wapi.kuwo.cn/api/pc/classify/playlist/"
                              "getTagPlayList?loginUid=0&loginSid=0&appUid="
                              "76039576&pn=1&rn=36&id=" +
                                  activeTag_;
  get(QUrl(endpoint), [this, gen](QJsonObject obj, QString err) {
    if (gen != discoveryGeneration_)
      return;
    if (err.isEmpty() && obj.value("code").toVariant().toInt() == 200) {
      QVariantList rows;
      for (const auto &v :
           obj.value("data").toObject().value("data").toArray()) {
        const auto o = v.toObject();
        if (o.value("digest").toVariant().toInt() != 8)
          continue;
        rows.append(QVariantMap{{"id", o.value("id").toVariant().toString()},
                                {"title", clean(o.value("name"))},
                                {"subtitle", clean(o.value("uname"))},
                                {"playCount", o.value("listencnt").toVariant()},
                                {"artwork", o.value("img").toString()},
                                {"kind", "playlist"},
                                {"color", "#5699c5"},
                                {"cover", 0}});
      }
      recommendations_ = rows;
    } else
      error_ = err.isEmpty() ? QStringLiteral("歌单服务暂不可用") : err;
    --requests_;
    emit discoverChanged();
  });
  get(QUrl("https://qukudata.kuwo.cn/"
           "q.k?op=query&cont=tree&node=2&pn=0&rn=1000&fmt=json&level=2"),
      [this, gen](QJsonObject obj, QString err) {
        if (gen != discoveryGeneration_)
          return;
        if (err.isEmpty()) {
          QVariantList rows;
          for (const auto &v : obj.value("child").toArray()) {
            auto o = v.toObject();
            if (o.value("source").toVariant().toString() != "1")
              continue;
            rows.append(
                QVariantMap{{"id", o.value("sourceid").toVariant().toString()},
                            {"title", clean(o.value("name"))},
                            {"artwork", o.value("pic").toString()},
                            {"kind", "chart"},
                            {"color", "#5699c5"}});
          }
          charts_ = rows;
        } else
          error_ = err;
        --requests_;
        emit discoverChanged();
      });
  get(QUrl("https://wapi.kuwo.cn/api/pc/classify/playlist/"
           "getTagList?cmd=rcm_keyword_playlist&user=0&prod=kwplayer_pc_9.0.5."
           "0&vipver=9.0.5.0&source=kwplayer_pc_9.0.5.0&loginUid=0&loginSid=0&"
           "appUid=76039576"),
      [this, gen](QJsonObject obj, QString err) {
        if (gen != discoveryGeneration_)
          return;
        if (err.isEmpty() && obj.value("code").toVariant().toInt() == 200) {
          QVariantList groups;
          QHash<QString, QString> ids;
          for (const auto &v : obj.value("data").toArray()) {
            const auto group = v.toObject();
            QStringList labels;
            for (const auto &item : group.value("data").toArray()) {
              const auto tag = item.toObject();
              if (tag.value("digest").toVariant().toInt() != 10000)
                continue;
              const auto label = clean(tag.value("name"));
              labels.append(label);
              ids[label] = tag.value("id").toVariant().toString();
            }
            if (!labels.isEmpty())
              groups.append(QVariantMap{{"title", clean(group.value("name"))},
                                        {"labels", labels}});
          }
          tags_ = groups;
          tagIds_ = ids;
        }
        --requests_;
        emit discoverChanged();
      });
}
void CollectionService::filter(const QString &key, const QString &value) {
  if (key == "sort") {
    activeTag_.clear();
    refresh(value);
    return;
  }
  QString label = value;
  if (key == "category") {
    if (value == "ranking")
      return;
    label = value == "chinese"    ? "华语"
            : value == "western"  ? "欧美"
            : value == "japanese" ? "日语"
                                  : "默认";
  }
  if (label == "默认")
    activeTag_.clear();
  else if (tagIds_.contains(label))
    activeTag_ = tagIds_.value(label);
  else {
    emit notice("分类尚未加载完成，请稍后重试");
    return;
  }
  refresh(order_);
}
void CollectionService::cancelDetail() {
  ++detailGeneration_;
  detailTrackIds_.clear();
  detailTracksById_.clear();
  detailPageDigests_.clear();
  if (bilibili_) bilibili_->cancel(bilibiliDetailId_);
  bilibiliDetailId_.clear();
  detailBusy_ = false;
  if (detailReply_) {
    detailReply_->abort();
    detailReply_ = nullptr;
  }
  emit detailChanged();
}
void CollectionService::open(const QVariantMap &collection) {
  cancelDetail();
  detail_ = collection;
  if(collection.contains("playlistId")) detail_["id"]=collection.value("playlistId");
  // Remote cards may contain a preview or an old saved snapshot, not a page.
  detail_["tracks"] = collection.value("kind") == "Local"
                          ? collection.value("tracks", QVariantList{}) : QVariantList{};
  detail_["error"] = "";
  detailBusy_ = collection.value("kind").toString() != "Local";
  emit detailChanged();
  if (detailBusy_) {
    const auto provider=collection.value("source","kw").toString();
    if (provider=="bili") {
      if (!bilibili_) { detailBusy_=false; detail_["error"]="哔哩哔哩尚未准备好"; emit detailChanged(); return; }
      const auto generation=detailGeneration_;
      bilibiliDetailId_=bilibili_->detail(detail_.value("bvid",detail_.value("id")).toString(),this,
          [this,generation](QVariantMap data,QString error) {
            if (generation!=detailGeneration_) return;
            bilibiliDetailId_.clear(); detailBusy_=false;
            if (error.isEmpty()) for (auto i=data.cbegin();i!=data.cend();++i) detail_[i.key()]=i.value();
            detail_["error"]=error; emit detailChanged();
          });
    }
    else if(collection.value("kind")=="album")albumPage(1,detailGeneration_);
    else if(provider=="kw")page(0,detailGeneration_);
    else if(provider=="wy" || provider=="kg")remotePlaylist(detailGeneration_);
    else {
      const auto gen=detailGeneration_;auto* reply=online::platformRequest(*network_,provider,"detail",detail_.value("id").toString());
      if(!reply){detailBusy_=false;detail_["error"]="此平台歌单暂不可用";emit detailChanged();return;}
      detailReply_=reply;connect(reply,&QNetworkReply::finished,this,[this,reply,provider,gen]{reply->deleteLater();if(gen!=detailGeneration_)return;detailReply_=nullptr;detailBusy_=false;
        if(reply->error()==QNetworkReply::NoError){const auto parsed=online::platformDetail(provider,online::platformJson(reply->readAll()));for(auto i=parsed.cbegin();i!=parsed.cend();++i)if(i.value().isValid()&&i.value()!=QString(""))detail_[i.key()]=i.value();}
        if(detail_.value("tracks").toList().isEmpty())detail_["error"]="歌单不存在、为空或平台暂不可用";emit detailChanged();});
    }
  }
}
void CollectionService::releaseDetail() {
  if (detail_.isEmpty() && !detailBusy_ && !detailReply_ && bilibiliDetailId_.isEmpty()) return;
  // The page owns this temporary snapshot; saved lists and the queue have
  // independent shared references. Invalidate requests before abort callbacks.
  detail_.clear();
  cancelDetail();
}
void CollectionService::finishRemoteDetail(const QString &error) {
  detailBusy_ = false;
  const auto count = detail_.value("tracks").toList().size();
  const auto total = detail_.value("total").toInt();
  if (!error.isEmpty())
    detail_["error"] = QStringLiteral("%1（已加载 %2 首）").arg(error).arg(count);
  else if (count >= playlistTrackLimit && total > count)
    detail_["error"] = QStringLiteral("此歌单已加载前 5000 首歌曲");
  else if (count < total)
    detail_["error"] = QStringLiteral("已加载 %1 / %2 首，部分歌曲暂不可用").arg(count).arg(total);
  detailTrackIds_.clear();
  detailTracksById_.clear();
  detailPageDigests_.clear();
  emit detailChanged();
}

void CollectionService::remotePlaylist(quint64 gen) {
  if (gen != detailGeneration_ || !detailBusy_) return;
  const auto provider = detail_.value("source").toString();
  auto *reply = online::platformRequest(*network_, provider, "detail", detail_.value("id").toString());
  detailReply_ = reply;
  connect(reply, &QNetworkReply::finished, this, [this, reply, provider, gen] {
    reply->deleteLater();
    if (gen != detailGeneration_) return;
    detailReply_ = nullptr;
    const auto object = online::platformJson(reply->readAll());
    const auto playlist = object.value("playlist").toObject();
    const bool valid = provider == "wy"
        ? object.value("code").toInt() == 200 && !playlist.isEmpty()
        : object.value("list").toObject().value("list").toObject().contains("total");
    if (reply->error() != QNetworkReply::NoError || !valid) {
      finishRemoteDetail(QStringLiteral("歌单获取失败，请重新打开重试"));
      return;
    }
    const auto parsed = online::platformDetail(provider, object);
    for (auto i = parsed.cbegin(); i != parsed.cend(); ++i)
      if (i.key() != "tracks" && i.value().isValid() && i.value() != QString(""))
        detail_[i.key()] = i.value();
    if (provider == "kg") {
      // The mobile web response is a ten-song preview, even with page parameters.
      // Load the actual pages through the catalog API instead.
      kugouPage(1, 0, gen);
      return;
    }
    const auto ids = playlist.value("trackIds").toArray();
    QSet<QString> seen;
    for (const auto &value : ids) {
      const auto id = value.toObject().value("id").toVariant().toString();
      if (id.isEmpty() || seen.contains(id)) continue;
      seen.insert(id);
      if (detailTrackIds_.size() < playlistTrackLimit) detailTrackIds_.append(id);
    }
    detail_["total"] = qMax(detail_.value("total").toInt(), int(seen.size()));
    const auto rows = parsed.value("tracks").toList().mid(0, playlistTrackLimit);
    for (const auto &value : rows) {
      const auto row = value.toMap();
      detailTracksById_.insert(row.value("rid").toString(), row);
    }
    detail_["tracks"] = rows;
    // Anonymous NetEase detail can contain only ten tracks; trackIds retains
    // the playlist order and is the cursor, regardless of missing song details.
    neteaseTracks(0, gen);
  });
}

void CollectionService::neteaseTracks(int offset, quint64 gen) {
  if (gen != detailGeneration_ || !detailBusy_) return;
  QStringList batch;
  while (offset < detailTrackIds_.size() && batch.isEmpty()) {
    const auto end = qMin(offset + playlistPageSize, int(detailTrackIds_.size()));
    for (; offset < end; ++offset) {
      const auto &id = detailTrackIds_[offset];
      if (!detailTracksById_.contains(id)) batch.append(id);
    }
  }
  if (!detailTrackIds_.isEmpty()) {
    QVariantList rows;
    for (const auto &id : detailTrackIds_)
      if (detailTracksById_.contains(id)) rows.append(detailTracksById_.value(id));
    detail_["tracks"] = rows;
  }
  if (batch.isEmpty()) {
    finishRemoteDetail();
    return;
  }
  emit detailChanged();
  if (gen != detailGeneration_ || !detailBusy_) return;
  auto *reply = online::platformRequest(*network_, "wy", "songs", batch.join(','));
  detailReply_ = reply;
  connect(reply, &QNetworkReply::finished, this, [this, reply, batch, offset, gen] {
    reply->deleteLater();
    if (gen != detailGeneration_) return;
    detailReply_ = nullptr;
    const auto object = online::platformJson(reply->readAll());
    if (reply->error() != QNetworkReply::NoError || object.value("code").toInt() != 200 || !object.value("songs").isArray()) {
      finishRemoteDetail(QStringLiteral("歌曲详情加载中断，请重新打开重试"));
      return;
    }
    for (const auto &value : online::platformSongs("wy", object)) {
      const auto row = value.toMap();
      const auto id = row.value("rid").toString();
      if (batch.contains(id)) detailTracksById_.insert(id, row);
    }
    neteaseTracks(offset, gen);
  });
}

void CollectionService::kugouPage(int number, int received, quint64 gen) {
  if (gen != detailGeneration_ || !detailBusy_) return;
  auto *reply = online::platformRequest(*network_, "kg", "playlistSongs", detail_.value("id").toString(),
                                        "hot", number, playlistPageSize);
  detailReply_ = reply;
  connect(reply, &QNetworkReply::finished, this, [this, reply, number, received, gen] {
    reply->deleteLater();
    if (gen != detailGeneration_) return;
    detailReply_ = nullptr;
    const auto object = online::platformJson(reply->readAll());
    const auto data = object.value("data").toObject();
    if (reply->error() != QNetworkReply::NoError || object.value("status").toInt() != 1 || !data.value("info").isArray()) {
      finishRemoteDetail(QStringLiteral("歌单分页加载中断，请重新打开重试"));
      return;
    }
    const auto raw = data.value("info").toArray();
    const auto digest = QCryptographicHash::hash(QJsonDocument(raw).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256);
    if (!raw.isEmpty() && detailPageDigests_.contains(digest)) {
      finishRemoteDetail(QStringLiteral("平台重复返回同一页，请稍后重试"));
      return;
    }
    detailPageDigests_.insert(digest);
    if (data.contains("total")) detail_["total"] = data.value("total").toVariant().toInt();
    auto rows = detail_.value("tracks").toList();
    for (const auto &value : online::platformSongs("kg", object)) {
      // Different album/file versions can share audio_id. Preserve the actual
      // playlist entries and their hashes; repeated pages are checked above.
      if (rows.size() >= playlistTrackLimit) break;
      rows.append(value);
    }
    detail_["tracks"] = rows;
    const int consumed = received + int(raw.size());
    // Raw entries advance the page even when one entry has no usable identity.
    const bool more = !raw.isEmpty() && consumed < detail_.value("total").toInt()
                      && number * playlistPageSize < playlistTrackLimit;
    if (!more) {
      finishRemoteDetail();
      return;
    }
    emit detailChanged();
    kugouPage(number + 1, consumed, gen);
  });
}

void CollectionService::albumPage(int number, quint64 gen) {
  const auto provider=detail_.value("source").toString();
  auto* reply=online::platformRequest(*network_,provider,"album",detail_.value("id").toString(),"hot",number,100);
  if(!reply){detailBusy_=false;detail_["error"]="此平台专辑暂不可用";emit detailChanged();return;}
  detailReply_=reply;
  connect(reply,&QNetworkReply::finished,this,[this,reply,provider,number,gen] {
    reply->deleteLater();if(gen!=detailGeneration_)return;detailReply_=nullptr;
    const auto data=online::platformJson(reply->readAll());
    const auto batch=online::platformAlbumSongs(provider,data);
    auto rows=detail_.value("tracks").toList();
    for(auto value:batch) {
      auto row=value.toMap();
      if(row.value("artwork").toString().isEmpty())row["artwork"]=detail_.value("artwork");
      if(row.value("album").toString().isEmpty())row["album"]=detail_.value("title");
      if(row.value("artist").toString().isEmpty())row["artist"]=detail_.value("artist");
      rows.append(row);
    }
    detail_["tracks"]=rows;
    // NetEase returns the complete album; other providers accept page offsets.
    const auto miguTotal=data.value("data").toObject().value("totalCount").toVariant().toInt();
    const bool more=provider!="wy" && !batch.isEmpty() && (batch.size()==100 || (provider=="mg" && rows.size()<miguTotal))
                    && rows.size()<5000 && reply->error()==QNetworkReply::NoError;
    detailBusy_=more;
    if(reply->error()!=QNetworkReply::NoError || rows.isEmpty())detail_["error"]="专辑为空或平台暂未提供歌曲，请稍后重试";
    emit detailChanged();if(more)albumPage(number+1,gen);
  });
}
void CollectionService::reloadSaved() {
  lists_=QJsonDocument::fromJson(QByteArray::fromStdString(db_.getSetting("collections.v1").value_or("[]"))).array().toVariantList();
  refreshLikedTrackIndex();
  const auto selected=index(detail_.value("id").toString());
  if(selected>=0){detail_=lists_[selected].toMap();emit detailChanged();}
  emit playlistsChanged();
}
void CollectionService::openTitle(const QString &title) {
  for (const auto &list : {lists_, recommendations_, charts_})
    for (const auto &v : list)
      if (v.toMap().value("title") == title) {
        open(v.toMap());
        return;
      }
}
void CollectionService::openLink(const QString &link) {
  QRegularExpression re("(?:[?&](?:id|disstid|pid)=|playlist_detail/|playlist/|single/|^)([0-9]+)");
  const auto m = re.match(link.trimmed());
  if (!m.hasMatch()) {
    emit notice("请输入当前平台的歌单链接或歌单 ID");
    return;
  }
  open(
      {{"id", m.captured(1)}, {"source",platform_}, {"kind", "playlist"}, {"title", "正在加载歌单"}});
}
void CollectionService::page(int number, quint64 gen) {
  const bool chart = detail_.value("kind") == "chart";
  const auto id = detail_.value("id").toString();
  QUrl url(chart ? "https://kbangserver.kuwo.cn/ksong.s"
                 : "https://nplserver.kuwo.cn/pl.svc");
  QUrlQuery q(chart ? "from=pc&fmt=json&type=bang&data=content&show_copyright_"
                      "off=0&pcmp4=1&isbang=1"
                    : "op=getlistinfo&encode=utf8&keyset=pl2012&identity=kuwo&"
                      "pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1");
  q.addQueryItem(chart ? "id" : "pid", id);
  q.addQueryItem("pn", QString::number(number));
  q.addQueryItem("rn", "100");
  url.setQuery(q);
  detailReply_ =
      get(url, [this, gen, number, chart](QJsonObject obj, QString err) {
        if (gen != detailGeneration_)
          return;
        detailReply_ = nullptr;
        if (err.isEmpty() && !chart && obj.value("result").toString() != "ok")
          err = "歌单不存在或暂不可用";
        if (!err.isEmpty()) {
          detail_["error"] = err;
          detailBusy_ = false;
          emit detailChanged();
          return;
        }
        auto rows = detail_.value("tracks").toList();
        const auto batch = obj.value("musiclist").toArray();
        for (const auto &v : batch)
          rows.append(song(v.toObject()));
        detail_["tracks"] = rows;
        detail_["title"] = clean(obj.value(chart ? "name" : "title"));
        detail_["artwork"] =
            obj.value("pic").toString(detail_.value("artwork").toString());
        if (obj.contains("playnum")) detail_["playCount"] = obj.value("playnum").toVariant();
        detail_["total"] =
            obj.value(chart ? "num" : "total").toVariant().toInt();
        const bool more = batch.size() == 100 &&
                          rows.size() < detail_.value("total").toInt() &&
                          rows.size() < 5000;
        if (!more && rows.size() < detail_.value("total").toInt() &&
            rows.size() >= 5000)
          detail_["error"] = "此歌单已加载前 5000 首歌曲";
        detailBusy_ = more;
        emit detailChanged();
        if (more)
          page(number + 1, gen);
      });
}
} // namespace listenfree::qmlbridge

namespace listenfree::qmlbridge {
void CollectionService::setPlatform(const QString& value) {
  if(value==platform_||!QStringList{"kw","kg","tx","wy","mg"}.contains(value))return;
  platform_=value;activeTag_.clear();emit platformChanged();refresh(order_);
}
}

namespace listenfree::qmlbridge {
void CollectionService::updateTrackMetadata(const QVariantMap& track) {
    const auto path=track.value("localPath").toString();
    if(path.isEmpty())return;
    auto lists=lists_;bool changed=false;
    for(auto& value:lists) {
        auto list=value.toMap();auto tracks=list.value("tracks").toList();
        for(auto& item:tracks) {
            auto row=item.toMap();
            if(row.value("localPath").toString().compare(path,Qt::CaseInsensitive)!=0)continue;
            for(const auto& key:{"title","artist","album","year","track","genre","lyrics"})if(track.contains(key))row[key]=track.value(key);
            item=row;changed=true;
        }
        list["tracks"]=tracks;value=list;
    }
    if(changed)save(lists);
}
}
