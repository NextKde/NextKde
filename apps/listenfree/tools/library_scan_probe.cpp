#include "infrastructure/database/database.h"
#include "infrastructure/database/repositories.h"
#include "infrastructure/library/library_scanner.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QTextStream>

#include <map>
#include <memory>

using listenfree::application::ScanStatus;
using listenfree::infrastructure::database::Database;
using listenfree::infrastructure::database::TrackRepository;
using listenfree::infrastructure::library::LocalLibraryScannerAdapter;

namespace {

QString statusText(ScanStatus status) {
    switch (status) {
    case ScanStatus::Completed: return QStringLiteral("completed");
    case ScanStatus::Cancelled: return QStringLiteral("cancelled");
    case ScanStatus::Failed: return QStringLiteral("failed");
    }
    return QStringLiteral("unknown");
}

} // namespace

int main(int argc, char* argv[]) {
    QCoreApplication app(argc, argv);
    const auto arguments = app.arguments();
    if (arguments.size() < 2 || arguments.size() > 3) {
        QTextStream(stderr) << "Usage: listenfree-library-scan-probe <root> [database-path]\n"
                            << "The database defaults to :memory: and is never persisted.\n";
        return 2;
    }

    const QString root = arguments.at(1);
    const QFileInfo rootInfo(root);
    if (!rootInfo.exists() || !rootInfo.isDir()) {
        QTextStream(stderr) << "Scan root is not a directory: " << root << '\n';
        return 2;
    }

    Database database;
    const QString databasePath = arguments.size() == 3 ? arguments.at(2) : QStringLiteral(":memory:");
    if (!database.open(databasePath)) {
        QTextStream(stderr) << "Unable to open scan database: " << databasePath << '\n';
        return 3;
    }
    TrackRepository repository(database);
    LocalLibraryScannerAdapter scanner;
    std::size_t batchCount = 0;
    std::size_t trackCount = 0;
    std::chrono::milliseconds totalDuration{0};
    std::map<QString, std::size_t> extensions;
    bool repositoryFailure = false;

    listenfree::application::ScanRequest request;
    request.roots.push_back(std::filesystem::path(root.toStdWString()));
    request.recursive = true;
    scanner.start(request, {
        [&](std::vector<listenfree::domain::Track> tracks) {
            ++batchCount;
            if (!repository.upsert(tracks)) {
                repositoryFailure = true;
                return;
            }
            for (const auto& track : tracks) {
                ++trackCount;
                totalDuration += track.duration;
                if (track.localPath) {
                    const auto extension = QFileInfo(QString::fromStdString(*track.localPath))
                                                .suffix()
                                                .toLower();
                    ++extensions[extension.isEmpty() ? QStringLiteral("<none>") : extension];
                }
            }
        },
        [&](listenfree::application::ScanOutcome outcome) {
            QTextStream out(stdout);
            out << "root=" << root << '\n'
                << "status=" << statusText(outcome.status) << '\n'
                << "batches=" << batchCount << '\n'
                << "tracks=" << trackCount << '\n'
                << "database_rows=" << database.loadTracks().size() << '\n'
                << "duration_ms=" << totalDuration.count() << '\n';
            out << "extensions=";
            bool first = true;
            for (const auto& [extension, count] : extensions) {
                if (!first) out << ',';
                first = false;
                out << extension << ':' << count;
            }
            out << '\n';
            if (repositoryFailure) {
                out << "error=repository-upsert-failed\n";
                QCoreApplication::exit(1);
            } else if (outcome.status == ScanStatus::Completed) {
                QCoreApplication::exit(0);
            } else {
                if (!outcome.error.empty()) out << "error=" << QString::fromStdString(outcome.error) << '\n';
                QCoreApplication::exit(outcome.status == ScanStatus::Cancelled ? 4 : 1);
            }
        }});

    return app.exec();
}
