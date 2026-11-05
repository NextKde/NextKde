#include "IndependentAppWidgets.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDate>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTemporaryDir>
#include <QTimeZone>
#include <QtTest>

using namespace KosPlatform::IndependentAppWidgets;

class IndependentAppWidgetsTest : public QObject {
    Q_OBJECT
    QString data;
    QString summary(const QString &key) const
    {
        return key == "calendar" ? data + "/kos/pim/widget-snapshot.json"
            : qEnvironmentVariable("XDG_STATE_HOME") + "/quickshell/kos-weather/standalone-backend/widget-snapshot.json";
    }
    void write(const QString &path, const QByteArray &bytes)
    {
        QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(bytes), bytes.size());
    }
    void entry(const QString &id, const QByteArray &extra = {})
    {
        write(data + "/applications/" + id + ".desktop",
              "[Desktop Entry]\nType=Application\nName=Fixture\nExec=/bin/true\nTryExec=/bin/true\n" + extra);
    }
    QJsonObject calendar() const
    {
        return {{"widgetContractVersion", 2}, {"schemaVersion", 1}, {"appId", "org.nextks.calendar"},
            {"channel", "native"}, {"storageMode", "default"}, {"storagePath", data + "/kos/pim"},
            {"generatedAt", QDateTime::currentMSecsSinceEpoch()}, {"today", QDate::currentDate().toString(Qt::ISODate)},
            {"timeZone", QString::fromUtf8(QTimeZone::systemTimeZoneId())},
            {"events", QJsonArray{}}, {"todos", QJsonArray{}}};
    }
    QJsonObject weather() const
    {
        const auto now = QDateTime::currentMSecsSinceEpoch();
        return {{"widgetContractVersion", 2}, {"appId", "org.nextks.weather"},
            {"channel", "native"}, {"storageMode", "default"}, {"generatedAt", now},
            {"weather", QJsonObject{{"schemaVersion", 1}, {"status", "ready"}, {"units", "metric"},
                {"fetchedAt", now}, {"staleAt", now + 3600000},
                {"location", QJsonObject{{"id", "fixture"}, {"name", "Fixture"},
                    {"latitude", 30.0}, {"longitude", 120.0}}},
                {"current", QJsonObject{{"time", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
                    {"temperature", 20.0}, {"apparentTemperature", 21.0}, {"relativeHumidity", 50.0},
                    {"windSpeed", 5.0}, {"windDirection", 90.0}, {"weatherCode", 0}, {"isDay", true}}},
                {"locations", QJsonArray{}}, {"hourly", QJsonArray{}}, {"daily", QJsonArray{}}}}};
    }
    QJsonObject inspect(const QString &key = "calendar")
    {
        return snapshot(key, std::make_shared<QueryControl>());
    }
    void publish(const QString &key, const QJsonObject &value)
    {
        write(summary(key), QJsonDocument(value).toJson(QJsonDocument::Compact));
    }
private slots:
    void init()
    {
        data = qEnvironmentVariable("XDG_DATA_HOME");
        QVERIFY(QDir(data).removeRecursively());
        QVERIFY(QDir(qEnvironmentVariable("XDG_STATE_HOME")).removeRecursively());
        qunsetenv("KOS_PIM_STORAGE_DIR");
        qunsetenv("KOS_DATA_SOCKET");
    }
    void absentAppDoesNotExposeRetainedData()
    {
        publish("calendar", calendar());
        const auto result = inspect();
        QCOMPARE(result["state"].toString(), "not-installed");
        QVERIFY(!result.contains("payload"));
    }
    void uniqueCalendarAndChangedLaunchToken()
    {
        entry("org.nextks.calendar");
        publish("calendar", calendar());
        const auto first = inspect();
        QCOMPARE(first["state"].toString(), "ready");
        QVERIFY(first["installed"].toBool());
        QCOMPARE(first["sourceToken"].toString().size(), 64);
        QVERIFY(launchEntryMatches(first));
        entry("org.nextks.calendar", "Comment=changed\n");
        QVERIFY(!launchEntryMatches(first));
        QVERIFY(inspect()["sourceToken"] != first["sourceToken"]);
        QVERIFY(QFile::remove(data + "/applications/org.nextks.calendar.desktop"));
        QVERIFY(!launchEntryMatches(first));
        QCOMPARE(inspect()["state"].toString(), "not-installed");
    }
    void missingDamagedAndRecoveredSummary()
    {
        entry("org.nextks.calendar");
        QCOMPARE(inspect()["state"].toString(), "missing");
        write(summary("calendar"), "{broken");
        QCOMPARE(inspect()["state"].toString(), "invalid");
        publish("calendar", calendar());
        QCOMPARE(inspect()["state"].toString(), "ready");
        write(summary("calendar"), QByteArray(512 * 1024 + 1, ' '));
        const auto rejected = inspect();
        QCOMPARE(rejected["state"].toString(), "missing");
        QVERIFY(!rejected.contains("payload"));
    }
    void staleFutureAndWrongSource_data()
    {
        QTest::addColumn<QString>("field");
        QTest::addColumn<QJsonValue>("value");
        QTest::addColumn<QString>("expected");
        QTest::newRow("old") << QString("generatedAt") << QJsonValue(QDateTime::currentMSecsSinceEpoch() - 13 * 60000) << QString("stale");
        QTest::newRow("future") << QString("generatedAt") << QJsonValue(QDateTime::currentMSecsSinceEpoch() + 120000) << QString("invalid");
        QTest::newRow("identity") << QString("appId") << QJsonValue("org.nextks.weather") << QString("unsupported");
        QTest::newRow("channel") << QString("channel") << QJsonValue("flatpak") << QString("unsupported");
        QTest::newRow("profile") << QString("storagePath") << QJsonValue("/different/profile") << QString("unsupported");
        QTest::newRow("custom") << QString("storageMode") << QJsonValue("custom") << QString("unsupported");
        QTest::newRow("events-type") << QString("events") << QJsonValue("not an array") << QString("invalid");
    }
    void staleFutureAndWrongSource()
    {
        QFETCH(QString, field); QFETCH(QJsonValue, value); QFETCH(QString, expected);
        entry("org.nextks.calendar");
        auto payload = calendar(); payload[field] = value;
        publish("calendar", payload);
        const auto result = inspect();
        QCOMPARE(result["state"].toString(), expected);
        if (expected != "stale") QVERIFY(!result.contains("payload"));
    }
    void symlinkSummaryIsNotFollowed()
    {
        entry("org.nextks.calendar");
        const auto external = data + "/external.json";
        write(external, QJsonDocument(calendar()).toJson());
        QVERIFY(QDir().mkpath(QFileInfo(summary("calendar")).absolutePath()));
        QVERIFY(QFile::link(external, summary("calendar")));
        QCOMPARE(inspect()["state"].toString(), "missing");
    }
    void duplicateIdentitiesAndHiddenEntry()
    {
        entry("org.nextks.calendar"); entry("kos-calendar");
        QCOMPARE(inspect()["state"].toString(), "ambiguous");
        QVERIFY(QFile::remove(data + "/applications/kos-calendar.desktop"));
        entry("org.nextks.calendar", "Hidden=true\n");
        QCOMPARE(inspect()["state"].toString(), "unavailable");
    }
    void nativeOverrideIsExplicitlyUnsupported()
    {
        entry("org.nextks.calendar"); publish("calendar", calendar());
        qputenv("KOS_PIM_STORAGE_DIR", "/custom");
        QCOMPARE(inspect()["state"].toString(), "unsupported");
        entry("org.nextks.weather");
        qputenv("KOS_DATA_SOCKET", "");
        QCOMPARE(inspect("weather")["state"].toString(), "unsupported");
    }
    void legacyCalendarIsNotAdoptedByNewIdentity()
    {
        auto payload = calendar();
        payload.remove("widgetContractVersion");
        entry("kos-calendar"); publish("calendar", payload);
        QCOMPARE(inspect()["state"].toString(), "ready");
        QVERIFY(QFile::remove(data + "/applications/kos-calendar.desktop"));
        entry("org.nextks.calendar");
        QCOMPARE(inspect()["state"].toString(), "unsupported");
    }
    void weatherUninstallDoesNotExposeRetainedSummary()
    {
        publish("weather", weather());
        QCOMPARE(inspect("weather")["state"].toString(), "not-installed");
        entry("org.nextks.weather");
        const auto first = inspect("weather");
        QCOMPARE(first["state"].toString(), "ready");
        QCOMPARE(first["payload"].toObject()["current"].toObject()["temperature"].toDouble(), 20.0);
        QVERIFY(launchEntryMatches(first));
        QVERIFY(QFile::remove(data + "/applications/org.nextks.weather.desktop"));
        const auto removed = inspect("weather");
        QCOMPARE(removed["state"].toString(), "not-installed");
        QVERIFY(!removed.contains("payload"));
        QVERIFY(!launchEntryMatches(first));
    }
    void weatherPublicationDoesNotRefreshOldReading()
    {
        entry("org.nextks.weather");
        auto payload = weather();
        auto reading = payload["weather"].toObject();
        reading["fetchedAt"] = QDateTime::currentMSecsSinceEpoch() - 3 * 3600000;
        reading["staleAt"] = QDateTime::currentMSecsSinceEpoch() - 2 * 3600000;
        payload["weather"] = reading;
        publish("weather", payload);
        const auto result = inspect("weather");
        QCOMPARE(result["state"].toString(), "stale");
        QCOMPARE(result["payload"].toObject()["fetchedAt"].toInteger(), reading["fetchedAt"].toInteger());
    }
    void malformedWeatherNeverBecomesEmptyOrReady_data()
    {
        QTest::addColumn<QString>("field"); QTest::addColumn<QJsonValue>("value");
        QTest::addColumn<QString>("expected");
        QTest::newRow("no-reading") << QString("current") << QJsonValue(QJsonValue::Null) << QString("missing");
        QTest::newRow("wrong-units") << QString("units") << QJsonValue("kelvin") << QString("invalid");
        QTest::newRow("bad-forecast") << QString("hourly") << QJsonValue("not an array") << QString("invalid");
        QTest::newRow("future-reading") << QString("fetchedAt")
            << QJsonValue(QDateTime::currentMSecsSinceEpoch() + 120000) << QString("invalid");
        QTest::newRow("invalid-location") << QString("location")
            << QJsonValue(QJsonObject{{"id", "fixture"}, {"name", "Fixture"}, {"latitude", 91}, {"longitude", 120}})
            << QString("invalid");
    }
    void malformedWeatherNeverBecomesEmptyOrReady()
    {
        QFETCH(QString, field); QFETCH(QJsonValue, value); QFETCH(QString, expected);
        entry("org.nextks.weather");
        auto payload = weather(); auto reading = payload["weather"].toObject();
        reading[field] = value; payload["weather"] = reading; publish("weather", payload);
        const auto result = inspect("weather");
        QCOMPARE(result["state"].toString(), expected);
        QVERIFY(!result.contains("payload"));
    }
    void cancelledQueryNeverClaimsInstalled()
    {
        entry("org.nextks.calendar"); publish("calendar", calendar());
        auto control = std::make_shared<QueryControl>(); control->cancel();
        const auto result = snapshot("calendar", control);
        QCOMPARE(result["state"].toString(), "unavailable");
        QVERIFY(!result.contains("installed"));
        QVERIFY(!result.contains("payload"));
    }
};

int main(int argc, char **argv)
{
    // All files and Flatpak installations belong to this disposable fixture.
    QDir().mkpath("tmp");
    QTemporaryDir fixture(QDir::currentPath() + "/tmp/widget-apps-XXXXXX");
    if (!fixture.isValid()) return 1;
    const auto environment = [&](const char *name, const QString &part) {
        const auto path = fixture.path() + '/' + part;
        QDir().mkpath(path);
        qputenv(name, path.toUtf8());
    };
    environment("HOME", "home");
    environment("XDG_DATA_HOME", "data");
    environment("XDG_STATE_HOME", "state");
    environment("XDG_CACHE_HOME", "cache");
    environment("XDG_CONFIG_HOME", "config");
    environment("XDG_DATA_DIRS", "system-data");
    environment("FLATPAK_USER_DIR", "flatpak-user");
    environment("FLATPAK_SYSTEM_DIR", "flatpak-system");
    environment("FLATPAK_CONFIG_DIR", "flatpak-config");
    QCoreApplication application(argc, argv);
    IndependentAppWidgetsTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "test_independent_app_widgets.moc"
