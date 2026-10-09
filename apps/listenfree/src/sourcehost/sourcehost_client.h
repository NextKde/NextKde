#pragma once

#include "application/ports.h"
#include "sourcehost/source_protocol.h"

#include <QByteArray>
#include <QHash>
#include <QPointer>
#include <QProcess>
#include <QObject>
#include <QTimer>

#include <memory>

namespace listenfree::sourcehost {

class SourceHostClient final : public QObject, public application::ISourceHostClient {
    Q_OBJECT
    Q_PROPERTY(HostState state READ state NOTIFY stateChanged)
public:
    enum class HostState { Stopped, Starting, Ready, RestartWaiting, Stopping };
    Q_ENUM(HostState)

    enum class RequestTerminal {
        Succeeded,
        RemoteError,
        TimedOut,
        Cancelled,
        HostStopped,
        HostCrashed,
        WriteFailed
    };
    Q_ENUM(RequestTerminal)

    explicit SourceHostClient(QString executablePath, QObject* parent = nullptr);
    ~SourceHostClient() override;

    bool start() override;
    void stop() noexcept override;
    bool loadPlugin(const std::filesystem::path& path) override;
    void cancel(const std::string& requestId) override;
    bool request(const SourceMessage& message, int timeoutMs = 5000);
    void setAutoRestart(bool enabled) noexcept { autoRestart_ = enabled; }
    [[nodiscard]] bool running() const noexcept {
        return process_ && process_->state() != QProcess::NotRunning;
    }
    [[nodiscard]] HostState state() const noexcept { return state_; }

signals:
    void ready();
    void crashed();
    void restarted();
    void messageReceived(const SourceMessage& message);
    void requestTimedOut(const QString& requestId);
    void requestFinished(const QString& requestId, RequestTerminal terminal);
    void protocolError(const QString& message);
    void stateChanged(HostState state);

private:
#ifdef Q_OS_WIN
    struct JobHandleDeleter {
        void operator()(void* handle) const noexcept;
    };
    using JobHandle = std::unique_ptr<void, JobHandleDeleter>;

    bool createJobObject();
    bool assignProcessToJob();
#endif
    void terminateProcessTree() noexcept;
    void closeJobObject() noexcept;
    void transitionTo(HostState state);
    void handleStandardOutput();
    void failHandshake(const QString& reason);
    void processFrames();
    void sendCancellation(const QString& requestId);
    bool finishRequest(const QString& requestId, RequestTerminal terminal);
    void finishAll(RequestTerminal terminal);

    QString executablePath_;
    std::unique_ptr<QProcess> process_;
    QTimer restartTimer_;
    QTimer restartStabilityTimer_;
    QTimer handshakeTimer_;
    QTimer stopTimer_;
    QByteArray readBuffer_;
    QString handshakeRequestId_;
    QHash<QString, QPointer<QTimer>> pending_;
    bool stopping_{false};
    bool handshakeComplete_{false};
    bool autoRestart_{true};
    bool restartInProgress_{false};
    int restartAttempts_{0};
    HostState state_{HostState::Stopped};
#ifdef Q_OS_WIN
    JobHandle jobHandle_{nullptr};
#endif
    static constexpr qsizetype MaxPendingRequests = 256;
    static constexpr qsizetype MaxRequestIdBytes = 256 * 1024;
    static constexpr qint64 MaxQueuedWriteBytes = 4 * 1024 * 1024;
    static constexpr int MaxRestartAttempts = 3;
    static constexpr int RestartBaseDelayMs = 50;
    static constexpr int RestartStableMs = 2000;
};

} // namespace listenfree::sourcehost
