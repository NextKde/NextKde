#include "PowerSettings.h"
#include "../../../../platform/src/daemon/PowerProfilesBus.h"
#include "../../../../platform/tests/fake_power_profiles.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QTimer>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThread>
#undef NDEBUG
#include <cassert>

namespace {

QString startPrivateBus(QProcess *daemon)
{
    // Resolve the helper before PATH is reduced to an empty directory.
    const QString program = QStandardPaths::findExecutable(QStringLiteral("dbus-daemon"));
    assert(!program.isEmpty());
    daemon->setProgram(program);
    daemon->setArguments({QStringLiteral("--session"), QStringLiteral("--nofork"),
                          QStringLiteral("--nopidfile"), QStringLiteral("--print-address=1")});
    daemon->start();
    assert(daemon->waitForStarted(3000));
    assert(daemon->waitForReadyRead(3000));
    const QByteArray address = daemon->readAllStandardOutput().trimmed();
    assert(address.startsWith("unix:"));
    // PowerSettings binds systemBus() in its constructor. The address has to
    // be in place before that, and before the child claims the well-known name.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", address);
    return QString::fromUtf8(address);
}

QProcess *startService(const QProcessEnvironment &environment)
{
    auto *service = new QProcess;
    service->setProgram(QCoreApplication::applicationFilePath());
    service->setArguments({QStringLiteral("--serve"), QStringLiteral("freedesktop")});
    service->setProcessEnvironment(environment);
    service->start();
    assert(service->waitForStarted(3000));
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < 3000) {
        const KosPlatform::PowerProfileSnapshot snapshot =
            KosPlatform::readPowerProfiles(QDBusConnection::systemBus());
        if (snapshot.ok
            && snapshot.service == QLatin1String("org.freedesktop.UPower.PowerProfiles"))
            return service;
        if (service->state() != QProcess::Running)
            break;
        QThread::msleep(20);
    }
    qCritical() << "fake PowerProfiles service did not answer" << service->exitCode()
                << service->readAllStandardError() << service->readAllStandardOutput();
    assert(false);
    return service;
}

void stopService(QProcess *service)
{
    service->kill();
    service->waitForFinished(1000);
    delete service;
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < 2000
           && KosPlatform::readPowerProfiles(QDBusConnection::systemBus()).ok)
        QThread::msleep(20);
}

} // namespace

int main(int argc, char **argv)
{
    if (argc > 1 && QString::fromLocal8Bit(argv[1]) == QLatin1String("--serve")) {
        QCoreApplication serveApp(argc, argv);
        return FakePowerProfiles::serve(argc > 2 ? QString::fromLocal8Bit(argv[2])
                                                 : QStringLiteral("freedesktop"));
    }

    QCoreApplication app(argc, argv);
    QProcess daemon;
    const QString address = startPrivateBus(&daemon);

    QTemporaryDir empty;
    assert(empty.isValid());
    qputenv("PATH", empty.path().toUtf8());
    assert(!KosPlatform::powerProfilesCommandAvailable());

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("DBUS_SYSTEM_BUS_ADDRESS"), address);
    environment.insert(QStringLiteral("KOS_FAKE_DELAY"), QStringLiteral("80"));
    QProcess *service = startService(environment);
    int heartbeats = 0;
    QTimer heartbeat;
    heartbeat.setInterval(10);
    QObject::connect(&heartbeat, &QTimer::timeout, [&] { ++heartbeats; });
    heartbeat.start();

    PowerSettings settings;
    auto wait = [&] {
        QElapsedTimer timer;
        timer.start();
        while (settings.state().value(QStringLiteral("busy")).toBool() && timer.elapsed() < 5000) {
            app.processEvents();
            QThread::msleep(2);
        }
        assert(!settings.state().value(QStringLiteral("busy")).toBool());
    };
    QElapsedTimer returned;
    returned.start();
    settings.refresh();
    assert(returned.elapsed() < 150);
    assert(settings.state().value(QStringLiteral("busy")).toBool());
    wait();
    assert(heartbeats >= 5);
    // A present executable with a missing interpreter exercises FailedToStart.
    QFile helper(empty.filePath(QStringLiteral("powerprofilesctl")));
    assert(helper.open(QIODevice::WriteOnly));
    helper.write("#!/nonexistent/kos-test-interpreter\n");
    helper.close();
    helper.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    assert(KosPlatform::powerProfilesCommandAvailable());
    assert(settings.state().value(QStringLiteral("activeProfile")).toString()
           == QLatin1String("balanced"));
    assert(settings.state().value(QStringLiteral("profiles")).toStringList().size() == 3);
    assert(settings.state().value(QStringLiteral("degraded")).toString().isEmpty());
    assert(settings.state().value(QStringLiteral("error")).toString().isEmpty());

    heartbeats = 0;
    returned.restart();
    settings.setProfile(QStringLiteral("power-saver"));
    assert(returned.elapsed() < 150);
    wait();
    assert(heartbeats >= 5);
    assert(settings.state().value(QStringLiteral("activeProfile")).toString()
           == QLatin1String("power-saver"));
    assert(KosPlatform::readPowerProfiles(QDBusConnection::systemBus()).activeProfile
           == QLatin1String("power-saver"));

    stopService(service);
    environment.insert(QStringLiteral("KOS_FAKE_ACTIVE"), QStringLiteral("power-saver"));
    environment.insert(QStringLiteral("KOS_FAKE_REJECT"), QStringLiteral("performance"));
    service = startService(environment);
    settings.setProfile(QStringLiteral("performance"));
    wait();
    assert(settings.state().value(QStringLiteral("activeProfile")).toString()
           == QLatin1String("power-saver"));
    assert(settings.state().value(QStringLiteral("error")).toString()
               .contains(QStringLiteral("Could not change")));

    stopService(service);
    environment.remove(QStringLiteral("KOS_FAKE_REJECT"));
    environment.insert(QStringLiteral("KOS_FAKE_STICK"), QStringLiteral("1"));
    service = startService(environment);
    settings.setProfile(QStringLiteral("balanced"));
    wait();
    assert(settings.state().value(QStringLiteral("activeProfile")).toString()
           == QLatin1String("power-saver"));
    assert(settings.state().value(QStringLiteral("error")).toString()
               .contains(QStringLiteral("did not keep")));
    settings.setProfile(QStringLiteral("invalid"));
    assert(!settings.state().value(QStringLiteral("busy")).toBool());

    stopService(service);
    daemon.kill();
    daemon.waitForFinished(1000);
    qInfo("Power settings bus fallback: modes, confirmed writes, denial and rejection passed");
    return 0;
}
