#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QProcess>
#include <QProcessEnvironment>
#include <QTemporaryDir>
#include <QThread>
#include <functional>
#include <stdexcept>

static void require(bool ok, const char *message)
{
    if (!ok)
        throw std::runtime_error(message);
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

class FakeScreenSaver : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.ScreenSaver")
public:
    bool active = false;

    void setActive(bool value)
    {
        active = value;
        emit ActiveChanged(value);
    }

public slots:
    bool GetActive() const { return active; }

signals:
    void ActiveChanged(bool active);
};

static QJsonObject readMessage(QLocalSocket &socket, const char *step)
{
    require(until([&] { return socket.canReadLine(); }), step);
    return QJsonDocument::fromJson(socket.readLine()).object();
}

static QJsonObject request(QLocalSocket &socket, const QString &operation,
                           const QJsonObject &payload = {})
{
    static int id = 0;
    const QString requestId = QString::number(++id);
    socket.write(QJsonDocument(QJsonObject{
        {"version", 1},
        {"requestId", requestId},
        {"operation", operation},
        {"payload", payload}
    }).toJson(QJsonDocument::Compact) + '\n');
    socket.flush();
    return readMessage(socket, "timed out waiting for request reply");
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QProcess daemon;
    try {
        require(argc == 2, "expected daemon path");
        auto bus = QDBusConnection::sessionBus();
        FakeScreenSaver screenSaver;
        require(bus.registerService(QStringLiteral("org.freedesktop.ScreenSaver")),
                "screen saver service registration");
        require(bus.registerObject(QStringLiteral("/ScreenSaver"),
                                   QStringLiteral("org.freedesktop.ScreenSaver"),
                                   &screenSaver,
                                   QDBusConnection::ExportAllSlots
                                       | QDBusConnection::ExportAllSignals),
                "screen saver object registration");

        QTemporaryDir runtime(QStringLiteral("/tmp/kos-lock-XXXXXX"));
        require(runtime.isValid(), "temporary directory");
        const QString socketPath = runtime.path() + QStringLiteral("/platform.sock");
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("KOS_PLATFORM_SOCKET"), socketPath);
        environment.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("offscreen"));
        daemon.setProcessEnvironment(environment);
        daemon.setProcessChannelMode(QProcess::MergedChannels);
        daemon.start(QString::fromLocal8Bit(argv[1]), {QStringLiteral("daemon")});
        require(until([&] { return QFileInfo::exists(socketPath); }), "daemon did not start");

        // Connect without kwin.subscribe: session.lock-changed must still arrive.
        QLocalSocket client;
        client.connectToServer(socketPath);
        require(client.waitForConnected(), "socket connect");

        const QJsonObject initial = request(client, QStringLiteral("session.visibility"));
        require(initial.value(QStringLiteral("ok")).toBool(), "initial session.visibility failed");
        require(!initial.value(QStringLiteral("result")).toObject().value(QStringLiteral("locked")).toBool(),
                "expected unlocked initially");

        screenSaver.setActive(true);
        const QJsonObject lockEvent = readMessage(client, "timed out waiting for lock event");
        require(lockEvent.value(QStringLiteral("event")).toString() == QStringLiteral("session.lock-changed"),
                "expected session.lock-changed event on lock");
        require(lockEvent.value(QStringLiteral("payload")).toObject().value(QStringLiteral("locked")).toBool(),
                "expected locked=true payload");

        const QJsonObject lockedReply = request(client, QStringLiteral("session.visibility"));
        require(lockedReply.value(QStringLiteral("ok")).toBool(), "locked session.visibility failed");
        require(lockedReply.value(QStringLiteral("result")).toObject().value(QStringLiteral("locked")).toBool(),
                "expected locked=true from session.visibility");

        screenSaver.setActive(false);
        const QJsonObject unlockEvent = readMessage(client, "timed out waiting for unlock event");
        require(unlockEvent.value(QStringLiteral("event")).toString() == QStringLiteral("session.lock-changed"),
                "expected session.lock-changed event on unlock");
        require(!unlockEvent.value(QStringLiteral("payload")).toObject().value(QStringLiteral("locked")).toBool(),
                "expected locked=false payload");

        daemon.kill();
        daemon.waitForFinished();
    } catch (const std::exception &error) {
        qCritical("%s", error.what());
        daemon.kill();
        daemon.waitForFinished();
        qCritical().noquote() << daemon.readAll();
        return 1;
    }
    return 0;
}

#include "test_session_lock.moc"
