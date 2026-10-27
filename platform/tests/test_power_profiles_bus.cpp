#include "../src/daemon/PowerProfilesBus.h"
#include "fake_power_profiles.h"

#include <QDBusConnection>
#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
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
    // Set before the first systemBus() call. The child owns the well-known
    // name; this process only calls it, so a missed address cannot Set the
    // host's tuned-ppd profile.
    qputenv("DBUS_SYSTEM_BUS_ADDRESS", address);
    return QString::fromUtf8(address);
}

QProcess *startService(const QString &which, const QProcessEnvironment &environment)
{
    auto *service = new QProcess;
    service->setProgram(QCoreApplication::applicationFilePath());
    service->setArguments({QStringLiteral("--serve"), which});
    service->setProcessEnvironment(environment);
    service->start();
    assert(service->waitForStarted(3000));
    const QString expected = which == QLatin1String("hadess")
        ? QStringLiteral("net.hadess.PowerProfiles")
        : QStringLiteral("org.freedesktop.UPower.PowerProfiles");
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < 3000) {
        const KosPlatform::PowerProfileSnapshot snapshot =
            KosPlatform::readPowerProfiles(QDBusConnection::systemBus());
        if (snapshot.ok && snapshot.service == expected)
            return service;
        if (service->state() != QProcess::Running)
            break;
        QThread::msleep(20);
    }
    qCritical() << "fake PowerProfiles service did not answer" << which
                << service->exitCode() << service->readAllStandardError()
                << service->readAllStandardOutput();
    assert(false);
    return service;
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

    QStringList decoded;
    const QVariantList rows{
        QVariantMap{{QStringLiteral("Profile"), QStringLiteral("performance")},
                    {QStringLiteral("Driver"), QStringLiteral("tuned")}},
        QVariantMap{{QStringLiteral("Profile"), QStringLiteral("custom")}},
        QVariantMap{{QStringLiteral("Profile"), QStringLiteral("balanced")}},
        QVariantMap{{QStringLiteral("Profile"), QStringLiteral("balanced")}},
    };
    assert(KosPlatform::decodePowerProfileList(rows, &decoded));
    assert(decoded == QStringList({QStringLiteral("performance"), QStringLiteral("balanced")}));
    assert(!KosPlatform::decodePowerProfileList(QStringLiteral("nope"), &decoded));
    assert(KosPlatform::normalizePowerDegradation(QStringLiteral("no")).isEmpty());
    assert(KosPlatform::normalizePowerDegradation(QStringLiteral("  ")).isEmpty());
    assert(KosPlatform::normalizePowerDegradation(QStringLiteral("high-operating-temperature"))
           == QLatin1String("high-operating-temperature"));

    const QByteArray savedPath = qgetenv("PATH");
    {
        QTemporaryDir empty;
        assert(empty.isValid());
        qputenv("PATH", empty.path().toUtf8());
        assert(!KosPlatform::powerProfilesCommandAvailable());
        QFile helper(empty.filePath(QStringLiteral("powerprofilesctl")));
        assert(helper.open(QIODevice::WriteOnly));
        helper.write("#!/bin/sh\n");
        helper.close();
        helper.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
        assert(KosPlatform::powerProfilesCommandAvailable());
    }
    qputenv("PATH", savedPath);

    QProcess daemon;
    const QString address = startPrivateBus(&daemon);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("DBUS_SYSTEM_BUS_ADDRESS"), address);
    environment.insert(QStringLiteral("KOS_FAKE_DEGRADED"), QStringLiteral("high-operating-temperature"));
    environment.insert(QStringLiteral("KOS_FAKE_REJECT"), QStringLiteral("performance"));
    QProcess *service = startService(QStringLiteral("freedesktop"), environment);
    const QDBusConnection bus = QDBusConnection::systemBus();
    const KosPlatform::PowerProfileSnapshot read = KosPlatform::readPowerProfiles(bus);
    assert(read.ok);
    assert(read.service == QLatin1String("org.freedesktop.UPower.PowerProfiles"));
    assert(read.activeProfile == QLatin1String("balanced"));
    assert(read.degraded == QLatin1String("high-operating-temperature"));
    assert(read.profiles == QStringList({QStringLiteral("power-saver"), QStringLiteral("balanced"),
                                        QStringLiteral("performance")}));
    assert(KosPlatform::writePowerProfile(bus, QStringLiteral("power-saver")));
    assert(KosPlatform::readPowerProfiles(bus).activeProfile == QLatin1String("power-saver"));
    assert(!KosPlatform::writePowerProfile(bus, QStringLiteral("performance")));
    assert(KosPlatform::readPowerProfiles(bus).activeProfile == QLatin1String("power-saver"));
    assert(!KosPlatform::writePowerProfile(bus, QStringLiteral("custom")));
    service->kill();
    service->waitForFinished(1000);
    delete service;

    environment.insert(QStringLiteral("KOS_FAKE_ACTIVE"), QStringLiteral("performance"));
    environment.insert(QStringLiteral("KOS_FAKE_DEGRADED"), QStringLiteral("no"));
    environment.remove(QStringLiteral("KOS_FAKE_REJECT"));
    QProcess *fallbackService = startService(QStringLiteral("hadess"), environment);
    const KosPlatform::PowerProfileSnapshot fallback = KosPlatform::readPowerProfiles(bus);
    assert(fallback.ok);
    assert(fallback.service == QLatin1String("net.hadess.PowerProfiles"));
    assert(fallback.activeProfile == QLatin1String("performance"));
    assert(fallback.degraded.isEmpty());
    fallbackService->kill();
    fallbackService->waitForFinished(1000);
    delete fallbackService;
    daemon.kill();
    daemon.waitForFinished(1000);
    qInfo("power profiles bus: decode, helper detection, read/set, rejection and hadess fallback passed");
    return 0;
}
