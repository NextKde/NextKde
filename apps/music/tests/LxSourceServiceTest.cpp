#include "LxSourceService.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtTest>

namespace {

bool writeSource(const QString &path, const QString &name,
                 const QString &url, int delayMs)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    const QString script = QStringLiteral(R"JS(/*
 * @name %1
 * @version 1.0.0
 * @description Lifecycle integration fixture
 */
const { EVENT_NAMES, on, send } = lx
on(EVENT_NAMES.request, ({ source, action, info }) =>
  new Promise(resolve => setTimeout(() => resolve("%2"), %3)))
send(EVENT_NAMES.inited, {
  sources: {
    wy: {
      name: "%1",
      type: "music",
      actions: ["musicUrl"],
      qualitys: ["128k", "320k"]
    }
  }
})
)JS").arg(name, url, QString::number(delayMs));
    return file.write(script.toUtf8()) == script.toUtf8().size();
}

QString sourceId(const QVariantList &sources, const QString &name)
{
    for (const QVariant &value : sources) {
        const QVariantMap source = value.toMap();
        if (source.value(QStringLiteral("name")).toString() == name)
            return source.value(QStringLiteral("id")).toString();
    }
    return {};
}

} // namespace

class LxSourceServiceTest final : public QObject {
    Q_OBJECT

private slots:
    void switchesSourcesCancelsPendingAndPersists();
    void replacingPendingImportDoesNotCrash();
};

void LxSourceServiceTest::switchesSourcesCancelsPendingAndPersists()
{
    QTemporaryDir dataDirectory;
    QTemporaryDir scriptDirectory;
    QVERIFY(dataDirectory.isValid());
    QVERIFY(scriptDirectory.isValid());

    const QString firstPath = scriptDirectory.filePath(QStringLiteral("first.js"));
    const QString secondPath = scriptDirectory.filePath(QStringLiteral("second.js"));
    QVERIFY(writeSource(firstPath, QStringLiteral("Fixture A"),
                        QStringLiteral("https://audio.test/a.mp3"), 1200));
    QVERIFY(writeSource(secondPath, QStringLiteral("Fixture B"),
                        QStringLiteral("https://audio.test/b.mp3"), 10));

    QString secondId;
    {
        LxSourceService service(dataDirectory.path());
        QSignalSpy failures(&service, &LxSourceService::resolveFailed);
        QSignalSpy resolved(&service, &LxSourceService::resolved);

        service.importSource(firstPath);
        QTRY_COMPARE_WITH_TIMEOUT(service.state(), QStringLiteral("ready"), 5000);
        QCOMPARE(service.sources().size(), 1);
        QCOMPARE(service.availableQualities(),
                 QStringList({QStringLiteral("128k"), QStringLiteral("320k")}));

        service.resolve(42, QStringLiteral("wy"), QStringLiteral("{}"),
                        QStringLiteral("128k"));
        QTest::qWait(50);
        service.importSource(secondPath);
        QTRY_COMPARE_WITH_TIMEOUT(service.state(), QStringLiteral("ready"), 5000);
        QTRY_COMPARE_WITH_TIMEOUT(failures.size(), 1, 3000);
        QCOMPARE(failures.first().at(0).toLongLong(), qint64(42));
        QVERIFY(!failures.first().at(1).toString().isEmpty());

        QCOMPARE(service.sources().size(), 2);
        secondId = sourceId(service.sources(), QStringLiteral("Fixture B"));
        QVERIFY(!secondId.isEmpty());
        QCOMPARE(service.activeSourceId(), secondId);
        QCOMPARE(service.availableQualities(),
                 QStringList({QStringLiteral("128k"), QStringLiteral("320k")}));

        service.resolve(43, QStringLiteral("wy"), QStringLiteral("{}"),
                        QStringLiteral("320k"));
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 5000);
        QCOMPARE(resolved.first().at(0).toLongLong(), qint64(43));
        QCOMPARE(resolved.first().at(1).toUrl(),
                 QUrl(QStringLiteral("https://audio.test/b.mp3")));
    }

    {
        LxSourceService restored(dataDirectory.path());
        QCOMPARE(restored.sources().size(), 2);
        QCOMPARE(restored.activeSourceId(), secondId);
        QTRY_COMPARE_WITH_TIMEOUT(restored.state(), QStringLiteral("ready"), 5000);
        QSignalSpy resolved(&restored, &LxSourceService::resolved);
        restored.resolve(44, QStringLiteral("wy"), QStringLiteral("{}"));
        restored.cancelResolves();
        restored.resolve(44, QStringLiteral("wy"), QStringLiteral("{}"));
        QTRY_COMPARE_WITH_TIMEOUT(resolved.size(), 1, 5000);
        QTest::qWait(100);
        QCOMPARE(resolved.size(), 1);
        restored.removeSource(secondId);
        QCOMPARE(restored.state(), QStringLiteral("inactive"));
        QCOMPARE(restored.sources().size(), 1);
        QVERIFY(restored.activeSourceId().isEmpty());
    }
}

void LxSourceServiceTest::replacingPendingImportDoesNotCrash()
{
    QTemporaryDir directory;
    const QString scriptPath = directory.filePath(QStringLiteral("replacement.js"));
    QVERIFY(writeSource(scriptPath, QStringLiteral("Replacement"), QStringLiteral("https://audio.test/file.mp3"), 0));
    QFile script(scriptPath);
    QVERIFY(script.open(QIODevice::ReadOnly));
    const QByteArray body = script.readAll();
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost));
    int requests = 0;
    connect(&server, &QTcpServer::newConnection, this, [&] {
        while (auto *socket = server.nextPendingConnection()) {
            connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QTcpSocket::readyRead, socket, [&, socket] {
                const QByteArray request = socket->readAll();
                if (socket->property("received").toBool()) return;
                socket->setProperty("received", true);
                ++requests;
                if (request.contains("/replacement")) {
                    socket->write("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: "
                        + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                    socket->disconnectFromHost();
                }
            });
        }
    });
    LxSourceService service(directory.filePath(QStringLiteral("data")));
    const QString base = QStringLiteral("http://127.0.0.1:%1/").arg(server.serverPort());
    service.importSource(base + QStringLiteral("hang"));
    QTRY_COMPARE(requests, 1);
    QSignalSpy errors(&service, &LxSourceService::errorMessageChanged);
    service.importSource(base + QStringLiteral("replacement"));
    QTRY_COMPARE_WITH_TIMEOUT(service.state(), QStringLiteral("ready"), 5000);
    QCOMPARE(requests, 2);
    QCOMPARE(errors.size(), 0);
    QCOMPARE(service.sources().size(), 1);
    QVERIFY(!sourceId(service.sources(), QStringLiteral("Replacement")).isEmpty());
}

QTEST_GUILESS_MAIN(LxSourceServiceTest)

#include "LxSourceServiceTest.moc"
