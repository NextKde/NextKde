#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTcpServer>
#include <QTcpSocket>
#include <QtTest>

class LxSourceHostTest : public QObject {
    Q_OBJECT

private slots:
    void resolvesThroughCompatibleScript();
    void parsesJsonResponseBodies();
};

void LxSourceHostTest::resolvesThroughCompatibleScript()
{
    const QString host = qEnvironmentVariable("KOS_MUSIC_SOURCE_HOST_TEST");
    QVERIFY2(!host.isEmpty(), "Source host path was not provided");
    QProcess process;
    process.setProgram(host);
    process.start();
    QVERIFY2(process.waitForStarted(), qPrintable(process.errorString()));

    const QString script = QStringLiteral(R"JS(
        const { EVENT_NAMES, on, send, utils, version, currentScriptInfo } = globalThis.lx;
        if (version !== "2.0.0")
            throw new Error("Unexpected custom source API version");
        if (!currentScriptInfo.rawScript.includes("EVENT_NAMES"))
            throw new Error("Missing raw script metadata");
        if (utils.crypto.md5("test") !== "098f6bcd4621d373cade4e832627b4f6")
            throw new Error("MD5 helper failed");
        if (utils.crypto.md5(utils.buffer.from("test"))
            !== "098f6bcd4621d373cade4e832627b4f6")
            throw new Error("MD5 Buffer helper failed");
        if (utils.crypto.randomBytes(8).length !== 8)
            throw new Error("Random helper failed");
        const key = utils.buffer.from("1234567890abcdef");
        const encrypted = utils.crypto.aesEncrypt(
            utils.buffer.from("payload"), "aes-128-cbc", key, key);
        if (encrypted.length === 0)
            throw new Error("AES helper failed");
        setTimeout(() => {
            on(EVENT_NAMES.request, ({ source, info }) =>
                Promise.resolve(`https://audio.test/${source}/${info.musicInfo.songmid}.mp3`));
            send(EVENT_NAMES.inited, { sources: { wy: { name: "Test", type: "music", actions: ["musicUrl"], qualitys: ["128k"] } } });
        }, 10);
    )JS");
    const QJsonObject load{
        {QStringLiteral("id"), QStringLiteral("load-1")},
        {QStringLiteral("op"), QStringLiteral("load")},
        {QStringLiteral("script"), script},
        {QStringLiteral("info"), QJsonObject{{QStringLiteral("fileName"),
                                               QStringLiteral("test.js")}}},
    };
    process.write(QJsonDocument(load).toJson(QJsonDocument::Compact) + '\n');
    QVERIFY(process.waitForBytesWritten(3000));
    QVERIFY2(process.waitForReadyRead(3000), process.readAllStandardError().constData());
    QJsonObject response = QJsonDocument::fromJson(process.readLine()).object();
    QCOMPARE(response.value(QStringLiteral("id")).toString(), QStringLiteral("load-1"));
    QVERIFY(response.value(QStringLiteral("ok")).toBool());

    const QJsonObject resolve{
        {QStringLiteral("id"), QStringLiteral("resolve-1")},
        {QStringLiteral("op"), QStringLiteral("resolve")},
        {QStringLiteral("request"), QJsonObject{
             {QStringLiteral("source"), QStringLiteral("wy")},
             {QStringLiteral("action"), QStringLiteral("musicUrl")},
             {QStringLiteral("info"), QJsonObject{
                  {QStringLiteral("type"), QStringLiteral("128k")},
                  {QStringLiteral("musicInfo"), QJsonObject{
                       {QStringLiteral("songmid"), QStringLiteral("347230")},
                  }},
             }},
        }},
    };
    process.write(QJsonDocument(resolve).toJson(QJsonDocument::Compact) + '\n');
    QVERIFY(process.waitForBytesWritten(3000));
    QVERIFY2(process.waitForReadyRead(3000), process.readAllStandardError().constData());
    response = QJsonDocument::fromJson(process.readLine()).object();
    QVERIFY2(response.value(QStringLiteral("ok")).toBool(),
             qPrintable(response.value(QStringLiteral("error")).toString()));
    QCOMPARE(response.value(QStringLiteral("result")).toObject()
                 .value(QStringLiteral("url")).toString(),
             QStringLiteral("https://audio.test/wy/347230.mp3"));
    process.terminate();
    QVERIFY(process.waitForFinished(3000));
}

void LxSourceHostTest::parsesJsonResponseBodies()
{
    QTcpServer server;
    QVERIFY(server.listen(QHostAddress::LocalHost, 0));

    const QString host = qEnvironmentVariable("KOS_MUSIC_SOURCE_HOST_TEST");
    QVERIFY2(!host.isEmpty(), "Source host path was not provided");
    QProcess process;
    process.setProgram(host);
    process.start();
    QVERIFY2(process.waitForStarted(), qPrintable(process.errorString()));

    const QString script = QStringLiteral(R"JS(
        const { EVENT_NAMES, request, on, send, utils } = globalThis.lx;
        utils.zlib.deflate(utils.buffer.from("payload")).then(compressed =>
            utils.zlib.inflate(compressed)).then(decompressed => {
            if (utils.buffer.bufToString(decompressed) !== "payload")
                throw new Error("zlib helper failed");
            on(EVENT_NAMES.request, () => new Promise((resolve, reject) => {
                request("http://127.0.0.1:%1/json", {}, (error, response) => {
                    if (error) reject(error);
                    else if (response.body && response.body.url) resolve(response.body.url);
                    else reject(new Error("JSON response body was not parsed"));
                });
            }));
            send(EVENT_NAMES.inited, {
                sources: {
                    wy: {
                        name: "JSON test",
                        type: "music",
                        actions: ["musicUrl"],
                        qualitys: ["128k"]
                    }
                }
            });
        });
    )JS").arg(server.serverPort());
    const QJsonObject load{
        {QStringLiteral("id"), QStringLiteral("load-json")},
        {QStringLiteral("op"), QStringLiteral("load")},
        {QStringLiteral("script"), script},
        {QStringLiteral("info"), QJsonObject{{QStringLiteral("fileName"),
                                               QStringLiteral("json-test.js")}}},
    };
    process.write(QJsonDocument(load).toJson(QJsonDocument::Compact) + '\n');
    QVERIFY(process.waitForBytesWritten(3000));
    QVERIFY2(process.waitForReadyRead(3000), process.readAllStandardError().constData());
    QJsonObject response = QJsonDocument::fromJson(process.readLine()).object();
    QVERIFY2(response.value(QStringLiteral("ok")).toBool(),
             qPrintable(response.value(QStringLiteral("error")).toString()));

    const QJsonObject resolve{
        {QStringLiteral("id"), QStringLiteral("resolve-json")},
        {QStringLiteral("op"), QStringLiteral("resolve")},
        {QStringLiteral("request"), QJsonObject{
             {QStringLiteral("source"), QStringLiteral("wy")},
             {QStringLiteral("action"), QStringLiteral("musicUrl")},
             {QStringLiteral("info"), QJsonObject{
                  {QStringLiteral("type"), QStringLiteral("128k")},
                  {QStringLiteral("musicInfo"), QJsonObject{
                       {QStringLiteral("songmid"), QStringLiteral("185809")},
                  }},
             }},
        }},
    };
    process.write(QJsonDocument(resolve).toJson(QJsonDocument::Compact) + '\n');
    QVERIFY(process.waitForBytesWritten(3000));
    QTRY_VERIFY_WITH_TIMEOUT(server.hasPendingConnections(), 3000);
    QTcpSocket *socket = server.nextPendingConnection();
    QVERIFY(socket != nullptr);
    QVERIFY(socket->bytesAvailable() > 0 || socket->waitForReadyRead(3000));
    socket->readAll();
    const QByteArray body = QByteArray::fromBase64(
        "H4sIAAAAAAAC/6tWKi3KUbJSyigpKSi20tdPLE3JzNcrSS0u0S9ILCpOTdHLLTBWqgUA1fFjxCcAAAA=");
    const QByteArray httpResponse =
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\n"
        "Content-Length: " + QByteArray::number(body.size())
        + "\r\nConnection: close\r\n\r\n" + body;
    socket->write(httpResponse);
    QVERIFY(socket->waitForBytesWritten(3000));
    socket->disconnectFromHost();

    QVERIFY2(process.waitForReadyRead(3000), process.readAllStandardError().constData());
    response = QJsonDocument::fromJson(process.readLine()).object();
    QVERIFY2(response.value(QStringLiteral("ok")).toBool(),
             qPrintable(response.value(QStringLiteral("error")).toString()));
    QCOMPARE(response.value(QStringLiteral("result")).toObject()
                 .value(QStringLiteral("url")).toString(),
             QStringLiteral("https://audio.test/parsed.mp3"));
    process.terminate();
    QVERIFY(process.waitForFinished(3000));
}

QTEST_GUILESS_MAIN(LxSourceHostTest)

#include "LxSourceHostTest.moc"
