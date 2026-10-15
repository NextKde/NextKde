#include "SettingsProbeTasks.h"
#include "ShellIpcClient.h"
#include "WallpaperLibrary.h"

#include <QDir>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSemaphore>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <atomic>

namespace {
QString quoted(QString value) { return "'" + value.replace("'", "'\\''") + "'"; }

QString program(const QTemporaryDir& directory, const QString& body)
{
    const QString path = directory.filePath("fake-quickshell");
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(("#!/bin/sh\n" + body + "\n").toUtf8()) < 0)
        qFatal("Could not write IPC fixture");
    file.close();
    if (!file.setPermissions(
            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner))
        qFatal("Could not make IPC fixture executable");
    return path;
}

QStringList lines(const QString& path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return { };
    return QString::fromUtf8(file.readAll()).trimmed().split('\n');
}
}

class BackendModulesTest : public QObject {
    Q_OBJECT
private slots:
    void probeCompletionRunsOnOwnerThread()
    {
        SettingsProbeTasks tasks;
        QThread* owner = QThread::currentThread();
        std::atomic_bool usedWorker = false;
        int completions = 0;
        QVariantMap reply;
        tasks.start(
            [&] {
                usedWorker = QThread::currentThread() != owner;
                return QVariantMap { { "ready", true } };
            },
            [&](const QVariantMap& result) {
                QCOMPARE(QThread::currentThread(), owner);
                reply = result;
                ++completions;
            });
        QTRY_COMPARE(completions, 1);
        QVERIFY(usedWorker);
        QCOMPARE(reply.value("ready").toBool(), true);
    }

    void closingOwnerJoinsBothProbesAndDiscardsReplies()
    {
        QSemaphore started;
        std::atomic_int stopped = 0;
        int completions = 0;
        {
            SettingsProbeTasks tasks;
            for (int i = 0; i < 2; ++i) {
                tasks.start(
                    [&] {
                        started.release();
                        while (!QThread::currentThread()->isInterruptionRequested())
                            QThread::msleep(1);
                        ++stopped;
                        return QVariantMap { { "ready", true } };
                    },
                    [&](const QVariantMap&) { ++completions; });
            }
            QVERIFY(started.tryAcquire(2, 1000));
        }
        QCOMPARE(stopped.load(), 2);
        QCoreApplication::processEvents();
        QCOMPARE(completions, 0);
    }

    void initTestCase()
    {
        QVERIFY(m_storage.isValid());
        qputenv("XDG_DATA_HOME", m_storage.filePath("data").toUtf8());
        qputenv("XDG_CONFIG_HOME", m_storage.filePath("config").toUtf8());
        qputenv("XDG_CACHE_HOME", m_storage.filePath("cache").toUtf8());
    }

    void transportPreservesArgumentsAndEmptyReply()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        const QString log = directory.filePath("arguments");
        const QString executable = program(directory, "printf '%s\\n' \"$@\" > " + quoted(log));
        ShellIpcClient client(executable, { "/checkout/shell" }, 500);
        const QString json = "\"[\\\"wallpaper with space.png\\\"]\"";
        int calls = 0;
        ShellIpcClient::Result result;
        client.request(
            "wallpaper-settings", { "setSlideshow", json }, "failed", [&](const auto& reply) {
                result = reply;
                ++calls;
            });
        QCOMPARE(calls, 0); // Never blocks or invokes a completion inline.
        QTRY_COMPARE(calls, 1);
        QVERIFY(result.error.isEmpty());
        QVERIFY(result.payload.isEmpty()); // A void IPC verb is still success.
        QCOMPARE(result.shellDirectory, "/checkout/shell");
        QCOMPARE(lines(log),
            QStringList({ "--path", "/checkout/shell", "ipc", "call", "wallpaper-settings",
                "setSlideshow", json }));
        QTest::qWait(20);
        QCOMPARE(calls, 1);
    }

    void installedSessionUsesConfigurationName()
    {
        QTemporaryDir directory;
        const QString log = directory.filePath("arguments");
        const QString executable = program(directory, "printf '%s\\n' \"$@\" > " + quoted(log));
        ShellIpcClient client(executable, { ShellIpcClient::installedShellDirectory() }, 500);
        int calls = 0;
        client.request(
            "appearance-settings", { "snapshot" }, "failed", [&](const auto&) { ++calls; });
        QTRY_COMPARE(calls, 1);
        QCOMPARE(lines(log).mid(0, 2), QStringList({ "-c", "kos" }));
    }

    void preferredSessionRetriesBeforeFallback_data()
    {
        QTest::addColumn<QString>("diagnostic");
        QTest::newRow("missing-target") << "Target not found.";
        QTest::newRow("missing-function") << "Function not found.";
        QTest::newRow("missing-arguments") << "Function required to send message.";
    }

    void preferredSessionRetriesBeforeFallback()
    {
        QFETCH(QString, diagnostic);
        QTemporaryDir directory;
        const QString log = directory.filePath("sessions");
        const QString executable = program(directory,
            "printf '%s\\n' \"$2\" >> " + quoted(log)
                + "\nif [ \"$2\" = first ]; then printf '%s\\n' " + quoted(diagnostic)
                + "; else printf '  {\"ready\":true}  \\n'; fi");
        ShellIpcClient client(executable, { "first", "second" }, 500);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("test-target", { }, "failed", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        QTRY_COMPARE(calls, 1);
        QVERIFY(result.error.isEmpty());
        QCOMPARE(result.payload, "{\"ready\":true}");
        QCOMPARE(result.shellDirectory, "second");
        QCOMPARE(lines(log), QStringList({ "first", "first", "second" }));
    }

    void preferredSessionCanRecoverOnRetry()
    {
        QTemporaryDir directory;
        const QString marker = directory.filePath("attempted");
        const QString executable = program(directory,
            "if [ -f " + quoted(marker)
                + " ]; then printf recovered; else "
                  "touch "
                + quoted(marker) + "; printf 'Target not found.'; fi");
        ShellIpcClient client(executable, { "first", "unused-fallback" }, 500);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("snapshot", { }, "failed", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        QTRY_COMPARE(calls, 1);
        QCOMPARE(result.payload, "recovered");
        QCOMPARE(result.shellDirectory, "first");
    }

    void failedExitReportsErrorOnce()
    {
        QTemporaryDir directory;
        const QString executable
            = program(directory, "printf 'Function not found.'\nprintf rejected >&2\nexit 7");
        ShellIpcClient client(executable, { "first", "second" }, 500);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("test-target", { }, "fallback", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        QTRY_COMPARE(calls, 1);
        QVERIFY(result.payload.isEmpty());
        QVERIFY(result.error.contains("rejected"));
        QVERIFY(result.error.contains("test-target"));
        QVERIFY(result.error.contains("second"));
        QTest::qWait(20);
        QCOMPARE(calls, 1);
    }

    void failedStartCompletesOnce()
    {
        ShellIpcClient client("/nonexistent-kos-test-program", { "first", "second" }, 500);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("test-target", { }, "fallback", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        QTRY_COMPARE(calls, 1);
        QVERIFY(result.error.contains("Could not start"));
        QTest::qWait(20);
        QCOMPARE(calls, 1);
    }

    void timeoutKeepsEventLoopResponsive()
    {
        QTemporaryDir directory;
        const QString executable = program(directory, "exec /bin/sleep 5");
        ShellIpcClient client(executable, { "first" }, 30);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("snapshot", { }, "fallback", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        bool eventDelivered = false;
        QTimer::singleShot(0, [&] { eventDelivered = true; });
        QTRY_VERIFY(eventDelivered);
        QTRY_COMPARE(calls, 1);
        QVERIFY(result.error.contains("did not respond"));
    }

    void noCandidatesStillCompletesAsynchronously()
    {
        ShellIpcClient client("unused", { }, 500);
        int calls = 0;
        ShellIpcClient::Result result;
        client.request("snapshot", { }, "unavailable", [&](const auto& reply) {
            result = reply;
            ++calls;
        });
        QCOMPARE(calls, 0);
        QTRY_COMPARE(calls, 1);
        QCOMPARE(result.error, "unavailable");
    }

    void galleryImportDeduplicatesContentAndPreservesNameCollisions()
    {
        QTemporaryDir directory;
        QImage image(24, 24, QImage::Format_RGB32);
        image.fill(Qt::red);
        const QString source = directory.filePath("wallpaper.png");
        const QString duplicate = directory.filePath("same-content.png");
        QVERIFY(image.save(source));
        QVERIFY(image.save(duplicate));
        WallpaperLibrary library;
        QSignalSpy errors(&library, &WallpaperLibrary::errorOccurred);
        const QString imported = library.importGalleryImage(source);
        QVERIFY(!imported.isEmpty());
        QVERIFY(imported != source);
        QCOMPARE(library.importGalleryImage(duplicate), imported);
        QCOMPARE(library.galleryImages().count(), 1);
        image.fill(Qt::blue);
        QVERIFY(QDir(directory.path()).mkdir("other"));
        const QString collision = directory.filePath("other/wallpaper.png");
        QVERIFY(image.save(collision));
        const QString second = library.importGalleryImage(collision);
        QVERIFY(!second.isEmpty());
        QVERIFY(second != imported);
        QCOMPARE(QImage(imported).pixelColor(12, 12), QColor(Qt::red));
        QCOMPARE(QImage(second).pixelColor(12, 12), QColor(Qt::blue));
        QCOMPARE(library.galleryImages().count(), 2);
        QVERIFY(!library.deleteGalleryImage(source));
        QVERIFY(QFile::exists(source));
        QCOMPARE(errors.count(), 1);
    }

    void thumbnailCacheIsAsynchronousAndBakesRoundedAlpha()
    {
        QTemporaryDir directory;
        QImage image(160, 90, QImage::Format_RGB32);
        image.fill(Qt::green);
        const QString source = directory.filePath("thumbnail.png");
        QVERIFY(image.save(source));
        WallpaperLibrary library;
        QSignalSpy ready(&library, &WallpaperLibrary::thumbnailReady);
        QVERIFY(library.wallpaperThumbnail(source, 64, 36, 8, false).isEmpty());
        QVERIFY(library.wallpaperThumbnail(source, 64, 36, 8).isEmpty());
        library.wallpaperThumbnail(source, 64, 36, 8);
        QTRY_COMPARE(ready.count(), 1);
        const QString cached = library.wallpaperThumbnail(source, 64, 36, 8, false);
        QVERIFY(!cached.isEmpty());
        const QImage thumbnail(QUrl(cached).toLocalFile());
        QCOMPARE(thumbnail.size(), QSize(64, 36));
        QCOMPARE(thumbnail.pixelColor(0, 0).alpha(), 0);
        QVERIFY(thumbnail.pixelColor(32, 18).green() > 200);
        QVERIFY(library.wallpaperThumbnail(source, 4096, 36, 8).isEmpty());
        QTest::qWait(20);
        QCOMPARE(ready.count(), 1); // Cache lookup and invalid sizes schedule no work.
    }

private:
    QTemporaryDir m_storage;
};

QTEST_GUILESS_MAIN(BackendModulesTest)
#include "ModulesTest.moc"
