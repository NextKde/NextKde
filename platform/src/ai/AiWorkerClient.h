#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QQueue>
#include <QTimer>

#include <functional>

namespace KosPlatform {

// Bounded, asynchronous JSONL client for the optional inference subprocess.
// The worker owns all model/OpenCV/ONNX state; this class only supervises IPC.
class AiWorkerClient final : public QObject {
public:
    using Completion = std::function<void(bool, const QJsonObject &,
                                          const QString &, const QString &, bool)>;

    explicit AiWorkerClient(QObject *parent = nullptr);
    ~AiWorkerClient() override;
    void generateDepth(const QString &imagePath, Completion completion,
                       bool prepareSpatial = false);

    void resourceOperation(const QString &operation, const QString &kind, Completion completion);
    void cancel();
    QJsonObject status() const { return m_status; }

private:
    QJsonObject m_status;
    bool m_canceling = false;
    struct Request {
        QString id;
        QString imagePath;
        bool prepareSpatial = false;
        Completion completion;
        QString operation = QStringLiteral("depth.generate");
    };

    void ensureWorker();
    void dispatchNext();
    void readWorkerOutput();
    void failAll(const QString &code, const QString &message, bool retryable);
    void stopWorkerWhenIdle();

    QProcess m_worker;
    QTimer m_requestTimeout;
    QTimer m_idleTimeout;
    QQueue<Request> m_requests;
    QByteArray m_outputBuffer;
    bool m_active = false;
    bool m_starting = false;
    bool m_stopping = false;
    qint64 m_retryAfterMs = 0;
    int m_failureCount = 0;
};

} // namespace KosPlatform
