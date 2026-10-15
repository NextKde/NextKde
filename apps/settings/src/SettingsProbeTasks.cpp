#include "SettingsProbeTasks.h"

#include <QThread>
#include <memory>
#include <utility>

SettingsProbeTasks::SettingsProbeTasks(QObject* parent)
    : QObject(parent)
{
}

SettingsProbeTasks::~SettingsProbeTasks()
{
    // No event loop is pumped during shutdown. Queued delivery belongs to this
    // QObject, so it is removed by QObject destruction after the workers join.
    for (QThread* thread : m_threads) {
        disconnect(thread, nullptr, this, nullptr);
        thread->requestInterruption();
    }
    for (QThread* thread : m_threads)
        thread->wait();
}

void SettingsProbeTasks::start(Work work, Completion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    auto result = std::make_shared<QVariantMap>();
    auto* worker = QThread::create([work = std::move(work), result] { *result = work(); });
    worker->setParent(this);
    m_threads.append(worker);
    connect(worker, &QThread::finished, this,
        [this, worker, result, completion = std::move(completion)] {
            m_threads.removeAll(worker);
            worker->deleteLater();
            completion(*result);
        });
    worker->start();
}
