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
    void fixture(const QByteArray& body)
    {
        QVERIFY(QDir().mkpath(temporary.path() + "/app-store"));
        QFile file(temporary.path() + "/app-store/installer.py");
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("import json,sys,time\nkey=sys.argv[2]\naction=sys.argv[3]\n"
            "ids={'calendar':'org.nextks.calendar','calculator':'org.nextks.calculator','weather':'org.nextks.weather','listenfree':'org.nextkde.ListenFree'}\n"
            "def emit(**kw):\n d=dict(schemaVersion=1,appId=ids[key],action=action,type='result',success=True,code='OK'); d.update(kw); print(json.dumps(d),flush=True)\n");
        file.write(body);
    }
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
        AppStore store(temporary.path());
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
        QVERIFY(!store.catalogError().isEmpty());
        const auto firstRequests = requests;
        store.ensureCatalogFresh();
        QTRY_VERIFY_WITH_TIMEOUT(!store.catalogBusy(), 3000);
        QCOMPARE(requests, firstRequests); // The page timer cannot cause a retry storm.
    }
    void closePolicyKeepsMutationsAndVerificationProtected()
    {
        IndependentApps store(temporary.path());
        store.m_active = 0;
        for (const auto &action : {"status", "check-update", "cleanup-plan"}) {
            store.m_action = action;
            QVERIFY(store.busy());
            QVERIFY(!store.hasActiveMutation());
        }
        for (const auto &action : {"install", "update", "uninstall", "prune"}) {
            store.m_action = action;
            QVERIFY(store.hasActiveMutation());
        }
        store.m_action = "status";
        store.m_verifying = true;
        QVERIFY(store.hasActiveMutation());
        store.m_active = -1;
        QVERIFY(!store.hasActiveMutation());
    }
    void init() { QVERIFY(temporary.isValid()); oldState = qgetenv("XDG_STATE_HOME"); qputenv("XDG_STATE_HOME", (temporary.path()+"/state").toUtf8()); }
    void cleanup() { if (oldState.isNull()) qunsetenv("XDG_STATE_HOME"); else qputenv("XDG_STATE_HOME", oldState); }
    void explicitCancellationWaitsForNativeProcess()
    {
        fixture("time.sleep(10)\nemit()\n");
        IndependentApps store(temporary.path());
        store.start(store.indexOf("calendar"), "update");
        QVERIFY(store.hasActiveMutation());
        store.cancel("calendar");
        QVERIFY(store.hasActiveMutation());
        QTRY_VERIFY_WITH_TIMEOUT(!store.hasActiveMutation(), 4000);
        QCOMPARE(state(store, "calendar").value("code").toString(), "CANCELLED");
    }
    void registryAndLegacyFacade()
    {
        AppStore store(temporary.path());
        QCOMPARE(store.apps().size(), AppCatalog::apps().size());
        QCOMPARE(store.apps()[0].toMap().value("id").toString(), "kmusic");
        QVERIFY(!store.anyBusy());
        store.install("unknown"); QVERIFY(!store.anyBusy());
        QCOMPARE(store.music().value("code").toString(), "");
    }
    void nativeStatusDoesNotAppearAsFlatpakInstallation()
    {
        fixture("emit(details=dict(installed=True,managed=True,currentVersion='1.0'))\n");
        IndependentApps store(temporary.path());
        store.start(store.indexOf("calendar"), "status");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QVERIFY(!state(store, "calendar").value("installed").toBool());
        QVERIFY(!state(store, "calendar").value("managed").toBool());
        QCOMPARE(state(store, "calendar").value("version").toString(), "");
    }
    void protocolMismatch_data()
    {
        QTest::addColumn<QByteArray>("body");
        QTest::newRow("app") << QByteArray("emit(appId='org.nextkde.Weather')\n");
        QTest::newRow("action") << QByteArray("emit(action='uninstall')\n");
        QTest::newRow("duplicate") << QByteArray("emit()\nemit()\n");
        QTest::newRow("malformed") << QByteArray("print('bad json')\n");
        QTest::newRow("false-success") << QByteArray("emit()\nsys.exit(1)\n");
    }
    void protocolMismatch()
    {
        QFETCH(QByteArray, body); fixture(body);
        IndependentApps store(temporary.path());
        // This tests the bundled source protocol, not Flatpak release discovery.
        store.start(store.indexOf("calendar"), "check-update");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QCOMPARE(state(store,"calendar").value("code").toString(), "RESULT_UNKNOWN");
        QCOMPARE(state(store,"weather").value("code").toString(), "");
    }
    void mutationResultMustMatchVerifiedState_data()
    {
        QTest::addColumn<QByteArray>("body");
        QTest::newRow("wrong-success-code") << QByteArray("emit(code='BUILD_FAILED',version='1.0',revision='abc')\n");
        QTest::newRow("wrong-version") << QByteArray("emit(code='INSTALLED',version='1.0' if action=='install' else '2.0',revision='abc',details=dict(installed=True,managed=True,currentVersion='2.0'))\n");
        QTest::newRow("wrong-revision") << QByteArray("emit(code='INSTALLED',version='1.0',revision='abc' if action=='install' else 'def',details=dict(installed=True,managed=True,currentVersion='1.0'))\n");
    }
    void mutationResultMustMatchVerifiedState()
    {
        QFETCH(QByteArray,body); fixture(body);
        IndependentApps store(temporary.path());
        QSignalSpy finished(&store, &IndependentApps::taskFinished);
        store.start(store.indexOf("calendar"), "install");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QCOMPARE(state(store,"calendar").value("code").toString(),"RESULT_UNKNOWN");
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished.first()[0].toString(), "Calendar");
        QCOMPARE(finished.first()[1].toString(), "RESULT_UNKNOWN");
    }
    void notificationWaitsForVerificationAndIgnoresQueries()
    {
        fixture("if action=='status': emit(details=dict(installed=True,managed=True,currentVersion='1.0'),version='1.0',revision='abc')\nelse: emit(code='INSTALLED',version='1.0',revision='abc')\n");
        IndependentApps store(temporary.path());
        QSignalSpy finished(&store, &IndependentApps::taskFinished);
        store.start(store.indexOf("calendar"), "status");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QCOMPARE(finished.size(), 0);
        store.start(store.indexOf("calendar"), "install");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QCOMPARE(finished.size(), 1);
        QCOMPARE(finished.first()[1].toString(), "");
    }
    void missingFlatpakDisablesCachedInstallationsAndRecovers()
    {
        IndependentApps store(temporary.path());
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
        IndependentApps store(temporary.path());
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
