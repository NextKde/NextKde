#include "../src/kwin/DesktopTransitionMonitor.h"

#include <QCoreApplication>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QElapsedTimer>
#include <QThread>
#include <QTimer>
#include <functional>
#include <stdexcept>

static void require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static void spin(int ms)
{
    QElapsedTimer elapsed;
    elapsed.start();
    while (elapsed.elapsed() < ms) {
        QCoreApplication::processEvents();
        QThread::msleep(1);
    }
}

static bool until(const std::function<bool()> &condition, int timeout = 1500)
{
    QElapsedTimer elapsed;
    elapsed.start();
    while (!condition() && elapsed.elapsed() < timeout)
        spin(2);
    return condition();
}

// Invoked only under dbus-run-session; never owns or queries the real KWin bus.
class FakeEffects final : public QDBusVirtualObject {
public:
    QStringList active{QStringLiteral("slide")};
    int requests = 0;
    int delayMs = 0;
    bool fail = false;
    bool hang = false;

    QString introspect(const QString &) const override { return {}; }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &bus) override
    {
        require(message.interface() == QStringLiteral("org.freedesktop.DBus.Properties")
            && message.member() == QStringLiteral("Get")
            && message.arguments() == QVariantList{QStringLiteral("org.kde.kwin.Effects"),
                                                   QStringLiteral("activeEffects")},
            "unexpected effects request");
        ++requests;
        if (hang)
            return true;
        const auto reply = fail
            ? message.createErrorReply(QStringLiteral("org.freedesktop.DBus.Error.Failed"),
                                       QStringLiteral("test failure"))
            : message.createReply(QVariant::fromValue(QDBusVariant(active)));
        QTimer::singleShot(delayMs, this, [bus, reply] { bus.send(reply); });
        return true;
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    auto bus = QDBusConnection::sessionBus();
    FakeEffects effects;
    require(bus.registerService(QStringLiteral("org.kde.KWin")), "fake service registration");
    require(bus.registerVirtualObject(QStringLiteral("/Effects"), &effects), "fake effects registration");
    KosPlatform::DesktopTransitionMonitor monitor(bus);
    QStringList settled;
    QObject::connect(&monitor, &KosPlatform::DesktopTransitionMonitor::settled,
                     [&](const QString &id) { settled.append(id); });

    require(!monitor.observeDesktop(QStringLiteral("desk1")), "initial snapshot animated");
    spin(100);
    require(effects.requests == 0, "idle monitor polled KWin");
    for (const auto &name : {QStringLiteral("slide"), QStringLiteral("cubeslide"),
                              QStringLiteral("fadedesktop")}) {
        effects.active = {name};
        const QString next = name;
        require(monitor.observeDesktop(next), "switch did not close the gate");
        const int before = effects.requests;
        spin(320); // Longer than Stage's entrance: no premature release.
        require(settled.isEmpty() && effects.requests > before, "released during desktop effect");
        effects.active = {QStringLiteral("glass"), QStringLiteral("stageanim13")};
        require(until([&] { return settled.size() == 1; }), "effect completion not observed");
        require(settled.takeFirst() == next, "wrong desktop released");
        const int finished = effects.requests;
        spin(100);
        require(effects.requests == finished, "monitor kept polling after completion");
    }

    // A delayed first activation must not be mistaken for disabled animations.
    effects.active.clear();
    monitor.observeDesktop(QStringLiteral("late"));
    spin(45);
    effects.active = {QStringLiteral("slide")};
    spin(120);
    require(settled.isEmpty(), "released before delayed activation");
    effects.active.clear();
    require(until([&] { return settled.size() == 1; }), "late effect did not settle");
    settled.clear();

    // A reply for an older desktop must not release a newer switch.
    effects.delayMs = 180;
    monitor.observeDesktop(QStringLiteral("old"));
    const int beforeOld = effects.requests;
    require(until([&] { return effects.requests > beforeOld; }), "old query not started");
    effects.active = {QStringLiteral("slide")};
    effects.delayMs = 0;
    monitor.observeDesktop(QStringLiteral("new"));
    spin(260);
    require(settled.isEmpty(), "stale reply released the newer desktop");
    effects.active.clear();
    require(until([&] { return settled.size() == 1; }), "new desktop did not settle");
    require(settled.takeFirst() == QStringLiteral("new"), "released stale desktop");

    monitor.observeDesktop(QStringLiteral("no-animation"));
    require(until([&] { return settled.size() == 1; }), "disabled animations never released");
    settled.clear();
    effects.fail = true;
    monitor.observeDesktop(QStringLiteral("error"));
    require(until([&] { return settled.size() == 1; }), "D-Bus error left gate closed");
    settled.clear();
    effects.fail = false;
    effects.hang = true;
    monitor.observeDesktop(QStringLiteral("hung"));
    require(until([&] { return settled.size() == 1; }), "hung reply was not bounded");
    settled.clear();
    effects.hang = false;

    effects.active = {QStringLiteral("slide")};
    monitor.observeDesktop(QStringLiteral("reset"));
    monitor.reset();
    require(settled.size() == 1 && settled.takeFirst() == QStringLiteral("reset"),
            "disconnect did not release pending entrance");
    require(!monitor.observeDesktop(QStringLiteral("reconnected")), "reconnection animated initial snapshot");

    monitor.observeDesktop(QStringLiteral("stuck-effect"));
    require(until([&] { return settled.size() == 1; }, 6000), "stuck effect exceeded deadline");
    require(settled.takeFirst() == QStringLiteral("stuck-effect"), "wrong deadline desktop");
    return 0;
}
