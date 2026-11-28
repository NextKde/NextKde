#include "AppUpdateAgent.h"
#include "AppCatalog.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QLockFile>
#include <QSslConfiguration>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName("kos-app-update-agent");
    QDir().mkpath(AppCatalog::stateDirectory());
    const bool requested = app.arguments().contains("--check-now");
    if (requested && !AppCatalog::writeState("check-request", {{"timestamp", QDateTime::currentMSecsSinceEpoch()}})) return 1;
    QLockFile lock(AppCatalog::stateDirectory() + "/update-agent.lock");
    if (!lock.tryLock(0)) return requested ? 0 : 1;
#ifndef QT_NO_SSL
    // Initialize Qt's TLS backend and system CA cache on the main thread
    // before QtConcurrent workers issue HTTPS requests.
    (void)QSslConfiguration::defaultConfiguration();
#endif
    AppUpdateAgent agent;
    if (requested) agent.requestCheck();
    return app.exec();
}
