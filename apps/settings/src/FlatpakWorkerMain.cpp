#include "FlatpakApps.h"
#ifdef KOS_FLATPAK_NATIVE_HELPERS
#include "FlatpakCompatibility.h"
#include "FlatpakTransactionProcess.h"
#endif
#include "IndependentAppRegistry.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QJsonObject>
#include <QHash>
#include <QDateTime>
#include <QUuid>
#include <QSocketNotifier>
#include <QTimer>
#include <csignal>
#include <cstdio>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <unistd.h>

namespace {
QByteArray inputBuffer;
QString requestId;
QString appId;
QString action;
bool requestPending = false;
bool confirmRechecking = false;
bool settingUpSource = false;
bool sourceSetupAttempted = false;
bool preparingPlan() { return action == "prepare-install" || action == "prepare-update"; }
bool installingPlan() { return action == "prepare-install"; }
QHash<QString, QVariantMap> plans;

QString planDirectory()
{
    return qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + "/.local/state")
        + "/kos-settings/flatpak-plans";
}

QString planPath(const QString& appId)
{
    return planDirectory() + "/" + appId + ".json";
}

void removePersistedPlan(const QString& appId)
{
    QFile::remove(planPath(appId));
}

bool validPersistedPlan(const QString& appId, const QVariantMap& plan)
{
    const auto expiry = QDateTime::fromString(plan.value("expiresAt").toString(), Qt::ISODateWithMs);
    const auto planId = plan.value("planId").toString();
    return plan.value("appId").toString() == appId && !planId.isEmpty() && planId.size() <= 128
        && expiry.isValid() && expiry > QDateTime::currentDateTimeUtc();
}

bool persistPlan(const QString& appId, const QVariantMap& plan)
{
    if (!validPersistedPlan(appId, plan) || !QDir().mkpath(planDirectory())) return false;
    QFile::setPermissions(planDirectory(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    QSaveFile file(planPath(appId));
    if (!file.open(QIODevice::WriteOnly)) return false;
    const auto bytes = QJsonDocument::fromVariant(plan).toJson(QJsonDocument::Compact);
    if (file.write(bytes) != bytes.size() || !file.commit()) return false;
    QFile::setPermissions(planPath(appId), QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

void loadPersistedPlans()
{
    for (const auto& entry : IndependentAppRegistry::apps()) {
        const auto appId = entry.appId;
        QFile file(planPath(appId));
        if (!file.open(QIODevice::ReadOnly) || file.size() > 1024 * 1024) {
            removePersistedPlan(appId);
            continue;
        }
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(file.readAll(), &error);
        const auto plan = document.isObject() ? document.object().toVariantMap() : QVariantMap{};
        if (error.error == QJsonParseError::NoError && validPersistedPlan(appId, plan))
            plans.insert(appId, plan);
        else
            removePersistedPlan(appId);
    }
}

void send(const QJsonObject& object)
{
    std::puts(QJsonDocument(object).toJson(QJsonDocument::Compact).constData());
    std::fflush(stdout);
}

QJsonObject response(const QString& type, const QJsonObject& payload = {})
{
    QJsonObject result{{"schemaVersion", 1}, {"requestId", requestId}, {"type", type},
        {"action", action}, {"appId", appId}};
    for (auto it = payload.begin(); it != payload.end(); ++it) result.insert(it.key(), it.value());
    return result;
}

QJsonObject inventoryResult(FlatpakApps& backend)
{
    QJsonObject apps;
    for (const auto& entry : IndependentAppRegistry::apps()) {
        const auto id = entry.appId;
        apps.insert(id, QJsonObject::fromVariantMap(backend.state(id)));
    }
    const auto first = backend.state((IndependentAppRegistry::apps().isEmpty() ? QString() : IndependentAppRegistry::apps().first().appId));
    return {{"known", first.value("known").toBool()}, {"error", first.value("error").toString()},
        {"apps", apps}};
}

int inventoryOnce(int argc, char** argv)
{
    QCoreApplication application(argc, argv);
    FlatpakApps backend;
    QTimer poll;
    poll.setInterval(25);
    QObject::connect(&poll, &QTimer::timeout, &application, [&] {
        if (backend.querying()) return;
        QJsonObject apps;
        for (const auto& entry : IndependentAppRegistry::apps()) {
            const auto id = entry.appId;
            apps.insert(id, QJsonObject::fromVariantMap(backend.state(id)));
        }
        const auto first = backend.state((IndependentAppRegistry::apps().isEmpty() ? QString() : IndependentAppRegistry::apps().first().appId));
        send({{"schemaVersion", 1}, {"type", "inventory"}, {"known", first.value("known").toBool()},
            {"error", first.value("error").toString()}, {"apps", apps}});
        application.exit(first.value("known").toBool() ? 0 : 2);
    });
    poll.start();
    return application.exec();
}

void finishRequest(FlatpakApps& backend, const QString& code = {}, const QString& message = {})
{
    if (!requestPending) return;
    const auto current = backend.state(appId);
    QJsonObject result = QJsonObject::fromVariantMap(current);
    result.insert("code", code);
    result.insert("message", message);
    // Discovery and plan preparation are separate steps. Keep the final failure
    // in the same app log rather than leaving a misleading successful query.
    if (!code.isEmpty() && preparingPlan()) {
        QFile log(current.value("logPath").toString());
        if (log.open(QIODevice::WriteOnly | QIODevice::Append))
            log.write((action + " " + code + ": " + message + '\n').toUtf8());
    }
    send(response("result", {{"appId", appId}, {"result", result}}));
    requestPending = false;
    confirmRechecking = false;
    requestId.clear(); appId.clear(); action.clear();
}

bool dispatch(FlatpakApps& backend, const QJsonObject& request)
{
    if (request.value("schemaVersion").toInt() != 1 || request.value("requestId").toString().isEmpty()
        || request.value("requestId").toString().size() > 64 || requestPending) return false;
    requestId = request.value("requestId").toString();
    action = request.value("action").toString();
    appId = request.value("appId").toString();
    requestPending = true;
    sourceSetupAttempted = false;
    if (action == "inventory") {
        backend.refresh();
        return true;
    }
    const auto app = IndependentAppRegistry::find(appId);
    if (!app || !QStringList{"check-update", "install", "update", "uninstall", "prepare-install", "prepare-update", "confirm-plan"}.contains(action)) {
        finishRequest(backend, "INVALID_REQUEST", "Unsupported Flatpak worker action or application.");
        return true;
    }
    if (action == "install" || action == "update") {
        finishRequest(backend, "PLAN_REQUIRED", "Prepare and explicitly confirm a dependency plan before downloading or deploying a Flatpak.");
        return true;
    }
    if (action == "check-update") {
        if (!backend.checkUpdates(appId)) finishRequest(backend, "FLATPAK_UNAVAILABLE", "The application state is unknown or conflicts with another installation.");
        return true;
    }
    if (preparingPlan()) {
        // A fresh preparation supersedes any unconfirmed plan for this app.
        plans.remove(appId);
        removePersistedPlan(appId);
        // Install/Update prepares missing component sources automatically. No
        // application or runtime download starts before the normal plan consent.
        if (!backend.checkUpdates(appId)) {
            finishRequest(backend, "FLATPAK_UNAVAILABLE", "The application state is unknown or conflicts with another installation.");
        }
        return true;
    }
    if (action == "confirm-plan") {
        const auto supplied = request.value("planId").toString();
        const auto plan = plans.value(appId);
        const auto expiry = QDateTime::fromString(plan.value("expiresAt").toString(), Qt::ISODateWithMs);
        if (supplied.isEmpty() || plan.isEmpty() || supplied != plan.value("planId").toString()
            || !expiry.isValid() || expiry <= QDateTime::currentDateTimeUtc()) {
            plans.remove(appId);
            removePersistedPlan(appId);
            finishRequest(backend, "PLAN_CHANGED", "The requested plan is no longer available; prepare a fresh plan.");
            return true;
        }
        // A worker started for a later CLI invocation has no discovery cache. Rebuild
        // the signed candidate first; confirmPlan performs the full exact-plan check.
        confirmRechecking = true;
        if (!backend.checkUpdates(appId)) {
            plans.remove(appId);
            removePersistedPlan(appId);
            finishRequest(backend, "PLAN_CHANGED", "The installation state or signed release changed; prepare a fresh plan.");
        }
        return true;
    }
    bool started = false;
    if (action == "install") started = backend.install(appId);
    else if (action == "update") started = backend.update(appId);
    else started = backend.uninstall(appId);
    if (!started) finishRequest(backend, "FLATPAK_UNAVAILABLE", "The requested signed bundle or unambiguous user installation is unavailable.");
    return true;
}
}

int main(int argc, char** argv)
{
    if (argc == 2 && QByteArray(argv[1]) == "--inventory") return inventoryOnce(argc, argv);

    QCoreApplication application(argc, argv);
#ifdef KOS_FLATPAK_NATIVE_HELPERS
    if (argc == 2 && QByteArray(argv[1]) == "--flatpak-transaction-helper")
        return FlatpakTransactionProcess::helperMain();
    if (argc == 2 && QByteArray(argv[1]) == "--probe-flatpak-bundle-cleanup")
        return FlatpakCompatibility::probeBundleCleanup();
#endif
    if (argc != 2 || QByteArray(argv[1]) != "--rpc") return 2;
    const auto parent = ::getppid();
    if (parent <= 1 || ::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || ::getppid() != parent) return 2;
    const rlimit noCore{0, 0};
    setrlimit(RLIMIT_CORE, &noCore);

    loadPersistedPlans();
    FlatpakApps backend;
    QObject::connect(&backend, &FlatpakApps::changed, &application, [&] {
        if (requestPending && action == "inventory" && !backend.querying()) {
            send(response("result", {{"appId", ""}, {"result", inventoryResult(backend)}}));
            requestPending = false; requestId.clear(); appId.clear(); action.clear();
            return;
        }
        if (requestPending && preparingPlan()
            && !settingUpSource && !backend.busy() && !backend.querying()) {
            auto current = backend.state(appId);
            QVariantMap failure;
            auto plan = backend.makePlan(appId, installingPlan(), &failure);
            QString planError;
            if (!plan.isEmpty()) {
                plan.insert("planId", QUuid::createUuid().toString(QUuid::WithoutBraces));
                if (persistPlan(appId, plan)) plans.insert(appId, plan);
                else { plan.clear(); planError = "The dependency plan could not be retained for confirmation."; }
            }
            if (plan.isEmpty() && failure.value("code").toString() == "RUNTIME_SOURCE_MISSING" && !sourceSetupAttempted) {
                sourceSetupAttempted = true;
                settingUpSource = true;
                if (!backend.setupRuntimeSource(appId)) {
                    settingUpSource = false;
                    finishRequest(backend, "RUNTIME_SETUP_FAILED");
                }
                return;
            }
            if (plan.isEmpty()) {
                finishRequest(backend, failure.value("code").toString(),
                    planError.isEmpty() ? failure.value("message").toString() : planError);
                return;
            }
            current.insert("plan", plan);
            current.insert("code", "");
            current.insert("message", "");
            send(response("result", {{"appId", appId}, {"result", QJsonObject::fromVariantMap(current)}}));
            requestPending = false; requestId.clear(); appId.clear(); action.clear();
            return;
        }
        if (!requestPending || appId.isEmpty()) return;
        const auto progress = backend.state(appId).value("progressState").toMap();
        const auto status = progress.value("status").toString();
        const auto reported = progress.value("progress");
        const int value = reported.isValid() ? reported.toInt() : -1;
        send(response("progress", {{"appId", appId}, {"status", status.left(4096)}, {"progress", value}}));
    });
    QObject::connect(&backend, &FlatpakApps::operationFinished, &application,
        [&](const QString& completedId, const QString& code, const QString& message) {
            if (!requestPending || completedId != appId) return;
            if (settingUpSource) {
                settingUpSource = false;
                if (!code.isEmpty()) finishRequest(backend, code, message);
                else if (!backend.checkUpdates(appId)) finishRequest(backend, "PLAN_UNAVAILABLE");
                return;
            }
            if (preparingPlan()) {
                // Do not replace discovery errors (network/signature/release) with
                // a generic empty-plan error from the subsequent changed signal.
                if (!code.isEmpty()) finishRequest(backend, code, message);
                return;
            }
            if (action == "confirm-plan" && confirmRechecking) {
                confirmRechecking = false;
                const auto plan = plans.value(appId);
                if (!code.isEmpty() || plan.isEmpty() || !backend.confirmPlan(appId, plan)) {
                    plans.remove(appId);
                    removePersistedPlan(appId);
                    finishRequest(backend, "PLAN_CHANGED", "The installation state, source or dependency plan changed while awaiting confirmation.");
                } else {
                    // A plan is single-use. The transaction still performs its own
                    // ready-stage operation-set and source verification.
                    plans.remove(appId);
                    removePersistedPlan(appId);
                }
                return;
            }
            finishRequest(backend, code, message);
        });
    QSocketNotifier input(STDIN_FILENO, QSocketNotifier::Read, &application);
    QObject::connect(&input, &QSocketNotifier::activated, &application, [&] {
        char buffer[8192];
        const auto count = ::read(STDIN_FILENO, buffer, sizeof buffer);
        if (count <= 0) { application.quit(); return; }
        inputBuffer.append(buffer, count);
        if (inputBuffer.size() > 1024 * 1024) { application.exit(2); return; }
        qsizetype newline;
        while ((newline = inputBuffer.indexOf('\n')) >= 0) {
            const auto line = inputBuffer.left(newline);
            inputBuffer.remove(0, newline + 1);
            QJsonParseError error;
            const auto document = QJsonDocument::fromJson(line, &error);
            if (error.error != QJsonParseError::NoError || !document.isObject()) { application.exit(2); return; }
            const auto request = document.object();
            if (request.value("action") == QLatin1String("cancel")) {
                if (requestPending && request.value("requestId").toString() == requestId) backend.cancel();
                continue;
            }
            if (!dispatch(backend, request)) { application.exit(2); return; }
        }
    });
    return application.exec();
}
