#include "FlatpakTransactionProcess.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>
#include <cerrno>
#include <csignal>
#include <cstdio>

class FlatpakProcessTest : public QObject {
    Q_OBJECT
private slots:
    void supervision_data()
    {
        QTest::addColumn<QString>("scenario");
        QTest::addColumn<QString>("code");
        QTest::newRow("success") << QString("success") << QString{};
        QTest::newRow("ignored-cancellation") << QString("stall") << QString("CANCELLED");
        QTest::newRow("crash") << QString("crash") << QString("RESULT_UNKNOWN");
        QTest::newRow("malformed-protocol") << QString("malformed") << QString("RESULT_UNKNOWN");
        QTest::newRow("oversized-protocol") << QString("flood") << QString("RESULT_UNKNOWN");
        QTest::newRow("missing-companion") << QString("missing") << QString("RESULT_UNKNOWN");
    }
    void supervision()
    {
        QFETCH(QString, scenario); QFETCH(QString, code);
        QTemporaryDir temporary(QDir::currentPath() + "/tmp/flatpak-process-XXXXXX");
        QVERIFY(temporary.isValid());
        const auto driver = temporary.filePath("supervisor-driver");
        QVERIFY(QFile::copy(QCoreApplication::applicationFilePath(), driver));
        if (scenario != "missing") {
            QFile helper(temporary.filePath("kos-flatpak-worker"));
            QVERIFY(helper.open(QIODevice::WriteOnly | QIODevice::NewOnly));
            const QByteArray script = R"(#!/usr/bin/python3
import json, os, signal, sys, time
request = json.load(sys.stdin)
scenario = request['scenario']
if scenario == 'stall':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print(json.dumps({'type': 'progress', 'status': str(os.getpid()), 'progress': 12}), flush=True)
    time.sleep(60)
elif scenario == 'crash':
    os._exit(7)
elif scenario == 'malformed':
    print('not-json', flush=True)
elif scenario == 'flood':
    print('x' * 70000, flush=True)
else:
    print(json.dumps({'type': 'result', 'result': {}}), flush=True)
)";
            QCOMPARE(helper.write(script), script.size());
            helper.close();
            QVERIFY(helper.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner));
        }
        QProcess process;
        process.start(driver, {"--supervisor-case", scenario});
        QVERIFY(process.waitForStarted(1000));
        QVERIFY(process.waitForFinished(7000));
        QCOMPARE(process.exitStatus(), QProcess::NormalExit);
        QCOMPARE(process.exitCode(), 0);
        const auto result = QJsonDocument::fromJson(process.readAllStandardOutput()).object();
        QCOMPARE(result.value("code").toString(), code);
        QVERIFY(result.value("elapsedMs").toInt() < 5000);
        if (scenario == "stall") {
            const auto pid = result.value("pid").toString().toLongLong();
            QVERIFY(pid > 1);
            errno = 0;
            QCOMPARE(::kill(pid, 0), -1);
            QCOMPARE(errno, ESRCH);
        }
    }
};

int main(int argc, char** argv)
{
    QCoreApplication application(argc, argv);
    if (argc == 3 && QByteArray(argv[1]) == "--supervisor-case") {
        QElapsedTimer elapsed;
        elapsed.start();
        QString pid;
        const QString scenario = QString::fromLocal8Bit(argv[2]);
        const auto result = FlatpakTransactionProcess::run({{"scenario", scenario}},
            [&] { return scenario == "stall" && elapsed.elapsed() > 300; },
            [&](const QString& status, int) { pid = status; });
        auto object = QJsonObject::fromVariantMap(result);
        object["elapsedMs"] = elapsed.elapsed();
        object["pid"] = pid;
        const auto output = QJsonDocument(object).toJson(QJsonDocument::Compact);
        std::puts(output.constData());
        return 0;
    }
    QDir().mkpath("tmp");
    FlatpakProcessTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "flatpak_process.moc"
