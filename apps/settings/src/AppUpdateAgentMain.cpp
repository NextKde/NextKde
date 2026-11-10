#include "AppUpdateAgent.h"
#include "AppCatalog.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QLockFile>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName("kos-app-update-agent");
    QDir().mkpath(AppCatalog::stateDirectory());
    const bool requested = app.arguments().contains("--check-now");
    if (requested && !AppCatalog::writeState("check-request", {{"timestamp", QDateTime::currentMSecsSinceEpoch()}})) return 1;
    QLockFile lock(AppCatalog::stateDirectory() + "/update-agent.lock");
    if (!lock.tryLock(0)) return requested ? 0 : 1;
    AppUpdateAgent agent;
    if (requested) agent.requestCheck();
    return app.exec();
}
