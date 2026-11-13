#include "LockScreenNotifications.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocalServer>
#include <QProcess>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <memory>

using KosPlatform::LockScreenNotifications;
namespace {
const auto service = QStringLiteral("org.kos.LockScreen");
const auto path = QStringLiteral("/org/kos/LockScreen");
const auto iface = QStringLiteral("org.kos.LockScreen1");
QJsonObject row(QString name = QStringLiteral("Mail"))
{
    return {{"id", "7"}, {"appName", name}, {"appIcon", "org.kde.kmail"},
            {"createdAt", 1700000000000.0}, {"summary", ""}, {"body", ""}};
}
QJsonObject payload(QJsonArray rows = QJsonArray{row()}) { return {{"notifications", rows}}; }
struct Peer {
    QTemporaryDir dir;
    QLocalServer server;
    QLocalSocket client;
    QLocalSocket *accepted = nullptr;
    Peer()
    {
        if (!server.listen(dir.filePath("test.sock"))) qFatal("isolated socket listen failed");
        client.connectToServer(server.fullServerName());
        if (!client.waitForConnected(1000)) qFatal("isolated socket connect failed");
        if (!server.hasPendingConnections() && !server.waitForNewConnection(1000))
            qFatal("isolated socket accept failed");
        accepted = server.nextPendingConnection();
    }
};
}

class BridgeTest : public QObject {
    Q_OBJECT
    std::unique_ptr<LockScreenNotifications> bridge;
    std::unique_ptr<Peer> peer;
    std::unique_ptr<QDBusConnection> reader;
    QDBusMessage call(const QString &interface, const QString &method, const QVariantList &args = {})
    {
        auto message = QDBusMessage::createMethodCall(service, path, interface, method);
        message.setArguments(args);
        QDBusPendingCallWatcher pending(reader->asyncCall(message, 2000));
        QElapsedTimer timer;
        timer.start();
        while (!pending.isFinished() && timer.elapsed() < 3000) QTest::qWait(2);
        return pending.reply();
    }
    QString readJson()
    {
        const auto reply = call(iface, "GetNotifications");
        return reply.type() == QDBusMessage::ReplyMessage ? reply.arguments().value(0).toString() : QString();
    }
    void noNotificationOwner()
    {
        const auto reply = reader->interface()->isServiceRegistered("org.freedesktop.Notifications");
        QVERIFY(reply.isValid());
        QVERIFY(!reply.value());
    }
private slots:
    void initTestCase()
    {
        // Refuse to perform test registrations on the user's real session bus.
        QVERIFY2(qEnvironmentVariable("KOS_LOCKSCREEN_TEST_BUS") == "1",
                 "Run via ctest (dbus-run-session), never on the real notification bus");
        reader = std::make_unique<QDBusConnection>(QDBusConnection::connectToBus(
            QDBusConnection::SessionBus, "lockscreen-isolated-reader"));
        QVERIFY(reader->isConnected());
        noNotificationOwner();
    }
    void init()
    {
        peer = std::make_unique<Peer>();
        bridge = std::make_unique<LockScreenNotifications>();
    }
    void cleanup()
    {
        bridge.reset();
        peer.reset();
        noNotificationOwner();
    }
    void propertySignal(const QString &interface, const QVariantMap &changed, const QStringList &)
    {
        if (interface == iface) emit observed(changed.value("NotificationsJson").toString());
    }
    void readOnlyContract()
    {
        QVERIFY(!reader->interface()->isServiceRegistered(service).value());
        QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        QCOMPARE(readJson(), bridge->notificationsJson());
        auto reply = call("org.freedesktop.DBus.Properties", "Get", {iface, "NotificationsJson"});
        QCOMPARE(reply.type(), QDBusMessage::ReplyMessage);
        QCOMPARE(qvariant_cast<QDBusVariant>(reply.arguments().at(0)).variant().toString(), readJson());
        reply = call("org.freedesktop.DBus.Introspectable", "Introspect");
        const auto xml = reply.arguments().value(0).toString();
        QVERIFY(xml.contains("name=\"NotificationsJson\" type=\"s\" access=\"read\""));
        QVERIFY(xml.contains("name=\"GetNotifications\""));
        QVERIFY(!xml.contains("name=\"publish\""));
        QVERIFY(!xml.contains("name=\"objectName\""));
        reply = call("org.freedesktop.DBus.Properties", "Set", {iface, "NotificationsJson",
            QVariant::fromValue(QDBusVariant(QStringLiteral("[]")))});
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        reply = call(iface, "Dismiss", {"7"});
        QCOMPARE(reply.type(), QDBusMessage::ErrorMessage);
        QCOMPARE(readJson(), bridge->notificationsJson());
    }
    void rejectsPrivateAndUnboundedData()
    {
        QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        const auto original = readJson();
        QList<QJsonObject> bad;
        for (const auto &key : {"summary", "body"}) {
            auto n = row(); n[key] = "PRIVATE"; bad << payload({n});
        }
        for (const auto &icon : {"/tmp/icon.png", "https://example.invalid/icon", "image://foo/bar", "../icon"}) {
            auto n = row(); n["appIcon"] = icon; bad << payload({n});
        }
        auto n = row(); n["actions"] = QJsonArray{"open"}; bad << payload({n});
        n = row(); n["appName"] = QString(257, 'a'); bad << payload({n});
        n = row(); n["appName"] = "a\nb"; bad << payload({n});
        n = row(); n["id"] = ""; bad << payload({n});
        n = row(); n["createdAt"] = "1700000000000"; bad << payload({n});
        for (const double time : {-1.0, 1.5, 9007199254740992.0}) {
            n = row(); n["createdAt"] = time; bad << payload({n});
        }
        n = row(); n.remove("body"); bad << payload({n});
        bad << payload({row(), row()}) << payload({row(), row(), row(), row(), row()});
        bad << QJsonObject{{"notifications", QJsonArray{}}, {"extra", true}};
        bad << QJsonObject{{"notifications", "[]"}} << QJsonObject{};
        for (const auto &invalid : bad) {
            QCOMPARE(bridge->publish(peer->accepted, invalid), "invalid-lockscreen-notifications");
            QCOMPARE(readJson(), original);
        }
        QLocalSocket disconnected;
        QCOMPARE(bridge->publish(&disconnected, payload()), "lockscreen-publisher-denied");
        QCOMPARE(bridge->publish(nullptr, payload()), "lockscreen-publisher-denied");
    }
    void updatesDisconnectAndRestart()
    {
        QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        QVERIFY(reader->connect(service, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                this, SLOT(propertySignal(QString,QVariantMap,QStringList))));
        QSignalSpy changes(this, &BridgeTest::observed);
        QCOMPARE(readJson(), bridge->notificationsJson()); // flush reader's subscription
        QVERIFY(bridge->publish(peer->accepted, payload({row("Updated")})).isEmpty());
        QTRY_COMPARE(changes.count(), 1);
        QVERIFY(readJson().contains("Updated"));
        Peer other;
        QCOMPARE(bridge->publish(other.accepted, payload()), "lockscreen-publisher-busy");
        other.client.disconnectFromServer();
        QTest::qWait(20);
        QVERIFY(readJson().contains("Updated")); // non-publisher disconnect cannot clear
        peer->client.disconnectFromServer();
        QTRY_COMPARE(bridge->notificationsJson(), "[]");
        QTRY_COMPARE(changes.count(), 2);
        QCOMPARE(readJson(), "[]");
        reader->disconnect(service, path, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                           this, SLOT(propertySignal(QString,QVariantMap,QStringList)));
        bridge.reset();
        QVERIFY(!reader->interface()->isServiceRegistered(service).value());
        bridge = std::make_unique<LockScreenNotifications>();
        peer = std::make_unique<Peer>();
        QCOMPARE(bridge->notificationsJson(), "[]");
        QVERIFY(bridge->publish(peer->accepted, payload({})).isEmpty());
        QCOMPARE(readJson(), "[]");
    }
    void expiration()
    {
        QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        // Exercise the real production TTL, not a test-only shortened timer.
        QTRY_COMPARE_WITH_TIMEOUT(bridge->notificationsJson(), "[]", LockScreenNotifications::leaseMs + 3000);
        QCOMPARE(readJson(), "[]");
        Peer next;
        QVERIFY(bridge->publish(next.accepted, payload({row("New lease")})).isEmpty());
        QVERIFY(readJson().contains("New lease"));
    }
    void registrationFailureIsNonfatal()
    {
        auto owner = QDBusConnection::connectToBus(QDBusConnection::SessionBus, "lockscreen-existing-owner");
        QVERIFY(owner.registerService(service));
        QCOMPARE(bridge->publish(peer->accepted, payload()), "lockscreen-bridge-unavailable");
        QCOMPARE(bridge->notificationsJson(), "[]");
        QVERIFY(owner.interface()->isServiceRegistered(service).value());
        QVERIFY(owner.unregisterService(service));
        QDBusConnection::disconnectFromBus("lockscreen-existing-owner");
        QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        QVERIFY(readJson().contains("Mail"));
    }
    void kdeQmlConsumer_data()
    {
        QTest::addColumn<bool>("publishBeforeConsumer");
        QTest::newRow("existing-owner") << true;
        QTest::newRow("late-owner") << false;
    }
    void kdeQmlConsumer()
    {
        QFETCH(bool, publishBeforeConsumer);
        const auto qs = QStandardPaths::findExecutable("quickshell");
        if (qs.isEmpty()) QSKIP("Quickshell is unavailable");
        if (publishBeforeConsumer) QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        QTemporaryDir home;
        QVERIFY(home.isValid());
        // Quickshell's scanner rejects local imports outside its config root.
        // Copy the shipped components unchanged into the isolated fixture root.
        QVERIFY(QDir().mkpath(home.filePath("lockscreen")));
        for (const auto &file : {"LockNotifications.qml", "LockGlass.qml", "liquidglass.frag.qsb"}) {
            QVERIFY(QFile::copy(QStringLiteral(LOCKSCREEN_TEST_DIR "/../../apps/lockscreen/contents/lockscreen/")
                                    + QLatin1String(file), home.filePath("lockscreen/" + QString::fromLatin1(file))));
        }
        QVERIFY(QFile::copy(QStringLiteral(LOCKSCREEN_TEST_DIR "/consumer.qml"), home.filePath("shell.qml")));
        QProcess consumer;
        const auto stopConsumer = qScopeGuard([&] {
            if (consumer.state() == QProcess::NotRunning) return;
            consumer.terminate();
            if (!consumer.waitForFinished(2000)) { consumer.kill(); consumer.waitForFinished(2000); }
        });
        auto environment = QProcessEnvironment::systemEnvironment();
        environment.insert("XDG_CACHE_HOME", home.filePath("cache"));
        environment.insert("XDG_CONFIG_HOME", home.filePath("config"));
        environment.insert("XDG_STATE_HOME", home.filePath("state"));
        environment.insert("XDG_RUNTIME_DIR", home.path());
        consumer.setProcessEnvironment(environment);
        consumer.setProcessChannelMode(QProcess::MergedChannels);
        consumer.start(qs, {"-p", home.path()});
        QVERIFY(consumer.waitForStarted(2000));
        QByteArray output, pending;
        QJsonObject latest;
        auto hasState = [&](const QJsonArray &expected) {
            const auto chunk = consumer.readAll();
            output += chunk;
            pending += chunk;
            qsizetype newline;
            while ((newline = pending.indexOf('\n')) >= 0) {
                const auto line = pending.left(newline);
                pending.remove(0, newline + 1);
                const QByteArray marker("LOCKSCREEN_UI_STATE ");
                const auto offset = line.indexOf(marker);
                if (offset >= 0) {
                    const auto document = QJsonDocument::fromJson(line.mid(offset + marker.size()));
                    if (document.isObject()) latest = document.object();
                }
            }
            QJsonArray appNames;
            for (const auto &item : expected) appNames.append(item.toObject().value("appName"));
            // Assert the latest production model AND actual delegate labels, not
            // a stale substring anywhere in the process's historical output.
            return latest.value("notifications") == QJsonValue(expected)
                && latest.value("appNames") == QJsonValue(appNames);
        };
        if (!publishBeforeConsumer) {
            QTRY_VERIFY2_WITH_TIMEOUT(hasState({}), output.constData(), 5000);
            QVERIFY(bridge->publish(peer->accepted, payload()).isEmpty());
        }
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({row()}), output.constData(), 5000);
        QJsonArray replacement;
        for (int index = 0; index < 4; ++index) {
            auto item = row(QStringLiteral("QML-replacement-%1").arg(index));
            item["id"] = QString::number(index);
            replacement.append(item);
        }
        QVERIFY(bridge->publish(peer->accepted, payload(replacement)).isEmpty());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState(replacement), output.constData(), 3000);
        QVERIFY(bridge->publish(peer->accepted, payload({})).isEmpty());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({}), output.constData(), 3000);

        QVERIFY(bridge->publish(peer->accepted, payload({row("QML-disconnect")})).isEmpty());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({row("QML-disconnect")}), output.constData(), 3000);
        peer->client.disconnectFromServer();
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({}), output.constData(), 3000);
        peer = std::make_unique<Peer>();
        QVERIFY(bridge->publish(peer->accepted, payload({row("QML-owner-loss")})).isEmpty());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({row("QML-owner-loss")}), output.constData(), 3000);
        bridge.reset(); // No empty PropertiesChanged: the UI must watch owner loss.
        QVERIFY(!reader->interface()->isServiceRegistered(service).value());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({}), output.constData(), 3000);
        bridge = std::make_unique<LockScreenNotifications>();
        QVERIFY(bridge->publish(peer->accepted, payload({row("QML-restarted")})).isEmpty());
        QTRY_VERIFY2_WITH_TIMEOUT(hasState({row("QML-restarted")}), output.constData(), 3000);
        consumer.terminate();
        QVERIFY(consumer.waitForFinished(2000));
        output += consumer.readAll();
        QVERIFY2(!output.contains("TypeError") && !output.contains("ReferenceError")
                 && !output.contains("Failed to load") && !output.contains("Unable to assign"), output.constData());
    }
signals:
    void observed(const QString &json);
};

QTEST_GUILESS_MAIN(BridgeTest)
#include "test_bridge.moc"
