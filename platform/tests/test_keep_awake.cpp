#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusServiceWatcher>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSet>
#include <QTemporaryDir>
#include <QThread>
#include <functional>
#include <stdexcept>

static void require(bool ok, const char *message)
{
    if (!ok) throw std::runtime_error(message);
}

static bool until(const std::function<bool()> &condition)
{
    QElapsedTimer timer;
    timer.start();
    while (!condition() && timer.elapsed() < 6000) {
        QCoreApplication::processEvents();
        QThread::msleep(2);
    }
    return condition();
}

// Mimics KDE's cookies and caller-disconnection cleanup on a private bus.
class FakeInhibitor : public QObject, protected QDBusContext {
    Q_OBJECT
public:
    FakeInhibitor() : watcher(this)
    {
        watcher.setConnection(QDBusConnection::sessionBus());
        watcher.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
        connect(&watcher, &QDBusServiceWatcher::serviceUnregistered, this,
            [this](const QString &owner) {
                for (auto it = cookies.begin(); it != cookies.end();) {
                    if (it.value() == owner) it = cookies.erase(it);
                    else ++it;
                }
            });
    }
    QHash<uint, QString> cookies;
    QDBusServiceWatcher watcher;
    bool fail = false;
    bool delay = false;
    QDBusMessage delayed;
    uint sequence = 0;
public slots:
    uint Inhibit(const QString &app, const QString &reason)
    {
        require(app == QStringLiteral("NextKde") && !reason.isEmpty(), "missing inhibition identity");
        if (fail) {
            sendErrorReply(QStringLiteral("org.freedesktop.DBus.Error.Failed"), QStringLiteral("test failure"));
            return 0;
        }
        const uint cookie = ++sequence;
        cookies.insert(cookie, message().service());
        watcher.addWatchedService(message().service());
        if (delay) {
            setDelayedReply(true);
            delayed = message();
        }
        return cookie;
    }
    void UnInhibit(uint cookie) { cookies.remove(cookie); }
};

static QJsonObject request(QLocalSocket &socket, const QString &operation,
                           const QJsonObject &payload = {})
{
    static int id = 0;
    socket.write(QJsonDocument(QJsonObject{{"version", 1}, {"requestId", QString::number(++id)},
        {"operation", operation}, {"payload", payload}}).toJson(QJsonDocument::Compact) + '\n');
    socket.flush();
    require(until([&] { return socket.canReadLine(); }), "request timed out");
    return QJsonDocument::fromJson(socket.readLine()).object();
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QProcess daemon;
    try {
        require(argc == 2, "expected daemon path");
        auto bus = QDBusConnection::sessionBus();
        FakeInhibitor power, screen;
        require(bus.registerService("org.freedesktop.PowerManagement"), "power service registration");
        require(bus.registerService("org.freedesktop.ScreenSaver"), "screen service registration");
        require(bus.registerObject("/org/freedesktop/PowerManagement/Inhibit",
            "org.freedesktop.PowerManagement.Inhibit", &power, QDBusConnection::ExportAllSlots), "power object registration");
        require(bus.registerObject("/ScreenSaver", "org.freedesktop.ScreenSaver", &screen,
            QDBusConnection::ExportAllSlots), "screen object registration");
        QTemporaryDir runtime("/tmp/kos-awake-XXXXXX");
        require(runtime.isValid(), "temporary directory");
        const QString socketPath = runtime.path() + "/platform.sock";
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert("KOS_PLATFORM_SOCKET", socketPath);
        environment.insert("QT_QPA_PLATFORM", "offscreen");
        daemon.setProcessEnvironment(environment);
        daemon.setProcessChannelMode(QProcess::MergedChannels);
        daemon.start(QString::fromLocal8Bit(argv[1]), {"daemon"});
        require(until([&] { return QFileInfo::exists(socketPath); }), "daemon did not start");
        QLocalSocket client, other;
        client.connectToServer(socketPath);
        other.connectToServer(socketPath);
        require(client.waitForConnected() && other.waitForConnected(), "socket connect");
        auto enable = [&] { return request(client, "keepawake.set", {{"enabled", true}}); };
        auto off = [&] { return request(client, "keepawake.set", {{"enabled", false}}); };
        auto empty = [&] { return power.cookies.isEmpty() && screen.cookies.isEmpty(); };
        require(!request(client, "keepawake.set", {{"enabled", "yes"}}).value("ok").toBool(), "invalid payload accepted");
        require(enable().value("ok").toBool(), "enable failed");
        require(power.cookies.size() == 1 && screen.cookies.size() == 1, "missing inhibitors");
        require(enable().value("ok").toBool() && power.cookies.size() == 1, "enable must be idempotent");
        require(!request(other, "keepawake.get").value("result").toObject().value("enabled").toBool(), "state leaked to other client");
        require(off().value("ok").toBool() && until(empty), "disable leaked inhibitors");
        screen.fail = true;
        require(!enable().value("ok").toBool() && until(empty), "partial failure did not roll back");
        screen.fail = false;
        require(enable().value("ok").toBool(), "second enable");
        require(request(other, "keepawake.set", {{"enabled", true}}).value("ok").toBool(), "other client enable");
        require(power.cookies.size() == 2, "leases must be independent");
        client.abort();
        require(until([&] { return power.cookies.size() == 1 && screen.cookies.size() == 1; }), "disconnect failed to release own lease");
        require(request(other, "keepawake.set", {{"enabled", false}}).value("ok").toBool() && until(empty), "other lease release");
        client.connectToServer(socketPath);
        require(client.waitForConnected(), "reconnect");
        require(!request(client, "keepawake.get").value("result").toObject().value("enabled").toBool(), "reconnect should default off");
        power.delay = true;
        client.write("{\"version\":1,\"requestId\":\"pending\",\"operation\":\"keepawake.set\",\"payload\":{\"enabled\":true}}\n");
        client.flush();
        require(until([&] { return !power.cookies.isEmpty(); }), "pending inhibitor not acquired");
        auto busy = request(client, "keepawake.set", {{"enabled", true}});
        require(busy.value("error").toObject().value("code") == "busy", "concurrent enable not guarded");
        client.abort();
        require(until(empty), "disconnect during acquisition leaked inhibitor");
        bus.send(power.delayed.createReply(QVariant::fromValue(power.sequence)));
        power.delay = false;
        client.connectToServer(socketPath);
        require(client.waitForConnected(), "reconnect after pending");
        require(enable().value("ok").toBool(), "enable before restart");
        bus.unregisterService("org.freedesktop.ScreenSaver");
        screen.cookies.clear(); // The restarted service loses its old cookies.
        require(until([&] { return power.cookies.isEmpty(); }), "service loss leaked power inhibitor");
        auto state = request(client, "keepawake.get").value("result").toObject();
        require(!state.value("enabled").toBool() && !state.value("available").toBool(), "service loss left stale state");
        require(bus.registerService("org.freedesktop.ScreenSaver"), "screen restart");
        require(enable().value("ok").toBool(), "enable after restart");
        daemon.kill();
        require(daemon.waitForFinished() && until(empty), "daemon crash leaked inhibitors");
        qInfo("Keep-awake lifecycle tests passed");
    } catch (const std::exception &error) {
        qCritical("%s", error.what());
        daemon.kill();
        daemon.waitForFinished();
        qCritical().noquote() << daemon.readAll();
        return 1;
    }
    return 0;
}

#include "test_keep_awake.moc"
