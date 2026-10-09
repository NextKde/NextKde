#pragma once
#include <QObject>
#include <QFutureWatcher>
#include <memory>

namespace listenfree::media {
// One bounded, cancellable analysis job. The output is a source-time boundary,
// never PCM; -1 means that no safe trailing-silence boundary was established.
class AudioTailProbe final : public QObject {
    Q_OBJECT
public:
    explicit AudioTailProbe(QObject* parent=nullptr);
    ~AudioTailProbe() override;
    void request(const QString& source, qint64 durationMs);
    void cancel();
signals:
    void finished(qint64 audibleEndMs);
private:
    struct Job;
    std::shared_ptr<Job> job_;
    QFutureWatcher<qint64> worker_;
    QString pendingSource_;
    qint64 pendingDuration_{};
    void startPending();
    static qint64 analyze(const std::shared_ptr<Job>& job, const QString& source, qint64 durationMs);
};
}
