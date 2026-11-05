#include "FlatpakCompatibility.h"
#include "FlatpakApps.h"

#include <QCoreApplication>
#include <QDir>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>

class FlatpakCompatibilityTest : public QObject {
    Q_OBJECT
private slots:
    void closePolicyDistinguishesDiscoveryFromTransactions()
    {
        FlatpakApps backend;
        backend.m_activeId = "org.nextks.calendar";
        backend.m_action = "check-update";
        QVERIFY(backend.busy());
        QVERIFY(!backend.hasActiveMutation());
        for (const auto &action : {"install", "update", "uninstall", "remove-retired"}) {
            backend.m_action = action;
            QVERIFY(backend.hasActiveMutation());
            backend.m_verifying = true;
            QVERIFY(backend.hasActiveMutation());
        }
        backend.m_activeId.clear();
        QVERIFY(!backend.hasActiveMutation());
    }
    void incompatibleLibraryStopsBeforeDownload()
    {
        if (FlatpakCompatibility::checkBundleCleanup().isEmpty())
            QSKIP("This library has the upstream fix; rejection is exercised on unpatched installations.");
        FlatpakApps backend;
        QTRY_VERIFY_WITH_TIMEOUT(!backend.querying() && backend.state("org.nextks.calendar").value("known").toBool(), 4000);
        backend.m_updates["org.nextks.calendar"] = QVariantMap{
            {"version", "0.2.0"}, {"commit", QString(64, 'a')}, {"arch", "x86_64"},
            {"available", true}, {"installation", QVariantMap{}}};
        QSignalSpy finished(&backend, &FlatpakApps::operationFinished);
        QVERIFY(backend.install("org.nextks.calendar"));
        QTRY_COMPARE_WITH_TIMEOUT(finished.size(), 1, 10000);
        QCOMPARE(finished.first()[1].toString(), "FLATPAK_INCOMPATIBLE");
        QVERIFY(!backend.busy());
        QVERIFY(backend.state("org.nextks.calendar").value("installations").toList().isEmpty());
        QVERIFY(!QFileInfo::exists(qEnvironmentVariable("XDG_CACHE_HOME") + "/kos-settings/flatpak"));
    }
    void detectsCleanupWithoutDeployment()
    {
        const auto repo = qEnvironmentVariable("FLATPAK_USER_DIR") + "/repo";
        const bool existed = QFileInfo::exists(repo);
        const auto entries = QDir(repo).entryList(QDir::AllEntries | QDir::NoDotAndDotDot);
        QProcess probe;
        probe.start(QCoreApplication::applicationDirPath() + "/kos-apps",
                    {"--probe-flatpak-bundle-cleanup"});
        QVERIFY(probe.waitForStarted(1000));
        QVERIFY(probe.waitForFinished(5000));
        const bool safe = probe.exitStatus() == QProcess::NormalExit && probe.exitCode() == 0;
        if (safe) QCOMPARE(probe.readAllStandardOutput().trimmed(), "KOS_FLATPAK_BUNDLE_CLEANUP_OK");
        const auto result = FlatpakCompatibility::checkBundleCleanup();
        if (safe) QVERIFY2(result.isEmpty(), qPrintable(result.value("message").toString()));
        else {
            QCOMPARE(result.value("code").toString(), "FLATPAK_INCOMPATIBLE");
            QVERIFY(result.value("message").toString().contains("95b70b71"));
        }
        // Neither the standalone probe nor its parent may touch the user's repo.
        QCOMPARE(QFileInfo::exists(repo), existed);
        QCOMPARE(QDir(repo).entryList(QDir::AllEntries | QDir::NoDotAndDotDot), entries);
    }
};

int main(int argc, char** argv)
{
    QDir().mkpath("tmp");
    QTemporaryDir temporary(QDir::currentPath() + "/tmp/flatpak-compatibility-XXXXXX");
    if (!temporary.isValid()) return 1;
    for (const auto* name : {"HOME", "TMPDIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
                            "XDG_STATE_HOME", "FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR"}) {
        const auto path = temporary.filePath(QString::fromLatin1(name));
        if (!QDir().mkpath(path)) return 1;
        qputenv(name, path.toUtf8());
    }
    QCoreApplication application(argc, argv);
    FlatpakCompatibilityTest test;
    return QTest::qExec(&test, argc, argv);
}
#include "flatpak_compatibility.moc"
