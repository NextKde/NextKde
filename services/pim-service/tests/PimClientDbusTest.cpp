#include "PimClient.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

class PimClientDbusTest : public QObject {
    Q_OBJECT

private slots:
    void clientTracksRemoteService();
};

void PimClientDbusTest::clientTracksRemoteService()
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
        busInterface->isServiceRegistered(QStringLiteral("org.nextkde.Kos.Pim1")).value(),
        5000);

    PimClient client;
    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 5000);
    QTRY_VERIFY_WITH_TIMEOUT(client.ready(), 5000);
    QVERIFY(client.writable());
    QCOMPARE(client.todos().size(), 0);

    QSignalSpy successSpy(&client, &PimClient::operationSucceeded);
    QSignalSpy snapshotSpy(&client, &PimClient::snapshotChanged);
    client.createTodo({
        {QStringLiteral("title"), QStringLiteral("Client-observed task")},
        {QStringLiteral("listId"), QStringLiteral("inbox")},
        {QStringLiteral("due"), QStringLiteral("2026-09-04T18:00:00+08:00")},
    });
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 1, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(snapshotSpy.count() >= 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.todos().size(), 1, 5000);
    QCOMPARE(client.todos().first().toMap().value(QStringLiteral("title")).toString(),
             QStringLiteral("Client-observed task"));
    client.setEventRange(QStringLiteral("2026-09-01"), QStringLiteral("2026-09-10"));
    QTRY_COMPARE_WITH_TIMEOUT(client.todoOccurrences().size(), 1, 5000);

    const QString uid = client.todos().first().toMap().value(QStringLiteral("id")).toString();
    client.updateTodo(uid, {{QStringLiteral("completed"), true}});
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 2, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(
        client.todos().first().toMap().value(QStringLiteral("completed")).toBool(), 5000);

    client.createEvent({
        {QStringLiteral("title"), QStringLiteral("Client-linked event")},
        {QStringLiteral("start"), QStringLiteral("2026-09-06T10:00:00+08:00")},
        {QStringLiteral("end"), QStringLiteral("2026-09-06T11:00:00+08:00")},
        {QStringLiteral("linkedTodo"), true},
        {QStringLiteral("todoListId"), QStringLiteral("inbox")},
    });
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 3, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.events().size(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.todos().size(), 2, 5000);
    const QVariantMap linkedEvent = client.events().first().toMap();
    const QString linkedTodoId = linkedEvent.value(QStringLiteral("linkedTodoId")).toString();
    QVERIFY(!linkedTodoId.isEmpty());

    client.updateEvent(linkedEvent.value(QStringLiteral("id")).toString(), {
        {QStringLiteral("title"), QStringLiteral("Client-linked update")},
        {QStringLiteral("start"), QStringLiteral("2026-09-06T12:00:00+08:00")},
        {QStringLiteral("end"), QStringLiteral("2026-09-06T13:00:00+08:00")},
    });
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 4, 5000);
    QTRY_VERIFY_WITH_TIMEOUT([&] {
        for (const QVariant &entry : client.todos()) {
            const QVariantMap todo = entry.toMap();
            if (todo.value(QStringLiteral("id")).toString() == linkedTodoId) {
                return todo.value(QStringLiteral("title")).toString()
                    == QStringLiteral("Client-linked update")
                    && todo.value(QStringLiteral("due")).toString().startsWith(
                        QStringLiteral("2026-09-06T12:00"));
            }
        }
        return false;
    }(), 5000);

    service.terminate();
    if (!service.waitForFinished(3000)) {
        service.kill();
        QVERIFY(service.waitForFinished(3000));
    }
}

QTEST_GUILESS_MAIN(PimClientDbusTest)

#include "PimClientDbusTest.moc"
