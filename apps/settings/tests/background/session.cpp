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
            if (!window.started) { window.started = true; appStore.install() }
            if (!window.hiddenOnce && appStore.music.stage === "build") {
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
        const QByteArray revision(40, 'a');
        const QByteArray script = "#!/bin/sh\nexec python3 \"$(dirname \"$0\")/packaging/installer.py\" \"$@\"\n";
        const QByteArray implementation = R"PY(
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ['BACKGROUND_FIXTURE'])
action = sys.argv[1]
revision = 'a' * 40
def emit(**kw):
    obj = dict(schemaVersion=1, type='result', appId='org.nextkde.KMusic', action=action, success=True, code='OK')
    obj.update(kw)
    print(json.dumps(obj), flush=True)
if action == 'check':
    emit()
elif action == 'install':
    emit(type='progress', stage='build')
    while not (root / 'release').exists(): time.sleep(.02)
    if os.environ['BACKGROUND_OUTCOME'] == 'failure':
        emit(success=False, code='BUILD_FAILED')
        sys.exit(1)
    data = root / 'data/kmusic-app'
    (data / 'current/bin').mkdir(parents=True)
    executable = data / 'current/bin/kmusic'
    executable.write_text('#!/bin/sh\nexit 0\n')
    executable.chmod(0o755)
    (data / 'manifest.json').write_text(json.dumps(dict(appId='org.nextkde.KMusic', version=revision)))
    emit(code='INSTALLED', version=revision)
elif action == 'status':
    emit(installed=os.environ['BACKGROUND_OUTCOME'] != 'verification-failure')
)PY";
        QJsonObject hashes{{"install.sh", QString::fromLatin1(QCryptographicHash::hash(script, QCryptographicHash::Sha256).toHex())},
            {"packaging/installer.py", QString::fromLatin1(QCryptographicHash::hash(implementation, QCryptographicHash::Sha256).toHex())}};
        QJsonObject release{{"revision", QString::fromLatin1(revision)}, {"sha256", hashes}};
        QJsonObject music{{"appId", "org.nextkde.KMusic"}, {"repository", "https://github.com/NextKde/KMusic"}, {"release", release}};
        write(resources + "/app-store/catalog.json", QJsonDocument(QJsonObject{{"schemaVersion", 1}, {"kmusic", music}}).toJson());
        const QString cache = root + "/cache/Quickshell/kos-settings/installers/KMusic/" + QString::fromLatin1(revision);
        write(cache + "/install.sh", script);
        write(cache + "/packaging/installer.py", implementation);
        QVERIFY(QDir().mkpath(root + "/runtime"));
        QFile::setPermissions(root + "/runtime", QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        auto env = QProcessEnvironment::systemEnvironment();
        env.insert("QT_QPA_PLATFORM", qEnvironmentVariable("QT_QPA_PLATFORM", "offscreen")); env.insert("QT_QUICK_BACKEND", "software");
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
        QTRY_VERIFY_WITH_TIMEOUT(contains("CLOSED:false:true") || owner.state() == QProcess::NotRunning, 10000);
        QVERIFY2(contains("CLOSED:false:true"), output.constData());
        QCOMPARE(owner.state(), QProcess::Running);
        QCOMPARE(notifications.summaries.size(), 0);
        QProcess relaunch;
        relaunch.setProcessEnvironment(env);
        relaunch.start(binary, {});
        QVERIFY(relaunch.waitForFinished(5000));
        QCOMPARE(relaunch.exitCode(), 0);
        QTRY_VERIFY(contains("REOPENED:build:9"));
        QTest::qWait(100);
        relaunch.start(binary, {QStringLiteral("--page=windows")});
        QVERIFY(relaunch.waitForFinished(5000));
        QCOMPARE(relaunch.exitCode(), 0);
        QTRY_VERIFY(contains("REOPENED:build:11"));
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
