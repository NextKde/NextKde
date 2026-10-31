#include "WindowSettings.h"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QEventLoop>
#include <QTemporaryDir>
#include <QTimer>
#include <QDebug>

#define CHECK(x) do { if (!(x)) qFatal("Line %d: %s", __LINE__, #x); } while (false)

class SlowKWin : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kde.kwin.Effects")
public:
    int delay = 120;
    QMap<QString, bool> loaded;
public slots:
    bool isEffectLoaded(const QString &name) {
        setDelayedReply(true);
        const auto bus = connection();
        const auto request = message();
        const bool value = loaded.value(name);
        QTimer::singleShot(delay, this, [bus, request, value] { bus.send(request.createReply(value)); });
        return false;
    }
    bool isEffectSupported(const QString &) { return true; }
    bool loadEffect(const QString &name) { loaded[name] = true; return true; }
    void unloadEffect(const QString &name) { loaded[name] = false; }
    void reconfigureEffect(const QString &) {}
};

int main(int argc, char **argv) {
    QTemporaryDir temporary;
    CHECK(temporary.isValid());
    qputenv("XDG_CONFIG_HOME", temporary.path().toUtf8());
    QCoreApplication app(argc, argv);
    SlowKWin kwin;
    auto bus = QDBusConnection::sessionBus();
    CHECK(bus.registerService("org.kde.KWin"));
    CHECK(bus.registerObject("/Effects", &kwin, QDBusConnection::ExportAllSlots));
    WindowSettings settings;
    int ticks = 0;
    QTimer heartbeat;
    heartbeat.setInterval(10);
    QObject::connect(&heartbeat, &QTimer::timeout, [&] { ++ticks; settings.state(); });
    heartbeat.start();
    for (int delay : {120, 1500}) {
        kwin.delay = delay;
        ticks = 0;
        QEventLoop loop;
        QObject::connect(&settings, &WindowSettings::changed, &loop, [&] {
            if (!settings.animationBusy()) loop.quit();
        });
        CHECK(settings.requestAnimation("hide", "genie"));
        CHECK(settings.animationBusy());
        CHECK(!settings.requestAnimation("hide", "scale"));
        QTimer::singleShot(8000, &loop, [&] { qFatal("Animation worker exceeded deadline"); });
        loop.exec();
        CHECK(ticks > 30);
        CHECK(settings.error().isEmpty());
        CHECK(settings.state()["hideAnimation"] == "genie");
        if (delay == 120) CHECK(settings.state()["nativeGenieFallback"].toString().isEmpty());
        else CHECK(!settings.state()["nativeGenieFallback"].toString().isEmpty());
    }
    qInfo("Slow KWin leaves settings event loop responsive");
}
#include "async.moc"
