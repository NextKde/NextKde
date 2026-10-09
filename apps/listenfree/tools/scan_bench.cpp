// Scan benchmark driving the production scan pipeline (LibraryController +
// LibraryScanWriter + LocalLibraryScannerAdapter + Database) to verify the
// Phase 2.1 gate: large-library scanning stays responsive on the main thread
// and scales linearly.
//
// Usage:
//   listenfree-scan-bench --generate <count> <dir> [--keep]
//   listenfree-scan-bench --scan <dir> [--db <path>] [--max-lag <ms>] [--target <count>] [--rescan] [--cancel-after-rows <count>]
//
// Metrics printed as key=value lines; exit code 0 when the gate passes.

#include "application/ports.h"
#include "domain/domain.h"
#include "infrastructure/database/database.h"
#include "infrastructure/database/repositories.h"
#include "infrastructure/library/library_scanner.h"
#include "qmlbridge/controllers.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QFile>
#include <QTemporaryDir>
#include <QTimer>

#include <taglib/fileref.h>
#include <taglib/tag.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>

namespace {

constexpr int kProbeIntervalMs = 16;

QByteArray minimalWav() {
    QByteArray pcm(1600, '\0');
    QByteArray wav;
    wav.reserve(44 + pcm.size());
    auto append = [&wav](const void* value, int size) { wav.append(static_cast<const char*>(value), size); };
    auto appendU32 = [&append](std::uint32_t value) { append(&value, 4); };
    auto appendU16 = [&append](std::uint16_t value) { append(&value, 2); };
    append("RIFF", 4);
    appendU32(static_cast<std::uint32_t>(36 + pcm.size()));
    append("WAVE", 4);
    append("fmt ", 4);
    appendU32(16);
    appendU16(1);
    appendU16(1);
    appendU32(8000);
    appendU32(8000);
    appendU16(1);
    appendU16(8);
    append("data", 4);
    appendU32(static_cast<std::uint32_t>(pcm.size()));
    append(pcm.constData(), pcm.size());
    return wav;
}

bool generateFiles(int count, const QString& dir) {
    if (!QDir().mkpath(dir)) return false;
    for (int index = 0; index < count; ++index) {
        const QString artist = QStringLiteral("Artist %1").arg(index % 40);
        const QString album = QStringLiteral("Album %1").arg(index % 120);
        const QString title = QStringLiteral("Track %1").arg(index, 5, 10, QLatin1Char('0'));
        const QString path = QDir(dir).filePath(QStringLiteral("bench_%1.wav").arg(index, 5, 10, QLatin1Char('0')));
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly)) return false;
        file.write(minimalWav());
        file.close();

        TagLib::FileRef ref(QDir::toNativeSeparators(path).toStdWString().c_str());
        if (ref.isNull()) return false;
        ref.tag()->setTitle(title.toStdWString());
        ref.tag()->setArtist(artist.toStdWString());
        ref.tag()->setAlbum(album.toStdWString());
        if (!ref.save()) return false;
    }
    return true;
}

void report(const char* key, qint64 value) {
    std::printf("%s=%lld\n", key, static_cast<long long>(value));
}

int runScan(const QString& dir, const QString& dbPath, int maxLagMs, int targetCount, bool rescan,
            int cancelAfterRows) {
    listenfree::infrastructure::database::Database database;
    if (!database.open(dbPath)) {
        std::fprintf(stderr, "error=database-open-failed\n");
        return 2;
    }
    listenfree::infrastructure::database::TrackRepository repository(database);
    listenfree::infrastructure::library::LocalLibraryScannerAdapter scanner;
    listenfree::qmlbridge::LibraryController controller(scanner, repository, nullptr, dbPath);
    bool cancelRequested = false;
    if (cancelAfterRows > 0) {
        QObject::connect(&controller, &listenfree::qmlbridge::LibraryController::importedCountChanged,
                         &controller, [&] {
            if (!cancelRequested && controller.importedCount() >= static_cast<quint64>(cancelAfterRows)) {
                cancelRequested = true;
                // Leave the commit notification stack before cancelling the scan.
                QTimer::singleShot(0, &controller, &listenfree::qmlbridge::LibraryController::cancel);
            }
        });
    }

    // Event-loop lag probe: a repeating timer whose drift measures how long
    // the main thread is blocked. UI responsiveness == bounded drift.
    QElapsedTimer clock;
    clock.start();
    qint64 lastTick = 0;
    qint64 maxLag = 0;
    QTimer probe;
    probe.setInterval(kProbeIntervalMs);
    QObject::connect(&probe, &QTimer::timeout, [&] {
        const qint64 now = clock.elapsed();
        maxLag = std::max(maxLag, now - lastTick - kProbeIntervalMs);
        lastTick = now;
    });

    const auto runOnce = [&](bool incremental) {
        const auto beforeRows = static_cast<qint64>(database.loadTracks().size());
        maxLag = 0;
        lastTick = clock.elapsed();
        const qint64 started = clock.elapsed();
        probe.start();
        QEventLoop loop;
        QObject::connect(&controller, &listenfree::qmlbridge::LibraryController::scanningChanged, &loop, [&] {
            if (!controller.scanning()) loop.quit();
        });
        controller.scan({dir});
        if (controller.scanning()) loop.exec();
        probe.stop();
        const qint64 wall = clock.elapsed() - started;
        const qint64 imported = static_cast<qint64>(controller.importedCount());
        const auto stored = static_cast<qint64>(database.loadTracks().size());
        report(incremental ? "rescan_wall_ms" : "scan_wall_ms", wall);
        report(incremental ? "rescan_imported" : "scan_imported", imported);
        report("rows", stored);
        report("cancel_requested", cancelRequested ? 1 : 0);
        report("max_event_loop_lag_ms", maxLag);
        if (imported > 0) {
            const long long rate = static_cast<long long>(imported) * 1000 / std::max<qint64>(wall, 1);
            std::printf("%s=%lld\n", incremental ? "rescan_files_per_s" : "scan_files_per_s", rate);
            const long long projected = wall * targetCount / imported;
            std::printf("%s=%lld\n", incremental ? "rescan_projected_wall_ms_for_target" : "scan_projected_wall_ms_for_target", projected);
        }
        std::printf("last_error=%s\n", controller.lastError().toStdString().c_str());
        // This benchmark keeps its input directory unchanged between passes.
        // An incremental pass should import zero tracks while retaining the DB.
        const bool countsMatch = incremental ? imported == 0 && stored == beforeRows
                                              : stored == beforeRows + imported;
        return controller.lastError().isEmpty() && countsMatch && maxLag <= maxLagMs &&
               (cancelAfterRows <= 0 || cancelRequested);
    };

    const bool firstOk = runOnce(false);
    bool secondOk = true;
    if (rescan) secondOk = runOnce(true);

    report("target_count", targetCount);
    return firstOk && secondOk ? 0 : 1;
}

} // namespace

int main(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);

    QString dir;
    QString dbPath;
    int generateCount = -1;
    int maxLagMs = 33;
    int targetCount = 2000;
    bool rescan = false;
    bool keepGenerated = false;
    int cancelAfterRows = -1;
    for (int index = 1; index < argc; ++index) {
        const QString argument = QString::fromLocal8Bit(argv[index]);
        const auto value = [&]() -> QString {
            return index + 1 < argc ? QString::fromLocal8Bit(argv[++index]) : QString{};
        };
        if (argument == QStringLiteral("--generate")) {
            generateCount = value().toInt();
        } else if (argument == QStringLiteral("--scan")) {
            dir = value();
        } else if (argument == QStringLiteral("--db")) {
            dbPath = value();
        } else if (argument == QStringLiteral("--max-lag")) {
            maxLagMs = value().toInt();
        } else if (argument == QStringLiteral("--target")) {
            targetCount = value().toInt();
        } else if (argument == QStringLiteral("--rescan")) {
            rescan = true;
        } else if (argument == QStringLiteral("--cancel-after-rows")) {
            cancelAfterRows = value().toInt();
        } else if (argument == QStringLiteral("--keep")) {
            keepGenerated = true;
        } else if (dir.isEmpty()) {
            dir = argument;
        }
    }

    if (generateCount >= 0 && dir.isEmpty()) {
        std::fprintf(stderr, "error=generate-needs-dir\n");
        return 2;
    }
    if (generateCount >= 0) {
        const bool ok = generateFiles(generateCount, dir);
        report("generated", ok ? generateCount : -1);
        if (!ok) return 2;
        if (!keepGenerated) return 0;
    }

    if (dir.isEmpty()) {
        std::fprintf(stderr, "usage: listenfree-scan-bench --generate <count> <dir> | --scan <dir> [--db path] [--max-lag ms] [--target count] [--rescan]\n");
        return 2;
    }

    QTemporaryDir dbHolder;
    if (dbPath.isEmpty()) dbPath = dbHolder.filePath(QStringLiteral("bench.sqlite"));
    if (cancelAfterRows > 0 && rescan) {
        std::fprintf(stderr, "error=cancel-and-rescan-need-separate-invocations\n");
        return 2;
    }
    return runScan(dir, dbPath, maxLagMs, targetCount, rescan, cancelAfterRows);
}
