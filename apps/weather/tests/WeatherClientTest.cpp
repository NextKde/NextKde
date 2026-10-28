#include "WeatherClient.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocalServer>
#include <QTemporaryDir>
#include <QtTest>

class WeatherClientTest : public QObject {
    Q_OBJECT

private slots:
    void initTestCase();
    void searchDiscardsStaleRepliesAndSeparatesErrors();
    void removalAcknowledgesServiceAndAcceptsEmptyState();
    void readsVersionedSnapshot();
    void destroysConnectedClient();
    void rejectsUnsupportedSnapshot();
    void reconnectsWhenServiceAppearsAfterInitialFailure();
    void citySwitchHidesOldForecastAndRejectsLateReplies();
    void failedCitySwitchCanBeRetried();
};

namespace {
QJsonObject forecast(const QString &id, const QString &status = QStringLiteral("ready"))
{
    return {{"schemaVersion", 1}, {"status", status}, {"units", "metric"},
            {"location", QJsonObject{{"id", id}, {"name", id}}},
            {"current", status == "ready" ? QJsonObject{{"temperature", 25}} : QJsonObject{}},
            {"error", status == "error" ? "Network unavailable" : ""}};
}

void reply(QLocalSocket *peer, const QJsonObject &request, const QJsonObject &weather)
{
    const QJsonObject message{{"requestId", request.value("requestId")}, {"ok", true},
                              {"result", QJsonObject{{"weather", weather}}}};
    peer->write(QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n');
    peer->flush();
}

QJsonObject readRequest(QLocalSocket *peer)
{
    return QJsonDocument::fromJson(peer->readLine()).object();
}
}

void WeatherClientTest::citySwitchHidesOldForecastAndRejectsLateReplies()
{
    QTemporaryDir state, runtime;
    qputenv("XDG_STATE_HOME", state.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    QLocalServer service;
    QVERIFY(service.listen(runtime.filePath("kos-data.sock")));
    WeatherClient client;
    QTRY_VERIFY(service.hasPendingConnections());
    auto *peer = service.nextPendingConnection();
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("A"));
    QTRY_VERIFY(client.ready());

    // Selecting the displayed city should neither clear it nor refresh it.
    client.selectLocation({{"id", "A"}});
    QVERIFY(client.ready());
    QVERIFY(!client.loading());

    // Leave one A snapshot in flight across both selections.
    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    const auto oldSnapshot = readRequest(peer);
    client.selectLocation({{"id", "B"}});
    QVERIFY(!client.ready()); // Must change before any service reply arrives.
    QVERIFY(client.loading());
    QVERIFY(client.current().isEmpty());
    QVERIFY(client.hourly().isEmpty());
    QVERIFY(client.daily().isEmpty());
    QVERIFY(client.airQuality().isEmpty());
    QCOMPARE(client.location().value("id").toString(), QStringLiteral("B"));
    QTRY_VERIFY(peer->canReadLine());
    QCOMPARE(readRequest(peer).value("operation").toString(), QStringLiteral("weather.set-location"));

    client.selectLocation({{"id", "C"}});
    QTRY_VERIFY(peer->canReadLine());
    readRequest(peer);
    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("B"));
    QTest::qWait(30);
    QVERIFY(!client.ready());
    QCOMPARE(client.location().value("id").toString(), QStringLiteral("C"));

    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("C", "loading"));
    QTest::qWait(30);
    QVERIFY(!client.ready());
    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("C"));
    QTRY_VERIFY(client.ready());
    QVERIFY(!client.loading());
    QCOMPARE(client.current().value("temperature").toInt(), 25);

    // An old response must not roll back a successfully displayed city either.
    reply(peer, oldSnapshot, forecast("A"));
    QTest::qWait(30);
    QCOMPARE(client.location().value("id").toString(), QStringLiteral("C"));
}

void WeatherClientTest::failedCitySwitchCanBeRetried()
{
    QTemporaryDir state, runtime;
    qputenv("XDG_STATE_HOME", state.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    QLocalServer service;
    QVERIFY(service.listen(runtime.filePath("kos-data.sock")));
    WeatherClient client;
    QTRY_VERIFY(service.hasPendingConnections());
    auto *peer = service.nextPendingConnection();
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("A"));
    QTRY_VERIFY(client.ready());
    client.selectLocation({{"id", "B"}});
    QTRY_VERIFY(peer->canReadLine());
    readRequest(peer);
    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("B", "error"));
    QTRY_VERIFY(!client.errorMessage().isEmpty());
    QVERIFY(!client.ready());
    QVERIFY(!client.loading());

    client.refresh();
    QVERIFY(client.errorMessage().isEmpty());
    QVERIFY(client.loading());
    QTRY_VERIFY(peer->canReadLine());
    const auto retry = readRequest(peer);
    QCOMPARE(retry.value("operation").toString(), QStringLiteral("weather.set-location"));
    QCOMPARE(retry.value("payload").toObject().value("location").toObject().value("id").toString(), QStringLiteral("B"));
    peer->disconnectFromServer();
    QTRY_VERIFY(!client.connected());
    QTRY_VERIFY(!client.errorMessage().isEmpty());
    QVERIFY(!client.ready());
    QVERIFY(!client.loading());
}

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
            }],
            "airQuality": {"time": "2026-08-30T12:00", "usAqi": 42, "category": "Good"}
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
    QCOMPARE(client.airQuality().value(QStringLiteral("usAqi")).toDouble(), 42.0);
    QCOMPARE(client.airQuality().value(QStringLiteral("category")).toString(), QStringLiteral("Good"));
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

void WeatherClientTest::destroysConnectedClient()
{
    QTemporaryDir stateDirectory, runtimeDirectory;
    qputenv("XDG_STATE_HOME", stateDirectory.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtimeDirectory.path().toUtf8());
    QLocalServer server;
    QVERIFY(server.listen(runtimeDirectory.filePath("kos-data.sock")));
    auto *client = new WeatherClient;
    QTRY_VERIFY_WITH_TIMEOUT(client->connected(), 1000);
    QTRY_VERIFY(server.hasPendingConnections());
    auto *peer = server.nextPendingConnection();
    QVERIFY(peer);
    delete client; // Must not restart a destroyed timer or corrupt the allocator.
    QTRY_COMPARE(peer->state(), QLocalSocket::UnconnectedState);
}

void WeatherClientTest::searchDiscardsStaleRepliesAndSeparatesErrors()
{
    QTemporaryDir state, runtime;
    qputenv("XDG_STATE_HOME", state.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    QLocalServer service;
    QVERIFY(service.listen(runtime.filePath("kos-data.sock")));
    WeatherClient client;
    QTRY_VERIFY(service.hasPendingConnections());
    auto *peer = service.nextPendingConnection();
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("A"));
    QTRY_VERIFY(client.ready());
    const auto answer = [peer](const QJsonObject &request, bool ok, const QJsonArray &cities) {
        const QJsonObject response{{"requestId", request.value("requestId")}, {"ok", ok},
            {"result", QJsonObject{{"locations", cities}}}, {"error", QJsonObject{{"message", "network failed"}}}};
        peer->write(QJsonDocument(response).toJson(QJsonDocument::Compact) + '\n');
        peer->flush();
    };
    client.searchLocations("old");
    QTRY_VERIFY(peer->canReadLine());
    const auto old = readRequest(peer);
    client.searchLocations("new");
    QVERIFY(client.searching());
    QTRY_VERIFY(peer->canReadLine());
    const auto current = readRequest(peer);
    answer(current, true, QJsonArray{QJsonObject{{"id", "new"}, {"name", "New"}}});
    QTRY_COMPARE(client.searchStatus(), QStringLiteral("ready"));
    answer(old, false, {});
    QTest::qWait(30);
    QCOMPARE(client.searchResults().first().toMap().value("id").toString(), QStringLiteral("new"));
    QVERIFY(client.searchError().isEmpty());
    QVERIFY(client.errorMessage().isEmpty());

    client.searchLocations("clear");
    QTRY_VERIFY(peer->canReadLine());
    const auto cleared = readRequest(peer);
    client.clearSearch();
    answer(cleared, true, QJsonArray{QJsonObject{{"id", "late"}}});
    QTest::qWait(30);
    QCOMPARE(client.searchStatus(), QStringLiteral("idle"));
    QVERIFY(client.searchResults().isEmpty());
    QVERIFY(!client.searching());

    client.searchLocations("retry");
    QTRY_VERIFY(peer->canReadLine());
    answer(readRequest(peer), false, {});
    QTRY_COMPARE(client.searchStatus(), QStringLiteral("error"));
    QVERIFY(!client.searchError().isEmpty());
    QVERIFY(client.errorMessage().isEmpty());
    QVERIFY(client.ready());
    client.searchLocations("retry");
    QTRY_VERIFY(peer->canReadLine());
    answer(readRequest(peer), true, {});
    QTRY_COMPARE(client.searchStatus(), QStringLiteral("empty"));
    QVERIFY(client.searchError().isEmpty());
    peer->disconnectFromServer();
}

void WeatherClientTest::removalAcknowledgesServiceAndAcceptsEmptyState()
{
    QTemporaryDir state, runtime;
    qputenv("XDG_STATE_HOME", state.path().toUtf8());
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    QLocalServer service;
    QVERIFY(service.listen(runtime.filePath("kos-data.sock")));
    WeatherClient client;
    QTRY_VERIFY(service.hasPendingConnections());
    auto *peer = service.nextPendingConnection();
    QTRY_VERIFY(peer->canReadLine());
    reply(peer, readRequest(peer), forecast("A"));
    QTRY_VERIFY(client.ready());
    peer->write("{\"event\":\"weather.changed\"}\n");
    QTRY_VERIFY(peer->canReadLine());
    const auto stale = readRequest(peer);
    client.removeLocation("A");
    QCOMPARE(client.removingLocationId(), QStringLiteral("A"));
    QTRY_VERIFY(peer->canReadLine());
    auto removal = readRequest(peer);
    QCOMPARE(removal.value("operation").toString(), QStringLiteral("weather.remove-location"));
    QCOMPARE(removal.value("payload").toObject().value("id").toString(), QStringLiteral("A"));
    reply(peer, removal, {});
    QTRY_VERIFY(client.removingLocationId().isEmpty());
    QTRY_VERIFY(peer->canReadLine());
    auto empty = forecast("", "idle");
    empty.insert("location", QJsonObject{});
    empty.insert("locations", QJsonArray{});
    reply(peer, readRequest(peer), empty);
    QTRY_VERIFY(client.location().isEmpty());
    QVERIFY(!client.ready());
    QVERIFY(!client.loading());
    reply(peer, stale, forecast("A"));
    QTest::qWait(30);
    QVERIFY(client.location().isEmpty());
    QVERIFY(client.locationError().isEmpty());
    peer->disconnectFromServer();
}

QTEST_GUILESS_MAIN(WeatherClientTest)

#include "WeatherClientTest.moc"
