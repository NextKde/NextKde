#include "app/single_instance.h"
#include "app/media_arguments.h"
#include <QFile>
#include <QSignalSpy>
#include <QGuiApplication>
#include <QProcess>
#include <QTemporaryDir>
#include <QTest>
#include <QTimer>
#include <cstdio>
#include <memory>
#include <vector>

using listenfree::SingleInstance;
class SingleInstanceTests final : public QObject {
    Q_OBJECT
private slots:
    void mediaArgumentsResolveUrlsAndSkipOptions() {
        QTemporaryDir directory;
        const auto path = directory.filePath(QString::fromUtf8("歌曲 one.wav"));
        QFile file(path); QVERIFY(file.open(QIODevice::WriteOnly)); file.close();
        const auto previous = QDir::currentPath();
        QVERIFY(QDir::setCurrent(directory.path()));
        const auto paths = listenfree::mediaFilesFromArguments({"--data-dir", path, "--view", path,
            "https://example.invalid/track.mp3", "missing.wav", "歌曲 one.wav", QUrl::fromLocalFile(path).toString()});
        QVERIFY(QDir::setCurrent(previous));
        QCOMPARE(paths, QStringList{path});
    }
    void filesAreRetainedUntilTheWindowIsReady() {
        QTemporaryDir directory;
        const auto first = directory.filePath("first.wav"), second = directory.filePath("second.wav");
        for (const auto& path : {first, second}) { QFile file(path); QVERIFY(file.open(QIODevice::WriteOnly)); }
        SingleInstance instance(directory.path());
        QSignalSpy opened(&instance, &SingleInstance::filesRequested);
        QCOMPARE(instance.acquire({first}), SingleInstance::Result::Primary);
        QProcess client;
        client.start(QCoreApplication::applicationFilePath(), {"--probe", directory.path(), second});
        QTRY_VERIFY_WITH_TIMEOUT(client.state() == QProcess::NotRunning, 6000);
        QCOMPARE(client.exitCode(), 0); QCOMPARE(opened.size(), 0);
        QQuickWindow window; instance.setWindow(&window);
        QCOMPARE(opened.size(), 1);
        QCOMPARE(opened.takeFirst().at(0).toStringList(), (QStringList{first, second}));
        client.start(QCoreApplication::applicationFilePath(), {"--probe", directory.path(), QUrl::fromLocalFile(first).toString()});
        QTRY_VERIFY_WITH_TIMEOUT(client.state() == QProcess::NotRunning, 6000);
        QCOMPARE(client.exitCode(), 0); QCOMPARE(opened.size(), 1);
        QCOMPARE(opened.takeFirst().at(0).toStringList(), QStringList{first});
    }
    void minimizedPresentationIsRestored_data() {
        QTest::addColumn<bool>("fullscreen");
        QTest::newRow("fullscreen") << true;
        QTest::newRow("maximized") << false;
    }
    void minimizedPresentationIsRestored() {
        QFETCH(bool,fullscreen);
        QTemporaryDir directory; SingleInstance instance(directory.path());
        QCOMPARE(instance.acquire(),SingleInstance::Result::Primary);
        QQuickWindow window; instance.setWindow(&window);
        if(fullscreen)window.showFullScreen();else window.showMaximized();
        window.showMinimized();
        QProcess client;client.start(QCoreApplication::applicationFilePath(),{"--probe",directory.path()});
        QTRY_VERIFY_WITH_TIMEOUT(client.state()==QProcess::NotRunning,6000);
        QCOMPARE(client.exitCode(),0);
        QCOMPARE(window.windowState(),fullscreen?Qt::WindowFullScreen:Qt::WindowMaximized);
    }
    void repeatedLaunchesRestoreTheExistingWindow() {
        QTemporaryDir directory;
        SingleInstance instance(directory.path());
        QCOMPARE(instance.acquire(), SingleInstance::Result::Primary);
        QQuickWindow window; instance.setWindow(&window);
        for (int i=0;i<5;++i) {
            window.hide();
            QProcess client;
            client.start(QCoreApplication::applicationFilePath(), {"--probe", directory.path()});
            QTRY_VERIFY_WITH_TIMEOUT(client.state() == QProcess::NotRunning, 6000);
            QCOMPARE(client.exitStatus(), QProcess::NormalExit); QCOMPARE(client.exitCode(), 0);
            QVERIFY(window.isVisible());
        }
    }
    void activationBeforeWindowCreationIsRetained() {
        QTemporaryDir directory; SingleInstance instance(directory.path());
        QCOMPARE(instance.acquire(), SingleInstance::Result::Primary);
        QProcess client; client.start(QCoreApplication::applicationFilePath(), {"--probe", directory.path()});
        QTRY_VERIFY_WITH_TIMEOUT(client.state() == QProcess::NotRunning, 6000);
        QCOMPARE(client.exitCode(),0);
        QQuickWindow window; QVERIFY(!window.isVisible()); instance.setWindow(&window);
        QVERIFY(window.isVisible());
    }
    void concurrentStartupElectsOnePrimary() {
        QTemporaryDir directory;
        std::vector<std::unique_ptr<QProcess>> clients;
        for (int i=0;i<6;++i) {
            auto client=std::make_unique<QProcess>();
            client->start(QCoreApplication::applicationFilePath(), {"--hold",directory.path()});
            clients.push_back(std::move(client));
        }
        int primaries=0;
        for (const auto& client:clients) {
            QTRY_VERIFY_WITH_TIMEOUT(client->state() == QProcess::NotRunning,6000);
            QCOMPARE(client->exitStatus(),QProcess::NormalExit);
            QVERIFY(client->exitCode()==0 || client->exitCode()==77);
            primaries += client->exitCode()==77;
        }
        QCOMPARE(primaries,1);
    }
    void staleOwnerAndSeparateDataDirectories() {
        QTemporaryDir directory, other;
        QProcess owner; owner.start(QCoreApplication::applicationFilePath(),{"--hold",directory.path()});
        QVERIFY(owner.waitForReadyRead(3000)); QCOMPARE(owner.readAllStandardOutput().trimmed(),QByteArray("primary"));
        owner.kill(); QVERIFY(owner.waitForFinished(3000));
        SingleInstance recovered(directory.path()), independent(other.path());
        QCOMPARE(recovered.acquire(),SingleInstance::Result::Primary);
        QCOMPARE(independent.acquire(),SingleInstance::Result::Primary);
    }
};
int main(int argc, char** argv) {
    QGuiApplication app(argc,argv);
    app.setApplicationName("listenfree-single-instance-tests");
    const auto args=app.arguments();
    if (args.size()>2 && (args[1]=="--probe" || args[1]=="--hold")) {
        SingleInstance instance(args[2]);
        const auto result=instance.acquire(listenfree::mediaFilesFromArguments(args.mid(3)));
        if (result==SingleInstance::Result::Forwarded) return 0;
        if (result==SingleInstance::Result::Error) return 2;
        if (args[1]=="--probe") return 77;
        std::puts("primary"); std::fflush(stdout);
        QTimer::singleShot(1800,&app,[&]{app.exit(77);});
        return app.exec();
    }
    SingleInstanceTests tests; return QTest::qExec(&tests,argc,argv);
}
#include "single_instance_tests.moc"
