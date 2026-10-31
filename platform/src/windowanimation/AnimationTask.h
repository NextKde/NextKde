#pragma once

#include <QObject>
#include <QThread>
#include <QString>
#include <functional>
#include <memory>
#include <utility>

namespace KOS::WindowAnimation {

// Own the worker until completion, including during application shutdown.
// Work must capture values only; completion runs on the owner's event loop.
class AnimationTask final : public QObject {
    QThread *m_worker = nullptr;
public:
    using Result = std::pair<bool, QString>;
    AnimationTask(QObject *owner, std::function<Result()> work,
                  std::function<void(const Result &)> completion) : QObject(owner) {
        auto result = std::make_shared<Result>();
        m_worker = QThread::create([work = std::move(work), result] { *result = work(); });
        connect(m_worker, &QThread::finished, this,
            [this, result, completion = std::move(completion)] {
                completion(*result);
                deleteLater();
            });
        m_worker->start();
    }
    ~AnimationTask() override {
        m_worker->wait();
        delete m_worker;
    }
};

} // namespace KOS::WindowAnimation
