#include "app/update_service.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QLibrary>
#include <QSettings>
#include <QSignalSpy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTest>
#include <QThread>
#include <atomic>
#include <windows.h>

namespace listenfree {
class UpdateServiceTests : public QObject {
    Q_OBJECT
    QTcpServer server;
    QByteArray payload, publicKey, signature;
    QByteArray version = "9.0.0";
    bool tamper = false, holdDownload = false;
    int downloads = 0;
    QString registryPath;
    static QByteArray fixture(const char *name) {
        QFile f(QString::fromUtf8(UPDATE_FIXTURE_DIR) + '/' + name);
        if (!f.open(QIODevice::ReadOnly)) return {};
        return f.readAll();
    }
    QByteArray feed() const {
        return "<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><title>Test</title><item><title>Test</title><sparkle:version>"
            + version + "</sparkle:version><enclosure url=\"http://127.0.0.1:"
            + QByteArray::number(server.serverPort()) + "/setup.exe\" length=\""
            + QByteArray::number(payload.size()) + "\" type=\"application/octet-stream\" sparkle:os=\"windows-x64\" sparkle:edSignature=\""
            + signature + "\"/></item></channel></rss>";
    }
    UpdateService::Configuration configuration() const {
        auto c = UpdateService::productionConfiguration();
        c.feedUrl = QString("http://127.0.0.1:%1/appcast.xml").arg(server.serverPort());
        c.publicKey = QString::fromLatin1(publicKey);
        c.version = "0.3.3";
        c.registryPath = registryPath;
        c.appDirectory = "C:/ListenFree 测试路径/portable app";
        c.portable = true;
        return c;
    }
    void startAutomaticDownload(UpdateService &service) {
        QString error;
        QVERIFY2(service.initialize(&error), qPrintable(error));
        QLibrary dll(configuration().libraryPath);
        auto run = reinterpret_cast<void(__cdecl *)()>(dll.resolve("win_sparkle_check_update_with_ui_and_install"));
        QVERIFY(run);
        run(); // Test only: installation is intercepted, never executes a file.
    }
private slots:
    void initTestCase() {
        payload = fixture("payload.txt");
        publicKey = fixture("public-key.txt").trimmed();
        signature = fixture("signature.txt").trimmed();
        QVERIFY(!payload.isEmpty());
        QVERIFY(server.listen(QHostAddress::LocalHost));
        registryPath = QString("Software\\ListenFreeUpdaterTests\\%1").arg(QCoreApplication::applicationPid());
        connect(&server, &QTcpServer::newConnection, this, [this] {
            while (server.hasPendingConnections()) {
                auto *s = server.nextPendingConnection();
                connect(s, &QTcpSocket::readyRead, this, [this, s] {
                    auto request = s->property("request").toByteArray() + s->readAll();
                    s->setProperty("request", request);
                    if (!request.contains("\r\n\r\n") || s->property("sent").toBool()) return;
                    s->setProperty("sent", true);
                    if (request.startsWith("GET /setup.exe")) {
                        ++downloads;
                        if (holdDownload) {
                            s->write("HTTP/1.1 200 OK\r\nContent-Length: 100000000\r\n\r\nx");
                            return;
                        }
                        auto bytes = payload;
                        if (tamper) bytes[0] = '?';
                        s->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(bytes.size()) + "\r\nConnection: close\r\n\r\n" + bytes);
                    } else {
                        const auto bytes = feed();
                        s->write("HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: " + QByteArray::number(bytes.size()) + "\r\nConnection: close\r\n\r\n" + bytes);
                    }
                    s->disconnectFromHost();
                });
            }
        });
    }
    void cleanupTestCase() {
        QSettings registry("HKEY_CURRENT_USER\\" + registryPath, QSettings::NativeFormat);
        registry.remove("");
    }
    void missingLibrary() {
        auto c = configuration(); c.libraryPath += ".missing";
        UpdateService service(c);
        QString error;
        QVERIFY(!service.check(&error)); QVERIFY(!error.isEmpty());
        QVERIFY(!service.loaded());
    }
    void currentVersion() {
        version = "0.3.3";
        QVERIFY(!GetModuleHandleW(L"WinSparkle.dll"));
        UpdateService service(configuration());
        QVERIFY(!service.loaded());
        QVERIFY(!GetModuleHandleW(L"WinSparkle.dll"));
        QSignalSpy latest(&service, &UpdateService::noUpdateFound);
        QVERIFY(service.check());
        QTRY_COMPARE_WITH_TIMEOUT(latest.count(), 1, 15000);
        QCOMPARE(downloads, 0);
        QSettings registry("HKEY_CURRENT_USER\\" + registryPath, QSettings::NativeFormat);
        QCOMPARE(registry.value("CheckForUpdates").toInt(), 0);
    }
    void newerVersion() {
        UpdateService service(configuration());
        QSignalSpy found(&service, &UpdateService::updateFound);
        QVERIFY(service.check());
        QTRY_COMPARE_WITH_TIMEOUT(found.count(), 1, 15000);
        QCOMPARE(downloads, 0); // Manual check never starts a download by itself.
    }
    void signedDownload() {
        auto c = configuration();
        std::atomic_bool verified{false};
        c.launchInstaller = [&](const QString &file, const QStringList &args) {
            QFile f(file);
            verified = f.open(QIODevice::ReadOnly) && f.readAll() == payload
                && args.contains("/PORTABLE=1") && args.contains("/UPDATE=1")
                && args.contains("/DIR=C:\\ListenFree 测试路径\\portable app");
            return true;
        };
        UpdateService service(c);
        QSignalSpy shutdown(&service, &UpdateService::shutdownRequested);
        bool mainThread = false;
        connect(&service, &UpdateService::shutdownRequested, this, [&] { mainThread = QThread::currentThread() == thread(); });
        startAutomaticDownload(service);
        QTRY_COMPARE_WITH_TIMEOUT(shutdown.count(), 1, 20000);
        QVERIFY(verified); QVERIFY(mainThread); QCOMPARE(downloads, 1);
    }
    void invalidSignature() {
        tamper = true;
        auto c = configuration();
        std::atomic_bool launched{false};
        c.launchInstaller = [&](const QString &, const QStringList &) { launched = true; return true; };
        UpdateService service(c);
        QSignalSpy errors(&service, &UpdateService::updateError);
        QSignalSpy shutdown(&service, &UpdateService::shutdownRequested);
        startAutomaticDownload(service);
        QTRY_VERIFY_WITH_TIMEOUT(!errors.isEmpty(), 20000);
        QVERIFY(!launched); QCOMPARE(shutdown.count(), 0); QCOMPARE(downloads, 1);
    }
    void cancelledDownload() {
        holdDownload = true;
        auto c = configuration();
        std::atomic_bool launched{false};
        c.launchInstaller = [&](const QString &, const QStringList &) { launched = true; return true; };
        auto service = std::make_unique<UpdateService>(c);
        startAutomaticDownload(*service);
        QTRY_COMPARE_WITH_TIMEOUT(downloads, 1, 15000);
        QElapsedTimer timer; timer.start();
        service.reset(); // Closing the application cancels active work and joins.
        QVERIFY(timer.elapsed() < 5000);
        QVERIFY(!launched);
    }
    void installerArguments() {
        const auto args = UpdateService::installerArguments("C:/应用 空格", false);
        QVERIFY(args.contains("/DIR=C:\\应用 空格"));
        QVERIFY(!args.contains("/PORTABLE=1"));
        QVERIFY(!args.contains("/VERYSILENT"));
    }
};
} // namespace listenfree
QTEST_GUILESS_MAIN(listenfree::UpdateServiceTests)
#include "update_service_tests.moc"
