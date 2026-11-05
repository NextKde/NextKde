#include "AppStore.h"
#include "IndependentApps.h"
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

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
    void init() { QVERIFY(temporary.isValid()); oldState = qgetenv("XDG_STATE_HOME"); qputenv("XDG_STATE_HOME", (temporary.path()+"/state").toUtf8()); }
    void cleanup() { if (oldState.isNull()) qunsetenv("XDG_STATE_HOME"); else qputenv("XDG_STATE_HOME", oldState); }
    void registryAndLegacyFacade()
    {
        AppStore store(temporary.path());
        QCOMPARE(store.apps().size(), 5);
        QCOMPARE(store.apps()[0].toMap().value("id").toString(), "kmusic");
        QVERIFY(!store.anyBusy());
        store.install("unknown"); QVERIFY(!store.anyBusy());
        QCOMPARE(store.music().value("code").toString(), "");
    }
    void offlineStatusAndUpdate()
    {
        fixture("emit(details=dict(installed=True,managed=True,currentVersion='1.0',latestVersion='2.0',updateAvailable=action=='check-update'))\n");
        IndependentApps store(temporary.path());
        store.refresh(); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QCOMPARE(state(store,"calendar").value("version").toString(), "1.0");
        QVERIFY(state(store,"weather").value("managed").toBool());
        store.perform("calendar", "check-update"); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QVERIFY(state(store,"calendar").value("updateAvailable").toBool());
        QVERIFY(!state(store,"weather").value("updateAvailable").toBool());
        fixture("emit(code='INSTALLED' if action=='update' else 'INSTALLED',version='2.0',revision='abc',details=dict(installed=True,managed=True,currentVersion='2.0',latestVersion='2.0',updateAvailable=False))\n");
        QTRY_VERIFY_WITH_TIMEOUT(!store.m_flatpak.querying(), 4000);
        QVERIFY(store.m_flatpak.state("org.nextks.calendar").value("known").toBool());
        store.perform("calendar", "update"); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(), 4000);
        QCOMPARE(state(store,"calendar").value("code").toString(), "");
        QVERIFY(QFileInfo::exists(state(store,"calendar").value("logPath").toString()));
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
        store.start(store.indexOf("calendar"), "install");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QCOMPARE(state(store,"calendar").value("code").toString(),"RESULT_UNKNOWN");
    }
    void networkFailureKeepsOfflineState()
    {
        fixture("if action=='status': emit(details=dict(installed=True,managed=True,currentVersion='1.0'))\nelse: emit(success=False,code='RATE_LIMITED'); sys.exit(1)\n");
        IndependentApps store(temporary.path()); store.refresh(); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QTRY_VERIFY_WITH_TIMEOUT(!store.m_flatpak.querying(), 4000);
        QVERIFY(store.m_flatpak.state("org.nextks.weather").value("known").toBool());
        store.perform("weather","check-update"); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QVERIFY(state(store,"weather").value("installed").toBool());
        QCOMPARE(state(store,"weather").value("version").toString(),"1.0");
        QCOMPARE(state(store,"weather").value("code").toString(),"RATE_LIMITED");
        store.perform("weather","uninstall"); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QCOMPARE(state(store,"weather").value("code").toString(),"RATE_LIMITED");
    }
    void serializationCancellationDeadlineAndExternalOwnership()
    {
        fixture("time.sleep(10)\nemit()\n");
        AppStore facade(temporary.path()); facade.refreshApps(); QVERIFY(facade.anyBusy());
        facade.install(); QCOMPARE(facade.music().value("code").toString(), "");
        facade.checkUpdates("weather"); facade.cancel("weather"); QVERIFY(facade.anyBusy());
        facade.cancel("calendar"); QTRY_VERIFY_WITH_TIMEOUT(!facade.anyBusy(),4000);
        QCOMPARE(facade.apps()[1].toMap().value("code").toString(),"CANCELLED");
        IndependentApps store(temporary.path()); store.m_releaseTimeout=50;
        store.start(store.indexOf("calendar"), "check-update");
        QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        QCOMPARE(state(store,"calendar").value("code").toString(),"OPERATION_TIMEOUT");
        fixture("emit(details=dict(installed=True,managed=False,currentVersion='external'))\n");
        store.m_statusTimeout = 30000;
        store.refresh(); QTRY_VERIFY_WITH_TIMEOUT(!store.busy(),4000);
        store.perform("calendar","uninstall"); QVERIFY(!store.busy());
        store.perform("calendar","update"); QVERIFY(!store.busy());
        store.perform("calendar","install"); QVERIFY(!store.busy());
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
