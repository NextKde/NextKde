#include "AppCatalog.h"
#include "AppStore.h"
#include "IndependentApps.h"
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>
#include <QNetworkProxy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QScopeGuard>

class IndependentAppsTest : public QObject {
    Q_OBJECT
    QTemporaryDir temporary;
    QByteArray oldState;
    QVariantMap state(const IndependentApps& store, const QString& id)
    {
        for (const auto& entry : store.apps()) if (entry.toMap().value("id") == id) return entry.toMap();
        return {};
    }
private slots:
    void pageRefreshDoesNotBlockOrDiscardCachedApps()
    {
        QTemporaryDir config;
        const auto oldConfig = qgetenv("XDG_CONFIG_HOME");
        const auto oldProxy = QNetworkProxy::applicationProxy();
        const auto restore = qScopeGuard([&] {
            if (oldConfig.isNull()) qunsetenv("XDG_CONFIG_HOME"); else qputenv("XDG_CONFIG_HOME", oldConfig);
            QNetworkProxy::setApplicationProxy(oldProxy);
        });
        qputenv("XDG_CONFIG_HOME", config.path().toUtf8());
        QTcpServer proxy;
        QVERIFY(proxy.listen(QHostAddress::LocalHost));
        QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::HttpProxy, "127.0.0.1", proxy.serverPort()));
        int requests = 0, heartbeats = 0;
        connect(&proxy, &QTcpServer::newConnection, this, [&] {
            auto socket = proxy.nextPendingConnection();
            ++requests;
            QTimer::singleShot(300, socket, [socket] {
                socket->write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                socket->disconnectFromHost();
            });
        });
        QTimer heartbeat;
        heartbeat.setInterval(10);
        connect(&heartbeat, &QTimer::timeout, this, [&] { ++heartbeats; });
        heartbeat.start();
        AppStore store;
        const auto count = store.apps().size();
        QVERIFY(count > 0);
        QElapsedTimer elapsed; elapsed.start();
        store.ensureCatalogFresh();
        store.ensureCatalogFresh();
        QVERIFY(elapsed.elapsed() < 100);
        QTRY_VERIFY_WITH_TIMEOUT(requests > 0, 3000);
        QTRY_VERIFY_WITH_TIMEOUT(!store.catalogBusy(), 5000);
        QVERIFY(heartbeats >= 5);
        QCOMPARE(store.apps().size(), count);
        // The worker can finish before its queued completion updates the UI.
        QTRY_VERIFY_WITH_TIMEOUT(!store.catalogError().isEmpty(), 5000);
        const auto firstRequests = requests;
        store.ensureCatalogFresh();
        QTRY_VERIFY_WITH_TIMEOUT(!store.catalogBusy(), 3000);
        QCOMPARE(requests, firstRequests); // The page timer cannot cause a retry storm.
    }
    void closePolicyUsesFlatpakWorkerState()
    {
        IndependentApps store;
        auto& client = store.m_flatpak;
        client.m_activeId = "org.nextks.calendar";
        for (const auto& action : {"check-update", "inventory"}) {
            client.m_activeAction = action;
            QVERIFY(!store.hasActiveMutation());
        }
        for (const auto& action : {"prepare-install", "prepare-update", "confirm-plan", "uninstall"}) {
            client.m_activeAction = action;
            QVERIFY(store.busy());
            QVERIFY(store.hasActiveMutation());
        }
        client.m_activeId.clear();
        QVERIFY(!store.busy());
        QVERIFY(!store.hasActiveMutation());
    }
    void init() { QVERIFY(temporary.isValid()); oldState = qgetenv("XDG_STATE_HOME"); qputenv("XDG_STATE_HOME", (temporary.path()+"/state").toUtf8()); }
    void cleanup() { if (oldState.isNull()) qunsetenv("XDG_STATE_HOME"); else qputenv("XDG_STATE_HOME", oldState); }
    void registryAndLegacyFacade()
    {
        AppStore store;
        QCOMPARE(store.apps().size(), AppCatalog::apps().size());
        QCOMPARE(store.apps()[0].toMap().value("id").toString(), "kmusic");
        QVERIFY(!store.anyBusy());
        store.install("unknown"); QVERIFY(!store.anyBusy());
        QCOMPARE(store.music().value("code").toString(), "");
    }
    void sourceArtifactsDoNotAppearAsFlatpakInstallation()
    {
        const auto data = qEnvironmentVariable("XDG_DATA_HOME");
        QVERIFY(QDir().mkpath(data + "/nextkde-apps/calendar"));
        QFile sourceState(data + "/nextkde-apps/calendar/ownership.json");
        QVERIFY(sourceState.open(QIODevice::WriteOnly));
        sourceState.write("{\"appId\":\"org.nextkde.Calendar\",\"version\":\"1.0.0\"}");
        sourceState.close();
        IndependentApps store;
        QVERIFY(!state(store, "calendar").value("installed").toBool());
        QVERIFY(!state(store, "calendar").value("managed").toBool());
        QCOMPARE(state(store, "calendar").value("version").toString(), "");
    }
    void missingFlatpakDisablesCachedInstallationsAndRecovers()
    {
        IndependentApps store;
        auto& client = store.m_flatpak;
        const QString appId = "org.nextks.calculator";
        const QVariantList installed{QVariantMap{{"scope", "user"}, {"version", "0.2.2"}}};
        client.m_states[appId] = QVariantMap{{"known", true}, {"installations", installed}};
        QVERIFY(state(store, "calculator").value("statusKnown").toBool());
        const auto oldPath = qgetenv("PATH");
        qputenv("PATH", "/nonexistent-kos-flatpak-fixture");
        store.refresh();
        QTRY_VERIFY_WITH_TIMEOUT(!client.querying(), 4000);
        qputenv("PATH", oldPath);
        QCOMPARE(client.state(appId).value("errorCode").toString(), "FLATPAK_NOT_INSTALLED");
        QVERIFY(!state(store, "calculator").value("statusKnown").toBool());
        QVERIFY(!state(store, "calculator").value("managed").toBool());
        QVERIFY(client.plan(appId).isEmpty());
        store.m_flatpakResults[appId] = QVariantMap{{"code", "FLATPAK_NOT_INSTALLED"}};
        client.m_states[appId] = QVariantMap{{"known", true}, {"installations", installed}};
        QVERIFY(state(store, "calculator").value("statusKnown").toBool());
        QCOMPARE(state(store, "calculator").value("code").toString(), "");
    }
    void installationFailureSurvivesInventoryRefresh()
    {
        IndependentApps store;
        const QString appId = "org.nextks.calculator";
        store.m_flatpakResults[appId] = QVariantMap{{"code", "DISK_FULL"},
            {"diskSpace", QVariantMap{{"missingBytes", 123456}, {"location", "download"}}}};
        store.m_flatpak.m_states[appId] = QVariantMap{{"known", true}, {"installations", QVariantList{}}};
        QCOMPARE(state(store, "calculator").value("code").toString(), "DISK_FULL");
        QCOMPARE(state(store, "calculator").value("diskSpace").toMap().value("missingBytes").toInt(), 123456);
    }

};
int main(int argc, char **argv)
{
    QDir().mkpath("tmp");
    QTemporaryDir fixture(QDir::currentPath() + "/tmp/independent-apps-XXXXXX");
    if (!fixture.isValid()) return 1;
    const auto environment = [&](const char *name, const QString &part) {
        const auto path = fixture.path() + '/' + part;
        QDir().mkpath(path);
        qputenv(name, path.toUtf8());
    };
    environment("HOME", "home");
    environment("TMPDIR", "temporary");
    environment("XDG_DATA_HOME", "data");
    environment("XDG_STATE_HOME", "state");
    environment("XDG_CACHE_HOME", "cache");
    environment("XDG_CONFIG_HOME", "config");
    environment("XDG_DATA_DIRS", "system-data");
    environment("FLATPAK_USER_DIR", "flatpak-user");
    environment("FLATPAK_SYSTEM_DIR", "flatpak-system");
    environment("FLATPAK_CONFIG_DIR", "flatpak-config");
    QCoreApplication application(argc, argv);
    IndependentAppsTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "independent.moc"
