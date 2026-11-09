#include "FlatpakAppsClient.h"
#include "AppCatalog.h"
#include <QDateTime>

#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QStandardPaths>
#include <utility>

namespace {
constexpr qsizetype maximumMessageBytes = 1024 * 1024;
QString workerPath()
{
    const auto directory = QCoreApplication::applicationDirPath();
    for (const auto& path : {directory + "/kos-flatpak-worker", directory + "/../bin/kos-flatpak-worker"})
        if (QFileInfo(path).isExecutable()) return path;
#ifdef KOS_FLATPAK_WORKER_BUILD_PATH
    if (QFileInfo(QStringLiteral(KOS_FLATPAK_WORKER_BUILD_PATH)).isExecutable())
        return QStringLiteral(KOS_FLATPAK_WORKER_BUILD_PATH);
#endif
    return directory + "/kos-flatpak-worker";
}
bool validState(const QJsonObject& state)
{
    return state.value("known").isBool() && state.value("installations").isArray()
        && state.value("installations").toArray().size() <= 256;
}
}

FlatpakAppsClient::FlatpakAppsClient(QObject* parent, bool polling) : QObject(parent)
{
    m_process.setProcessChannelMode(QProcess::SeparateChannels);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_stdout += m_process.readAllStandardOutput();
        if (m_stdout.size() > maximumMessageBytes) {
            failActive("PROTOCOL_ERROR", "Flatpak worker output exceeded its limit."); return;
        }
        while (m_stdout.contains('\n')) {
            const auto end = m_stdout.indexOf('\n');
            const auto line = m_stdout.left(end);
            m_stdout.remove(0, end + 1);
            QJsonParseError error;
            const auto document = QJsonDocument::fromJson(line, &error);
            const auto object = document.object();
            if (error.error != QJsonParseError::NoError || !document.isObject()
                || m_requestId.isEmpty() || object.value("schemaVersion").toInt() != 1
                || object.value("requestId").toString() != m_requestId
                || object.value("action").toString() != m_activeAction
                || object.value("appId").toString() != m_activeId) {
                failActive("PROTOCOL_ERROR", "Flatpak worker response identity or protocol did not match."); return;
            }
            const auto type = object.value("type").toString();
            m_workerResponded = true;
            if (type == "progress") {
                const int progress = object.value("progress").toInt(-2);
                if (m_activeId.isEmpty() || !object.value("status").isString()
                    || object.value("status").toString().size() > 4096 || progress < -1 || progress > 100) {
                    failActive("PROTOCOL_ERROR", "Flatpak worker progress was invalid."); return;
                }
                auto state = m_states.value(m_activeId).toMap();
                auto status = state.value("progressState").toMap();
                status.insert("status", object.value("status").toString());
                status.insert("progress", progress);
                status.insert("cancelling", m_cancelRequested);
                state.insert("progressState", status);
                m_states.insert(m_activeId, state);
                emit changed();
                continue;
            }
            if (type != "result" || !object.value("result").isObject()) {
                failActive("PROTOCOL_ERROR", "Flatpak worker response type was invalid."); return;
            }
            const auto result = object.value("result").toObject();
            if (m_activeAction == "inventory") {
                if (!result.value("apps").isObject()) {
                    failActive("PROTOCOL_ERROR", "Flatpak inventory response was invalid."); return;
                }
                const auto apps = result.value("apps").toObject();
                for (auto it = apps.begin(); it != apps.end(); ++it) {
                    if (!it.value().isObject() || !validState(it.value().toObject())) {
                        failActive("PROTOCOL_ERROR", "Flatpak inventory state was invalid."); return;
                    }
                }
                for (auto it = apps.begin(); it != apps.end(); ++it) {
                    auto state = it.value().toObject().toVariantMap();
                    const auto previous = m_states.value(it.key()).toMap();
                    if (!previous.value("plan").toMap().isEmpty())
                        state.insert("plan", previous.value("plan"));
                    if (!previous.value("update").toMap().isEmpty())
                        state.insert("update", previous.value("update"));
                    m_states.insert(it.key(), state);
                }
                m_lastStatus.clear();
                m_lastCode.clear();
            } else {
                if (!validState(result)) {
                    failActive("PROTOCOL_ERROR", "Flatpak operation state was invalid."); return;
                }
                auto state = result.toVariantMap();
                if (m_activeAction.startsWith("prepare-")) {
                    // Only the worker may issue an installation plan. The client
                    // must never turn an update description into authorization.
                    state.insert("plan", state.value("plan").toMap());
                }
                m_states.insert(m_activeId, state);
                if (m_activeAction == "check-update") {
                    AppCatalog::writeState("update-" + m_activeId, {{"state", state},
                        {"checkedAt", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}});
                }
            }
            const auto id = m_activeId;
            const auto action = m_activeAction;
            const auto code = result.value("code").toString();
            const auto message = result.value("message").toString();
            m_activeId.clear(); m_activeAction.clear(); m_requestId.clear(); m_cancelRequested = false;
            m_deadline.stop();
            if (!id.isEmpty()) {
                emit operationFinished(id, code, message);
                if (isWorkerMutation(action)) emit mutationFinished(id, code);
            }
            emit changed();
            startNext();
        }
    });
    // Diagnostics may contain signed URLs; never forward raw worker stderr to UI.
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] { m_process.readAllStandardError(); });
    connect(&m_process, &QProcess::finished, this, &FlatpakAppsClient::finish);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && !m_requestId.isEmpty())
            failActive("WORKER_UNAVAILABLE", "The optional Flatpak backend could not start. Install the KOS Flatpak backend and its distribution dependencies, then recheck.");
    });
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        failActive("WORKER_TIMEOUT", "Flatpak backend timed out; installed state is unknown. Recheck before retrying.");
    });
    m_killTimer.setSingleShot(true);
    connect(&m_killTimer, &QTimer::timeout, this, [this] { if (m_process.state() != QProcess::NotRunning) m_process.kill(); });
    m_refreshTimer.setInterval(5000);
    connect(&m_refreshTimer, &QTimer::timeout, this, &FlatpakAppsClient::refresh);
    if (polling) {
        m_refreshTimer.start();
        QTimer::singleShot(0, this, &FlatpakAppsClient::refresh);
    }
}

FlatpakAppsClient::~FlatpakAppsClient()
{
    m_process.disconnect(this);
    if (m_process.state() != QProcess::NotRunning) {
        m_process.terminate();
        if (!m_process.waitForFinished(1000)) { m_process.kill(); m_process.waitForFinished(1000); }
    }
}

QVariantMap FlatpakAppsClient::plan(const QString& appId) const
{
    return m_states.value(appId).toMap().value("plan").toMap();
}

void FlatpakAppsClient::releaseIdleWorker()
{
    if (querying()) return;
    // The session update agent has no reason to keep an inventory process alive
    // for six hours between scans. Keep its last snapshot without reporting a crash.
    m_process.blockSignals(true);
    if (m_process.state() != QProcess::NotRunning) {
        m_process.terminate();
        if (!m_process.waitForFinished(1000)) { m_process.kill(); m_process.waitForFinished(1000); }
    }
    m_stdout.clear();
    m_process.blockSignals(false);
}

QString FlatpakAppsClient::planId(const QString& appId) const
{
    return plan(appId).value("planId").toString();
}

QVariantMap FlatpakAppsClient::state(const QString& appId) const
{
    auto result = m_states.value(appId).toMap();
    if (result.isEmpty()) result = {{"known", false}, {"installations", QVariantList{}},
        {"error", m_lastStatus}, {"errorCode", m_lastCode}};
    // Only reuse a background result for the exact installation and directory entry.
    const auto entry = AppCatalog::find(appId);
    const auto saved = AppCatalog::readState("update-" + appId).value("state").toMap();
    const auto savedUpdate = saved.value("update").toMap();
    auto current = result.value("update").toMap();
    const auto matches = [&](const QVariantMap& update) {
        const auto installations = result.value("installations").toList();
        const auto selected = update.value("installation").toMap();
        return entry.value("active").toBool()
            && update.value("catalogEntryDigest").toString() == AppCatalog::entryDigest(entry)
            && (installations.isEmpty() ? selected.isEmpty()
                : installations.size() == 1 && selected == installations.first().toMap());
    };
    if (!matches(current)) current.clear();
    if (saved.value("known").toBool() && saved.value("installations") == result.value("installations") && matches(savedUpdate)) current = savedUpdate;
    result["update"] = current;
    result["canDiscover"] = result.value("canDiscover").toBool() && entry.value("active").toBool();
    result.insert("querying", querying());
    result.insert("busy", m_activeId == appId);
    if (m_activeId == appId) result.insert("stage", m_activeAction);
    return result;
}

void FlatpakAppsClient::refresh()
{
    if (!m_requestId.isEmpty() || !m_queue.isEmpty()) return;
    m_queue.append("*");
    startNext();
}
bool FlatpakAppsClient::uninstall(const QString& appId) { return start(appId, "uninstall"); }
bool FlatpakAppsClient::checkUpdates(const QString& appId) { return start(appId, "check-update"); }
bool FlatpakAppsClient::update(const QString& appId) { return start(appId, "update"); }
bool FlatpakAppsClient::install(const QString& appId) { return start(appId, "install"); }
bool FlatpakAppsClient::preparePlan(const QString& appId, bool installing) { return start(appId, installing ? "prepare-install" : "prepare-update"); }
bool FlatpakAppsClient::confirmPlan(const QString& appId, const QString& planId)
{
    if (planId.isEmpty() || planId.size() > 128 || !m_requestId.isEmpty()) return false;
    m_planId = planId;
    const bool started = start(appId, "confirm-plan");
    if (!started) m_planId.clear();
    return started;
}

bool FlatpakAppsClient::start(const QString& appId, const QString& action)
{
    if (appId.isEmpty() || appId.contains('\n') || !m_queue.isEmpty() || !m_requestId.isEmpty()) return false;
    m_queue.append(appId + '\n' + action);
    startNext();
    return true;
}

bool FlatpakAppsClient::ensureWorker()
{
    if (m_process.state() == QProcess::Running) return true;
    if (m_process.state() != QProcess::NotRunning || !QFileInfo(workerPath()).isExecutable()) return false;
    m_process.setProgram(workerPath());
    m_process.setArguments({"--rpc"});
    m_workerResponded = false;
    m_process.start();
    return m_process.waitForStarted(1000);
}

void FlatpakAppsClient::startNext()
{
    if (!m_requestId.isEmpty() || m_queue.isEmpty()) return;
    const auto queued = m_queue.takeFirst();
    if (queued == "*") { m_activeId.clear(); m_activeAction = "inventory"; }
    else { const auto parts = queued.split('\n'); m_activeId = parts.at(0); m_activeAction = parts.at(1); }
    m_requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    // Check again for every request, including confirmation, so an environment
    // removed after inventory cannot reach bundle download or deployment.
    if (QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty()) {
        failActive("FLATPAK_NOT_INSTALLED", "Flatpak is not installed or its command is not available. Install Flatpak using your system software manager, then check again."); return;
    }
    if (!ensureWorker()) {
        failActive("WORKER_UNAVAILABLE", "The optional Flatpak backend is not installed or cannot start. Install the KOS Flatpak backend and its distribution dependencies, then recheck."); return;
    }
    // Process startup can deliver an error/exit signal while waiting above.
    if (m_requestId.isEmpty()) return;
    QJsonObject request{{"schemaVersion", 1}, {"requestId", m_requestId}, {"action", m_activeAction}, {"appId", m_activeId}};
    if (m_activeAction == "confirm-plan") request.insert("planId", std::exchange(m_planId, {}));
    m_process.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    const bool preparing = m_activeAction.startsWith("prepare-");
    m_deadline.start(m_activeAction == "inventory" ? 15000 : m_activeAction == "check-update" || preparing ? 120000 : 60 * 60 * 1000);
    emit changed();
}

void FlatpakAppsClient::cancel()
{
    if (m_activeId.isEmpty() || m_requestId.isEmpty() || m_process.state() != QProcess::Running) return;
    m_cancelRequested = true;
    m_process.write(QJsonDocument(QJsonObject{{"schemaVersion", 1}, {"requestId", m_requestId},
        {"action", "cancel"}, {"appId", m_activeId}}).toJson(QJsonDocument::Compact) + '\n');
}

void FlatpakAppsClient::finish(int, QProcess::ExitStatus)
{
    m_killTimer.stop();
    const auto code = m_workerResponded ? QStringLiteral("RESULT_UNKNOWN") : QStringLiteral("WORKER_UNAVAILABLE");
    const auto message = m_workerResponded
        ? QStringLiteral("Flatpak backend exited; installed state is unknown. Recheck before retrying.")
        : QStringLiteral("The optional Flatpak backend could not start. Install the KOS Flatpak backend and its distribution dependencies, then recheck.");
    failActive(m_forcedCode.isEmpty() ? code : m_forcedCode,
        m_forcedMessage.isEmpty() ? message : m_forcedMessage);
}

void FlatpakAppsClient::failActive(const QString& code, const QString& message)
{
    m_deadline.stop();
    if (m_process.state() != QProcess::NotRunning) {
        m_forcedCode = code; m_forcedMessage = message;
        m_process.terminate(); m_killTimer.start(2000); return;
    }
    const auto id = m_activeId;
    m_lastStatus = message;
    m_lastCode = code;
    for (auto it = m_states.begin(); it != m_states.end(); ++it) {
        auto state = it.value().toMap();
        state.insert("known", false); state.insert("querying", false); state.insert("busy", false);
        state.insert("error", message); state.insert("plan", QVariantMap{}); state.insert("update", QVariantMap{});
        state.insert("errorCode", code);
        it.value() = state;
    }
    m_activeId.clear(); m_activeAction.clear(); m_requestId.clear(); m_planId.clear();
    m_forcedCode.clear(); m_forcedMessage.clear(); m_stdout.clear(); m_cancelRequested = false;
    if (!id.isEmpty()) emit operationFinished(id, code, message);
    emit changed();
}

QVariantMap FlatpakAppsClient::inventory(const std::function<bool()>& cancelled)
{
    if (QStandardPaths::findExecutable(QStringLiteral("flatpak")).isEmpty())
        return {{"known", false}, {"errorCode", "FLATPAK_NOT_INSTALLED"},
            {"error", "Flatpak is not installed or its command is not available. Install Flatpak using your system software manager, then check again."}};
    QProcess process;
    process.setProgram(workerPath());
    process.setArguments({"--inventory"});
    process.start();
    if (!process.waitForStarted(1000)) return {{"known", false}, {"error", "Optional Flatpak backend is unavailable; installation state is unknown."}};
    QByteArray bytes;
    QElapsedTimer elapsed; elapsed.start();
    while (process.state() != QProcess::NotRunning && elapsed.elapsed() < 14000 && !cancelled()) {
        process.waitForFinished(50);
        bytes += process.readAllStandardOutput();
        process.readAllStandardError();
        if (bytes.size() > maximumMessageBytes) break;
    }
    if (process.state() != QProcess::NotRunning) {
        process.kill(); process.waitForFinished(1000);
        return {{"known", false}, {"error", "Flatpak inventory was cancelled, timed out or exceeded its limit."}};
    }
    bytes += process.readAllStandardOutput();
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(bytes, &error);
    const auto result = document.object();
    if (bytes.size() > maximumMessageBytes || process.exitStatus() != QProcess::NormalExit
        || error.error != QJsonParseError::NoError || result.value("schemaVersion").toInt() != 1
        || result.value("type").toString() != "inventory" || !result.value("known").isBool()
        || !result.value("apps").isObject())
        return {{"known", false}, {"error", "Flatpak inventory protocol or backend failed; installation state is unknown."}};
    const auto apps = result.value("apps").toObject();
    for (auto it = apps.begin(); it != apps.end(); ++it)
        if (!validState(it.value().toObject())) return {{"known", false}, {"error", "Flatpak inventory state is invalid."}};
    return result.toVariantMap();
}
