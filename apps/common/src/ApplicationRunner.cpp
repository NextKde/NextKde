#include "KosApp/ApplicationRunner.h"
#include "KosApp/ApplicationQmlReloader.h"
#include "ApplicationActivation.h"
#include "ApplicationPreferences.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>

#include <cstdlib>

#if defined(KOS_HAVE_KWINDOWSYSTEM)
#include <KWindowEffects>
#endif

namespace Kos::App {

int run(int argc, char *argv[], const Metadata &metadata)
{
    QGuiApplication application(argc, argv);
    application.setApplicationName(metadata.applicationName);
    application.setApplicationDisplayName(metadata.displayName);
    application.setApplicationVersion(metadata.version);
    application.setDesktopFileName(metadata.desktopFileName);
    application.setOrganizationName(QStringLiteral("NextKde"));
    application.setOrganizationDomain(QStringLiteral("github.com/SuceV587"));

    QCommandLineParser parser;
    parser.setApplicationDescription(metadata.displayName);
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption smokeTestOption(
        QStringLiteral("smoke-test"),
        QStringLiteral("Load the complete QML root, then exit automatically."));
    parser.addOption(smokeTestOption);
    QCommandLineOption screenshotOption(
        QStringLiteral("screenshot"),
        QStringLiteral("Render the application window to an image and exit."),
        QStringLiteral("path"));
    parser.addOption(screenshotOption);
    QCommandLineOption settingsOption(
        QStringLiteral("settings"),
        QStringLiteral("Open the application appearance settings."));
    parser.addOption(settingsOption);
    parser.addOption({QStringLiteral("view"), QStringLiteral("Open a named application view."),
                      QStringLiteral("view")});
    parser.addOption({QStringLiteral("date"), QStringLiteral("Open an ISO calendar date."),
                      QStringLiteral("date")});
    parser.addOption({QStringLiteral("item"), QStringLiteral("Open an item by identifier."),
                      QStringLiteral("id")});
    parser.addOption({QStringLiteral("location"), QStringLiteral("Open a weather location."),
                      QStringLiteral("id")});
    parser.addPositionalArgument(QStringLiteral("urls"),
                                 QStringLiteral("Files or URLs to open."),
                                 QStringLiteral("[urls...]") );
    QCommandLineOption watchOption(
        QStringLiteral("watch-qml"),
        QStringLiteral("Load the QML entry point from a source directory and "
                       "rebuild the window when it changes (development)."),
        QStringLiteral("path"));
    parser.addOption(watchOption);
    parser.process(application);

    // Development entry selection: --watch-qml (or KOS_APP_QML_DIR) runs the
    // QML from a source tree instead of the copy compiled into the binary and
    // rebuilds the window whenever that tree changes. The path may name the
    // directory holding Main.qml or the entry file itself.
    QString watchPath = parser.value(watchOption);
    if (watchPath.isEmpty())
        watchPath = qEnvironmentVariable("KOS_APP_QML_DIR");
    QString entryFile;
    if (!watchPath.isEmpty()) {
        entryFile = QFileInfo(watchPath).isDir()
            ? QDir(watchPath).filePath(QStringLiteral("Main.qml"))
            : watchPath;
        entryFile = QDir::cleanPath(QFileInfo(entryFile).absoluteFilePath());
        if (!QFileInfo::exists(entryFile)) {
            qCritical().noquote() << "QML entry point not found:" << entryFile;
            return EXIT_FAILURE;
        }
    }

    QStringList activationArguments = application.arguments().mid(1);
    activationArguments.removeAll(QStringLiteral("--smoke-test"));
    for (qsizetype index = activationArguments.size() - 1; index >= 0; --index) {
        if (activationArguments.at(index).startsWith(QStringLiteral("--screenshot="))) {
            activationArguments.removeAt(index);
        } else if (activationArguments.at(index) == QStringLiteral("--screenshot")) {
            activationArguments.removeAt(index);
            if (index < activationArguments.size())
                activationArguments.removeAt(index);
        }
    }
    ApplicationActivation activation(metadata.dbusServiceName);
    // A watch run is a development instance of the same application: it must
    // neither forward its arguments to nor displace the user's running copy.
    const bool isolatedTestRun = parser.isSet(smokeTestOption)
        || parser.isSet(screenshotOption)
        || !entryFile.isEmpty();
    if (!isolatedTestRun) {
        const auto activationResult = activation.acquireOrForward(
            activationArguments);
        if (activationResult == ApplicationActivation::AcquireResult::Forwarded)
            return EXIT_SUCCESS;
        if (activationResult == ApplicationActivation::AcquireResult::Error)
            return EXIT_FAILURE;
    }

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    // A transparent default framebuffer must be requested before the first
    // QQuickWindow is created. Glass can be enabled at runtime, so opting in
    // only for an initially translucent preference is too late on some
    // Wayland and X11 backends.
    QQuickWindow::setDefaultAlphaBuffer(true);

    ApplicationPreferences preferences;
#if defined(KOS_HAVE_KWINDOWSYSTEM)
    const auto refreshNativeCapabilities = [&preferences] {
        preferences.setNativeEffectsAvailable(
            KWindowEffects::isEffectAvailable(KWindowEffects::BlurBehind),
            KWindowEffects::isEffectAvailable(KWindowEffects::BackgroundContrast));
    };
    refreshNativeCapabilities();
    auto *effectsMonitor = new QTimer(&application);
    effectsMonitor->setInterval(2500);
    effectsMonitor->setTimerType(Qt::VeryCoarseTimer);
    QObject::connect(effectsMonitor, &QTimer::timeout, &application,
                     refreshNativeCapabilities);
    effectsMonitor->start();
#endif

    QQmlApplicationEngine engine;
    QVariantMap initialProperties;
    initialProperties.insert(
        QStringLiteral("applicationSettings"),
        QVariant::fromValue(static_cast<QObject *>(&preferences)));
    if (metadata.prepareEngine)
        metadata.prepareEngine(engine, initialProperties);
    QObject::connect(&engine, &QQmlEngine::warnings, &application,
                     [](const QList<QQmlError> &warnings) {
                         for (const QQmlError &warning : warnings)
                             qWarning().noquote() << warning.toString();
                     });
    // Startup aborts on a root that does not build; a hot reload must not --
    // the running window is worth more than a strict failure, and the next
    // change that compiles brings the new tree up.
    bool startupComplete = false;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &application,
        [&startupComplete](const QUrl &url) {
            qCritical() << "QML object creation failed for" << url;
            if (!startupComplete)
                QCoreApplication::exit(EXIT_FAILURE);
        },
        Qt::QueuedConnection);

    const auto loadRoot = [&engine, &initialProperties, &metadata, &entryFile] {
        // Initial properties are re-applied on every load: a rebuilt window
        // must receive the same controllers as the first one.
        engine.setInitialProperties(initialProperties);
        if (entryFile.isEmpty())
            engine.loadFromModule(metadata.qmlUri, QStringLiteral("Main"));
        else
            engine.load(QUrl::fromLocalFile(entryFile));
    };

    loadRoot();
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Unable to load the application QML root for"
                    << (entryFile.isEmpty() ? metadata.qmlUri : entryFile);
        return EXIT_FAILURE;
    }

    // Activation dispatches to whichever root exists at call time and is
    // connected with the application as context, so it keeps working across a
    // hot reload instead of ending with the window it was attached to.
    const auto dispatchActivation = [&engine](const QStringList &arguments,
                                              const QString &workingDirectory) {
        QObject *rootObject = engine.rootObjects().isEmpty()
            ? nullptr : engine.rootObjects().constFirst();
        if (!rootObject)
            return;
        if (arguments.contains(QStringLiteral("--settings"))) {
            if (QObject *settingsDialog = rootObject->findChild<QObject *>(
                    QStringLiteral("kosSettingsDialog"))) {
                QMetaObject::invokeMethod(settingsDialog, "open");
            }
        }
        const bool invoked = QMetaObject::invokeMethod(
            rootObject, "handleActivation",
            Q_ARG(QVariant, QVariant::fromValue(arguments)),
            Q_ARG(QVariant, QVariant::fromValue(workingDirectory)));
        if (!invoked)
            qWarning() << "Unable to dispatch activation to the QML root";
    };
    QObject::connect(&activation, &ApplicationActivation::activationRequested,
                     &application, dispatchActivation);

    // (Re)hooks the window after every load: a rebuilt window needs the same
    // native effects and activation target as the first one. The effects
    // connections are rooted at the window, so they end with it.
    const auto wireRoot = [&activation, &preferences](QObject *rootObject) {
        auto *window = qobject_cast<QQuickWindow *>(rootObject);
        if (!window)
            return;
        activation.setWindow(window);
#if defined(KOS_HAVE_KWINDOWSYSTEM)
        const auto applyWindowEffects = [window, &preferences] {
            const bool blur = preferences.glassActive()
                && preferences.nativeBlurAvailable();
            KWindowEffects::enableBlurBehind(window, blur);
            KWindowEffects::enableBackgroundContrast(
                window, blur && preferences.nativeContrastAvailable(),
                1.08, 1.0, 1.12);
        };
        QObject::connect(&preferences, &ApplicationPreferences::preferencesChanged,
                         window, applyWindowEffects);
        QObject::connect(&preferences, &ApplicationPreferences::capabilitiesChanged,
                         window, applyWindowEffects);
        QObject::connect(window, &QQuickWindow::visibleChanged, window,
                         [window, applyWindowEffects] {
                             if (window->isVisible())
                                 applyWindowEffects();
                         });
        QTimer::singleShot(0, window, applyWindowEffects);
#endif
    };

    QObject *rootObject = engine.rootObjects().constFirst();
    auto *window = qobject_cast<QQuickWindow *>(rootObject);
    wireRoot(rootObject);
    if (!entryFile.isEmpty())
        qInfo().noquote() << metadata.applicationName << ": loading QML from"
                          << entryFile << "(watch mode, reloads on change)";
    startupComplete = true;

    if (!activationArguments.isEmpty())
        QTimer::singleShot(0, rootObject,
                           [dispatchActivation, activationArguments] {
                               dispatchActivation(activationArguments,
                                                  QDir::currentPath());
                           });

    // Inert unless the QML came from a source tree, which is the only case
    // where there is something to watch.
    ApplicationQmlReloader reloader(
        &engine, QUrl::fromLocalFile(entryFile),
        entryFile.isEmpty()
            ? QStringList{}
            : QStringList{QFileInfo(entryFile).absolutePath()},
        [&engine, &loadRoot, &wireRoot, &startupComplete] {
            startupComplete = false;
            const QList<QObject *> roots = engine.rootObjects();
            for (QObject *root : roots)
                delete root;
            engine.clearComponentCache();
            loadRoot();
            if (engine.rootObjects().isEmpty())
                return false;
            wireRoot(engine.rootObjects().constFirst());
            startupComplete = true;
            return true;
        },
        metadata.applicationName);
    reloader.start();

    if (parser.isSet(screenshotOption)) {
        const QString screenshotPath = parser.value(screenshotOption);
        if (!window || screenshotPath.isEmpty()) {
            qCritical() << "A valid application window and screenshot path are required";
            return EXIT_FAILURE;
        }
        QTimer::singleShot(650, window, [window, screenshotPath] {
            const QImage image = window->grabWindow();
            if (image.isNull() || !image.save(screenshotPath)) {
                qCritical() << "Unable to save application screenshot to"
                            << screenshotPath;
                QCoreApplication::exit(EXIT_FAILURE);
                return;
            }
            QCoreApplication::quit();
        });
    } else if (parser.isSet(smokeTestOption)) {
        QTimer::singleShot(250, &application, &QCoreApplication::quit);
    }

    return application.exec();
}

} // namespace Kos::App
