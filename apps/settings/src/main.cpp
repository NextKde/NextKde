#include "AppStore.h"
#include "PowerSettings.h"
#include "CacheMaintenance.h"
#include "SettingsBridge.h"
#include "SettingsRuntime.h"
#include "WindowSettings.h"
#include "../../common/include/KosApp/DesktopTypography.h"

#include <QDebug>
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
    // Keep this window out of the Shell's KWin rules. This must match the
    // installed desktop entry basename: kos-settings.desktop.
    application.setApplicationName(QStringLiteral("kos-settings"));
    application.setApplicationDisplayName(QStringLiteral(""));
    application.setDesktopFileName(QStringLiteral("kos-settings"));
    application.setOrganizationName(QStringLiteral("Quickshell"));

    SettingsBridge bridge;
    WindowSettings windowSettings;
    PowerSettings powerSettings;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBridge"), &bridge);
    engine.rootContext()->setContextProperty(QStringLiteral("windowSettings"), &windowSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("powerSettings"), &powerSettings);

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
    AppStore appStore(QFileInfo(entry.qmlPath).absolutePath());
    engine.rootContext()->setContextProperty(QStringLiteral("appStore"), &appStore);
    const QUrl entrypoint = QUrl::fromLocalFile(entry.qmlPath);
    engine.load(entrypoint);
    if (engine.rootObjects().isEmpty())
        return 1;
    // Generic page selector for probes and manual debugging: --page=N opens
    // contentByPage index N directly (integration status is 6). --page=windows
    // keeps its named form for the existing window-install test.
    for (const QString& argument : application.arguments()) {
        if (argument == QStringLiteral("--page=windows")) {
            engine.rootObjects().constFirst()->setProperty("currentPage", 11);
        } else if (argument.startsWith(QStringLiteral("--page="))) {
            bool ok = false;
            const int page = argument.mid(7).toInt(&ok);
            if (ok)
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
