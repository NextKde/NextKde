#include "AppUpdateAgent.h"
#include "AppCatalog.h"
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QTemporaryDir>
#include <QtTest>

class UpdateNotifications final : public QDBusVirtualObject {
public:
    int requests = 0;
    bool reject = false;
    QString title;
    QString introspect(const QString&) const override { return {}; }
    bool handleMessage(const QDBusMessage& request, const QDBusConnection& connection) override {
        if (request.member() != "Notify") return false;
        ++requests;
        title = request.arguments().value(3).toString();
        if (reject) connection.send(request.createErrorReply("org.freedesktop.DBus.Error.Failed", "Fixture rejects delivery"));
        else connection.send(request.createReply(QVariantList{uint(requests)}));
        return true;
    }
};

class AppUpdateAgentTest final : public QObject {
    Q_OBJECT
    QTemporaryDir profile;
    UpdateNotifications notifications;
    const QString id = "org.nextks.calendar";
    void candidate(AppUpdateAgent& agent) {
        const QVariantMap installation{{"scope", "user"}, {"commit", QString(64, 'a')}};
        agent.m_client.m_states[id] = QVariantMap{{"known", true}, {"canDiscover", true},
            {"installations", QVariantList{installation}}, {"update", QVariantMap{
                {"available", true}, {"version", "1.1.0"}, {"commit", QString(64, 'b')},
                {"installation", installation}, {"catalogEntryDigest", AppCatalog::entryDigest(AppCatalog::find(id))}}}};
    }
private slots:
    void modeChangeClearsClientPlan() {
        AppUpdateAgent agent;
        candidate(agent);
        QVERIFY(!agent.m_client.state(id).contains("plan"));
        auto state = agent.m_client.m_states[id].toMap();
        state["plan"] = QVariantMap{{"planId", "fixture"},
            {"catalogEntryDigest", AppCatalog::entryDigest(AppCatalog::find(id))}};
        agent.m_client.m_states[id] = state;
        QCOMPARE(agent.m_client.state(id).value("plan").toMap().value("planId").toString(), QString("fixture"));
        QCOMPARE(AppCatalog::setTestMode(true), QString());
        QVERIFY(!agent.m_client.state(id).contains("plan"));
        QCOMPARE(AppCatalog::setTestMode(false), QString());
        QVERIFY(!agent.m_client.state(id).contains("plan"));
    }
    void testModePausesScheduledChecks() {
        QCOMPARE(AppCatalog::setTestMode(true), QString());
        QVERIFY(AppCatalog::writeState("check-request", {{"timestamp", 123}}));
        QCOMPARE(AppCatalog::setTestMode(false), QString());
        AppUpdateAgent agent;
        QCOMPARE(AppCatalog::setTestMode(true), QString());
        agent.m_nextCheck = 0;
        agent.tick();
        QVERIFY(!agent.m_running);
        QCOMPARE(AppCatalog::readState("check-request").value("timestamp").toInt(), 0);
        agent.requestCheck();
        QVERIFY(agent.m_running);
        QTRY_VERIFY_WITH_TIMEOUT(!agent.m_running, 15000);
        QVERIFY(!AppCatalog::readState("update-status").value("finishedAt").toString().isEmpty());
        QCOMPARE(AppCatalog::setTestMode(false), QString());
    }
    void initTestCase() {
        QVERIFY(profile.isValid());
        qputenv("XDG_CONFIG_HOME", profile.filePath("config").toUtf8());
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerService("org.freedesktop.Notifications"));
        QVERIFY(bus.registerVirtualObject("/org/freedesktop/Notifications", &notifications));
    }
    void init() {
        qputenv("XDG_STATE_HOME", profile.filePath(QString::fromLatin1(QTest::currentTestFunction())).toUtf8());
        notifications.requests = 0; notifications.reject = false;
    }
    void acknowledgementAndRestartDeduplicate() {
        {
            AppUpdateAgent agent;
            candidate(agent);
            agent.finish();
            QVERIFY(AppCatalog::readState("notified").isEmpty());
            QTRY_COMPARE(notifications.requests, 1);
            QTRY_VERIFY(!AppCatalog::readState("notified").value(id).toString().isEmpty());
            QVERIFY(!notifications.title.isEmpty());
            QVERIFY(!agent.m_client.m_process.isOpen());
        }
        AppUpdateAgent restarted;
        candidate(restarted);
        restarted.finish();
        QTest::qWait(100);
        QCOMPARE(notifications.requests, 1);
    }
    void disabledNotificationsDoNotConsumeCandidate() {
        QVERIFY(AppCatalog::writeState("preferences", {{"updateNotifications", false}}));
        AppUpdateAgent agent;
        candidate(agent);
        agent.finish();
        QTest::qWait(100);
        QCOMPARE(notifications.requests, 0);
        QVERIFY(AppCatalog::readState("notified").isEmpty());
        QVERIFY(AppCatalog::writeState("preferences", {{"updateNotifications", true}}));
        agent.finish();
        QTRY_VERIFY(!AppCatalog::readState("notified").isEmpty());
    }
    void failedDeliveryDoesNotSuppressRetry() {
        notifications.reject = true;
        AppUpdateAgent agent;
        candidate(agent);
        agent.finish();
        QTRY_COMPARE(notifications.requests, 1);
        QTest::qWait(100);
        QVERIFY(AppCatalog::readState("notified").isEmpty());
        notifications.reject = false;
        agent.finish();
        QTRY_VERIFY(!AppCatalog::readState("notified").isEmpty());
        QCOMPARE(notifications.requests, 2);
    }
    void staleCatalogResultCannotNotify() {
        AppUpdateAgent agent;
        candidate(agent);
        auto state = agent.m_client.m_states[id].toMap();
        auto update = state.value("update").toMap();
        update["catalogEntryDigest"] = "stale";
        state["update"] = update;
        agent.m_client.m_states[id] = state;
        agent.finish();
        QTest::qWait(100);
        QCOMPARE(notifications.requests, 0);
        QVERIFY(AppCatalog::readState("notified").isEmpty());
    }
};
QTEST_GUILESS_MAIN(AppUpdateAgentTest)
#include "update_agent.moc"
