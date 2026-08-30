#include "KosApp/ApplicationRunner.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

#include <cstdlib>

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
    parser.process(application);

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &application,
        [] { QCoreApplication::exit(EXIT_FAILURE); },
        Qt::QueuedConnection);

    engine.loadFromModule(metadata.qmlUri, QStringLiteral("Main"));
    return application.exec();
}

} // namespace Kos::App
