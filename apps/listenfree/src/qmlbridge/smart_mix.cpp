#include "qmlbridge/portable_session.h"
#include "online/platform_catalog.h"
#include <utility>
#include <QFileInfo>
#include <QNetworkReply>
#include <QTimer>

namespace listenfree::qmlbridge {
namespace {
constexpr int naturalOverlap = 6000;
constexpr int manualOverlap = 4000;
constexpr int onlineResolutionLead = 25000;
constexpr int decoderPreparationLead = 10000;
constexpr int manualResolutionWait = 2500;
}
void PortableSession::setSmartTransition(bool enabled) {
    if (!enabled) { resetMixAnalysis(); cancelSmartMix(); }
    smartTransition_ = enabled;
    mixAttempted_ = false;
    // One existing effect, and only one output clock. No analysis worker while idle.
    player_.configureTransition(enabled, naturalOverlap);
    if (mixTimer_) {
        if (enabled && state()=="Playing") mixTimer_->start(); else mixTimer_->stop();
    }
    emit changed();
}
int PortableSession::mixTargetIndex() const {
    if (mixTarget_.isEmpty() || mixIndex_<0 || mixIndex_>=navigation_.trackCount()) return -1;
    return entries_.value(navigation_.track(mixIndex_)).value("entryId").toString()==mixTarget_ ? mixIndex_ : -1;
}
void PortableSession::cancelSmartMix() {
    // Qmmp may deliver an already completed handoff during cancellation. Keep
    // the identity alive until that event has committed, then discard preparation.
    const bool hadNotice=mixManual_ || mixArmed_;
    const bool rewind=mixArmed_;
    const auto resume=player_.position();
    player_.cancelPrepared();
    // If a pending mix was cancelled before commit, reread from the audible
    // source position rather than dropping the tail already held by the effect.
    if (rewind && !mixTarget_.isEmpty()) player_.seek(resume);
    const auto resolution=std::exchange(mixResolution_,QString{});
    mixTarget_.clear(); mixManual_=false; mixArmed_=false;
    mixReadyUrl_.clear(); mixReadyHeaders_.clear();
    if (!resolution.isEmpty()) sources_.cancelResolution(resolution);
    if (mixProxy_) { mixProxy_->cancel(); mixProxy_.reset(); }
    if (hadNotice) emit changed();
}
bool PortableSession::prepareSmartMix(int index, bool manual, bool advanceNavigation) {
    if (!smartTransition_ || state()!="Playing" || !seekable() || live() ||
        position()<mixCooldown_ || index<0 || index>=navigation_.trackCount() || index==navigation_.currentIndex()) return false;
    const auto target=entries_.value(navigation_.track(index));
    if (target.value("isLive").toBool() || !target.value("radioId").toString().isEmpty()) return false;
    const auto entry=target.value("entryId").toString();
    if (mixTarget_==entry) {
        mixAdvance_=advanceNavigation;
        if (mixArmed_) return true; // preserve the already scheduled window and cooldown
        mixManual_=manual; mixPreparationClock_.start();
        if (manual && !mixReadyUrl_.isEmpty()) {
            const auto url=std::exchange(mixReadyUrl_, QString{});
            const auto headers=std::exchange(mixReadyHeaders_, QVariantMap{});
            queueSmartMix(url, headers);
        }
        emit changed(); return !mixTarget_.isEmpty();
    }
    cancelSmartMix();
    mixAttempted_=true; mixTarget_=entry; mixIndex_=index; mixManual_=manual; mixAdvance_=advanceNavigation;
    mixPreparationClock_.start();
    const auto local=target.value("localPath").toString();
    if (!local.isEmpty()) {
        if (!QFileInfo(local).isFile() || (!embeddedLyricWritePath_.isEmpty() &&
             QFileInfo(local)==QFileInfo(embeddedLyricWritePath_))) { cancelSmartMix(); return false; }
        queueSmartMix();
    } else if (!target.value("rid").toString().isEmpty()) {
        mixResolution_=sources_.resolveMusicUrl(sources_.activeId(),
            QString::fromStdString(database_.getSetting("playback.quality").value_or("flac")),
            online::sourceMusicInfo(target));
        if (mixResolution_.isEmpty()) { cancelSmartMix(); return false; }
    } else queueSmartMix(target.value("remoteUrl").toString());
    emit changed();
    return !mixTarget_.isEmpty();
}
void PortableSession::queueSmartMix(const QString& url, const QVariantMap& headers) {
    const auto index=mixTargetIndex();
    if (index<0) { cancelSmartMix(); return; }
    const auto target=entries_.value(navigation_.track(index));
    domain::PlaybackItem item{toTrack(target),std::nullopt};
    if (target.value("localPath").toString().isEmpty()) {
        mixProxy_=std::make_unique<media::MediaStreamProxy>();
        const auto proxyUrl=mixProxy_->publish(QUrl(url),headers);
        if (proxyUrl.isEmpty()) { cancelSmartMix(); return; }
        item.resolvedUrl=proxyUrl.toString().toStdString();
    }
    if (!player_.prepareNext(item)) cancelSmartMix();
}
void PortableSession::resetMixAnalysis() {
    tailProbe_.cancel(); tailProbeSource_.clear(); effectiveMixEnd_=-1;
}
void PortableSession::updateSmartMix() {
    if (!smartTransition_ || state()!="Playing" || !mediaReady_ || live()) return;
    const auto source=player_.analysisSource();
    if (duration()>10000 && !source.isEmpty() && tailProbeSource_!=source) {
        tailProbeSource_=source;effectiveMixEnd_=-1;
        tailProbe_.request(source,duration());
    }
    const auto mixEnd=effectiveMixEnd_>0?effectiveMixEnd_:duration();
    if (mixTarget_.isEmpty()) {
        const auto remaining=mixEnd-position();
        if (!mixAttempted_ && duration()>10000 && duration()-position()>500 &&
            mode_!="singleLoop" && mode_!="stopAfterCurrent") {
            const int next=navigation_.indexOf(navigation_.nextTrack());
            if (next>=0) {
                const bool resolvesOnline=!entries_.value(navigation_.track(next)).value("rid").toString().isEmpty();
                if (remaining <= (resolvesOnline ? onlineResolutionLead : decoderPreparationLead))
                    prepareSmartMix(next,false);
            }
        }
        return;
    }
    const int target=mixTargetIndex();
    if (target<0) { cancelSmartMix(); return; }
    if (mixArmed_) return;
    const auto elapsed=mixPreparationClock_.elapsed();
    if (mixManual_) {
        if (player_.startPreparedTransition(manualOverlap)) { mixArmed_=true; emit changed(); return; }
        // Address resolution is asynchronous. Keep A audible for a bounded
        // interval instead of making an ordinary cold switch after 350 ms.
        if (elapsed>=manualResolutionWait) {
            cancelSmartMix(); navigation_.setCurrent(target); beginCurrent();
        }
        return;
    }
    if (!mixReadyUrl_.isEmpty() && mixEnd-position()<=decoderPreparationLead) {
        const auto url=std::exchange(mixReadyUrl_, QString{});
        const auto headers=std::exchange(mixReadyHeaders_, QVariantMap{});
        queueSmartMix(url, headers);
        if (mixTarget_.isEmpty()) return;
    }
    const auto next=entries_.value(navigation_.track(target));
    const auto current=currentTrack();
    const bool sameAlbum=!current.value("album").toString().trimmed().isEmpty() &&
        current.value("album")==next.value("album") && current.value("artist")==next.value("artist") &&
        mode_!="shuffle" && target==navigation_.currentIndex()+1;
    // Schedule against decoded source frames before the last six seconds enter
    // the output queue. The effect retains exactly the final overlap window.
    if (!sameAlbum && mixEnd-position()<=naturalOverlap+3000 && duration()-position()>0) {
        mixArmed_=mixEnd>position() ? player_.startPreparedTransition(naturalOverlap,mixEnd) :
            player_.startPreparedTransition(180);
        if (mixArmed_) emit changed();
    }
    // Preload failures don't interrupt A. Normal end-of-track resolution retries B.
    if (!player_.hasPrepared() && mixResolution_.isEmpty() && mixReadyUrl_.isEmpty() && elapsed>8000)
        cancelSmartMix();
}
void PortableSession::commitSmartMix() {
    const int index=mixTargetIndex();
    if (index<0) return;
    // Previous has already moved Qmmp's shuffle history while resolving the
    // destination. Do not consume Next on commit (including two-song loops).
    const bool advance=mixAdvance_ && navigation_.nextTrack()==navigation_.track(index);
    const bool mixed=mixArmed_;
    resetMixAnalysis();
    mixCooldown_=mixed ? (mixManual_ ? manualOverlap : naturalOverlap)+250 : 0;
    mixTarget_.clear(); mixResolution_.clear(); mixReadyUrl_.clear(); mixReadyHeaders_.clear();
    mixManual_=false; mixArmed_=false;
    mixAttempted_=false;
    ++generation_; ++seekRequest_;
    if (advance) navigation_.next(); else navigation_.setCurrent(index);
    if (mixProxy_) { proxy_->cancel(); proxy_=std::move(mixProxy_); }
    else proxy_->cancel();
    mediaReady_=true; loading_=false; error_.clear();
    resumePosition_=0; resumePaused_=false;
    lyrics_.clear(); emit lyricsChanged();
    if (lyricsReply_) { lyricsReply_->disconnect(this);lyricsReply_->abort();lyricsReply_->deleteLater();lyricsReply_=nullptr; }
    if (commentsReply_) { commentsReply_->disconnect(this);commentsReply_->abort();commentsReply_->deleteLater();commentsReply_=nullptr; }
    comments_.clear();commentsMode_.clear();commentsError_.clear();commentsBusy_=false;emit commentsChanged();
    motionUrl_.clear();artworkEntry_.clear();emit artworkChanged();
    const auto track=currentTrack();
    decoderLocalPath_=track.value("localPath").toString();
    if (!decoderLocalPath_.isEmpty()) loadLyrics(decoderLocalPath_);
    else if (!track.value("rid").toString().isEmpty()) fetchLyrics(track.value("rid").toString());
    fetchOnlineArtwork(track);
    syncQueue();emit currentTrackChanged();emit changed();
    emit smartMixCommitted(mixed);
    QTimer::singleShot(0,this,&PortableSession::pumpEmbeddedLyrics);
}
}
