#include "AppStore.h"
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtTest>

// Only synthetic installers are executed. Run these tests in a disposable VM.
class AppStoreTest : public QObject {
    Q_OBJECT
    QTemporaryDir temporary;
    QByteArray oldData, oldCache, oldRoot, oldState;
    const QString revision = QString(40, 'a');
    QString cache;
    QString root;

    static void write(const QString& path, const QByteArray& bytes)
    {
        QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        QCOMPARE(file.write(bytes), bytes.size());
    }
    void prepare(const QByteArray& installBody)
    {
        const QByteArray prefix =
            "#!/bin/sh\n"
            "result() { printf '{\"schemaVersion\":1,\"type\":\"result\",\"appId\":\"org.nextkde.KMusic\",\"action\":\"%s\",%s}\\n' \"$1\" \"$2\"; }\n"
            "case \"$1\" in\n"
            "check) result check '\"success\":true,\"code\":\"OK\"';;\n"
            "uninstall) rm -rf \"$KOS_STORE_TEST_ROOT\"; result uninstall '\"success\":true,\"code\":\"OK\"';;\n"
            "status) if [ -f \"$KOS_STORE_TEST_ROOT/current/bin/kmusic\" ]; then installed=true; else installed=false; fi; "
            "result status \"\\\"success\\\":true,\\\"code\\\":\\\"OK\\\",\\\"installed\\\":$installed\";;\n"
            "install)\n";
        const QByteArray script = prefix + installBody + "\n;;\nesac\n";
        const QByteArray implementation = "# synthetic installer fixture\n";
        QJsonObject hashes;
        hashes["install.sh"] = QString::fromLatin1(QCryptographicHash::hash(script, QCryptographicHash::Sha256).toHex());
        hashes["packaging/installer.py"] = QString::fromLatin1(QCryptographicHash::hash(implementation, QCryptographicHash::Sha256).toHex());
        QJsonObject release{{"revision", revision}, {"sha256", hashes}};
        QJsonObject entry{{"appId", "org.nextkde.KMusic"}, {"repository", "https://github.com/NextKde/KMusic"}, {"release", release}};
        write(temporary.path() + "/app-store/catalog.json", QJsonDocument(QJsonObject{{"schemaVersion", 1}, {"kmusic", entry}}).toJson());
        write(cache + "/install.sh", script);
        write(cache + "/packaging/installer.py", implementation);
    }
    static QByteArray progress(const QByteArray& stage)
    {
        return "printf '{\"schemaVersion\":1,\"type\":\"progress\",\"appId\":\"org.nextkde.KMusic\",\"action\":\"install\",\"stage\":\""
            + stage + "\"}\\n'\n";
    }
    static QByteArray countAttempts()
    {
        return "mkdir -p \"$KOS_STORE_TEST_ROOT\"\nprintf x >> \"$KOS_STORE_TEST_ROOT-attempts\"\n";
    }
    int attempts() const
    {
        QFile file(root + "-attempts");
        return file.open(QIODevice::ReadOnly) ? file.readAll().size() : 0;
    }
    QByteArray successBody() const
    {
        return "mkdir -p \"$KOS_STORE_TEST_ROOT/current/bin\"\n"
            "printf '#!/bin/sh\\nexit 0\\n' > \"$KOS_STORE_TEST_ROOT/current/bin/kmusic\"\n"
            "chmod +x \"$KOS_STORE_TEST_ROOT/current/bin/kmusic\"\n"
            "printf '{\"appId\":\"org.nextkde.KMusic\",\"version\":\"" + revision.toUtf8()
            + "\"}' > \"$KOS_STORE_TEST_ROOT/manifest.json\"\n"
            "result install '\"success\":true,\"code\":\"INSTALLED\",\"version\":\"" + revision.toUtf8() + "\"'\n";
    }
private slots:
    void init()
    {
        QVERIFY(temporary.isValid());
        oldData = qgetenv("XDG_DATA_HOME");
        oldCache = qgetenv("XDG_CACHE_HOME");
        oldRoot = qgetenv("KOS_STORE_TEST_ROOT");
        oldState = qgetenv("XDG_STATE_HOME");
        qputenv("XDG_STATE_HOME", (temporary.path() + "/state").toUtf8());
        qputenv("XDG_DATA_HOME", (temporary.path() + "/data").toUtf8());
        qputenv("XDG_CACHE_HOME", (temporary.path() + "/cache").toUtf8());
        root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/kmusic-app";
        qputenv("KOS_STORE_TEST_ROOT", root.toUtf8());
        cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/installers/KMusic/" + revision;
    }
    void cleanup()
    {
        QDir(temporary.path() + "/data").removeRecursively();
        QDir(temporary.path() + "/cache").removeRecursively();
        QDir(temporary.path() + "/app-store").removeRecursively();
        auto restore = [](const char* name, const QByteArray& value) {
            if (value.isNull()) qunsetenv(name); else qputenv(name, value);
        };
        restore("XDG_DATA_HOME", oldData);
        restore("XDG_CACHE_HOME", oldCache);
        restore("KOS_STORE_TEST_ROOT", oldRoot);
        restore("XDG_STATE_HOME", oldState);
    }
    void unpublishedCatalogueCannotInstall()
    {
        AppStore store(temporary.path());
        QVERIFY(!store.music().value("available").toBool());
        store.install();
        QCOMPARE(store.music().value("code").toString(), "RELEASE_UNAVAILABLE");
        QVERIFY(!store.music().value("busy").toBool());
    }
    void installAndUninstall()
    {
        prepare(successBody());
        AppStore store(temporary.path());
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), "");
        QVERIFY(store.music().value("installed").toBool());
        store.uninstall();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), "");
        QVERIFY(!store.music().value("installed").toBool());
    }
    void malformedResult_data()
    {
        QTest::addColumn<QByteArray>("body");
        QTest::newRow("no-result") << QByteArray("exit 0");
        QTest::newRow("nonzero-success") << (successBody() + "exit 1\n");
        QTest::newRow("duplicate") << (successBody() + successBody());
        QTest::newRow("invalid-json") << QByteArray("printf 'not json\\n'");
        QTest::newRow("wrong-app") << QByteArray("printf '{\"schemaVersion\":1,\"type\":\"result\",\"appId\":\"other\",\"action\":\"install\",\"success\":true,\"code\":\"INSTALLED\"}\\n'");
    }
    void malformedResult()
    {
        QFETCH(QByteArray, body);
        prepare(body);
        AppStore store(temporary.path());
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), "RESULT_UNKNOWN");
    }
    void dependencyFailure()
    {
        prepare("result install '\"success\":false,\"code\":\"DEPENDENCY_UNSATISFIED\",\"details\":{\"dependencies\":[{\"id\":\"taglib\",\"required\":\">=1.12\"}]}'\nexit 11");
        AppStore store(temporary.path());
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), "DEPENDENCY_UNSATISFIED");
        QCOMPARE(store.music().value("dependencies").toList().size(), 1);
    }
    void sourceDownloadTimeoutStopsAfterFiveAttempts()
    {
        prepare(countAttempts() + progress("download") + "sleep 30\n" + successBody());
        AppStore store(temporary.path());
        QCOMPARE(store.m_downloadTimeout, 300000);
        store.m_downloadTimeout = 60;
        store.m_retryDelay = 1;
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), "DOWNLOAD_TIMEOUT");
        QCOMPARE(attempts(), 5);
        QVERIFY(!store.m_deadline.isActive());
        QVERIFY(!store.m_retryTimer.isActive());
        QVERIFY(!store.music().value("installed").toBool());
    }
    void sourceDownloadFailureThenSuccess()
    {
        prepare(countAttempts() + progress("download")
            + "if [ $(wc -c < \"$KOS_STORE_TEST_ROOT-attempts\") -lt 3 ]; then\n"
              "result install '\"success\":false,\"code\":\"DOWNLOAD_FAILED\"'\nexit 1\nfi\n"
            + progress("build") + successBody());
        AppStore store(temporary.path());
        store.m_retryDelay = 1;
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(attempts(), 3);
        QCOMPARE(store.music().value("code").toString(), "");
        QVERIFY(store.music().value("installed").toBool());
    }
    void cancelRetryAndStartFresh()
    {
        prepare(countAttempts() + progress("download")
            + "result install '\"success\":false,\"code\":\"DOWNLOAD_FAILED\"'\nexit 1");
        AppStore store(temporary.path());
        store.m_retryDelay = 1000;
        store.install();
        QTRY_COMPARE_WITH_TIMEOUT(store.music().value("stage").toString(), "retry-download", 5000);
        store.cancel();
        QCOMPARE(store.music().value("code").toString(), "CANCELLED");
        QVERIFY(!store.music().value("busy").toBool());
        QVERIFY(!store.m_retryTimer.isActive());
        QCOMPARE(attempts(), 1);
        store.install();
        QTRY_COMPARE_WITH_TIMEOUT(store.music().value("stage").toString(), "retry-download", 5000);
        QCOMPARE(store.music().value("attempt").toInt(), 2); // new operation reset the budget
        store.cancel();
    }
    void neverReplayBuildFailure()
    {
        prepare(countAttempts() + progress("download") + progress("build")
            + "result install '\"success\":false,\"code\":\"DOWNLOAD_FAILED\"'\nexit 1");
        AppStore store(temporary.path());
        store.m_retryDelay = 1;
        store.install();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(attempts(), 1);
        QCOMPARE(store.music().value("code").toString(), "DOWNLOAD_FAILED");
    }
    void repeatedProgressDoesNotExtendDownloadDeadline()
    {
        prepare(progress("download") + "sleep 30\n");
        AppStore store(temporary.path());
        store.install();
        QTRY_COMPARE_WITH_TIMEOUT(store.music().value("stage").toString(), "download", 5000);
        const int remaining = store.m_deadline.remainingTime();
        store.processStage("download");
        QVERIFY(store.m_deadline.remainingTime() <= remaining);
        store.processStage("build");
        QVERIFY(store.m_deadline.remainingTime() > store.m_downloadTimeout);
        store.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
    }
    void bootstrapRecovery_data()
    {
        QTest::addColumn<QString>("mode");
        QTest::addColumn<int>("expectedRequests");
        QTest::addColumn<QString>("expectedCode");
        QTest::newRow("timeout") << QStringLiteral("hang") << 3 << QStringLiteral("DOWNLOAD_TIMEOUT");
        QTest::newRow("server-error") << QStringLiteral("503") << 3 << QStringLiteral("DOWNLOAD_FAILED");
        QTest::newRow("not-found") << QStringLiteral("404") << 1 << QStringLiteral("DOWNLOAD_FAILED");
        QTest::newRow("hash-mismatch") << QStringLiteral("corrupt") << 1 << QStringLiteral("INTEGRITY_FAILED");
        QTest::newRow("recovery") << QStringLiteral("recover") << 3 << QStringLiteral("");
        QTest::newRow("cancel-active") << QStringLiteral("cancel") << 1 << QStringLiteral("CANCELLED");
        QTest::newRow("cancel-backoff") << QStringLiteral("cancel-backoff") << 1 << QStringLiteral("CANCELLED");
    }
    void bootstrapRecovery()
    {
        QFETCH(QString, mode);
        QFETCH(int, expectedRequests);
        QFETCH(QString, expectedCode);
        prepare(successBody());
        QFile script(cache + "/install.sh");
        QVERIFY(script.open(QIODevice::ReadOnly));
        const auto bytes = script.readAll();
        script.close();
        QVERIFY(script.remove()); // require a real HTTP download, served only on loopback
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        int requests = 0;
        connect(&server, &QTcpServer::newConnection, &server, [&] {
            auto* socket = server.nextPendingConnection();
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                auto request = socket->property("request").toByteArray() + socket->readAll();
                socket->setProperty("request", request);
                if (!request.contains("\r\n\r\n") || socket->property("handled").toBool()) return;
                socket->setProperty("handled", true);
                ++requests;
                if (mode == "hang" || mode == "cancel") return;
                const bool success = mode == "recover" && requests == 3;
                const QByteArray body = success ? bytes : QByteArray("failure");
                const QByteArray status = success || mode == "corrupt" ? "200 OK"
                    : mode == "404" ? "404 Not Found" : "503 Unavailable";
                socket->write("HTTP/1.1 " + status + "\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
        AppStore store(temporary.path());
        QCOMPARE(store.m_bootstrapTimeout, 30000);
        store.m_downloadBaseUrl = QStringLiteral("http://127.0.0.1:%1/").arg(server.serverPort());
        store.m_bootstrapTimeout = mode == "cancel" ? 5000 : 150;
        store.m_retryDelay = mode == "cancel-backoff" ? 1000 : 1;
        store.install();
        if (mode == "cancel") {
            QTRY_COMPARE_WITH_TIMEOUT(requests, 1, 5000);
            store.cancel();
        } else if (mode == "cancel-backoff") {
            QTRY_COMPARE_WITH_TIMEOUT(store.music().value("stage").toString(), "retry-bootstrap", 5000);
            store.cancel();
        }
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 5000);
        QCOMPARE(store.music().value("code").toString(), expectedCode);
        QCOMPARE(requests, expectedRequests);
        QVERIFY(!store.m_deadline.isActive());
        QVERIFY(!store.m_retryTimer.isActive());
        QCOMPARE(store.music().value("installed").toBool(), mode == "recover");
    }
    void cancellationAndConcurrentClick()
    {
        prepare(progress("build") + "sleep 30\n" + successBody());
        AppStore store(temporary.path());
        store.install();
        QTRY_COMPARE_WITH_TIMEOUT(store.music().value("stage").toString(), "build", 5000);
        store.uninstall(); // ignored while installing
        QVERIFY(store.music().value("busy").toBool());
        store.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!store.music().value("busy").toBool(), 12000);
        QCOMPARE(store.music().value("code").toString(), "RESULT_UNKNOWN");
        QVERIFY(!store.music().value("installed").toBool());
    }
};
QTEST_GUILESS_MAIN(AppStoreTest)
#include "backend.moc"
