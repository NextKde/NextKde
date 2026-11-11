#include "UpdateController.h"

#include <QTest>

// Only the status-file mapping is covered: the agent does the work, and every
// other path here starts a real process.
class UpdateStatusTest : public QObject {
    Q_OBJECT
private slots:
    void mapsAgentStatus();
    void keepsDefaultsForMissingKeys();
    void rejectsInvalidJson();
};

void UpdateStatusTest::mapsAgentStatus()
{
    const QByteArray json = R"({
        "schemaVersion": 1,
        "state": "available",
        "stage": "fetch",
        "startedAt": "2026-11-11T09:59:58Z",
        "branch": "main",
        "upstream": "origin/main",
        "channel": "main",
        "behind": 3,
        "logPath": "/home/user/.local/state/kos/update/agent.log",
        "error": "",
        "needsRestart": false,
        "sourceAhead": true
    })";
    const UpdateController::Status status = UpdateController::statusFromJson(json);
    QVERIFY(status.valid);
    QCOMPARE(status.state, QStringLiteral("available"));
    QCOMPARE(status.stage, QStringLiteral("fetch"));
    QCOMPARE(status.branch, QStringLiteral("main"));
    QCOMPARE(status.upstream, QStringLiteral("origin/main"));
    QCOMPARE(status.channel, QStringLiteral("main"));
    // readStatus compares this with the click time to reject stale results.
    QCOMPARE(status.startedAt, QStringLiteral("2026-11-11T09:59:58Z"));
    QCOMPARE(status.behind, 3);
    QVERIFY(!status.needsRestart);
    QVERIFY(status.sourceAhead);
    QCOMPARE(status.logPath, QStringLiteral("/home/user/.local/state/kos/update/agent.log"));
}

void UpdateStatusTest::keepsDefaultsForMissingKeys()
{
    const UpdateController::Status status
        = UpdateController::statusFromJson(R"({"schemaVersion": 1})");
    QVERIFY(status.valid);
    QCOMPARE(status.state, QStringLiteral("idle"));
    QVERIFY(status.stage.isEmpty());
    QCOMPARE(status.behind, 0);
    QVERIFY(!status.needsRestart);
    QVERIFY(status.error.isEmpty());
}

void UpdateStatusTest::rejectsInvalidJson()
{
    for (const QByteArray &bytes : {QByteArray(), QByteArray("not json"), QByteArray("[]"),
             QByteArray("null")}) {
        const UpdateController::Status status = UpdateController::statusFromJson(bytes);
        QVERIFY2(!status.valid, bytes.constData());
        QCOMPARE(status.state, QStringLiteral("idle"));
    }
}

QTEST_GUILESS_MAIN(UpdateStatusTest)
#include "UpdateStatusTest.moc"
