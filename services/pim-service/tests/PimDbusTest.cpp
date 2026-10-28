#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

namespace {

constexpr auto serviceName = "org.nextkde.Kos.Pim1";
constexpr auto objectPath = "/Pim";
constexpr auto interfaceName = "org.nextkde.Kos.Pim1";

QJsonObject parseObject(const QString &encoded)
{
    return QJsonDocument::fromJson(encoded.toUtf8()).object();
}

QString encode(const QJsonObject &object)
{
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

} // namespace

class FakeNotifications : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

public:
    QStringList lastActions;
    QVariantMap lastHints;
    uint nextId = 1;
public slots:
    uint Notify(const QString &, uint, const QString &, const QString &summary,
                const QString &body, const QStringList &actions, const QVariantMap &hints, int)
    {
        lastActions = actions;
        lastHints = hints;
        emit notified(summary, body);
        return nextId++;
    }

signals:
    void notified(const QString &summary, const QString &body);
    void ActionInvoked(uint id, const QString &action);
    void ActivationToken(uint id, const QString &token);
    void NotificationClosed(uint id, uint reason);
};

class FakeCalendar : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nextkde.Kos.Application1")
public slots:
    void Activate(const QStringList &args, const QString &token, const QString &) {
        emit activated(args, token);
    }
signals:
    void activated(const QStringList &args, const QString &token);
};

class PimDbusTest : public QObject {
    Q_OBJECT

private slots:
    void servicePublishesMutations();
    void serviceDeliversReminder();
};

void PimDbusTest::servicePublishesMutations()
{
    const QString serviceExecutable = qEnvironmentVariable("KOS_PIM_TEST_SERVICE");
    QVERIFY2(!serviceExecutable.isEmpty(), "PIM service executable environment is missing");
    QTemporaryDir storage;
    QVERIFY(storage.isValid());

    QProcess service;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("KOS_PIM_STORAGE_DIR"), storage.path());
    service.setProcessEnvironment(environment);
    service.setProgram(serviceExecutable);
    service.start();
    QVERIFY(service.waitForStarted(5000));

    QDBusConnectionInterface *busInterface = QDBusConnection::sessionBus().interface();
    QVERIFY(busInterface);
    QTRY_VERIFY_WITH_TIMEOUT(
        busInterface->isServiceRegistered(QString::fromLatin1(serviceName)).value(), 5000);

    QDBusInterface pim(QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
                       QString::fromLatin1(interfaceName), QDBusConnection::sessionBus());
    QVERIFY2(pim.isValid(), qPrintable(pim.lastError().message()));
    QSignalSpy changedSpy(&pim, SIGNAL(changed(qulonglong)));
    QVERIFY(changedSpy.isValid());

    const QDBusReply<QString> createReply = pim.call(
        QStringLiteral("createTodo"), encode({
            {QStringLiteral("title"), QStringLiteral("Cross-process task")},
            {QStringLiteral("listId"), QStringLiteral("inbox")},
        }));
    QVERIFY2(createReply.isValid(), qPrintable(createReply.error().message()));
    const QJsonObject created = parseObject(createReply.value());
    QVERIFY(created.value(QStringLiteral("ok")).toBool());
    const QString uid = created.value(QStringLiteral("item")).toObject()
                            .value(QStringLiteral("id")).toString();
    QVERIFY(!uid.isEmpty());
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 1, 3000);

    const QDBusReply<QString> snapshotReply = pim.call(QStringLiteral("snapshot"));
    QVERIFY(snapshotReply.isValid());
    const QJsonObject snapshot = parseObject(snapshotReply.value());
    QCOMPARE(snapshot.value(QStringLiteral("schemaVersion")).toInt(), 1);
    const QJsonArray todos = snapshot.value(QStringLiteral("todos")).toArray();
    QCOMPARE(todos.size(), 1);
    QCOMPARE(todos.first().toObject().value(QStringLiteral("id")).toString(), uid);

    const QDBusReply<QString> updateReply = pim.call(
        QStringLiteral("updateTodo"), uid, encode({
            {QStringLiteral("completed"), true},
        }));
    QVERIFY(updateReply.isValid());
    QVERIFY(parseObject(updateReply.value()).value(QStringLiteral("ok")).toBool());
    QTRY_COMPARE_WITH_TIMEOUT(changedSpy.count(), 2, 3000);

    service.terminate();
    if (!service.waitForFinished(3000)) {
        service.kill();
        QVERIFY(service.waitForFinished(3000));
    }
}

void PimDbusTest::serviceDeliversReminder()
{
    const QString serviceExecutable = qEnvironmentVariable("KOS_PIM_TEST_SERVICE");
    QVERIFY2(!serviceExecutable.isEmpty(), "PIM service executable environment is missing");
    QTemporaryDir storage;
    QVERIFY(storage.isValid());

    FakeNotifications notifications;
    QDBusConnection bus = QDBusConnection::sessionBus();
    QVERIFY(bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"),
                               &notifications, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
    QVERIFY(bus.registerService(QStringLiteral("org.freedesktop.Notifications")));
    QSignalSpy notifiedSpy(&notifications, &FakeNotifications::notified);
    FakeCalendar calendar;
    QVERIFY(bus.registerObject(QStringLiteral("/org/nextkde/Kos/Application"),
                               &calendar, QDBusConnection::ExportAllSlots));
    QVERIFY(bus.registerService(QStringLiteral("org.nextkde.Kos.Calendar")));
    QSignalSpy activatedSpy(&calendar, &FakeCalendar::activated);

    QProcess service;
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("KOS_PIM_STORAGE_DIR"), storage.path());
    service.setProcessEnvironment(environment);
    service.setProgram(serviceExecutable);
    service.start();
    QVERIFY(service.waitForStarted(5000));

    QDBusConnectionInterface *busInterface = bus.interface();
    QVERIFY(busInterface);
    QTRY_VERIFY_WITH_TIMEOUT(
        busInterface->isServiceRegistered(QString::fromLatin1(serviceName)).value(), 5000);
    QDBusInterface pim(QString::fromLatin1(serviceName), QString::fromLatin1(objectPath),
                       QString::fromLatin1(interfaceName), bus);
    QVERIFY(pim.isValid());

    const QDateTime start = QDateTime::currentDateTimeUtc().addSecs(1);
    const QDBusReply<QString> createReply = pim.call(
        QStringLiteral("createEvent"), encode({
            {QStringLiteral("title"), QStringLiteral("Reminder fixture")},
            {QStringLiteral("start"), start.toString(Qt::ISODateWithMs)},
            {QStringLiteral("end"), start.addSecs(3600).toString(Qt::ISODateWithMs)},
            {QStringLiteral("reminderMinutes"), 0},
        }));
    QVERIFY2(createReply.isValid(), qPrintable(createReply.error().message()));
    QVERIFY(parseObject(createReply.value()).value(QStringLiteral("ok")).toBool());
    QTRY_COMPARE_WITH_TIMEOUT(notifiedSpy.count(), 1, 5000);
    QCOMPARE(notifiedSpy.first().at(0).toString(), QStringLiteral("Reminder fixture"));

    QVERIFY(notifications.lastActions.contains(QStringLiteral("default")));
    QCOMPARE(notifications.lastHints.value(QStringLiteral("desktop-entry")).toString(), QStringLiteral("kos-calendar"));
    const QString uid = parseObject(createReply.value()).value(QStringLiteral("item")).toObject().value(QStringLiteral("id")).toString();
    // Notify's async reply installs the ID mapping before user interaction.
    QTest::qWait(100);
    emit notifications.ActivationToken(1, QStringLiteral("test-activation-token"));
    emit notifications.ActionInvoked(1, QStringLiteral("default"));
    QTRY_COMPARE_WITH_TIMEOUT(activatedSpy.count(), 1, 3000);
    QCOMPARE(activatedSpy.first().at(0).toStringList(), QStringList({QStringLiteral("--item"), QStringLiteral("event:") + uid}));
    QCOMPARE(activatedSpy.first().at(1).toString(), QStringLiteral("test-activation-token"));
    emit notifications.NotificationClosed(1, 2);
    emit notifications.ActionInvoked(1, QStringLiteral("default"));
    emit notifications.ActionInvoked(999, QStringLiteral("default"));
    QTest::qWait(100);
    QCOMPARE(activatedSpy.count(), 1);

    const auto todoDue = QDateTime::currentDateTimeUtc().addSecs(1);
    const QDBusReply<QString> todoReply = pim.call(QStringLiteral("createTodo"), encode({
        {QStringLiteral("title"), QStringLiteral("Reminder completion fixture")},
        {QStringLiteral("due"), todoDue.toString(Qt::ISODateWithMs)},
        {QStringLiteral("reminderMinutes"), 0},
        {QStringLiteral("calendarId"), QStringLiteral("sport")},
    }));
    QVERIFY(todoReply.isValid());
    QTRY_COMPARE_WITH_TIMEOUT(notifiedSpy.count(), 2, 5000);
    QVERIFY(notifications.lastActions.contains(QStringLiteral("complete")));
    QTest::qWait(100);
    emit notifications.ActionInvoked(2, QStringLiteral("complete"));
    auto completed = [&] {
        const QDBusReply<QString> reply = pim.call(QStringLiteral("snapshot"));
        return parseObject(reply.value()).value(QStringLiteral("todos")).toArray().first().toObject().value(QStringLiteral("completed")).toBool();
    };
    QTRY_VERIFY_WITH_TIMEOUT(completed(), 3000);
    bus.unregisterService(QStringLiteral("org.nextkde.Kos.Calendar"));
    bus.unregisterObject(QStringLiteral("/org/nextkde/Kos/Application"));

    service.terminate();
    if (!service.waitForFinished(3000)) {
        service.kill();
        QVERIFY(service.waitForFinished(3000));
    }
    bus.unregisterService(QStringLiteral("org.freedesktop.Notifications"));
    bus.unregisterObject(QStringLiteral("/org/freedesktop/Notifications"));
}

QTEST_GUILESS_MAIN(PimDbusTest)

#include "PimDbusTest.moc"
