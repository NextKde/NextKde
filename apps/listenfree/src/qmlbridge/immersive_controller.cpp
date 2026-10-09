#include "immersive_controller.h"
#include "online/bilibili_client.h"
#include <qmmp/visual.h>
#include <QNetworkReply>
#include <QVideoFrame>
#include <QCryptographicHash>
#include <QDateTime>
#include <QTextDocumentFragment>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFileInfo>
#include <QVideoFrame>
#include <QCryptographicHash>
#include <QDateTime>
#include <QTextDocumentFragment>
#include <QRegularExpression>
#include <cmath>
#include <algorithm>

namespace listenfree::qmlbridge {
class SpectrumSampler final : public Visual {
public:
    SpectrumSampler() : Visual(nullptr) { setAttribute(Qt::WA_DontShowOnScreen); }
    bool read(float* left, float* right) { return takeFFTData(left, right); }
};
ImmersiveController::ImmersiveController(QObject* parent) : QObject(parent) {
    spectrum_ = reduceSpectrum(nullptr, nullptr);
    timer_.setInterval(33);
    connect(&timer_, &QTimer::timeout, this, &ImmersiveController::sample);
    loadTimeout_.setSingleShot(true);
    loadTimeout_.setInterval(15000);
    connect(&loadTimeout_, &QTimer::timeout, this, [this] { failVideo(tr("MV 加载超时，请重新选择或使用本地视频")); });
}
ImmersiveController::~ImmersiveController() {
    cancelRequest();loadTimeout_.stop();nativeVideo_.reset();
    if(video_)video_->disconnect(this);
    video_.reset();proxy_.reset();
}
void ImmersiveController::setActive(bool value) {
    if (active_ == value) return;
    active_ = value;
    if (!value) { autoMatching_=false; clearVideo(); candidates_.clear(); emit mvChanged(); }
    updateSampling(); emit activeChanged();
}
void ImmersiveController::setSuspended(bool value) {
    if (suspended_ == value) return;
    suspended_ = value; updateSampling(); syncVideo(true); emit activeChanged();
}
void ImmersiveController::setSpectrumEnabled(bool value) {
    if (spectrumEnabled_ == value) return;
    spectrumEnabled_ = value; updateSampling(); emit activeChanged();
}
void ImmersiveController::setPlayback(qint64 position, bool playing, const QString& identity) {
    if (identity_ != identity) {
        identity_ = identity; autoMatching_=false; clearVideo(); candidates_.clear(); offsetMs_ = 0; emit mvChanged();
    }
    const bool jumped = std::abs(position - position_) > 1200;
    position_ = position; playing_ = playing;
    updateSampling(); syncVideo(jumped);
}
void ImmersiveController::updateSampling() {
    if (active_ && !suspended_ && spectrumEnabled_ && playing_) {
        if (!sampler_) sampler_ = std::make_unique<SpectrumSampler>();
        if (!timer_.isActive()) timer_.start();
    } else {
        if (!timer_.isActive() && !sampler_) return;
        timer_.stop(); sampler_.reset();
        spectrum_ = reduceSpectrum(nullptr, nullptr); emit spectrumChanged();
    }
}
QVariantList ImmersiveController::reduceSpectrum(const float* left, const float* right) {
    QVariantList values; values.reserve(32);
    for (int band = 0; band < 32; ++band) {
        const int begin = std::clamp(int(std::pow(257., band / 32.)) - 1, 0, 255);
        const int end = std::clamp(int(std::pow(257., (band + 1) / 32.)) - 1, begin + 1, 256);
        double power = 0;
        if (left && right) for (int bin = begin; bin < end; ++bin)
            power = std::max(power, double(std::max(left[bin], right[bin])));
        // Qmmp FFT uses signed-16-bit scale. Log amplitude preserves quiet detail.
        values.append(std::clamp(std::log1p(power / 1000.) / 6., 0., 1.));
    }
    return values;
}
void ImmersiveController::sample() {
    float left[256]{}, right[256]{};
    if (sampler_) sampler_->read(left, right);
    auto next = reduceSpectrum(left, right);
    for (int i = 0; i < next.size(); ++i) {
        const double old = spectrum_[i].toDouble(), target = next[i].toDouble();
        next[i] = old + (target - old) * (target > old ? .68 : .17);
    }
    spectrum_ = next; emit spectrumChanged();
}
void ImmersiveController::cancelRequest() {
    ++generation_;
    if (request_) { auto* reply = request_.data(); request_ = nullptr; reply->abort(); reply->deleteLater(); }
    busy_ = false;
}
void ImmersiveController::clearVideo() {
    cancelRequest(); loadTimeout_.stop();
    nativeVideo_.reset();
    if(video_)video_->disconnect(this);
    video_.reset(); proxy_.reset();
    if (sink_) sink_->setVideoFrame(QVideoFrame{});
    videoReady_ = false; videoTitle_.clear(); error_.clear(); emit mvChanged();
}
void ImmersiveController::failVideo(const QString& message) {
    clearVideo();
    if(autoMatching_&&!autoTriedBili_){autoTriedBili_=true;performSearch(autoQuery_,"bili");return;}
    autoMatching_=false;error_ = message; emit mvChanged();
}
void ImmersiveController::attachVideoSink(QObject* sink) {
    QObject::disconnect(videoSizeConnection_);
    sink_ = qobject_cast<QVideoSink*>(sink);
    videoSize_=sink_?sink_->videoSize():QSize{};
    if(sink_)videoSizeConnection_=connect(sink_,&QVideoSink::videoSizeChanged,this,[this]{
        const auto size=sink_?sink_->videoSize():QSize{};
        if(videoSize_!=size){videoSize_=size;emit mvChanged();}
    });
    if (video_) video_->setVideoSink(sink_);
}
static QNetworkRequest mvRequest(const QUrl& url) {
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "Mozilla/5.0");
    request.setRawHeader("Referer", "https://music.163.com/");
    request.setTransferTimeout(12000);
    return request;
}
void ImmersiveController::getJson(QUrl url, std::function<void(QJsonObject)> callback) {
    auto request=mvRequest(url);
    if(url.host()=="api.bilibili.com") {
        request.setRawHeader("Referer","https://www.bilibili.com/");
        const auto cookie=biliAccountCookie_.isEmpty()?biliCookie_.toUtf8():biliAccountCookie_;
        if(!cookie.isEmpty())request.setRawHeader("Cookie",cookie);
    }
    auto* reply=network_.get(request);request_=reply;const auto generation=generation_;
    connect(reply,&QNetworkReply::finished,this,[this,reply,generation,callback=std::move(callback)]{
        reply->deleteLater();if(generation!=generation_)return;request_=nullptr;
        auto root=QJsonDocument::fromJson(reply->readAll()).object();
        if(reply->error()!=QNetworkReply::NoError)root={};callback(root);
    });
}
QUrl ImmersiveController::biliUrl(const QString& path,const QMap<QString,QString>& values) const {
    return online::bilibiliSignedUrl(path,values,biliMixin_);
}
void ImmersiveController::prepareBili(std::function<void()> callback) {
    if(!biliMixin_.isEmpty()&&(!biliCookie_.isEmpty()||!biliAccountCookie_.isEmpty())){callback();return;}
    getJson(QUrl("https://api.bilibili.com/x/web-interface/nav"),[this,callback](QJsonObject root){
        biliMixin_=online::bilibiliMixinKey(root);
        if(!biliAccountCookie_.isEmpty()){callback();return;}
        getJson(QUrl("https://api.bilibili.com/x/frontend/finger/spi"),[this,callback](QJsonObject spi){
            const auto data=spi.value("data").toObject();const auto b3=data.value("b_3").toString();
            if(!b3.isEmpty())biliCookie_="buvid3="+b3+"; buvid4="+data.value("b_4").toString();callback();
        });
    });
}
void ImmersiveController::searchMv(const QString& query,const QString& provider) {
    autoMatching_=false;performSearch(query,provider=="bili"?"bili":"wy");
}
void ImmersiveController::autoMatchMv(const QString& title,const QString& artist,qint64 duration) {
    if(title.trimmed().isEmpty())return;
    autoMatching_=true;autoTriedBili_=false;autoTitle_=title;autoArtist_=artist;autoDuration_=duration;
    autoQuery_=(title+" "+artist).trimmed();performSearch(autoQuery_,"wy");
}
void ImmersiveController::performSearch(const QString& query,const QString& provider) {
    if(!active_||query.trimmed().isEmpty())return;
    cancelRequest();candidates_.clear();error_.clear();busy_=true;searchProvider_=provider;emit mvChanged();
    if(provider=="bili"){
        prepareBili([this,query]{searchBiliPage(query,1);});return;
    }
    QUrl url("https://music.163.com/api/search/get");QUrlQuery params;params.addQueryItem("s",query.trimmed().left(200));params.addQueryItem("type","1004");params.addQueryItem("limit","30");url.setQuery(params);
    getJson(url,[this](QJsonObject root){
        for(const auto& value:root.value("result").toObject().value("mvs").toArray()){
            const auto row=value.toObject();candidates_.append(QVariantMap{{"provider","wy"},{"id",row.value("id").toVariant()},{"title",row.value("name").toString()},{"artist",row.value("artistName").toString()},{"cover",row.value("cover").toString()},{"duration",row.value("duration").toInt()},{"playCount",row.value("playCount").toVariant().toLongLong()}});
        }
        if(root.value("code").toInt()!=200)error_=tr("网易云 MV 搜索失败，请重试或切换 B 站");finishSearch();
    });
}
void ImmersiveController::searchBiliPage(const QString& query,int page) {
    // Ten results per page keeps the total fetched bounded at thirty even on
    // endpoints that do not support a page size of thirty. Requests are cancellable.
    getJson(biliUrl("/x/web-interface/wbi/search/type",{{"keyword",query.left(200)},{"search_type","video"},{"order","click"},{"page_size","10"},{"page",QString::number(page)}}),[this,query,page](QJsonObject root){
        const auto data=root.value("data").toObject();
        const auto results=data.value("result").toArray();
        for(const auto& value:results){
            const auto row=value.toObject();const QString id=row.value("bvid").toString();
            if(id.isEmpty()||std::any_of(candidates_.cbegin(),candidates_.cend(),[&](const QVariant& v){return v.toMap().value("id")==id;}))continue;
            qint64 duration=0;for(const auto& part:row.value("duration").toString().split(':'))duration=duration*60+part.toLongLong();
            QString cover=row.value("pic").toString();if(cover.startsWith("//"))cover="https:"+cover;
            candidates_.append(QVariantMap{{"provider","bili"},{"id",id},{"title",QTextDocumentFragment::fromHtml(row.value("title").toString()).toPlainText()},{"artist",row.value("author").toString()},{"cover",cover},{"duration",duration*1000},{"playCount",row.value("play").toVariant().toLongLong()}});
            if(candidates_.size()>=30)break;
        }
        if(root.value("code").toInt(-1)!=0)error_=tr("B 站暂时无法搜索，请稍后重试或切换网易云");
        else if(page<3&&candidates_.size()<30&&!results.isEmpty()&&page<data.value("numPages").toInt(1)){searchBiliPage(query,page+1);return;}
        finishSearch();
    });
}
void ImmersiveController::setBilibiliCookie(const QByteArray& cookie) {
    if(biliAccountCookie_==cookie)return;
    biliAccountCookie_.fill(0);
    biliAccountCookie_=cookie;
    biliMixin_.clear();
}
void ImmersiveController::finishSearch() {
    busy_=false;
    std::stable_sort(candidates_.begin(),candidates_.end(),[](const QVariant& a,const QVariant& b){return a.toMap().value("playCount").toLongLong()>b.toMap().value("playCount").toLongLong();});
    if(candidates_.size()>30)candidates_=candidates_.mid(0,30);
    if(autoMatching_){
        const auto normalize=[](QString text){text=text.toCaseFolded();text.remove(QRegularExpression("[\\s\\p{P}\\p{S}]+"));return text;};
        const QString title=normalize(autoTitle_),artist=normalize(autoArtist_);
        for(auto& value:candidates_){auto row=value.toMap();const QString name=normalize(row.value("title").toString()),author=normalize(row.value("artist").toString());
            double score=name==title?80:name.contains(title)?65:0;
            if(!artist.isEmpty()&&(name.contains(artist)||author.contains(artist)))score+=15;
            const qint64 duration=row.value("duration").toLongLong();if(autoDuration_>0&&duration>0)score+=10*std::max(0.,1.-double(std::abs(duration-autoDuration_))/60000.);
            if(!title.contains("cover")&&(name.contains("cover")||name.contains(QStringLiteral("翻唱"))||name.contains(QStringLiteral("伴奏"))))score-=30;
            row["score"]=score;value=row;
        }
        const auto best=std::max_element(candidates_.cbegin(),candidates_.cend(),[](const QVariant& a,const QVariant& b){return a.toMap().value("score").toDouble()<b.toMap().value("score").toDouble();});
        if(best!=candidates_.cend()&&best->toMap().value("score").toDouble()>=60){const auto selected=best->toMap();emit mvChanged();resolveMv(selected);return;}
        if(!autoTriedBili_){autoTriedBili_=true;performSearch(autoQuery_,"bili");return;}
        autoMatching_=false;error_=tr("未找到足够匹配的 MV，请从候选项手动选择");
    }else if(candidates_.isEmpty()&&error_.isEmpty())error_=tr("没有找到 MV，请调整关键词或选择其他来源");
    emit mvChanged();
}
void ImmersiveController::selectMv(int index) {
    if(!active_||index<0||index>=candidates_.size())return;
    autoMatching_=false;resolveMv(candidates_[index].toMap());
}
void ImmersiveController::resolveMv(const QVariantMap& row) {
    clearVideo();busy_=true;emit mvChanged();
    if(row.value("provider")=="bili"){
        const QString bvid=row.value("id").toString();videoReferer_="https://www.bilibili.com/video/"+bvid;
        prepareBili([this,bvid,row]{getJson(biliUrl("/x/web-interface/view",{{"bvid",bvid}}),[this,bvid,row](QJsonObject view){
            const auto cid=view.value("data").toObject().value("cid").toVariant().toString();
            if(cid.isEmpty()){failVideo(tr("B 站视频信息暂不可用"));return;}
            getJson(biliUrl("/x/player/wbi/playurl",{{"bvid",bvid},{"cid",cid},{"qn","80"},{"fnval","4048"},{"fnver","0"},{"fourk","0"}}),[this,row](QJsonObject root){
                const auto selected=online::BilibiliClient::videoFromPlayInfo(root.value("data").toObject());
                const QString url=selected.value("url").toString();
                if(url.isEmpty()){failVideo(tr("B 站未提供可播放画面，请选择其他候选"));return;}loadVideo(QUrl(url),row.value("title").toString(),true);
            });
        });});return;
    }
    videoReferer_="https://music.163.com/";QUrl url("https://music.163.com/api/song/enhance/play/mv/url");QUrlQuery params;params.addQueryItem("id",row.value("id").toString());params.addQueryItem("r","1080");url.setQuery(params);
    getJson(url,[this,row](QJsonObject root){const QUrl url(root.value("data").toObject().value("url").toString());if(url.scheme()!="http"&&url.scheme()!="https"){failVideo(tr("这个 MV 暂时无法播放，请选择其他候选"));return;}loadVideo(url,row.value("title").toString(),true);});
}
void ImmersiveController::openLocalVideo(const QUrl& url) {
    if (!active_) return;
    autoMatching_=false;
    if (!url.isLocalFile() || !QFileInfo(url.toLocalFile()).isFile()) {
        failVideo(tr("本地视频不存在")); return;
    }
    clearVideo(); loadVideo(url, QFileInfo(url.toLocalFile()).completeBaseName(), false);
}
void ImmersiveController::loadVideo(const QUrl& url, const QString& title, bool remote) {
    videoTitle_ = title; busy_ = true; error_.clear();
    if (remote) proxy_ = std::make_unique<media::MediaStreamProxy>();
    const QUrl source=remote ? proxy_->publish(url, {{"Referer", videoReferer_}, {"User-Agent", "Mozilla/5.0"}}) : url;
    if(remote && qEnvironmentVariable("QT_LISTENFREE_NATIVE_MV")!="0") {
        nativeVideo_=std::make_unique<media::MvFrameStream>();
        connect(nativeVideo_.get(),&media::MvFrameStream::frameReady,this,[this](const QVideoFrame& frame){if(sink_)sink_->setVideoFrame(frame);});
        connect(nativeVideo_.get(),&media::MvFrameStream::ready,this,[this]{
            videoReady_=true;busy_=false;loadTimeout_.stop();emit mvChanged();
        });
        connect(nativeVideo_.get(),&media::MvFrameStream::fallbackRequested,this,[this,source,generation=generation_]{
            QTimer::singleShot(0,this,[this,source,generation]{
                if(generation!=generation_ || !nativeVideo_)return;
                nativeVideo_.reset();videoReady_=false;busy_=true;startQtVideo(source);
            });
        });
        nativeVideo_->open(source);
        nativeVideo_->synchronize(std::max(qint64(0),position_+offsetMs_),playing_&&!suspended_,true);
    } else startQtVideo(source);
    loadTimeout_.start();emit mvChanged();
}
void ImmersiveController::startQtVideo(const QUrl& source) {
    video_ = std::make_unique<QMediaPlayer>();
    video_->setVideoSink(sink_);
    // Never attach a QAudioOutput: Qmmp remains the only sound source.
    connect(video_.get(), &QMediaPlayer::tracksChanged, this, [this] {
        video_->setActiveAudioTrack(-1); video_->setActiveSubtitleTrack(-1);
    });
    connect(video_.get(), &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error, const QString&) {
        // Defer deletion until QMediaPlayer's signal stack has unwound.
        const auto generation = generation_;
        QTimer::singleShot(0, this, [this, generation] { if (generation == generation_) failVideo(tr("MV 解码或网络失败，请重新选择视频")); });
    });
    connect(video_.get(), &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        if (status == QMediaPlayer::LoadedMedia || status == QMediaPlayer::BufferedMedia) {
            if (!video_->hasVideo()) {
                const auto generation = generation_;
                QTimer::singleShot(0, this, [this, generation] { if (generation == generation_) failVideo(tr("所选文件没有视频画面")); });
                return;
            }
            const bool first = !videoReady_;
            videoReady_ = true; busy_ = false; loadTimeout_.stop(); syncVideo(first); emit mvChanged();
        }
    });
    video_->setSource(source);
    loadTimeout_.start(); emit mvChanged();
}
void ImmersiveController::setOffsetMs(int value) {
    value = std::clamp(value, -300000, 300000);
    if (value == offsetMs_) return;
    offsetMs_ = value; syncVideo(true); emit mvChanged();
}
void ImmersiveController::syncVideo(bool force) {
    if(active_ && nativeVideo_) {
        const qint64 target=std::max(qint64(0),position_+offsetMs_);
        const auto duration=nativeVideo_->duration();
        nativeVideo_->synchronize(target,playing_&&!suspended_&&(!duration || target<duration),force);
        return;
    }
    if (!active_ || !video_ || !videoReady_) return;
    if (suspended_) { video_->pause(); return; }
    const qint64 target = std::max(qint64(0), position_ + offsetMs_);
    const qint64 duration = video_->duration();
    if (duration > 0 && target >= duration) { video_->pause(); return; }
    if (force || std::abs(video_->position() - target) > 650) video_->setPosition(target);
    if (playing_ && video_->playbackState() != QMediaPlayer::PlayingState) video_->play();
    else if (!playing_ && video_->playbackState() != QMediaPlayer::PausedState) video_->pause();
}
}
