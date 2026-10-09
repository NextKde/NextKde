#pragma once
#include <QFutureWatcher>
#include <QTcpServer>
#include <QTcpSocket>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <memory>

namespace listenfree::media {
// HLS/FLV -> compressed audio packets -> ADTS/MP3/Matroska -> existing Qmmp.
// No decoder, PCM, transcoding, or second audio output lives here.
class LiveStreamRelay final : public QObject {
    Q_OBJECT
public:
    explicit LiveStreamRelay(QObject* parent=nullptr);
    ~LiveStreamRelay() override;
    QUrl publish(const QUrl& upstream);
    void cancel();
signals:
    void errorOccurred(const QString& message);
private:
    struct Job;
    std::shared_ptr<Job> job_;
    QFutureWatcher<void> worker_;
    QTcpServer server_;
    QPointer<QTcpSocket> client_;
    QTimer pump_;
    QUrl upstream_;QByteArray path_;
    bool started_{};
    void start();
    void drain();
    static void remux(const std::shared_ptr<Job>& job,const QUrl& url);
};
}
