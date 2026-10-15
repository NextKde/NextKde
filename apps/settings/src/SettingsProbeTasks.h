#pragma once

#include <QList>
#include <QObject>
#include <QVariantMap>
#include <functional>

class QThread;

// Owns the two settings probes (integration and model verification). Work runs
// without accessing the bridge; completion runs on the owning UI thread.
// Destruction interrupts and joins all workers, discarding queued completions.
class SettingsProbeTasks final : public QObject {
public:
    using Work = std::function<QVariantMap()>;
    using Completion = std::function<void(const QVariantMap&)>;

    explicit SettingsProbeTasks(QObject* parent = nullptr);
    ~SettingsProbeTasks() override;
    void start(Work work, Completion completion);

private:
    QList<QThread*> m_threads;
};
