#include "PimStore.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>
#include <QSocketNotifier>
#include <QTimer>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <sys/socket.h>
#include <unistd.h>

namespace {

// Async-signal-safe wake-up channel: the raw handler only writes one byte,
// and the event loop does the real shutdown work so destructors still run.
int signalSocketPair[2] = {-1, -1};

void forwardSignalToEventLoop(int)
{
    const char marker = 1;
    // The sockets are non-blocking, so a burst of signals can never block
    // inside the handler.
    ::write(signalSocketPair[1], &marker, sizeof(marker));
}

bool installSignalHandlers(QCoreApplication *application)
{
    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0, signalSocketPair) != 0) {
        qCritical() << "Unable to create signal socketpair:"
                    << std::strerror(errno);
        return false;
    }
    auto *notifier = new QSocketNotifier(signalSocketPair[0],
                                         QSocketNotifier::Read, application);
    QObject::connect(notifier, &QSocketNotifier::activated, application,
                     [application] {
                         char marker;
                         ::read(signalSocketPair[0], &marker, sizeof(marker));
                         // quit() unwinds exec() normally, which is what runs
                         // the store destructor and its final flush.
                         application->quit();
                     });

    struct sigaction action;
    std::memset(&action, 0, sizeof(action));
    action.sa_handler = forwardSignalToEventLoop;
    ::sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    // QCoreApplication does not intercept SIGTERM/SIGINT on Unix; without
    // these handlers `systemctl stop` or QProcess::terminate() would kill
    // the process inside the write-debounce window and drop the last
    // acknowledged mutations.
    if (::sigaction(SIGTERM, &action, nullptr) != 0
        || ::sigaction(SIGINT, &action, nullptr) != 0) {
        qCritical() << "Unable to install termination signal handlers:"
                    << std::strerror(errno);
        return false;
    }
    return true;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("kos-pim-service"));
    application.setApplicationVersion(QStringLiteral(KOS_APP_VERSION));
    application.setOrganizationName(QStringLiteral("NextKde"));
    application.setOrganizationDomain(QStringLiteral("nextkde.org"));

    if (!installSignalHandlers(&application))
        return 1;

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

    // D-Bus-activated services must not outlive the session bus. This can
    // otherwise leave a detached PIM process behind when a user logs out or a
    // private test session ends.
    QTimer connectionWatchdog;
    connectionWatchdog.setInterval(1000);
    QObject::connect(&connectionWatchdog, &QTimer::timeout, &application,
                     [&application, &bus] {
                         if (!bus.isConnected())
                             application.quit();
                     });
    connectionWatchdog.start();

    return application.exec();
}
