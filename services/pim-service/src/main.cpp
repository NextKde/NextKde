#include "PimStore.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("kos-pim-service"));
    application.setApplicationVersion(QStringLiteral(KOS_APP_VERSION));
    application.setOrganizationName(QStringLiteral("NextKde"));
    application.setOrganizationDomain(QStringLiteral("nextkde.org"));

    PimStore store;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QStringLiteral("/Pim"), &store,
                            QDBusConnection::ExportAllSlots
                                | QDBusConnection::ExportAllSignals)) {
        qCritical() << "Unable to export PIM object:" << bus.lastError().message();
        return 1;
    }
    if (!bus.registerService(QStringLiteral("org.nextkde.Kos.Pim1"))) {
        qCritical() << "Unable to own PIM service name:" << bus.lastError().message();
        return 1;
    }
    return application.exec();
}
