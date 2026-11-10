#include "FlatpakAppsClient.h"
#ifdef KOS_FLATPAK_NATIVE_HELPERS
#include "FlatpakCompatibility.h"
#include "FlatpakTransactionProcess.h"
#endif
#include "IndependentAppRegistry.h"

#include <QCoreApplication>
#include <QCommandLineParser>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <cstdio>
#include <csignal>

namespace {
volatile std::sig_atomic_t interrupted = 0;
void interrupt(int) { interrupted = 1; }

void printState(const QString& appId, const QString& action, const QVariantMap& state,
    const QString& code = {}, const QString& message = {})
{
    const QJsonObject result{{"schemaVersion", 1}, {"appId", appId}, {"action", action},
        {"code", code}, {"message", message}, {"success", code.isEmpty()}, {"testMode", AppCatalog::testMode()},
        {"state", QJsonObject::fromVariantMap(state)}};
    std::puts(QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
}
}

int main(int argc, char** argv)
{
#ifdef KOS_FLATPAK_NATIVE_HELPERS
    if (argc == 2 && QByteArray(argv[1]) == "--flatpak-transaction-helper")
        return FlatpakTransactionProcess::helperMain();
    if (argc == 2 && QByteArray(argv[1]) == "--probe-flatpak-bundle-cleanup")
        return FlatpakCompatibility::probeBundleCleanup();
#endif
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName("kos-apps");
    QCommandLineParser parser;
    parser.setApplicationDescription("Manage catalogued user Flatpaks. Missing runtimes use the approved source. Normal uninstall preserves personal data.");
    parser.addHelpOption();
    parser.addOption({"app", "Application ID or unique key from the trusted catalog", "app"});
    parser.addOption({"yes", "Confirm a previously displayed plan without a terminal prompt"});
    parser.addOption({"plan-id", "Opaque plan ID returned by a prior plan operation", "plan-id"});
    parser.addPositionalArgument("action", "status, check-update, install, update or uninstall");
    parser.process(application);
    const auto entry = IndependentAppRegistry::find(parser.value("app"));
    const auto actions = parser.positionalArguments();
    const QStringList supported{"status", "check-update", "install", "update", "uninstall"};
    if (!entry || actions.size() != 1 || !supported.contains(actions.first())) parser.showHelp(2);
    const auto action = actions.first();
    const QString appId = entry->appId;
    if (action == "install" && entry->repository == "NextKde/kos-apps")
        std::fputs("This is a separate application: old program/data is not adopted or imported. Existing data for the new ID is kept. Legacy cleanup is a separate explicit operation.\n", stderr);

    FlatpakAppsClient backend;
    bool started = false;
    bool mutationStarted = false;
    bool done = false;
    const auto finish = [&](const QString& code, const QString& message) {
        if (done) return;
        done = true;
        printState(appId, action, backend.state(appId), code, message);
        application.exit(code.isEmpty() ? 0 : code == "CANCELLED" ? 130 : 2);
    };
    QObject::connect(&backend, &FlatpakAppsClient::operationFinished, &application,
        [&](const QString& completedId, const QString& code, const QString& message) {
            if (completedId != appId) return;
            if ((action == "install" || action == "update") && code.isEmpty()) {
                if (mutationStarted) { finish(code, message); return; }
                if (parser.isSet("yes")) return;
                const auto plan = backend.plan(appId);
                if (plan.isEmpty()) {
                    finish("PLAN_REQUIRED", "No dependency plan was returned; prepare a fresh plan.");
                    return;
                }
                std::fputs(QJsonDocument(QJsonObject::fromVariantMap(plan)).toJson(QJsonDocument::Compact).constData(), stdout);
                std::fputc('\n', stdout);
                finish("CONFIRMATION_REQUIRED", "Review the plan and rerun with --plan-id PLAN_ID --yes.");
                return;
            }
            finish(code, message);
        });
    QObject::connect(&backend, &FlatpakAppsClient::changed, &application, [&] {
        if (done || backend.querying()) return;
        if (interrupted) { backend.cancel(); return; }
        const auto state = backend.state(appId);
        if (!state.value("known").toBool()) {
            if (!state.value("querying").toBool()) finish("RESULT_UNKNOWN", state.value("error").toString());
            return;
        }
        if (action == "status") { finish({}, {}); return; }
        if (action == "check-update") {
            if (!started) {
                started = true;
                if (!backend.checkUpdates(appId)) finish("FLATPAK_UNAVAILABLE", "The application state is unknown or conflicts with another installation.");
            }
            return;
        }
        if (action == "uninstall") {
            if (!started) {
                started = true;
                if (!parser.isSet("yes")) { finish("CONFIRMATION_REQUIRED", "Use --yes to confirm uninstall; personal data is kept."); return; }
                if (!backend.uninstall(appId)) finish("FLATPAK_UNAVAILABLE", "No matching user Flatpak is installed.");
            }
            return;
        }
        const bool installing = action == "install";
        if (started) return;
        if (parser.isSet("yes")) {
            if (parser.value("plan-id").isEmpty()) {
                finish("PLAN_REQUIRED", "A plan must be prepared first; use --plan-id PLAN_ID --yes.");
                return;
            }
            started = true;
            mutationStarted = true;
            if (!backend.confirmPlan(appId, parser.value("plan-id")))
                finish("PLAN_CHANGED", "The requested plan is no longer available; prepare a fresh plan.");
            return;
        }
        if (parser.isSet("plan-id")) {
            finish("PLAN_REQUIRED", "Use --yes together with --plan-id PLAN_ID to confirm a plan.");
            return;
        }
        started = true;
        if (!backend.preparePlan(appId, installing))
            finish("FLATPAK_UNAVAILABLE", "Unable to prepare a dependency plan without downloading payloads.");
    });
    std::signal(SIGINT, interrupt);
    std::signal(SIGTERM, interrupt);
    QTimer signalTimer;
    signalTimer.setInterval(100);
    QObject::connect(&signalTimer, &QTimer::timeout, &application, [&] {
        if (interrupted) backend.cancel();
    });
    signalTimer.start();
    return application.exec();
}
