#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVirtualObject>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>
#include <qscopeguard.h>

class Notifications final : public QDBusVirtualObject {
public:
    QStringList summaries;
    QString introspect(const QString&) const override {
        return QStringLiteral("<interface name=\"org.freedesktop.Notifications\"><method name=\"Notify\">"
            "<arg type=\"s\" direction=\"in\"/><arg type=\"u\" direction=\"in\"/>"
            "<arg type=\"s\" direction=\"in\"/><arg type=\"s\" direction=\"in\"/>"
            "<arg type=\"s\" direction=\"in\"/><arg type=\"as\" direction=\"in\"/>"
            "<arg type=\"a{sv}\" direction=\"in\"/><arg type=\"i\" direction=\"in\"/>"
            "<arg type=\"u\" direction=\"out\"/></method></interface>");
    }
    bool handleMessage(const QDBusMessage& request, const QDBusConnection& connection) override {
        if (request.member() != "Notify") return false;
        summaries.append(request.arguments().at(3).toString());
        connection.send(request.createReply(QVariantList{uint(summaries.size())}));
        return true;
    }
};

class BackgroundSessionTest : public QObject {
    Q_OBJECT
    Notifications notifications;
    static void write(const QString& path, const QByteArray& content) {
        QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(content), content.size());
    }
private slots:
    void initTestCase() {
        auto bus = QDBusConnection::sessionBus();
        QVERIFY(bus.registerService("org.freedesktop.Notifications"));
        QVERIFY(bus.registerVirtualObject("/org/freedesktop/Notifications", &notifications));
    }
    void survivesCloseAndRelaunch_data() {
        QTest::addColumn<QString>("outcome");
        QTest::addColumn<QString>("summary");
        QTest::newRow("success") << "success" << "Application task completed";
        QTest::newRow("installer-failure") << "failure" << "Application task failed";
        QTest::newRow("verification-failure") << "verification-failure" << "Application task failed";
    }
    void survivesCloseAndRelaunch() {
        QFETCH(QString, outcome);
        QFETCH(QString, summary);
        notifications.summaries.clear();
        QTemporaryDir fixture;
        QVERIFY(fixture.isValid());
        const QString root = fixture.path();
        const QString binary = root + "/bin/kos-settings";
        QVERIFY(QDir().mkpath(root + "/bin"));
        QVERIFY(QFile::copy(QStringLiteral(SETTINGS_EXECUTABLE), binary));
        const QString resources = root + "/share/kos/settings";
        QByteArray qml = R"QML(
import QtQuick
import QtQuick.Controls
import "COMPONENTS_PATH" as Components
ApplicationWindow {
    id: window
    visible: true
    width: 600; height: 400
    property int currentPage: 3
    property string requestedApp: ""
    property bool started: false
    property bool confirmed: false
    property bool hiddenOnce: false
    Components.TaskCompletionNotifications {}
    function revealRequestedApp() {}
    onVisibleChanged: {
        if (visible && hiddenOnce) {
            console.log("REOPENED:" + appStore.music.stage + ":" + currentPage)
            hideAgain.start()
        }
    }
    Timer { id: hideAgain; interval: 50; onTriggered: window.close() }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (!window.started && appStore.music.statusKnown && !appStore.music.flatpak.querying) {
                window.started = true
                appStore.install()
            }
            const plan = appStore.music.flatpak ? appStore.music.flatpak.plan : null
            if (window.started && !window.confirmed && plan && plan.planId && !appStore.anyBusy) {
                window.confirmed = true
                appStore.confirmPlan("kmusic", plan.planId)
            }
            if (!window.hiddenOnce && appStore.music.stage === "confirm-plan") {
                window.close()
                window.hiddenOnce = true
                console.log("CLOSED:" + window.visible + ":" + appStore.music.busy)
            }
        }
    }
    Connections {
        target: appStore
        function onTaskFinished(name, code) {
            console.log("FINISHED:" + code + ":visible=" + window.visible)
        }
    }
}
)QML";
        qml.replace("COMPONENTS_PATH", "file:" + QByteArray(SETTINGS_COMPONENTS));
        write(resources + "/main.qml", qml);
        // The companion uses the real client RPC protocol. No native installer,
        // real Flatpak deployment, external network or host profile is involved.
        const QByteArray worker = R"PY(#!/usr/bin/env python3
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ['BACKGROUND_FIXTURE'])
ids = ['org.nextkde.KMusic', 'org.nextks.calendar', 'org.nextks.calculator', 'org.nextks.weather', 'org.nextkde.ListenFree']
installed = False
def state():
    refs = [dict(scope='user', version='0.2.2', bundleManaged=True, arch='x86_64', branch='stable')] if installed else []
    return dict(known=True, installations=refs, canDiscover=True, publisherConfigured=True)
for line in sys.stdin:
    request = json.loads(line)
    action = request['action']
    response = dict(schemaVersion=1, requestId=request['requestId'], appId=request['appId'], action=action, type='result')
    if action == 'inventory':
        response['result'] = dict(apps={app: state() for app in ids})
    elif action == 'prepare-install':
        response['result'] = dict(state(), plan=dict(planId='background-plan', operation='install'), code='', message='')
    elif action == 'confirm-plan':
        progress = dict(response, type='progress', status='Installing fixture', progress=10)
        print(json.dumps(progress), flush=True)
        while not (root / 'release').exists():
            if not root.exists() or os.getppid() == 1: sys.exit(1)
            time.sleep(.02)
        outcome = os.environ['BACKGROUND_OUTCOME']
        installed = outcome == 'success'
        code = '' if installed else 'FLATPAK_FAILED' if outcome == 'failure' else 'RESULT_UNKNOWN'
        response['result'] = dict(state(), code=code, message='')
    else:
        raise RuntimeError('Unexpected RPC action: ' + action)
    print(json.dumps(response), flush=True)
)PY";
        const QString companion = root + "/bin/kos-flatpak-worker";
        write(companion, worker);
        write(root + "/bin/flatpak", "#!/bin/sh\nexit 0\n");
        const auto executable = QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner;
        QVERIFY(QFile::setPermissions(companion, executable));
        QVERIFY(QFile::setPermissions(root + "/bin/flatpak", executable));
        QVERIFY(QDir().mkpath(root + "/runtime"));
        QFile::setPermissions(root + "/runtime", QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", qEnvironmentVariable("QT_QPA_PLATFORM", "offscreen")); env.insert("QT_QUICK_BACKEND", "software");
        // qml console.log only reaches the pipe when Qt logs to stderr.
        env.insert("QT_FORCE_STDERR_LOGGING", "1");
        env.insert("PATH", root + "/bin:" + env.value("PATH"));
        env.insert("LANG", "C.UTF-8"); env.insert("LC_ALL", "C.UTF-8"); env.insert("LANGUAGE", "en");
        env.insert("XDG_RUNTIME_DIR", root + "/runtime");
        env.insert("XDG_DATA_HOME", root + "/data"); env.insert("XDG_CACHE_HOME", root + "/cache");
        env.insert("XDG_CONFIG_HOME", root + "/config"); env.insert("XDG_STATE_HOME", root + "/state");
        env.insert("KOS_SHELL_DIR", root + "/shell");
        env.insert("BACKGROUND_FIXTURE", root); env.insert("BACKGROUND_OUTCOME", outcome);
        QProcess owner;
        owner.setProcessEnvironment(env); owner.setProcessChannelMode(QProcess::MergedChannels);
        owner.start(binary, {});
        QVERIFY(owner.waitForStarted());
        auto cleanup = qScopeGuard([&] { owner.kill(); owner.waitForFinished(); });
        QByteArray output;
        const auto contains = [&](const QByteArray& text) {
            output += owner.readAll();
            return output.contains(text);
        };
        // Drain the child pipe while waiting: a bare QTRY cadence can miss the
        // console.log lines when the child writes them in one burst.
        QElapsedTimer wait;
        wait.start();
        while (!contains("CLOSED:false:true") && owner.state() != QProcess::NotRunning
               && wait.elapsed() < 15000) {
            owner.waitForReadyRead(50);
        }
        QVERIFY2(contains("CLOSED:false:true"), output.constData());
        QCOMPARE(owner.state(), QProcess::Running);
        QCOMPARE(notifications.summaries.size(), 0);
        QProcess relaunch;
        relaunch.setProcessEnvironment(env);
        relaunch.start(binary, {});
        QVERIFY(relaunch.waitForFinished(5000));
        QCOMPARE(relaunch.exitCode(), 0);
        QTRY_VERIFY(contains("REOPENED:confirm-plan:9"));
        QTest::qWait(100);
        relaunch.start(binary, {QStringLiteral("--page=windows")});
        QVERIFY(relaunch.waitForFinished(5000));
        QCOMPARE(relaunch.exitCode(), 0);
        QTRY_VERIFY(contains("REOPENED:confirm-plan:11"));
        // Close again before completing the child; the same owner must deliver
        // exactly one notification, including failures of final verification.
        QTest::qWait(100);
        write(root + "/release", "go");
        QTRY_VERIFY2_WITH_TIMEOUT(contains("FINISHED:"), output.constData(), 5000);
        QTRY_VERIFY2_WITH_TIMEOUT(notifications.summaries.size() == 1, (output + owner.readAll()).constData(), 6000);
        QCOMPARE(notifications.summaries.first(), summary);
        QTRY_VERIFY(contains(":visible=false"));
        QCOMPARE(owner.state(), QProcess::Running);
        QTest::qWait(100);
        QCOMPARE(notifications.summaries.size(), 1);
    }
};
QTEST_GUILESS_MAIN(BackgroundSessionTest)
#include "session.moc"
