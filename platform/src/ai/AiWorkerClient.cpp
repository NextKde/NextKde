#include "AiWorkerClient.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QJsonDocument>
#include <QUuid>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QDebug>

namespace KosPlatform {
namespace {

constexpr qsizetype maximumWorkerResponseBytes = 1024 * 1024;
constexpr int workerRequestTimeoutMs = 270000;
constexpr int workerIdleTimeoutMs = 15000;
constexpr int maximumWorkerQueueSize = 2;

} // namespace

AiWorkerClient::AiWorkerClient(QObject *parent)
    : QObject(parent)
{
    m_worker.setProcessChannelMode(QProcess::SeparateChannels);
    m_requestTimeout.setSingleShot(true);
    m_idleTimeout.setSingleShot(true);
    m_idleTimeout.setInterval(workerIdleTimeoutMs);

    connect(&m_worker, &QProcess::started, this, [this] {
        m_starting = false;
        dispatchNext();
    });
    connect(&m_worker, &QProcess::readyReadStandardOutput,
            this, &AiWorkerClient::readWorkerOutput);
    connect(&m_worker, &QProcess::readyReadStandardError, this, [this] {
        const QByteArray diagnostics = m_worker.readAllStandardError();
        if (!diagnostics.isEmpty())
            qWarning().noquote() << "AI worker:" << QString::fromUtf8(diagnostics.right(4096)).trimmed();
    });
    connect(&m_worker, &QProcess::finished, this,
            [this](int exitCode, QProcess::ExitStatus exitStatus) {
        m_starting = false;
        m_outputBuffer.clear();
        const bool wasStopping = m_stopping;
        m_stopping = false;
        if (wasStopping && exitStatus == QProcess::NormalExit && exitCode == 0) {
            m_failureCount = 0;
            m_retryAfterMs = 0;
            dispatchNext();
            return;
        }
        if (!m_requests.isEmpty())
            failAll(QStringLiteral("depth-worker-exited"),
                    QStringLiteral("AI 推理进程意外退出"), true);
        if (m_canceling) return;
        if (exitStatus == QProcess::CrashExit || exitCode != 0) {
            ++m_failureCount;
            const int delayMs = qMin(30000, 1000 << qMin(m_failureCount - 1, 5));
            m_retryAfterMs = QDateTime::currentMSecsSinceEpoch() + delayMs;
        } else {
            m_failureCount = 0;
            m_retryAfterMs = 0;
        }
    });
    connect(&m_worker, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_starting = false;
        ++m_failureCount;
        const int delayMs = qMin(30000, 1000 << qMin(m_failureCount - 1, 5));
        m_retryAfterMs = QDateTime::currentMSecsSinceEpoch() + delayMs;
        failAll(QStringLiteral("depth-worker-unavailable"),
                QStringLiteral("AI 推理进程无法启动"), true);
    });
    connect(&m_requestTimeout, &QTimer::timeout, this, [this] {
        failAll(QStringLiteral("depth-worker-timeout"),
                QStringLiteral("AI 推理超时"), true);
        if (m_worker.state() != QProcess::NotRunning)
            m_worker.kill();
    });
    connect(&m_idleTimeout, &QTimer::timeout,
            this, &AiWorkerClient::stopWorkerWhenIdle);
}

AiWorkerClient::~AiWorkerClient()
{
    m_requestTimeout.stop();
    m_idleTimeout.stop();
    QObject::disconnect(&m_worker, nullptr, this, nullptr);
    m_requests.clear();
    m_active = false;
    if (m_worker.state() != QProcess::NotRunning) {
        m_worker.terminate();
        if (!m_worker.waitForFinished(250)) {
            m_worker.kill();
            m_worker.waitForFinished(1000);
        }
    }
}

void AiWorkerClient::generateDepth(const QString &imagePath, Completion completion,
                                   bool prepareSpatial)
{
    m_idleTimeout.stop();
    if (m_canceling || m_requests.size() >= maximumWorkerQueueSize) {
        completion(false, {}, QStringLiteral("depth-worker-busy"),
                   QStringLiteral("AI 推理队列已满"), true);
        return;
    }

    m_requests.enqueue({QUuid::createUuid().toString(QUuid::WithoutBraces),
                        imagePath, prepareSpatial, std::move(completion)});
    // A warm worker is already past its started() signal. Dispatch here as
    // well, otherwise the first request succeeds but later requests remain
    // queued forever while the worker waits on stdin.
    dispatchNext();
}

void AiWorkerClient::resourceOperation(const QString &operation, const QString &kind,
                                       Completion completion)
{
    if (m_canceling || !m_requests.isEmpty()) {
        completion(false, {}, "depth-worker-busy", "正在准备资源，请先取消当前任务", false);
        return;
    }
    m_idleTimeout.stop();
    m_requests.enqueue({QUuid::createUuid().toString(QUuid::WithoutBraces),
                        kind, false, std::move(completion), operation});
    dispatchNext();
}

void AiWorkerClient::cancel()
{
    if (m_canceling) return;
    m_canceling = true;
    m_stopping = false;
    failAll("spatial-canceled", "已取消", false);
    m_idleTimeout.stop();
    if (m_worker.state() != QProcess::NotRunning) {
        m_worker.kill();
        m_worker.waitForFinished(1000);
    }
    const QDir models(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                      + "/liquid-shell/models");
    for (const QString &file : models.entryList({"*.download*"}, QDir::Files | QDir::NoSymLinks))
        QFile::remove(models.filePath(file));
    m_outputBuffer.clear();
    m_starting = false;
    m_retryAfterMs = 0;
    m_failureCount = 0;
    m_status = {{"busy", false}, {"stage", "已取消"}};
    m_canceling = false;
}

void AiWorkerClient::ensureWorker()
{
    if (m_worker.state() != QProcess::NotRunning || m_starting)
        return;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now < m_retryAfterMs) {
        failAll(QStringLiteral("depth-worker-cooldown"),
                QStringLiteral("AI 推理进程正在冷却，请稍后重试"), true);
        return;
    }

    const QString executable = QCoreApplication::applicationDirPath()
        + QStringLiteral("/kos-ai-worker");
    m_worker.setProgram(executable);
    m_worker.setArguments({});
    m_starting = true;
    m_worker.start(QIODevice::ReadWrite);
}

void AiWorkerClient::dispatchNext()
{
    if (m_active || m_stopping || m_requests.isEmpty())
        return;
    if (m_worker.state() != QProcess::Running) {
        ensureWorker();
        return;
    }

    const Request &request = m_requests.head();
    const QJsonObject message{
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), request.id},
        {QStringLiteral("operation"), request.operation},
        {QStringLiteral("imagePath"), request.imagePath},
        {QStringLiteral("prepareSpatial"), request.prepareSpatial},
    };
    const QByteArray line = QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
    if (m_worker.write(line) != line.size()) {
        failAll(QStringLiteral("depth-worker-io"),
                QStringLiteral("无法向 AI 推理进程发送请求"), true);
        m_worker.kill();
        return;
    }
    m_status = {{"busy", true}, {"stage", "正在准备资源"}, {"received", -1}, {"total", -1}};
    m_active = true;
    m_requestTimeout.start(request.operation == "spatial.initialize" ? 1230000 : workerRequestTimeoutMs);
}

void AiWorkerClient::readWorkerOutput()
{
    const QByteArray incoming = m_worker.readAllStandardOutput();
    if (m_outputBuffer.size() + incoming.size() > maximumWorkerResponseBytes) {
        failAll(QStringLiteral("depth-worker-protocol"),
                QStringLiteral("AI 推理进程响应超过大小限制"), true);
        m_worker.kill();
        return;
    }
    m_outputBuffer.append(incoming);

    while (true) {
        const qsizetype newline = m_outputBuffer.indexOf('\n');
        if (newline < 0)
            return;
        const QByteArray line = m_outputBuffer.left(newline).trimmed();
        m_outputBuffer.remove(0, newline + 1);
        if (line.isEmpty())
            continue;

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()
            || !m_active || m_requests.isEmpty()) {
            failAll(QStringLiteral("depth-worker-protocol"),
                    QStringLiteral("AI 推理进程返回了无效响应"), true);
            m_worker.kill();
            return;
        }

        const QJsonObject response = document.object();
        const Request request = m_requests.head();
        if (response.value(QStringLiteral("version")).toInt() != 1
            || response.value(QStringLiteral("requestId")).toString() != request.id) {
            failAll(QStringLiteral("depth-worker-protocol"),
                    QStringLiteral("AI 推理进程响应与请求不匹配"), true);
            m_worker.kill();
            return;
        }

        if (response.value("event").toString() == "progress") {
            m_status = response;
            m_status.insert("busy", true);
            continue;
        }
        m_status = response.value("result").toObject();
        m_status.insert("busy", false);
        m_status.insert("error", response.value("error").toObject().value("message"));
        m_requestTimeout.stop();
        m_requests.dequeue();
        m_active = false;
        m_failureCount = 0;
        m_retryAfterMs = 0;
        const bool ok = response.value(QStringLiteral("ok")).toBool();
        if (ok) {
            request.completion(true,
                response.value(QStringLiteral("result")).toObject(), {}, {}, false);
        } else {
            const QJsonObject error = response.value(QStringLiteral("error")).toObject();
            request.completion(false, {},
                error.value(QStringLiteral("code")).toString(
                    QStringLiteral("depth-generation-failed")),
                error.value(QStringLiteral("message")).toString(
                    QStringLiteral("深度图生成失败")),
                error.value(QStringLiteral("retryable")).toBool(true));
        }

        if (!m_requests.isEmpty())
            dispatchNext();
        else
            m_idleTimeout.start();
    }
}

void AiWorkerClient::failAll(const QString &code, const QString &message,
                             bool retryable)
{
    m_requestTimeout.stop();
    m_active = false;
    m_status = {{"busy", false}, {"error", message}};
    while (!m_requests.isEmpty()) {
        const Request request = m_requests.dequeue();
        request.completion(false, {}, code, message, retryable);
    }
}

void AiWorkerClient::stopWorkerWhenIdle()
{
    if (m_active || !m_requests.isEmpty()
        || m_worker.state() != QProcess::Running)
        return;
    m_stopping = true;
    m_worker.closeWriteChannel();
}

} // namespace KosPlatform
