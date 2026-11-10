#include "IndependentApps.h"
#include "AppCatalog.h"
#include <QDateTime>

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonArray>
#include <QStandardPaths>
#include <QUuid>
#include <csignal>
#include <unistd.h>

namespace {
constexpr qint64 maximumOutput = 1024 * 1024;
}

IndependentApps::IndependentApps(const QString& resources, QObject* parent)
    : QObject(parent), m_script(resources + QStringLiteral("/app-store/installer.py"))
{
    syncCatalog();
    connect(&m_flatpak, &FlatpakAppsClient::changed, this, [this] { syncCatalog(); emit changed(); });
    connect(&m_flatpak, &FlatpakAppsClient::operationFinished, this,
        [this](const QString& appId, const QString& code, const QString& message) {
            m_flatpakResults[appId] = QVariantMap{{"code", code}, {"message", message},
                {"diskSpace", m_flatpak.state(appId).value("diskSpace")}};
            const auto state = m_flatpak.state(appId);
            if (state.contains("plan")) {
                emit changed();
                return;
            }
            refresh();
        });
    connect(&m_flatpak, &FlatpakAppsClient::mutationFinished, this,
        [this](const QString& appId, const QString& code) {
            for (const auto& entry : m_apps) {
                const auto state = entry.toMap();
                if (state.value("appId").toString() == appId) {
                    emit taskFinished(state.value("name").toString(), code);
                    break;
                }
            }
        });
    m_process.setChildProcessModifier([] { if (::setsid() < 0) ::_exit(126); });
    connect(&m_process, &QProcess::started, this, [this] {
        m_group = m_process.processId();
        // A user may cancel while QProcess is still Starting and has no pid.
        if (!m_forcedCode.isEmpty()) stop(SIGTERM);
    });
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &IndependentApps::consume);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        const auto bytes = m_process.readAllStandardError();
        log(bytes);
        m_outputBytes += bytes.size();
        if (m_outputBytes > maximumOutput && m_forcedCode.isEmpty()) {
            m_forcedCode = QStringLiteral("OUTPUT_LIMIT"); stop(SIGTERM); m_killTimer.start(15000);
        }
    });
    connect(&m_process, &QProcess::finished, this, &IndependentApps::finish);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) complete(QStringLiteral("START_FAILED"), m_process.errorString());
    });
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        m_forcedCode = QStringLiteral("OPERATION_TIMEOUT"); stop(SIGTERM); m_killTimer.start(15000);
    });
    m_killTimer.setSingleShot(true);
    connect(&m_killTimer, &QTimer::timeout, this, [this] { stop(SIGKILL); });
    m_elapsedTimer.setInterval(1000);
    connect(&m_elapsedTimer, &QTimer::timeout, this, [this] {
        if (m_active < 0) return;
        auto state = m_apps[m_active].toMap(); state["elapsedSeconds"] = m_elapsed.elapsed() / 1000;
        m_apps[m_active] = state; emit changed();
    });
}

IndependentApps::~IndependentApps()
{
    m_process.disconnect(this);
    // The engine owns compiler sessions and needs its cleanup grace before we
    // can kill it; killing Python first would strand those separate sessions.
    stop(SIGTERM);
    if (m_process.state() != QProcess::NotRunning && !m_process.waitForFinished(12000)) {
        stop(SIGKILL); m_process.waitForFinished(1000);
    }
}

void IndependentApps::syncCatalog()
{
    if (m_active >= 0) return;
    const auto context = AppCatalog::contextToken();
    if (context != m_catalogContext) { m_apps.clear(); m_flatpakResults.clear(); m_catalogContext = context; }
    QVariantList next;
    for (const auto& value : AppCatalog::apps()) {
        const auto entry = value.toMap();
        const auto appId = entry.value("appId").toString();
        const auto key = entry.value("key").toString();
        const auto id = entry.value("sourceId").toString() == "nextkde" ? key : appId;
        QVariantMap state;
        for (const auto& previous : m_apps) if (previous.toMap().value("appId").toString() == appId) state = previous.toMap();
        state["id"] = id; state["appId"] = appId;
        state["name"] = entry.value("name").toMap().value("en");
        state["nameLocales"] = entry.value("name");
        state["description"] = entry.value("description").toMap().value("en");
        state["descriptionLocales"] = entry.value("description");
        state["repository"] = "https://github.com/" + entry.value("repository").toString();
        state["sourceId"] = entry.value("sourceId");
        state["catalogActive"] = entry.value("active");
        state["catalogError"] = entry.value("error");
        state["format"] = entry.value("format");
        state["releaseTag"] = entry.value("releaseTag");
        state["testInstalled"] = AppCatalog::receipt(appId).value("entry").toMap().value("testMode").toBool();
        state["developerSignature"] = !entry.value("publisher").toMap().isEmpty();
        state["iconName"] = "grid";
        state["iconSource"] = AppCatalog::iconFile(entry);
        state["catalogVersion"] = entry.value("release").toMap().value("version");
        state["catalogApproved"] = !entry.value("release").toMap().isEmpty();
        next.append(state);
    }
    m_apps = next;
}

QVariantList IndependentApps::apps() const
{
    auto result = m_apps;
    for (int i = 0; i < result.size(); ++i) {
        auto state = result[i].toMap();
        const auto inventory = m_flatpak.state(state.value("appId").toString());
        const auto installations = inventory.value("installations").toList();
        // Only the current Flatpak identity is part of Settings inventory.
        // Native programs may coexist: they neither count as installed Flatpaks nor
        // block installation. Native cleanup is an independent, optional action.
        state["installed"] = false;
        state["managed"] = false;
        state["statusKnown"] = inventory.value("known").toBool();
        state["version"] = "";
        state["updateAvailable"] = false;
        state["flatpak"] = inventory;
        const auto progress = inventory.value("progressState").toMap();
        if (inventory.value("busy").toBool()) {
            state["busy"] = true;
            state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
        }
        if (!inventory.value("logPath").toString().isEmpty()) {
            state["logPath"] = inventory.value("logPath");
            state["engineLogPath"] = "";
        }
        if (inventory.value("busy").toBool()) {
            state["elapsedSeconds"] = progress.value("elapsedSeconds");
            state["progress"] = progress.value("progress").toInt() < 0 ? -1.0 : progress.value("progress").toDouble() / 100.0;
            state["transactionStatus"] = progress.value("status");
        }
        const auto appId = state.value("appId").toString();
        if (m_flatpakResults.contains(appId)) {
            const auto outcome = m_flatpakResults.value(appId).toMap();
            const auto code = outcome.value("code").toString();
            const bool environmentRecovered = inventory.value("known").toBool()
                && (code == "FLATPAK_NOT_INSTALLED" || code == "WORKER_UNAVAILABLE");
            if (!environmentRecovered) {
                state["code"] = outcome.value("code");
                state["message"] = outcome.value("message");
                state["diskSpace"] = outcome.value("diskSpace");
            }
        }
        if (!installations.isEmpty()) {
            const auto installation = installations.first().toMap();
            state["installed"] = true;
            state["managed"] = inventory.value("known").toBool() && installations.size() == 1
                && installation.value("scope").toString() == "user";
            if (inventory.value("busy").toBool()) {
                state["busy"] = true; state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
            }
            // Cached installations do not prove that the environment still works.
            state["statusKnown"] = inventory.value("known").toBool();
            state["backend"] = "flatpak";
            state["version"] = installation.value("version");
            state["scope"] = installation.value("scope");
            state["origin"] = installation.value("origin");
            const auto source = installation.value("source").toMap();
            state["flatpakSource"] = source;
            state["bundleManaged"] = installation.value("bundleManaged");
            state["canCheckUpdates"] = !inventory.value("querying").toBool() && inventory.value("canDiscover").toBool();
            state["flatpakUpdate"] = inventory.value("update");
            state["latestVersion"] = inventory.value("update").toMap().value("version");
            state["updateAvailable"] = inventory.value("canDiscover").toBool() && state.value("managed").toBool()
                && inventory.value("update").toMap().value("available").toBool();
            state["dependencies"] = QVariantList{};
        } else {
            state["backend"] = inventory.value("canDiscover").toBool() ? "flatpak-ready" : "flatpak-unavailable";
            // Install only needs a discoverable signed release; whether one exists is
            // answered by the prepare step, not by a prior update check.
            state["available"] = inventory.value("known").toBool() && inventory.value("canDiscover").toBool();
            state["canCheckUpdates"] = !inventory.value("querying").toBool() && inventory.value("known").toBool() && inventory.value("canDiscover").toBool();
            state["latestVersion"] = inventory.value("update").toMap().value("version");
            state["updateAvailable"] = false;
            if (inventory.value("busy").toBool()) {
                state["busy"] = true; state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
            }
        }
        state["available"] = state.value("available").toBool() && state.value("catalogActive").toBool()
            && state.value("format").toString() == "flatpak";
        state["canCheckUpdates"] = state.value("canCheckUpdates").toBool() && state.value("catalogActive").toBool();
        state["updateAvailable"] = state.value("updateAvailable").toBool() && state.value("catalogActive").toBool();
        const auto updateRecord = AppCatalog::readState("update-" + state.value("appId").toString());
        state["lastChecked"] = updateRecord.value("checkedAt");
        result[i] = state;
    }
    QVariantList visible;
    for (const auto& value : result) {
        const auto state = value.toMap();
        if (state.value("catalogActive").toBool() || state.value("installed").toBool()
            || !state.value("catalogError").toString().isEmpty()) visible.append(state);
    }
    return visible;
}
int IndependentApps::indexOf(const QString& id) const
{
    for (int i = 0; i < m_apps.size(); ++i)
        if (m_apps[i].toMap().value("id").toString() == id) return i;
    return -1;
}

void IndependentApps::refresh()
{
    syncCatalog();
    m_flatpak.refresh();
    // Source lifecycle remains an explicit CLI operation, never a fallback
    // for the Flatpak application catalogue.
}
void IndependentApps::nextStatus()
{
    if (m_active >= 0 || m_pendingStatus.isEmpty()) return;
    start(m_pendingStatus.takeFirst(), QStringLiteral("status"));
}
void IndependentApps::perform(const QString& id, const QString& action)
{
    const int index = indexOf(id);
    if (index < 0 || busy()) return;
    if (action != "install" && action != "update" && action != "uninstall" && action != "check-update") return;
    const auto descriptor = m_apps[index].toMap();
    const auto appId = descriptor.value("appId").toString();
    if (descriptor.value("format").toString() != "flatpak") return;
    if (action != "uninstall" && !descriptor.value("catalogActive").toBool()) return;
    m_flatpakResults.remove(appId);
    const auto flatpak = m_flatpak.state(appId);
    if (action == "install" || action == "update") {
        const bool installing = action == "install";
        auto state = m_apps[index].toMap();
        state["code"] = "";
        state["message"] = "";
        state["flatpak"] = QVariantMap{};
        m_apps[index] = state;
        if ((installing && state.value("installed").toBool())
            || (!installing && flatpak.value("installations").toList().isEmpty())
            || !m_flatpak.preparePlan(appId, installing)) {
            state["code"] = "FLATPAK_UNAVAILABLE";
            state["message"] = flatpak.value("error").toString();
            m_apps[index] = state;
            emit changed();
        }
        return;
    }
    if (action == "check-update") {
        if (!m_flatpak.checkUpdates(appId)) {
            auto state = m_apps[index].toMap(); state["code"] = flatpak.value("publisherConfigured").toBool() ? "FLATPAK_UNAVAILABLE" : "BUNDLE_KEY_MISSING";
            state["message"] = flatpak.value("error").toString();
            m_apps[index] = state; emit changed();
        }
        return;
    }
    if (action == "uninstall" && !flatpak.value("installations").toList().isEmpty()) {
        if (!m_flatpak.uninstall(appId)) {
            auto state = m_apps[index].toMap(); state["code"] = "FLATPAK_EXTERNAL";
            m_apps[index] = state; emit changed();
        }
        return;
    }
}
void IndependentApps::start(int index, const QString& action)
{
    m_active = index; m_action = action; m_forcedCode.clear();
    m_output.clear(); m_result = {}; m_resultCount = 0; m_outputBytes = 0; m_protocolError = false;
    auto state = m_apps[index].toMap();
    state["busy"] = true; state["stage"] = action; state["code"] = ""; state["message"] = "";
    state["elapsedSeconds"] = 0; state["progress"] = -1; state["dependencies"] = QVariantList{};
    if (!m_verifying) state["engineLogPath"] = "";
    m_apps[index] = state;
    const auto root = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + QStringLiteral("/.local/state"))
        + QStringLiteral("/kos-settings/app-store");
    if (!QDir::isAbsolutePath(root) || !QDir().mkpath(root)) { complete("PERMISSION_DENIED"); return; }
    m_log.setFileName(m_verifying ? state.value("logPath").toString()
        : root + '/' + state.value("id").toString() + '-' + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".log");
    if (!m_log.open(m_verifying ? QIODevice::WriteOnly | QIODevice::Append : QIODevice::WriteOnly | QIODevice::NewOnly)) {
        complete("PERMISSION_DENIED"); return;
    }
    m_log.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    state["logPath"] = m_log.fileName(); m_apps[index] = state;
    emit changed();
    m_elapsed.start(); m_elapsedTimer.start();
    // A fixed absolute deadline; repeated progress messages cannot keep a process alive indefinitely.
    m_deadline.start(action == "install" || action == "update" ? m_operationTimeout
        : action == "check-update" ? m_releaseTimeout : m_statusTimeout);
    m_process.setProgram(QFileInfo::exists(QStringLiteral("/usr/bin/python3"))
        ? QStringLiteral("/usr/bin/python3") : QStandardPaths::findExecutable(QStringLiteral("python3")));
    QStringList arguments{m_script, QStringLiteral("--app"), state.value("id").toString(), action};
    m_requestedVersion = (action == "install" || action == "update") ? state.value("latestVersion").toString() : QString();
    if (!m_requestedVersion.isEmpty()) arguments << QStringLiteral("--version") << m_requestedVersion;
    if (action == "prune") {
        const auto token = state.value("cleanupPlan").toMap().value("planToken").toString();
        if (token.isEmpty()) { complete("PLAN_CHANGED", "Preview old program versions before confirming cleanup."); return; }
        arguments << QStringLiteral("--yes") << QStringLiteral("--expected-plan") << token;
    }
    m_process.setArguments(arguments);
    m_process.start();
}
void IndependentApps::log(const QByteArray& bytes)
{
    if (m_log.isOpen()) { m_log.write(bytes.left(qMax<qint64>(0, maximumOutput - m_log.size()))); m_log.flush(); }
}
void IndependentApps::consume()
{
    const auto bytes = m_process.readAllStandardOutput(); log(bytes);
    m_outputBytes += bytes.size();
    if (m_outputBytes > maximumOutput) {
        if (m_forcedCode.isEmpty()) {
            m_forcedCode = QStringLiteral("OUTPUT_LIMIT"); stop(SIGTERM); m_killTimer.start(15000);
        }
        m_output.clear(); return;
    }
    m_output += bytes;
    qsizetype newline;
    while ((newline = m_output.indexOf('\n')) >= 0) {
        consumeLine(m_output.left(newline)); m_output.remove(0, newline + 1);
    }
}
void IndependentApps::consumeLine(const QByteArray& line)
{
    if (m_active < 0 || line.trimmed().isEmpty()) return;
    QJsonParseError error;
    const auto event = QJsonDocument::fromJson(line, &error).object();
    auto state = m_apps[m_active].toMap();
    if (error.error != QJsonParseError::NoError || event.value("schemaVersion").toInt() != 1
        || event.value("appId").toString() != state.value("appId").toString()
        || event.value("action").toString() != m_action) { m_protocolError = true; return; }
    if (event.value("type").toString() == "result") {
        ++m_resultCount; m_result = event;
    } else if (event.value("type").toString() == "progress" && m_resultCount == 0) {
        if (m_forcedCode.isEmpty()) state["stage"] = event.value("stage").toString();
        const auto progress = event.value("progress");
        if (progress.isDouble()) state["progress"] = qBound(-1.0, progress.toDouble(), 1.0);
        const auto engineLog = event.value("details").toObject().value("log").toString();
        if (!engineLog.isEmpty()) state["engineLogPath"] = engineLog;
        m_apps[m_active] = state; emit changed();
    } else m_protocolError = true;
}
void IndependentApps::applyStatus(QVariantMap& state, const QJsonObject& event)
{
    const auto details = event.value("details").toObject();
    if (event.value("action").toString() == "cleanup-plan" || event.value("action").toString() == "prune")
        state["cleanupPlan"] = details.toVariantMap();
    for (const auto& key : {"installed", "managed", "available", "latestVersion", "updateAvailable"})
        if (details.contains(key)) state[key] = details.value(key).toVariant();
    if (details.contains("currentVersion")) state["version"] = details.value("currentVersion").toString();
    else if (event.contains("version")) state["version"] = event.value("version").toString();
    state["dependencies"] = details.value("dependencies").toArray().toVariantList();
    const auto engineLog = details.value("log").toString();
    if (!engineLog.isEmpty()) state["engineLogPath"] = engineLog;
    if (details.contains("installed")) {
        state["statusKnown"] = true;
        if (!state.value("installed").toBool() || state.value("version").toString() == state.value("latestVersion").toString())
            state["updateAvailable"] = false;
    }
}
void IndependentApps::finish(int exitCode, QProcess::ExitStatus status)
{
    if (m_active < 0) return;
    consume(); if (!m_output.isEmpty()) consumeLine(m_output); m_output.clear();
    stop(SIGKILL); m_group = 0;
    if (!m_forcedCode.isEmpty()) { complete(m_forcedCode); return; }
    if (m_protocolError || m_resultCount != 1 || !m_result.value("success").isBool()
        || m_result.value("code").toString().isEmpty()) { complete("RESULT_UNKNOWN"); return; }
    const auto details = m_result.value("details").toObject();
    if (m_result.value("success").toBool() && ((m_action == "status" && (!details.value("installed").isBool() || !details.value("managed").isBool()))
        || (m_action == "check-update" && (!details.value("latestVersion").isString() || !details.value("updateAvailable").isBool())))) {
        complete("RESULT_UNKNOWN"); return;
    }
    auto state = m_apps[m_active].toMap();
    applyStatus(state, m_result); m_apps[m_active] = state;
    if (!m_result.value("success").toBool() || exitCode != 0 || status != QProcess::NormalExit) {
        complete(m_result.value("success").toBool() ? QStringLiteral("RESULT_UNKNOWN") : m_result.value("code").toString(),
            m_result.value("message").toString(m_result.value("details").toObject().value("message").toString())); return;
    }
    if (m_verifying && (!m_result.value("details").toObject().value("installed").isBool()
        || state.value("installed").toBool() != m_expectedInstalled
        || (m_expectedInstalled && (state.value("version").toString() != m_expectedVersion
            || m_result.value("revision").toString() != m_expectedRevision)))) { complete("RESULT_UNKNOWN"); return; }
    const int index = m_active;
    const bool mutated = m_action == "install" || m_action == "update" || m_action == "uninstall";
    if (mutated) {
        const auto code = m_result.value("code").toString();
        const bool expected = m_action == "uninstall" ? (code == "UNINSTALLED" || code == "NOT_INSTALLED")
            : (code == "INSTALLED" || code == "ALREADY_INSTALLED");
        m_expectedVersion = m_result.value("version").toString();
        m_expectedRevision = m_result.value("revision").toString();
        if (!expected || (m_action != "uninstall" && (m_expectedVersion.isEmpty() || m_expectedRevision.isEmpty()
            || (!m_requestedVersion.isEmpty() && m_expectedVersion != m_requestedVersion)))) {
            complete("RESULT_UNKNOWN"); return;
        }
        m_verifying = true; m_expectedInstalled = m_action != "uninstall";
        m_deadline.stop(); m_elapsedTimer.stop(); m_killTimer.stop(); m_log.close();
        m_active = -1;
        // Verify local state without network before reporting completion; keep busy continuously.
        start(index, QStringLiteral("status"));
    } else complete({});
}
void IndependentApps::complete(const QString& code, const QString& message)
{
    if (m_active < 0) return;
    m_deadline.stop(); m_killTimer.stop(); m_elapsedTimer.stop();
    log((code + ": " + message + '\n').toUtf8()); m_log.close();
    auto state = m_apps[m_active].toMap();
    state["busy"] = false; state["stage"] = ""; state["code"] = code; state["message"] = message;
    const bool mutated = m_verifying || isAppMutation(m_action);
    m_apps[m_active] = state; m_active = -1; m_verifying = false; emit changed();
    if (mutated) emit taskFinished(state.value("name").toString(), code);
    QTimer::singleShot(0, this, &IndependentApps::nextStatus);
}

void IndependentApps::confirmPlan(const QString& id, const QString& planId)
{
    const int index = indexOf(id);
    if (index < 0 || planId.isEmpty() || planId.size() > 128 || busy()) return;
    const auto appId = m_apps[index].toMap().value("appId").toString();
    const auto inventory = m_flatpak.state(appId);
    const auto plan = m_flatpak.plan(appId);
    if (!inventory.value("known").toBool() || inventory.value("querying").toBool()
        || inventory.value("busy").toBool() || plan.value("planId").toString() != planId
        || !m_flatpak.confirmPlan(appId, planId)) {
        auto state = m_apps[index].toMap();
        state["code"] = "PLAN_CHANGED";
        state["message"] = "The installation plan is no longer current. Prepare a fresh plan before continuing.";
        m_apps[index] = state;
        emit changed();
    }
}

void IndependentApps::stop(int signal)
{
    const auto group = m_group > 0 ? m_group : m_process.processId();
    if (group > 0) ::kill(-group, signal);
}
void IndependentApps::cancel(const QString& id)
{
    const int index = indexOf(id);
    if (index >= 0 && m_flatpak.state(m_apps[index].toMap().value("appId").toString()).value("busy").toBool()) {
        m_flatpak.cancel(); return;
    }
    if (m_active < 0 || indexOf(id) != m_active || !m_forcedCode.isEmpty()) return;
    m_pendingStatus.clear(); m_forcedCode = QStringLiteral("CANCELLED");
    auto state = m_apps[m_active].toMap(); state["stage"] = "cancelling"; m_apps[m_active] = state;
    m_deadline.stop(); stop(SIGTERM); m_killTimer.start(15000); emit changed();
}
void IndependentApps::open(const QString& id)
{
    const int index = indexOf(id);
    if (index < 0 || busy()) return;
    auto state = m_apps[index].toMap();
    const auto flatpak = m_flatpak.state(state.value("appId").toString());
    const auto installations = flatpak.value("installations").toList();
    if (!installations.isEmpty()) {
        if (!flatpak.value("known").toBool() || installations.size() != 1) {
            state["code"] = "FLATPAK_EXTERNAL"; m_apps[index] = state; emit changed(); return;
        }
        const auto installation = installations.first().toMap();
        QStringList arguments;
        if (installation.value("scope").toString() == "user") arguments << "--user";
        else arguments << "--installation=" + installation.value("installationId").toString();
        arguments << "run" << "--arch=" + installation.value("arch").toString()
            << "--branch=" + installation.value("branch").toString() << state.value("appId").toString();
        const auto executable = QStandardPaths::findExecutable(QStringLiteral("flatpak"));
        if (executable.isEmpty() || !QProcess::startDetached(executable, arguments)) {
            state["code"] = "OPEN_FAILED"; m_apps[index] = state; emit changed();
        }
        return;
    }
}
void IndependentApps::openLog(const QString& id)
{
    const int index = indexOf(id); if (index < 0) return;
    const auto stateHome = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + "/.local/state");
    QVariantMap state;
    for (const auto& item : apps()) if (item.toMap().value("id").toString() == id) state = item.toMap();
    const auto namespaceId = id == "listenfree" ? id : state.value("appId").toString();
    const auto engineRoot = QFileInfo(stateHome + "/nextkde-apps/" + namespaceId).canonicalFilePath();
    const auto enginePath = QFileInfo(state.value("engineLogPath").toString()).canonicalFilePath();
    if (!engineRoot.isEmpty() && !enginePath.isEmpty() && enginePath.startsWith(engineRoot + '/')) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(enginePath)); return;
    }
    const auto path = QFileInfo(state.value("logPath").toString()).canonicalFilePath();
    const auto root = QFileInfo(stateHome + "/kos-settings/app-store").canonicalFilePath();
    if (!root.isEmpty() && !path.isEmpty() && path.startsWith(root + '/'))
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}
void IndependentApps::openRepository(const QString& id)
{
    const int index = indexOf(id);
    if (index >= 0) QDesktopServices::openUrl(QUrl(m_apps[index].toMap().value("repository").toString()));
}

