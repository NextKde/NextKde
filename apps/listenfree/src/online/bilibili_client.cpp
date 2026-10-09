#include "bilibili_client.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSet>
#include <QTimer>
#include <QUrlQuery>
#include <QUuid>
#include <algorithm>

namespace listenfree::online {
namespace {
const QByteArray agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
QString plain(QString text) {
    text.remove(QRegularExpression("<[^>]*>"));
    return text.replace("&quot;", "\"").replace("&#039;", "'").replace("&apos;", "'")
        .replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ").replace("&amp;", "&").trimmed();
}
QString cover(QString url) { return url.startsWith("//") ? "https:"+url : url; }
bool validId(const QString& id) { return QRegularExpression("^BV[0-9A-Za-z]{10}$").match(id).hasMatch(); }
QString apiError(const QJsonObject& root) {
    const int code = root.value("code").toInt(-1);
    return code == 0 ? QString{} : QStringLiteral("哔哩哔哩暂不可用（%1），请稍后重试或在账号中登录").arg(code);
}
}
QString bilibiliMixinKey(const QJsonObject& nav) {
    const auto images = nav.value("data").toObject().value("wbi_img").toObject();
    const QString lookup = QFileInfo(QUrl(images.value("img_url").toString()).path()).completeBaseName()
        + QFileInfo(QUrl(images.value("sub_url").toString()).path()).completeBaseName();
    constexpr int table[]{46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13};
    QString key; if (lookup.size() >= 64) for (int i : table) key += lookup[i]; return key;
}
QUrl bilibiliSignedUrl(const QString& path, const QMap<QString, QString>& values, const QString& key) {
    auto params = values; params["wts"] = QString::number(QDateTime::currentSecsSinceEpoch());
    QByteArray query;
    for (auto it=params.cbegin(); it!=params.cend(); ++it) {
        QString value=it.value(); value.remove(QRegularExpression("[!'()*]"));
        if (!query.isEmpty()) query+='&';
        query+=QUrl::toPercentEncoding(it.key())+'='+QUrl::toPercentEncoding(value);
    }
    if (!key.isEmpty()) query+="&w_rid="+QCryptographicHash::hash(query+key.toUtf8(),QCryptographicHash::Md5).toHex();
    return QUrl("https://api.bilibili.com"+path+"?"+QString::fromLatin1(query));
}
QVariantMap BilibiliClient::videoFromPlayInfo(const QJsonObject& data) {
    QJsonObject best;
    int bestQuality=-1, bestCodec=-1;
    for(const auto& value:data.value("dash").toObject().value("video").toArray()) {
        const auto video=value.toObject();
        const QUrl url(video.value("baseUrl").toString(video.value("base_url").toString()));
        const int quality=video.value("id").toInt();
        const int width=video.value("width").toInt(),height=video.value("height").toInt();
        // API quality 80 is ordinary 1080p, including letterboxed 1920x800 MV.
        // Resolution is chosen before codec; 480p AVC must not beat 1080p HEVC.
        if(quality<=0 || quality>80 || std::max(width,height)>1920 || std::min(width,height)>1080 ||
           url.host().isEmpty() || (url.scheme()!="https" && url.scheme()!="http"))continue;
        const int codec=video.value("codecid").toInt()==7?2:video.value("codecid").toInt()==12?1:0;
        if(quality>bestQuality || (quality==bestQuality && codec>bestCodec)) {
            best=video;bestQuality=quality;bestCodec=codec;
        }
    }
    if(!best.isEmpty())return {{"url",best.value("baseUrl").toString(best.value("base_url").toString())},
        {"quality",bestQuality},{"width",best.value("width").toInt()},{"height",best.value("height").toInt()}};
    // A multi-part progressive response needs concatenation; never silently play only part 1.
    const auto urls=data.value("durl").toArray();
    if(urls.size()!=1)return {};
    const QUrl url(urls.first().toObject().value("url").toString());
    if(url.host().isEmpty() || (url.scheme()!="http" && url.scheme()!="https"))return {};
    return {{"url",url.toString()},{"quality",data.value("quality").toInt()}};
}
struct BilibiliClient::Job {
    QString id, cacheKey, category;
    Done done;
    QPointer<QObject> context;
    QMetaObject::Connection ownerGone;
    QPointer<QTimer> timer;
    QList<QPointer<QNetworkReply>> replies;
    QJsonArray videos;
    QList<QVariantMap> entries;
    int next{0}, active{0}, completed{0}, failed{0}, pages{1};
};
BilibiliClient::BilibiliClient(QObject* parent, QNetworkAccessManager* network)
    : QObject(parent), network_(network ? network : &ownedNetwork_) {}
BilibiliClient::~BilibiliClient() { const auto ids=jobs_.keys(); for (const auto& id:ids) cancel(id); }
void BilibiliClient::setCookie(const QByteArray& cookie) {
    if (accountCookie_==cookie) return;
    accountCookie_.fill(0); accountCookie_=cookie; mixin_.clear(); keyTime_=0; searchCache_.clear();
}
BilibiliClient::Task BilibiliClient::create(QObject* context, Done done) {
    auto job=std::make_shared<Job>(); job->id="bili-"+QUuid::createUuid().toString(QUuid::WithoutBraces);
    job->context=context ? context : this; job->done=std::move(done); jobs_.insert(job->id,job);
    job->ownerGone=connect(job->context,&QObject::destroyed,this,[this,id=job->id]{cancel(id);});
    job->timer=new QTimer(this); job->timer->setSingleShot(true);
    connect(job->timer,&QTimer::timeout,this,[this,job]{finish(job,{},QStringLiteral("哔哩哔哩请求超时，请重试"));});
    job->timer->start(30000); return job;
}
bool BilibiliClient::cancel(const QString& id) {
    const auto job=jobs_.take(id); if (!job) return false;
    disconnect(job->ownerGone);
    if (job->timer) { job->timer->stop(); job->timer->deleteLater(); }
    const auto replies=job->replies;
    job->replies.clear();
    for (const auto& reply:replies) if (reply) reply->abort();
    return true;
}
void BilibiliClient::finish(const Task& job, QVariantMap data, QString error) {
    if (!jobs_.contains(job->id)) return;
    cancel(job->id);
    if (job->context) job->done(std::move(data),std::move(error));
}
void BilibiliClient::get(const Task& job, const QUrl& url, std::function<void(QJsonObject,QString)> done) {
    if (!jobs_.contains(job->id)) return;
    QNetworkRequest request(url); request.setTransferTimeout(10000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute,QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute,QNetworkRequest::Manual);
    request.setRawHeader("User-Agent",agent); request.setRawHeader("Referer","https://www.bilibili.com/");
    QByteArray cookies=accountCookie_;
    if (!cookies.contains("buvid3=") && !visitorCookie_.isEmpty()) { if(!cookies.isEmpty())cookies+="; ";cookies+=visitorCookie_; }
    if (!cookies.isEmpty() && url.host()=="api.bilibili.com") request.setRawHeader("Cookie",cookies);
    auto* reply=network_->get(request); job->replies.append(reply); reply->setReadBufferSize(4*1024*1024+1);
    connect(reply,&QNetworkReply::readyRead,this,[reply]{if(reply->bytesAvailable()>4*1024*1024)reply->abort();});
    connect(reply,&QNetworkReply::finished,this,[this,job,reply,done=std::move(done)] {
        reply->deleteLater(); job->replies.removeAll(reply);
        if (!jobs_.contains(job->id)) return;
        if (reply->error()!=QNetworkReply::NoError) { done({},QStringLiteral("哔哩哔哩连接失败，请重试或检查账号登录状态")); return; }
        const auto root=QJsonDocument::fromJson(reply->readAll()).object();
        done(root,root.isEmpty()?QStringLiteral("哔哩哔哩未返回有效数据"):QString{});
    });
}
void BilibiliClient::prepare(const Task& job, std::function<void()> ready) {
    const auto visitor=[this,job,ready] {
        if (accountCookie_.contains("buvid3=") || !visitorCookie_.isEmpty()) { ready(); return; }
        get(job,QUrl("https://api.bilibili.com/x/frontend/finger/spi"),[this,ready](QJsonObject root,QString) {
            const auto data=root.value("data").toObject(); const auto b3=data.value("b_3").toString();
            if(!b3.isEmpty())visitorCookie_=("buvid3="+b3+"; buvid4="+data.value("b_4").toString()).toUtf8();
            ready();
        });
    };
    if (!mixin_.isEmpty() && QDateTime::currentSecsSinceEpoch()-keyTime_<30) { visitor(); return; }
    get(job,QUrl("https://api.bilibili.com/x/web-interface/nav"),[this,job,visitor](QJsonObject root,QString error) {
        mixin_=bilibiliMixinKey(root); keyTime_=QDateTime::currentSecsSinceEpoch();
        if (!error.isEmpty() || mixin_.isEmpty()) { finish(job,{},error.isEmpty()?QStringLiteral("哔哩哔哩暂时无法准备请求，请重试"):error); return; }
        visitor();
    });
}
QVariantMap BilibiliClient::trackFromPage(const QJsonObject& view,const QJsonObject& page) {
    const QString bvid=view.value("bvid").toString(), cid=page.value("cid").toVariant().toString();
    if (!validId(bvid) || cid.toLongLong()<=0) return {};
    const auto count=view.value("pages").toArray().size();
    const QString title=plain((count>1?page.value("part"):view.value("title")).toString());
    const auto ms=page.value("duration").toVariant().toLongLong()*1000;
    const QString rid=bvid+"_"+cid;
    return {{"source","bili"},{"trackId","bili:"+rid},{"rid",rid},{"bvid",bvid},{"cid",cid},
        {"aid",view.value("aid").toVariant()},{"page",page.value("page").toInt(1)},{"pageCount",qMax(1,count)},
        {"videoTitle",plain(view.value("title").toString())},{"title",title},{"album",""},
        {"artist",plain(view.value("owner").toObject().value("name").toString())},
        {"artwork",cover(view.value("pic").toString())},{"durationMs",ms},
        {"duration",QString("%1:%2").arg(ms/60000).arg(ms/1000%60,2,10,QChar('0'))},
        {"webUrl","https://www.bilibili.com/video/"+bvid+"?p="+QString::number(page.value("page").toInt(1))}};
}
QVariantMap BilibiliClient::collectionFromView(const QJsonObject& view) {
    const QString bvid=view.value("bvid").toString(); if(!validId(bvid))return {};
    auto pages=view.value("pages").toArray().toVariantList();
    std::stable_sort(pages.begin(),pages.end(),[](const QVariant& a,const QVariant& b){return a.toMap().value("page").toInt()<b.toMap().value("page").toInt();});
    QVariantList tracks; QSet<QString> seen;
    for(const auto& page:pages) {const auto track=trackFromPage(view,QJsonObject::fromVariantMap(page.toMap()));const auto id=track.value("trackId").toString();if(track.isEmpty()||seen.contains(id))continue;seen.insert(id);tracks.append(track);if(tracks.size()>=5000)break;}
    const QString artist=plain(view.value("owner").toObject().value("name").toString());
    return {{"id",bvid},{"bvid",bvid},{"source","bili"},{"kind","playlist"},{"title",plain(view.value("title").toString())},
        {"artist",artist},{"artwork",cover(view.value("pic").toString())},{"description",view.value("desc").toString()},
        {"subtitle",QStringLiteral("%1 · %2 首").arg(artist).arg(tracks.size())},{"total",tracks.size()},{"tracks",tracks},
        {"url","https://www.bilibili.com/video/"+bvid}};
}
QString BilibiliClient::search(const QString& query,int page,const QString& category,QObject* context,Done done) {
    auto job=create(context,std::move(done)); job->category=category; job->cacheKey=query.trimmed().left(200)+":"+QString::number(page);
    QTimer::singleShot(0,this,[this,job,query,page] {
        if(!jobs_.contains(job->id))return;
        if(query.trimmed().isEmpty() || (job->category!="songs" && job->category!="playlists")) {finish(job,{{"rows",QVariantList{}},{"pages",1},{"total",0}});return;}
        if(const auto* cached=searchCache_.object(job->cacheKey);cached && QDateTime::currentSecsSinceEpoch()-cached->time<120) {
            finish(job,{{"rows",cached->data.value(job->category)},{"pages",cached->data.value("pages")},{"total",-1}});return;
        }
        prepare(job,[this,job,query,page] {
            get(job,bilibiliSignedUrl("/x/web-interface/wbi/search/type",{{"keyword",query.trimmed().left(200)},{"search_type","video"},{"order","totalrank"},{"page_size","20"},{"page",QString::number(qMax(1,page))}},mixin_),[this,job](QJsonObject root,QString error) {
                if(error.isEmpty())error=apiError(root);
                if(!error.isEmpty()){finish(job,{},error);return;}
                const auto data=root.value("data").toObject(); job->pages=qMax(1,data.value("numPages").toInt(1));
                QSet<QString> seen;
                for(const auto& value:data.value("result").toArray()){const auto id=value.toObject().value("bvid").toString();if(!validId(id)||seen.contains(id))continue;seen.insert(id);job->videos.append(value);if(job->videos.size()>=30)break;}
                job->entries.resize(job->videos.size()); searchViews(job);
            });
        });
    }); return job->id;
}
void BilibiliClient::searchViews(const Task& job) {
    if(!jobs_.contains(job->id))return;
    if(job->completed==job->videos.size()) {
        QVariantList songs,playlists;
        for(const auto& entry:job->entries) {if(entry.isEmpty())continue;if(entry.contains("song"))songs.append(entry.value("song"));else playlists.append(entry);}
        QVariantMap all{{"songs",songs},{"playlists",playlists},{"pages",job->pages}};
        if(!job->failed)searchCache_.insert(job->cacheKey,new CacheEntry{QDateTime::currentSecsSinceEpoch(),all});
        finish(job,{{"rows",all.value(job->category)},{"pages",job->pages},{"total",job->videos.isEmpty()?0:-1}},
            job->failed==job->videos.size() && job->failed>0?QStringLiteral("视频详情暂不可用，无法确定分 P，请重试"):QString{}); return;
    }
    while(job->active<4 && job->next<job->videos.size()) {
        const int index=job->next++; ++job->active;
        const auto bvid=job->videos[index].toObject().value("bvid").toString();
        get(job,bilibiliSignedUrl("/x/web-interface/view",{{"bvid",bvid}},{}),[this,job,index](QJsonObject root,QString error) {
            --job->active; ++job->completed; const auto view=root.value("data").toObject();
            if(error.isEmpty())error=apiError(root);
            const auto collection=error.isEmpty()?collectionFromView(view):QVariantMap{};
            const auto tracks=collection.value("tracks").toList();
            if(tracks.isEmpty())++job->failed;
            else if(tracks.size()==1)job->entries[index]={{"song",tracks.first()}};
            else {auto summary=collection;summary.remove("tracks");summary.remove("description");job->entries[index]=summary;}
            searchViews(job);
        });
    }
}
QString BilibiliClient::detail(const QString& bvid,QObject* context,Done done) {
    auto job=create(context,std::move(done));
    QTimer::singleShot(0,this,[this,job,bvid] {
        if(!validId(bvid)){finish(job,{},QStringLiteral("B 站视频编号无效"));return;}
        get(job,bilibiliSignedUrl("/x/web-interface/view",{{"bvid",bvid}},{}),[this,job](QJsonObject root,QString error) {
            if(error.isEmpty())error=apiError(root);
            const auto result=collectionFromView(root.value("data").toObject());
            if(error.isEmpty() && result.value("tracks").toList().isEmpty())error=QStringLiteral("这个视频没有可用分 P");
            finish(job,result,error);
        });
    });return job->id;
}
QVariantMap BilibiliClient::audioFromPlayInfo(const QJsonObject& data,const QString& quality,const QString& bvid) {
    const auto dash=data.value("dash").toObject(); QJsonObject best; int score=-1;
    if(quality.startsWith("flac"))best=dash.value("flac").toObject().value("audio").toObject();
    if(best.isEmpty())for(const auto& value:dash.value("audio").toArray()) {
        const auto audio=value.toObject();const int bitrate=audio.value("bandwidth").toInt();
        if(audio.value("baseUrl").toString(audio.value("base_url").toString()).isEmpty())continue;
        const int target=quality=="128k"?160000:quality=="192k"?220000:quality=="320k"?350000:10000000;
        const int rank=bitrate<=target?10000000+bitrate:10000000-bitrate;
        if(rank>score){score=rank;best=audio;}
    }
    QString url=best.value("baseUrl").toString(best.value("base_url").toString());
    QString extension="m4a"; // DASH audio is an MP4 container, including FLAC-in-MP4.
    QString actual=best.value("id").toInt()==30251?"flac24bit":best.value("bandwidth").toInt()>220000?"320k":best.value("bandwidth").toInt()>160000?"192k":"128k";
    if(url.isEmpty()) {const auto durl=data.value("durl").toArray();if(durl.size()==1)url=durl.first().toObject().value("url").toString();actual="auto";extension=data.value("format").toString().contains("flv")?"flv":"mp4";}
    if(QUrl(url).scheme()!="https" && QUrl(url).scheme()!="http")return {};
    return {{"url",url},{"quality",actual},{"extension",extension},{"headers",QVariantMap{{"User-Agent",QString::fromLatin1(agent)},{"Referer","https://www.bilibili.com/video/"+bvid}}}};
}
QString BilibiliClient::audio(const QVariantMap& track,const QString& quality,QObject* context,Done done) {
    auto job=create(context,std::move(done));
    QTimer::singleShot(0,this,[this,job,track,quality] {prepare(job,[this,job,track,quality]{requestAudio(job,track,quality);});});return job->id;
}
void BilibiliClient::requestAudio(const Task& job,const QVariantMap& track,const QString& quality) {
    const QString bvid=track.value("bvid",track.value("rid").toString().section('_',0,0)).toString();
    const QString cid=track.value("cid",track.value("rid").toString().section('_',1,1)).toString();
    if(!validId(bvid)){finish(job,{},QStringLiteral("B 站视频编号无效"));return;}
    if(cid.toLongLong()<=0) {
        get(job,bilibiliSignedUrl("/x/web-interface/view",{{"bvid",bvid}},{}),[this,job,track,quality](QJsonObject root,QString error) {
            if(error.isEmpty())error=apiError(root);
            if(!error.isEmpty()){finish(job,{},error);return;}
            const auto view=root.value("data").toObject();QVariantMap selected;
            for(const auto& page:view.value("pages").toArray())if(page.toObject().value("page").toInt()==track.value("page",1).toInt())selected=trackFromPage(view,page.toObject());
            if(selected.isEmpty()){finish(job,{},QStringLiteral("原分 P 已不存在，请重新打开歌单"));return;}
            requestAudio(job,selected,quality);
        });return;
    }
    get(job,bilibiliSignedUrl("/x/player/wbi/playurl",{{"bvid",bvid},{"cid",cid},{"qn","80"},{"fnval","4048"},{"fnver","0"},{"fourk","1"}},mixin_),[this,job,bvid,quality](QJsonObject root,QString error) {
        if(error.isEmpty())error=apiError(root);
        const auto result=audioFromPlayInfo(root.value("data").toObject(),quality,bvid);
        if(error.isEmpty() && result.isEmpty())error=QStringLiteral("这个分 P 暂无可播放音频，请检查登录状态或选择其他歌曲");
        finish(job,result,error);
    });
}
}
