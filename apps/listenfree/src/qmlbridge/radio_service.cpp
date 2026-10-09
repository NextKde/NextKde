#include "radio_service.h"
#include <QDnsLookup>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRandomGenerator>
#include <QUrlQuery>
#include <QtConcurrentRun>
#include <algorithm>

namespace listenfree::qmlbridge {
namespace {
QString key(const QVariantMap& row) {return row.value("radioProvider").toString()+":"+row.value("radioId").toString();}
QUrl netease(const QString& path,const QUrlQuery& query={}) {
    QUrl url("https://music.163.com/api/"+path);url.setQuery(query);return url;
}
}
RadioService::RadioService(infrastructure::database::Database& db,QObject* parent):QObject(parent),db_(db) {
    for(const auto* provider:{"icecast","radiobrowser","netease"}) states_.insert(provider,{});
    favorites_=QJsonDocument::fromJson(QByteArray::fromStdString(db_.getSetting("radio.favorites.v1").value_or("[]"))).array().toVariantList();
    connect(&parser_,&QFutureWatcherBase::finished,this,[this] {
        auto future=parser_.future();
        auto parsed=future.takeResult();
        if(parsed.second.isEmpty()) {icecast_=std::move(parsed.first);icecastFetched_=QDateTime::currentDateTimeUtc();}
        if(provider_=="icecast" && !favoritesOnly_) {
            busy_=false;error_=parsed.second;
            if(error_.isEmpty())filterIcecast();else emit changed();
        }
    });
}
void RadioService::cancel() {
    ++generation_;busy_=false;error_.clear();
    if(reply_) {reply_->disconnect(this);reply_->abort();reply_->deleteLater();reply_=nullptr;}
}
void RadioService::setProvider(const QString& value) {
    if(value==provider_ || !states_.contains(value))return;
    cancel();provider_=value;emit categoriesChanged();load();
}
void RadioService::setMode(const QString& value) {
    if(provider_!="netease" || (value!="broadcast" && value!="podcast") || value==mode())return;
    cancel();state()=State{};state().mode=value;emit categoriesChanged();load();
}
QVariantList RadioService::categories()const {
    if(provider_=="netease" && mode()=="broadcast")return neteaseCategories_;
    if(provider_=="radiobrowser")return {QVariantMap{{"id",""},{"name","全部地区"}},QVariantMap{{"id","CN"},{"name","中国"}},QVariantMap{{"id","JP"},{"name","日本"}},QVariantMap{{"id","US"},{"name","美国"}},QVariantMap{{"id","GB"},{"name","英国"}}};
    return {};
}
void RadioService::setCategory(const QString& value) {
    if(value==category())return;cancel();state().category=value;state().page=1;state().loaded=false;state().pages.clear();state().cursors={"0|-1"};load();
}
void RadioService::setFavoritesOnly(bool value) {if(value==favoritesOnly_)return;cancel();favoritesOnly_=value;load();}
void RadioService::activate() {if(!activated_){activated_=true;load();}}
void RadioService::refresh() {cancel();state().loaded=false;state().pages.clear();state().page=1;state().cursors={"0|-1"};if(provider_=="netease")broadcastCategory_.clear();load(true);}
void RadioService::search(const QString& text) {
    const auto term=text.trimmed().left(160);if(term==query())return;
    cancel();state().query=term;state().loaded=false;state().page=1;state().pages.clear();state().cursors={"0|-1"};load();
}
void RadioService::goToPage(int requested) {
    if(busy_ || requested<1 || requested==page() || (requested>page() && !hasMore()))return;
    cancel();state().page=requested;state().loaded=false;load();
}
void RadioService::openPodcast(const QVariantMap& value) {
    if(value.value("radioId").toString().isEmpty())return;
    cancel();provider_="netease";favoritesOnly_=false;state().mode="podcast";
    state().podcast=value;state().page=1;state().rows.clear();state().total=-1;state().more=false;state().loaded=false;
    emit categoriesChanged();load();
}
void RadioService::closePodcast(){cancel();state().podcast.clear();state().page=1;state().rows.clear();state().total=-1;state().more=false;state().loaded=false;load();}
bool RadioService::isFavorite(const QVariantMap& row)const {
    const auto id=key(row);for(const auto& favorite:favorites_)if(key(favorite.toMap())==id)return true;return false;
}
void RadioService::toggleFavorite(const QVariantMap& row) {
    if(row.value("radioId").toString().isEmpty())return;
    const auto id=key(row);int at=-1;for(int i=0;i<favorites_.size();++i)if(key(favorites_[i].toMap())==id){at=i;break;}
    if(at>=0)favorites_.removeAt(at);else {auto saved=row;saved.remove("entryId");if(saved.value("radioProvider").toString().startsWith("netease"))saved.remove("remoteUrl");favorites_.prepend(saved);}
    db_.setSetting("radio.favorites.v1",QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(favorites_)).toJson(QJsonDocument::Compact)));
    ++favoritesRevision_;emit favoritesChanged();if(favoritesOnly_)showFavorites();
}
void RadioService::showFavorites() {
    QVariantList filtered;
    for(const auto& value:favorites_) {
        const auto row=value.toMap();const auto p=row.value("radioProvider").toString();
        if((p==provider_ || (provider_=="netease" && p.startsWith("netease"))) &&
            (query().isEmpty() || row.value("title").toString().contains(query(),Qt::CaseInsensitive)))filtered.append(row);
    }
    favoriteRows_=std::move(filtered);busy_=false;emit changed();
}
void RadioService::load(bool force) {
    activated_=true;
    if(favoritesOnly_){showFavorites();return;}
    if(!force && state().loaded){emit changed();return;}
    busy_=true;error_.clear();emit changed();
    if(provider_=="icecast")loadIcecast(force);
    else if(provider_=="radiobrowser")loadBrowser();
    else loadNetease();
}
void RadioService::finish(QVariantList rows,int count,bool more) {
    state().rows=std::move(rows);state().total=count;state().more=more;state().loaded=true;busy_=false;emit changed();
}
void RadioService::get(const QUrl& url,std::function<void(QByteArray,QString)> done,int limit) {
    const auto gen=generation_;
    QNetworkRequest request(url);request.setTransferTimeout(15000);
    request.setRawHeader("User-Agent","ListenFree/0.3 (desktop radio)");
    if(url.host()=="music.163.com") {request.setRawHeader("User-Agent","Mozilla/5.0");request.setRawHeader("Referer","https://music.163.com/");}
    auto* reply=network_.get(request);reply_=reply;reply->setReadBufferSize(limit+1);
    connect(reply,&QNetworkReply::readyRead,this,[reply,limit]{if(reply->bytesAvailable()>limit)reply->abort();});
    connect(reply,&QNetworkReply::finished,this,[this,reply,gen,done=std::move(done)] {
        const auto error=reply->error()==QNetworkReply::NoError?QString{}:QStringLiteral("连接失败，请稍后重试");
        const auto bytes=reply->isOpen()?reply->readAll():QByteArray{};reply->deleteLater();
        if(gen!=generation_)return;done(bytes,error);
    });
}
void RadioService::loadIcecast(bool force) {
    if(parser_.isRunning())return;
    if(!force && !icecast_.isEmpty() && icecastFetched_.secsTo(QDateTime::currentDateTimeUtc())<1800){filterIcecast();return;}
    get(QUrl("https://dir.xiph.org/yp.xml"),[this](QByteArray bytes,QString error) {
        if(!error.isEmpty()){busy_=false;error_=error;emit changed();return;}
        parser_.setFuture(QtConcurrent::run([bytes=std::move(bytes)] {
            QString error;auto rows=online::icecastStations(bytes,&error);return qMakePair(std::move(rows),error);
        }));
    },32*1024*1024);
}
void RadioService::filterIcecast() {
    const int from=(page()-1)*30;int count=0;QVariantList pageRows;
    for(const auto& row:icecast_) {
        if(!query().isEmpty() && !row.title.contains(query(),Qt::CaseInsensitive) && !row.tags.contains(query(),Qt::CaseInsensitive))continue;
        if(count>=from && pageRows.size()<30)pageRows.append(online::radioTrack(row,"icecast"));++count;
    }
    finish(pageRows,count,count>from+30);
}
void RadioService::loadBrowser(int attempt) {
    if(browserHosts_.isEmpty()) {
        const auto gen=generation_;auto* lookup=new QDnsLookup(QDnsLookup::SRV,"_api._tcp.radio-browser.info",this);
        connect(lookup,&QDnsLookup::finished,this,[this,lookup,gen] {
            for(const auto& record:lookup->serviceRecords()) {
                auto host=record.target();if(host.endsWith('.'))host.chop(1);
                if(host.endsWith(".api.radio-browser.info"))browserHosts_.append(host);
            }
            lookup->deleteLater();if(gen!=generation_)return;
            if(browserHosts_.isEmpty())browserHosts_.append("de1.api.radio-browser.info");
            std::shuffle(browserHosts_.begin(),browserHosts_.end(),*QRandomGenerator::global());loadBrowser();
        });lookup->lookup();return;
    }
    QUrlQuery q{{"limit","30"},{"offset",QString::number((page()-1)*30)},{"hidebroken","true"},{"order","clickcount"},{"reverse","true"}};
    if(!query().isEmpty())q.addQueryItem("name",query());
    if(!category().isEmpty())q.addQueryItem("countrycode",category());
    QUrl url("https://"+browserHosts_[hostIndex_%browserHosts_.size()]+"/json/stations/search");url.setQuery(q);
    get(url,[this,attempt](QByteArray bytes,QString error) {
        if(!error.isEmpty() && attempt+1<browserHosts_.size()){++hostIndex_;loadBrowser(attempt+1);return;}
        if(error.isEmpty() && !QJsonDocument::fromJson(bytes).isArray())error=QStringLiteral("电台目录返回了无效数据");
        if(!error.isEmpty()){busy_=false;error_=error;emit changed();return;}
        finish(online::radioBrowserStations(bytes),-1,QJsonDocument::fromJson(bytes).array().size()==30);
    });
}
void RadioService::loadNetease() {
    QUrl url;
    if(!podcast().isEmpty())url=netease("dj/program/byradio",{{"radioId",podcast().value("radioId").toString()},{"limit","30"},{"offset",QString::number((page()-1)*30)},{"asc","false"}});
    else if(mode()=="podcast") {
        if(query().isEmpty())url=netease("djradio/hot/v1",{{"limit","30"},{"offset",QString::number((page()-1)*30)}});
        else url=netease("search/get",{{"s",query()},{"type","1009"},{"limit","30"},{"offset",QString::number((page()-1)*30)}});
    } else {
        if(neteaseCategories_.isEmpty()) {
            get(netease("voice/broadcast/category/region/get"),[this](QByteArray bytes,QString error) {
                neteaseCategories_={QVariantMap{{"id","0"},{"name","全部分类"}}};
                const auto root=QJsonDocument::fromJson(bytes).object();
                for(const auto& value:root.value("data").toObject().value("categoryList").toArray()) {
                    const auto row=value.toObject();if(row.value("id").toVariant().toString()=="0")continue;
                    neteaseCategories_.append(QVariantMap{{"id",row.value("id").toVariant().toString()},{"name",row.value("name").toString()}});
                }
                emit categoriesChanged();loadNetease();
            });return;
        }
        if(broadcastCategory_==(category().isEmpty()?"0":category())){filterBroadcast();return;}
        broadcastCategory_.clear();broadcastRows_.clear();fetchBroadcast();return;
    }
    get(url,[this](QByteArray bytes,QString error) {
        const auto root=QJsonDocument::fromJson(bytes).object();
        if(error.isEmpty() && root.value("code").toInt()!=200)error=QStringLiteral("网易云暂不可用，请稍后重试");
        if(!error.isEmpty()){busy_=false;error_=error;emit changed();return;}
        if(!podcast().isEmpty()){finish(online::neteasePrograms(root),root.value("count").toInt(-1),root.value("more").toBool());return;}
        if(mode()=="podcast") {
            auto rows=online::neteasePodcasts(root);const int total=root.value("result").toObject().value("djRadiosCount").toInt(-1);
            finish(rows,total,total>=0?total>page()*30:root.value("hasMore").toBool());return;
        }
    });
}
void RadioService::fetchBroadcast(const QString& lastId,const QString& score) {
    get(netease("voice/broadcast/channel/list",{{"categoryId",category().isEmpty()?"0":category()},{"regionId","0"},{"limit","100"},{"lastId",lastId},{"score",score}}),
        [this,lastId](QByteArray bytes,QString error) {
            const auto root=QJsonDocument::fromJson(bytes).object();
            if(error.isEmpty() && root.value("code").toInt()!=200)error=QStringLiteral("网易云广播目录暂不可用");
            if(!error.isEmpty()){busy_=false;error_=error;emit changed();return;}
            const auto data=root.value("data").toObject();const auto rows=online::neteaseBroadcastStations(data);
            QSet<QString> seen;for(const auto& row:broadcastRows_)seen.insert(key(row.toMap()));
            int added=0;for(const auto& row:rows)if(!seen.contains(key(row.toMap()))){broadcastRows_.append(row);seen.insert(key(row.toMap()));++added;}
            if(data.value("hasMore").toBool() && added>0 && broadcastRows_.size()<5000) {
                const auto last=rows.last().toMap();if(last.value("radioId").toString()!=lastId){fetchBroadcast(last.value("radioId").toString(),last.value("score").toString());return;}
            }
            broadcastCategory_=category().isEmpty()?"0":category();filterBroadcast();
        });
}
void RadioService::filterBroadcast() {
    QVariantList filtered;for(const auto& value:broadcastRows_) {
        const auto row=value.toMap();
        if(query().isEmpty() || row.value("title").toString().contains(query(),Qt::CaseInsensitive) || row.value("artist").toString().contains(query(),Qt::CaseInsensitive))filtered.append(value);
    }
    finish(filtered.mid((page()-1)*30,30),filtered.size(),filtered.size()>page()*30);
}
}
