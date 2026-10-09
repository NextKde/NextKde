#pragma once
#include <QObject>
#include <QElapsedTimer>
#include <QTimer>
#include <QUrl>
#include <QVideoFrame>
#include <memory>
#include <thread>

namespace listenfree::media {
// A video-only adapter over the FFmpeg already used by Qmmp/radio. Qt owns
// presentation and color conversion; the audio player's clock owns timing.
class MvFrameStream final : public QObject {
    Q_OBJECT
public:
    explicit MvFrameStream(QObject* parent=nullptr);
    ~MvFrameStream() override;
    void open(const QUrl& url);
    void close() { stop(); }
    void synchronize(qint64 positionMs,bool playing,bool seek=false);
    qint64 position() const;
    qint64 duration() const;
    int queuedFrames() const;
    quint64 presentedFrames() const { return presented_; }
Q_SIGNALS:
    void frameReady(const QVideoFrame& frame);
    void ready();
    void fallbackRequested();
    void finished();
private:
    struct Job;
    static void decode(const std::shared_ptr<Job>& job,const QUrl& url);
    void drain();
    void stop();
    std::shared_ptr<Job> job_;
    std::thread worker_;
    QTimer pump_;
    QElapsedTimer clock_;
    QElapsedTimer lateClock_;
    qint64 anchorMs_=0;
    bool playing_=false,ready_=false;
    bool endEmitted_=false;
    quint64 presented_=0;
};
}
