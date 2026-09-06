#include "WeatherClient.h"

#include <QDir>
#include <QFile>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QtTest>

class WeatherClientTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void readsVersionedSnapshot();
    void rejectsUnsupportedSnapshot();
    void reconnectsWhenServiceAppearsAfterInitialFailure();
};

void WeatherClientTest::initTestCase()
{
    qputenv("KOS_WEATHER_DISABLE_SERVICE_AUTOSTART", "1");
}

void WeatherClientTest::readsVersionedSnapshot()
{
    QTemporaryDir stateDirectory;
    QTemporaryDir runtimeDirectory;
    QVERIFY(stateDirectory.isValid());
    QVERIFY(runtimeDirectory.isValid());
    qputenv("XDG_STATE_HOME", stateDirectory.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtimeDirectory.path().toUtf8());

    const QString serviceDirectory = QDir(stateDirectory.path()).filePath(
        QStringLiteral("quickshell/shell-data-service"));
    QVERIFY(QDir().mkpath(serviceDirectory));
    QFile snapshot(QDir(serviceDirectory).filePath(QStringLiteral("snapshot.json")));
    QVERIFY(snapshot.open(QIODevice::WriteOnly));
    snapshot.write(R"json({
        "schemaVersion": 1,
        "weather": {
            "schemaVersion": 1,
            "provider": "open-meteo",
            "status": "ready",
            "units": "metric",
            "location": {
                "id": "fixture:changsha",
                "name": "Changsha",
                "latitude": 28.2,
                "longitude": 112.9
            },
            "locations": [{
                "id": "fixture:changsha",
                "name": "Changsha",
                "latitude": 28.2,
                "longitude": 112.9
            }],
            "fetchedAt": 1000,
            "staleAt": 2000,
            "current": {
                "time": "2026-08-30T12:00",
                "temperature": 31.4,
                "apparentTemperature": 34.1,
                "relativeHumidity": 58,
                "isDay": true,
                "weatherCode": 2,
                "windSpeed": 12.5,
                "windDirection": 175
            },
            "hourly": [{
                "time": "2026-08-30T12:00",
                "temperature": 31.4,
                "weatherCode": 2
            }],
            "daily": [{
                "date": "2026-08-30",
                "weatherCode": 2,
                "temperatureMaximum": 34,
                "temperatureMinimum": 25
            }]
        }
    })json");
    snapshot.close();

    WeatherClient client;
    QVERIFY(client.ready());
    QVERIFY(client.stale());
    QCOMPARE(client.status(), QStringLiteral("ready"));
    QCOMPARE(client.units(), QStringLiteral("metric"));
    QCOMPARE(client.location().value(QStringLiteral("name")).toString(),
             QStringLiteral("Changsha"));
    QCOMPARE(client.current().value(QStringLiteral("weatherCode")).toInt(), 2);
    QCOMPARE(client.hourly().size(), 1);
    QCOMPARE(client.daily().size(), 1);
    QCOMPARE(client.fetchedAt(), 1000);
    QCOMPARE(client.staleAt(), 2000);
}

void WeatherClientTest::rejectsUnsupportedSnapshot()
{
    QTemporaryDir stateDirectory;
    QTemporaryDir runtimeDirectory;
    QVERIFY(stateDirectory.isValid());
    QVERIFY(runtimeDirectory.isValid());
    qputenv("XDG_STATE_HOME", stateDirectory.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtimeDirectory.path().toUtf8());

    const QString serviceDirectory = QDir(stateDirectory.path()).filePath(
        QStringLiteral("quickshell/shell-data-service"));
    QVERIFY(QDir().mkpath(serviceDirectory));
    QFile snapshot(QDir(serviceDirectory).filePath(QStringLiteral("snapshot.json")));
    QVERIFY(snapshot.open(QIODevice::WriteOnly));
    snapshot.write(R"json({"weather":{"schemaVersion":99,"status":"ready",
        "current":{"temperature":22}}})json");
    snapshot.close();

    WeatherClient client;
    QVERIFY(!client.ready());
    QCOMPARE(client.status(), QStringLiteral("idle"));
    QVERIFY(client.current().isEmpty());
}

void WeatherClientTest::reconnectsWhenServiceAppearsAfterInitialFailure()
{
    QTemporaryDir stateDirectory;
    QTemporaryDir runtimeDirectory;
    QVERIFY(stateDirectory.isValid());
    QVERIFY(runtimeDirectory.isValid());
    qputenv("XDG_STATE_HOME", stateDirectory.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtimeDirectory.path().toUtf8());

    // Keep the server alive until after the client has torn down its socket.
    // Destroying a QLocalServer with an unaccepted pending connection before
    // the peer socket can trigger allocator corruption on Qt 6.11.
    QLocalServer service;
    WeatherClient client;
    QTRY_VERIFY_WITH_TIMEOUT(!client.errorMessage().isEmpty(), 1000);
    QVERIFY(!client.connected());

    const QString socketPath = QDir(runtimeDirectory.path()).filePath(
        QStringLiteral("kos-data.sock"));
    QLocalServer::removeServer(socketPath);
    QVERIFY2(service.listen(socketPath), qPrintable(service.errorString()));

    QTRY_VERIFY_WITH_TIMEOUT(client.connected(), 3000);
    QTRY_VERIFY_WITH_TIMEOUT(service.hasPendingConnections(), 1000);

    QLocalSocket *serverSocket = service.nextPendingConnection();
    QVERIFY(serverSocket);
    serverSocket->disconnectFromServer();
    if (serverSocket->state() != QLocalSocket::UnconnectedState)
        QVERIFY(serverSocket->waitForDisconnected(1000));
    QTRY_VERIFY_WITH_TIMEOUT(!client.connected(), 1000);
}

QTEST_GUILESS_MAIN(WeatherClientTest)

#include "WeatherClientTest.moc"
