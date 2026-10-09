#pragma once
#include "mv_frame_stream.h"
#include <QMediaPlayer>
#include <QVideoSink>
#include <QPointer>

namespace listenfree::media {
// The existing bounded video decoder, with an independent cover clock. Qt
// retains its complete backend for ineligible media and sustained decode lag.
class ArtworkVideo final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool playing READ playing WRITE setPlaying NOTIFY playingChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorChanged)
    Q_PROPERTY(bool bounded READ bounded NOTIFY readyChanged)
    Q_PROPERTY(QVideoSink* videoSink READ videoSink WRITE setVideoSink NOTIFY videoSinkChanged)
public:
    explicit ArtworkVideo(QObject* parent=nullptr);
    QUrl source() const { return source_; }
    bool playing() const { return playing_; }
    bool ready() const { return ready_; }
    QString errorString() const { return error_; }
    bool bounded() const { return !fallback_; }
    QVideoSink* videoSink() const { return sink_; }
    void setSource(const QUrl& source);
    void setPlaying(bool playing);
    void setVideoSink(QVideoSink* sink);
    int queuedFrames() const { return stream_.queuedFrames(); }
Q_SIGNALS:
    void sourceChanged();
    void playingChanged();
    void readyChanged();
    void videoSinkChanged();
    void looped();
    void errorChanged();
private:
    void useQtBackend();
    void present(const QVideoFrame& frame);
    QUrl source_;
    QString error_;
    QPointer<QVideoSink> sink_;
    MvFrameStream stream_;
    std::unique_ptr<QMediaPlayer> fallback_;
    bool playing_=true, ready_=false;
};

class ArtworkVideoFactory final : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;
    Q_INVOKABLE QObject* create(QObject* owner) { return owner ? new ArtworkVideo(owner) : nullptr; }
};
}
