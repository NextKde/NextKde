#include "AppStore.h"
#include "PluginStore.h"
#include "AboutCache.h"
#include "TaskNotifications.h"
#include "PowerSettings.h"
#include "FontSettings.h"
#include "CacheMaintenance.h"
#include "SettingsBridge.h"
#include "SettingsRuntime.h"
#include "WindowSettings.h"
#include "DesktopTypography.h"

#include <QDebug>
#include <QCryptographicHash>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QProcess>
#include <QLockFile>
#include <QDir>
#include <QStandardPaths>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QQuickWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <QtQml/qqmlextensionplugin.h>

Q_IMPORT_QML_PLUGIN(Kos_DemoPlugin)

int main(int argc, char* argv[])
{
    for (int i = 1; i < argc; ++i) {
        const QByteArray argument(argv[i]);
        if (argument == "--set-window-animation" && i + 2 < argc) {
            QCoreApplication application(argc, argv);
            WindowSettings settings;
            const bool accepted = settings.setAnimation(QString::fromLocal8Bit(argv[i + 1]),
                                                        QString::fromLocal8Bit(argv[i + 2]));
            if (!accepted) qWarning().noquote() << settings.error();
            return accepted ? 0 : 1;
        }
        if (argument == "--install-window-defaults" || argument == "--restore-window-defaults") {
            QCoreApplication application(argc, argv);
            WindowSettings settings;
            const bool accepted = argument == "--install-window-defaults"
                ? settings.installDefaults()
                : settings.restoreAnimationDefaults() && settings.setTakeover(false);
            if (!accepted)
                qWarning().noquote() << settings.error();
            return accepted ? 0 : 1;
        }
    }
    QQuickWindow::setDefaultAlphaBuffer(true);
    QGuiApplication application(argc, argv);
    Kos::App::applyDesktopTypography(application);
    // This session's single Settings process owns installation tasks and their
    // results. Closing a window hides it; relaunching activates the same owner.
    // Keep the event loop alive even when all windows are hidden.
    application.setQuitOnLastWindowClosed(false);
    // Keep this window out of the Shell's KWin rules. This must match the
    // installed desktop entry basename: kos-settings.desktop.
    application.setApplicationName(QStringLiteral("kos-settings"));
    application.setApplicationDisplayName(QStringLiteral(""));
    application.setDesktopFileName(QStringLiteral("kos-settings"));
    application.setOrganizationName(QStringLiteral("Quickshell"));

    QString requestedApp;
    for (const auto &argument : application.arguments()) {
        if (argument == QLatin1String("--app=calendar") || argument == QLatin1String("--app=weather")
            || argument == QLatin1String("--app=plugins"))
            requestedApp = argument.mid(6);
    }
    // Installed and development shells must never navigate each other's window.
    const QByteArray session = QCryptographicHash::hash(qgetenv("KOS_SHELL_DIR"), QCryptographicHash::Sha256).toHex().left(16);
    const QString navigationPath = QDir(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation))
        .filePath(QStringLiteral("kos-settings-navigation-") + QString::fromLatin1(session));
    QLockFile navigationLock(navigationPath + QStringLiteral(".lock"));
    QLocalServer navigation;
    const bool navigationOwner = navigationLock.tryLock(0);
    QString navigationRequest = requestedApp.isEmpty() ? QStringLiteral("show") : requestedApp;
    for (const auto& argument : application.arguments()) {
        if (requestedApp.isEmpty() && argument.startsWith(QLatin1String("--page="))) {
            bool ok = false;
            const int page = argument.mid(7).toInt(&ok);
            if (argument == QLatin1String("--page=fonts")) navigationRequest = QStringLiteral("page:14");
            else if (argument == QLatin1String("--page=about")) navigationRequest = QStringLiteral("page:15");
            else if (argument == QLatin1String("--page=windows")) navigationRequest = QStringLiteral("page:11");
            else if (argument == QLatin1String("--page=plugins")) navigationRequest = QStringLiteral("page:16");
            else if (ok && page >= 0 && page <= 16) navigationRequest = QStringLiteral("page:%1").arg(page);
        }
    }
    if (!navigationOwner) {
        QLocalSocket existing;
        existing.connectToServer(navigationPath);
        if (!existing.waitForConnected(1500)) {
            qWarning() << "Settings navigation is not ready; try again";
            return 1;
        }
        existing.write(navigationRequest.toUtf8() + '\n');
        if (!existing.waitForBytesWritten(1500) || !existing.waitForReadyRead(1500)
            || existing.readAll() != "ok\n") {
            qWarning() << "Settings navigation was not acknowledged";
            return 1;
        }
        return 0;
    }
    if (navigationOwner) {
        QLocalServer::removeServer(navigationPath);
        navigation.setSocketOptions(QLocalServer::UserAccessOption);
        if (!navigation.listen(navigationPath)) {
            qWarning() << "Unable to establish Settings navigation" << navigation.errorString();
            return 1;
        }
    }

    TaskNotifications taskNotifications;
    SettingsBridge bridge;
    WindowSettings windowSettings;
    PowerSettings powerSettings;
    AboutCache aboutCache;
    PluginStore pluginStore;
    QQmlApplicationEngine engine;
    FontSettings fontSettings(&engine);
    engine.rootContext()->setContextProperty(QStringLiteral("fontSettings"), &fontSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBridge"), &bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("taskNotifications"), &taskNotifications);
    engine.rootContext()->setContextProperty(QStringLiteral("windowSettings"), &windowSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("powerSettings"), &powerSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("aboutCache"), &aboutCache);
    engine.rootContext()->setContextProperty(QStringLiteral("pluginStore"), &pluginStore);

    const SettingsEntry entry
        = chooseSettingsEntry(bridge.isDevelopmentSession(), bridge.sessionShellDir());
    // Recorded before the engine loads anything, so the banner and the reloader
    // cannot disagree about which tree the window is running.
    bridge.setSourceTreeEntry(!entry.checkoutRoot.isEmpty());
    if (entry.qmlPath.isEmpty()) {
        qWarning() << "kos-settings: no QML entry point found; looked beside the binary"
                      " and in"
                   << QStringLiteral(SETTINGS_QML_DIR);
        return 1;
    }
    qInfo().noquote() << "kos-settings: loading QML from" << entry.qmlPath
                      << QStringLiteral("(%1%2)").arg(entry.source,
                             entry.checkoutRoot.isEmpty() ? QString()
                                                          : QStringLiteral(", reloads on change"));
    AppStore appStore;
    const bool smokeTest = application.arguments().contains(QStringLiteral("--smoke-test"))
        || application.arguments().contains(QStringLiteral("--smoke-test-windows"));
    if (!smokeTest) appStore.startUpdateAgent();
    engine.rootContext()->setContextProperty(QStringLiteral("appStore"), &appStore);
    const QUrl entrypoint = QUrl::fromLocalFile(entry.qmlPath);
    engine.load(entrypoint);
    if (engine.rootObjects().isEmpty())
        return 1;
    const auto acceptNavigation = [&] {
        while (navigation.hasPendingConnections()) {
            QLocalSocket *client = navigation.nextPendingConnection();
            client->setReadBufferSize(64);
            QObject::connect(client, &QLocalSocket::disconnected, client, &QObject::deleteLater);
            QTimer::singleShot(2000, client, [client] { client->disconnectFromServer(); });
            const auto receive = [client, &engine, &appStore] {
                if (!client->canReadLine()) return;
                const QByteArray app = client->readLine(64).trimmed();
                bool pageOk = false;
                const int page = app.startsWith("page:") ? app.mid(5).toInt(&pageOk) : -1;
                pageOk = pageOk && page >= 0 && page <= 16;
                if (app != "show" && app != "calendar" && app != "weather" && app != "plugins" && !pageOk) {
                    client->disconnectFromServer();
                    return;
                }
                if (engine.rootObjects().isEmpty()) {
                    client->disconnectFromServer();
                    return;
                }
                QObject *root = engine.rootObjects().constFirst();
                if (app == "calendar" || app == "weather") {
                    root->setProperty("requestedApp", QString::fromUtf8(app));
                    root->setProperty("currentPage", 9);
                    QMetaObject::invokeMethod(root, "revealRequestedApp");
                } else if (app == "plugins") {
                    root->setProperty("currentPage", 16);
                } else if (pageOk) {
                    root->setProperty("currentPage", page);
                } else if (appStore.hasActiveMutation()) {
                    root->setProperty("currentPage", 9);
                }
                if (auto *window = qobject_cast<QQuickWindow *>(root)) {
                    window->show();
                    window->raise();
                    window->requestActivate();
                }
                client->write("ok\n");
                client->disconnectFromServer();
            };
            QObject::connect(client, &QLocalSocket::readyRead, client, receive);
            receive();
        }
    };
    QObject::connect(&navigation, &QLocalServer::newConnection, &application, acceptNavigation);
    QTimer::singleShot(0, &application, acceptNavigation);
    // Generic page selector for probes and manual debugging: --page=N opens
    // contentByPage index N directly (integration status is 6). --page=windows
    // keeps its named form for the existing window-install test.
    for (const QString& argument : application.arguments()) {
        if (argument == QStringLiteral("--app=calendar") || argument == QStringLiteral("--app=weather")) {
            engine.rootObjects().constFirst()->setProperty("requestedApp", argument.mid(6));
            engine.rootObjects().constFirst()->setProperty("currentPage", 9);
        } else if (argument == QStringLiteral("--app=plugins") || argument == QStringLiteral("--page=plugins")) {
            engine.rootObjects().constFirst()->setProperty("currentPage", 16);
        } else if (argument == QStringLiteral("--page=about")) {
            engine.rootObjects().constFirst()->setProperty("currentPage", 15);
        } else if (argument == QStringLiteral("--page=fonts")) {
            engine.rootObjects().constFirst()->setProperty("currentPage", 14);
        } else if (argument == QStringLiteral("--page=windows")) {
            engine.rootObjects().constFirst()->setProperty("currentPage", 11);
        } else if (argument.startsWith(QStringLiteral("--page="))) {
            bool ok = false;
            const int page = argument.mid(7).toInt(&ok);
            if (ok && page >= 0 && page <= 16)
                engine.rootObjects().constFirst()->setProperty("currentPage", page);
        }
    }
    if (application.arguments().contains(QStringLiteral("--smoke-test-windows"))) {
        engine.rootObjects().constFirst()->setProperty("currentPage", 11);
        QTimer::singleShot(1000, &application, [&engine, &application]() {
            auto* loader = engine.rootObjects().constFirst()->findChild<QObject*>(
                QStringLiteral("windowPageLoader"));
            if (!loader || loader->property("status").toInt() != 1
                || !engine.rootObjects().constFirst()->findChild<QObject*>(
                    QStringLiteral("windowAppearancePage"))) {
                qWarning() << "Window settings page did not instantiate";
                application.exit(1);
                return;
            }
            application.quit();
        });
    }

    // Inert unless the QML came from a checkout, which is the only case where
    // there is something to watch.
    SettingsQmlReloader reloader(&engine, entrypoint, entry.checkoutRoot);
    reloader.start();

    // 缓存维护:启动时调度一次(线程池内执行,阈值内零开销)。以后新增缓存
    // 目录都从这里追加 schedule 调用。
    CacheMaintenance::schedule(WallpaperLibrary::thumbnailCacheDirectory(), 64 * 1024 * 1024, 500);

    // Capture this window only, for local visual review without desktop pixels.
    const QStringList arguments = application.arguments();
    const qsizetype screenshotIndex = arguments.indexOf(QStringLiteral("--screenshot"));
    if (screenshotIndex >= 0) {
        auto* window = qobject_cast<QQuickWindow*>(engine.rootObjects().constFirst());
        if (!window || screenshotIndex + 1 >= arguments.size()
            || arguments.at(screenshotIndex + 1).startsWith(QStringLiteral("--"))) {
            qWarning() << "--screenshot requires an output image path";
            return 1;
        }
        const QString path = arguments.at(screenshotIndex + 1);
        bool delayOk = false;
        const int delay = qEnvironmentVariableIntValue("KOS_SCREENSHOT_DELAY_MS", &delayOk);
        QTimer::singleShot(delayOk && delay > 0 ? delay : 1500, window, [window, path]() {
            const QImage image = window->grabWindow();
            if (image.isNull() || !image.save(path)) {
                qWarning() << "Unable to save settings screenshot to" << path;
                QCoreApplication::exit(1);
                return;
            }
            QCoreApplication::quit();
        });
    }

    // --smoke-test is the build-side check that the settings window loads:
    // run one event loop turn (as ApplicationRunner does for the apps) and
    // exit, so CI can prove main.qml instantiates without a display.
    if (screenshotIndex < 0 && application.arguments().contains(QStringLiteral("--smoke-test")))
        QTimer::singleShot(250, &application, &QCoreApplication::quit);
    return application.exec();
}
