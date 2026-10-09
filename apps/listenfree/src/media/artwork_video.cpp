#include "artwork_video.h"
namespace listenfree::media {
ArtworkVideo::ArtworkVideo(QObject* parent):QObject(parent) {
    setObjectName("dynamicArtworkVideo");
    connect(&stream_, &MvFrameStream::frameReady, this, &ArtworkVideo::present);
    connect(&stream_, &MvFrameStream::ready, this, [this] { stream_.synchronize(0, playing_); });
    connect(&stream_, &MvFrameStream::fallbackRequested, this, &ArtworkVideo::useQtBackend);
    connect(&stream_, &MvFrameStream::finished, this, [this] {
        stream_.synchronize(0, playing_, true);
        emit looped();
    });
}
void ArtworkVideo::setSource(const QUrl& source) {
    if (source_ == source) return;
    stream_.close(); fallback_.reset();
    source_ = source; ready_ = false;
    if (!error_.isEmpty()) { error_.clear(); emit errorChanged(); }
    if (sink_) sink_->setVideoFrame({});
    if (!source.isEmpty()) stream_.open(source);
    emit sourceChanged(); emit readyChanged();
}
void ArtworkVideo::setPlaying(bool playing) {
    if (playing_ == playing) return;
    playing_ = playing;
    if (fallback_) { if (playing) fallback_->play(); else fallback_->pause(); }
    else stream_.synchronize(stream_.position(), playing && ready_);
    emit playingChanged();
}
void ArtworkVideo::setVideoSink(QVideoSink* sink) {
    if (sink_ == sink) return;
    if (sink_) disconnect(sink_, nullptr, this, nullptr);
    sink_ = sink;
    if (fallback_) fallback_->setVideoSink(sink);
    if (sink) connect(sink, &QVideoSink::videoFrameChanged, this, [this](const QVideoFrame& frame) {
        if (frame.isValid() && !ready_) {
            ready_ = true;
            if (fallback_ && !playing_) fallback_->pause();
            emit readyChanged();
        }
    });
    emit videoSinkChanged();
}
void ArtworkVideo::present(const QVideoFrame& frame) {
    if (sink_) sink_->setVideoFrame(frame);
}
void ArtworkVideo::useQtBackend() {
    stream_.close();
    fallback_ = std::make_unique<QMediaPlayer>();
    fallback_->setVideoSink(sink_);
    fallback_->setLoops(QMediaPlayer::Infinite);
    connect(fallback_.get(), &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error, const QString& error) {
        error_ = error; emit errorChanged();
        ready_ = false; emit readyChanged();
    });
    connect(fallback_.get(), &QMediaPlayer::tracksChanged, this, [this] {
        fallback_->setActiveAudioTrack(-1);
        fallback_->setActiveSubtitleTrack(-1);
    });
    connect(fallback_.get(), &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        if (status == QMediaPlayer::LoadedMedia && !fallback_->hasVideo()) {
            fallback_->stop(); error_ = tr("文件中没有可播放的视频画面。"); emit errorChanged();
        }
    });
    fallback_->setSource(source_);
    // Decode a poster even when a cover starts paused.
    fallback_->play();
    emit readyChanged();
}
}
