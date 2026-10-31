#include "PimClient.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDateTime>
#include <QFile>
#include <QProcess>
#include <QProcessEnvironment>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QUrl>
#include <QTcpServer>
#include <QTcpSocket>
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
                    && QDateTime::fromString(todo.value(QStringLiteral("due")).toString(), Qt::ISODate).toSecsSinceEpoch() / 60
                        == QDateTime::fromString(QStringLiteral("2026-09-06T12:00:00+08:00"), Qt::ISODate).toSecsSinceEpoch() / 60;
            }
        }
        return false;
    }(), 5000);

    const QString holidayPath = storage.filePath(QStringLiteral("holidays.ics"));
    QFile holidayFile(holidayPath);
    QVERIFY(holidayFile.open(QIODevice::WriteOnly));
    holidayFile.write("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//KOS//Test//EN\r\n"
                      "BEGIN:VEVENT\r\nUID:client-holiday\r\nDTSTAMP:20260101T000000Z\r\n"
                      "DTSTART;VALUE=DATE:20300101\r\nDTEND;VALUE=DATE:20300102\r\n"
                      "SUMMARY:Client holiday\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
    holidayFile.close();
    client.importHolidays(QUrl::fromLocalFile(holidayPath).toString());
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 5, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.events().size(), 2, 5000);
    QTRY_VERIFY_WITH_TIMEOUT([&] {
        for (const auto &entry : client.events()) {
            const auto event = entry.toMap();
            if (event.value(QStringLiteral("id")).toString() == QStringLiteral("client-holiday"))
                return event.value(QStringLiteral("calendarId")).toString() == QStringLiteral("holidays");
        }
        return false;
    }(), 5000);
    client.importHolidays(QUrl::fromLocalFile(holidayPath).toString());
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 6, 5000);
    QCOMPARE(client.events().size(), 2);
    QCOMPARE(client.todos().size(), 2);

    // Serve a real HTTP response on the isolated test bus. Exercise delayed
    // D-Bus replies, gzip decoding, failures and refresh/remove through PimClient.
    QTcpServer http;
    QVERIFY(http.listen(QHostAddress::LocalHost));
    int requests = 0;
    bool failDownload = false;
    QByteArray body = QByteArray::fromBase64("H4sIAAAAAAAC/22PsQrCMBCG90DewReoSSM4RBxSc0ixTUpyDdRNtGCh1MEuvr1plbp408H3/dx/GRxzI8NBFWC0cpQEcD63Roo1p6RyVudaJoydrGcM2+fIGBhKsk8MAhikpI7Ote/aYUzuj767XV6UaPSoykoKLrY85Snyec5f4nAXVFHDXiuEKG34JE0w9viDBCW+LkvlGmmHvhva1XIpBpYm8/575g0Zyy6p3gAAAA==");
    connect(&http, &QTcpServer::newConnection, &http, [&] {
        while (auto *socket = http.nextPendingConnection()) {
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                auto request = socket->property("request").toByteArray() + socket->readAll();
                socket->setProperty("request", request);
                if (!request.contains("\r\n\r\n") || socket->property("answered").toBool()) return;
                socket->setProperty("answered", true);
                ++requests;
                const QByteArray response = failDownload ? QByteArray("unavailable") : body;
                socket->write(failDownload ? "HTTP/1.1 503 Unavailable\r\n" : "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n");
                socket->write("Content-Type: text/calendar\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(response.size()) + "\r\n\r\n" + response);
                socket->disconnectFromHost();
            });
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        }
    });
    QSignalSpy failureSpy(&client, &PimClient::operationFailed);
    const auto sourceUrl = QStringLiteral("http://127.0.0.1:%1/holidays.ics").arg(http.serverPort());
    client.addHolidayCalendar({{"type", "url"}, {"name", "Subscribed holidays"}, {"url", sourceUrl}});
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 7, 5000);
    QCOMPARE(requests, 1);
    QTRY_COMPARE_WITH_TIMEOUT(client.holidayCalendars().size(), 2, 5000); // Includes legacy import.
    QTRY_COMPARE_WITH_TIMEOUT(client.events().size(), 3, 5000);
    const auto sourceId = client.holidayCalendars().last().toMap().value("id").toString();
    QVERIFY(sourceId.startsWith("holiday:"));
    client.addHolidayCalendar({{"type", "url"}, {"name", "Duplicate"}, {"url", sourceUrl}});
    QTRY_COMPARE_WITH_TIMEOUT(failureSpy.count(), 1, 5000);
    QCOMPARE(requests, 1);
    failDownload = true;
    client.refreshHolidayCalendar(sourceId);
    QTRY_COMPARE_WITH_TIMEOUT(failureSpy.count(), 2, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!client.holidayCalendars().last().toMap().value("lastError").toString().isEmpty(), 5000);
    QCOMPARE(client.events().size(), 3);
    client.setHolidayCalendarEnabled(sourceId, false);
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 8, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(!client.holidayCalendars().last().toMap().value("enabled").toBool(), 5000);
    failDownload = false;
    client.refreshHolidayCalendar(sourceId);
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 9, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(client.holidayCalendars().last().toMap().value("lastError").toString().isEmpty(), 5000);
    QCOMPARE(client.events().size(), 3);
    client.removeHolidayCalendar(sourceId);
    QTRY_COMPARE_WITH_TIMEOUT(successSpy.count(), 10, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.holidayCalendars().size(), 1, 5000);
    QTRY_COMPARE_WITH_TIMEOUT(client.events().size(), 2, 5000);
    QCOMPARE(client.todos().size(), 2);

    service.terminate();
    if (!service.waitForFinished(3000)) {
        service.kill();
        QVERIFY(service.waitForFinished(3000));
    }
}

QTEST_GUILESS_MAIN(PimClientDbusTest)

#include "PimClientDbusTest.moc"
