#include "FlatpakApps.h"
#include "FlatpakCompatibility.h"
#include "IndependentAppRegistry.h"

#include <QCoreApplication>
#include <QCommandLineParser>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <cstdio>
#include <csignal>
#include <unistd.h>

namespace {
volatile std::sig_atomic_t interrupted = 0;
void interrupt(int) { interrupted = 1; }
}

int main(int argc, char** argv)
{
    QCoreApplication application(argc, argv);
    if (argc == 2 && QByteArray(argv[1]) == "--flatpak-transaction-helper")
        return FlatpakTransactionProcess::helperMain();
    if (argc == 2 && QByteArray(argv[1]) == "--probe-flatpak-bundle-cleanup")
        return FlatpakCompatibility::probeBundleCleanup();
    QCoreApplication::setApplicationName("kos-apps");
    QCommandLineParser parser;
    parser.setApplicationDescription("Manage signed user Flatpaks and explicitly remove retired app refs. No automatic remote setup or personal-data deletion.");
    parser.addHelpOption();
    parser.addOption({"app", "Application key: calendar, calculator, weather, listenfree", "app"});
    parser.addOption({"yes", "Confirm an install, update, uninstall or retired-ref removal without a terminal prompt"});
    parser.addPositionalArgument("action", "status, check-update, install, update, uninstall or remove-retired");
    parser.process(application);
    const auto* entry = IndependentAppRegistry::find(parser.value("app"));
    const auto actions = parser.positionalArguments();
    const QStringList supported{"status", "check-update", "install", "update", "uninstall", "remove-retired"};
    if (!entry || actions.size() != 1 || !supported.contains(actions.first())) parser.showHelp(2);
    const auto action = actions.first();
    const QString appId = QString::fromLatin1(entry->appId);
    if (action == "install" && *entry->retiredId)
        std::fputs("Independent installation: old native/Flatpak data is not imported. Existing data for this ID is kept. See the compatibility guide; Calendar imports do not transfer all metadata, images or reminder permissions.\n", stderr);
    if (action == "remove-retired")
        std::fputs("Removes only the old program, not its data. No replacement is installed and reminders are not handed over. Keep the old installation until the replacement and its requirements are ready.\n", stderr);
    if ((action == "install" || action == "update" || action == "uninstall" || action == "remove-retired") && !parser.isSet("yes")) {
        if (!isatty(STDIN_FILENO)) {
            std::fputs("A package operation requires explicit confirmation: use --yes. Personal data is kept.\n", stderr);
            return 2;
        }
        std::fprintf(stderr, "%s %s (user Flatpak; personal data is kept)? [y/N] ", qPrintable(action), qPrintable(appId));
        char answer[16]{};
        if (!std::fgets(answer, sizeof answer, stdin) || (answer[0] != 'y' && answer[0] != 'Y')) return 130;
    }
    FlatpakApps backend;
    bool started = false, done = false, discovering = false;
    const auto finish = [&](const QString& code, const QString& message) {
        if (done) return;
        done = true;
        const QJsonObject result{{"schemaVersion", 1}, {"appId", appId}, {"action", action},
            {"code", code}, {"message", message}, {"success", code.isEmpty()},
            {"state", QJsonObject::fromVariantMap(backend.state(appId))}};
        std::puts(QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
        application.exit(code.isEmpty() ? 0 : code == "CANCELLED" ? 130 : 2);
    };
    QObject::connect(&backend, &FlatpakApps::operationFinished, &application,
        [&](const QString&, const QString& code, const QString& message) {
            if (!discovering || !code.isEmpty()) { finish(code, message); return; }
            discovering = false;
            if (interrupted) { finish("CANCELLED", "Cancelled before package mutation."); return; }
            const auto state = backend.state(appId);
            if (action == "update" && !state.value("update").toMap().value("available").toBool()) {
                finish({}, {}); return;
            }
            const bool accepted = action == "install" ? backend.install(appId) : backend.update(appId);
            if (!accepted) finish("FLATPAK_UNAVAILABLE", "No approved signed bundle or unambiguous user installation. Inspect state and resolve legacy/system/external-origin conflicts explicitly.");
        });
    QString lastProgress;
    QObject::connect(&backend, &FlatpakApps::changed, &application, [&] {
        const auto progress = backend.state(appId).value("progressState").toMap();
        const auto status = progress.value("status").toString();
        if (!status.isEmpty() && status != lastProgress) {
            lastProgress = status;
            std::fprintf(stderr, "%s\n", qPrintable(status));
        }
        if (started || done || backend.querying()) return;
        const auto state = backend.state(appId);
        started = true;
        if (interrupted) { finish("CANCELLED", "Cancelled before package mutation."); return; }
        if (!state.value("known").toBool()) { finish("RESULT_UNKNOWN", state.value("error").toString()); return; }
        if (action == "status") { finish({}, {}); return; }
        if (action == "remove-retired") {
            if (!backend.removeRetired(appId)) finish("RETIRED_REF_AMBIGUOUS", "Close old applications first. Only one exact user ref can be removed; system or ambiguous installations must be managed externally. Personal data is kept.");
            return;
        }
        if (!state.value("retiredInstallations").toList().isEmpty() && action != "uninstall") {
            finish("RETIRED_FLATPAK_ID", QStringLiteral("An older Flatpak identity (%1) is installed. Manage/uninstall that exact ref externally; no data migration or automatic removal was attempted.").arg(state.value("retiredAppId").toString())); return;
        }
        if (action == "uninstall" && state.value("installations").toList().isEmpty()) {
            finish("NOT_INSTALLED", "No matching Flatpak is installed; legacy files and user data were not touched."); return;
        }
        discovering = action == "install" || action == "update";
        const bool accepted = action == "uninstall" ? backend.uninstall(appId) : backend.checkUpdates(appId);
        if (!accepted) finish("FLATPAK_UNAVAILABLE", "No approved bundle-managed ref, or a legacy/system installation conflicts. No source-install fallback was attempted.");
    });
    std::signal(SIGINT, interrupt);
    std::signal(SIGTERM, interrupt);
    QTimer signalTimer;
    signalTimer.setInterval(100);
    QObject::connect(&signalTimer, &QTimer::timeout, &application, [&] { if (interrupted) backend.cancel(); });
    signalTimer.start();
    return application.exec();
}
