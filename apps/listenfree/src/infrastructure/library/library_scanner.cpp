#include "infrastructure/library/library_scanner.h"

#include <QDirIterator>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QPromise>
#include <QSet>
#include <QtConcurrent/QtConcurrentRun>

#include <taglib/audioproperties.h>
#include <taglib/fileref.h>
#include <taglib/tag.h>

#include <exception>
#include <system_error>

namespace listenfree::infrastructure::library {

QStringList musicFileFilters() {
    return{QStringLiteral("*.mp3"), QStringLiteral("*.flac"), QStringLiteral("*.wav"),
                                  QStringLiteral("*.aac"), QStringLiteral("*.m4a"), QStringLiteral("*.ogg"),
                                  QStringLiteral("*.oga"), QStringLiteral("*.opus"), QStringLiteral("*.wma"),
                                  QStringLiteral("*.ape"), QStringLiteral("*.wv"), QStringLiteral("*.aiff"),
                                  QStringLiteral("*.aif"), QStringLiteral("*.tta"), QStringLiteral("*.mp4")};
}

namespace {
constexpr qsizetype scanBatchSize = 64;
}

LibraryScanner::LibraryScanner(QObject* parent) : QObject(parent) {
    // No pending-results backpressure here: an addResult limit made the worker
    // block on GUI consumption, which could deadlock against start()'s
    // waitForFinished(). Consumers now only forward batches, so the result
    // queue stays bounded by the scan size.
    connect(&watcher_, &QFutureWatcher<ScanBatchPtr>::resultReadyAt, this, [this](int index) {
        const auto batch = watcher_.resultAt(index);
        if (!batch || batch->generation != generation_) return;
        if (!batch->error.isEmpty()) emit failed(batch->error);
        if (!batch->tracks.isEmpty()) emit tracksFound(std::move(batch->tracks));
        batch->tracks.clear();
        batch->tracks.squeeze();
    });
    connect(&watcher_, &QFutureWatcher<ScanBatchPtr>::finished, this, [this] {
        emit finished(cancelled_ && cancelled_->load());
    });
}

LibraryScanner::~LibraryScanner() {
    cancel();
    watcher_.waitForFinished();
}

void LibraryScanner::start(const QStringList& roots,
                           std::shared_ptr<application::IMetadataReader> metadataReader,
                           bool recursive,
                           std::vector<application::LocalFileFingerprint> knownFiles) {
    cancel();
    // Do not replace the watcher future while the previous worker still owns
    // its cancellation token and result buffer. Cancellation is cooperative,
    // so waiting here makes repeated starts deterministic and leak-free.
    watcher_.waitForFinished();
    cancelled_ = std::make_shared<std::atomic_bool>(false);
    const auto token = cancelled_;
    const auto generation = generation_;
    QHash<QString, application::LocalFileFingerprint> known;
    known.reserve(static_cast<qsizetype>(knownFiles.size()));
    for (const auto& file : knownFiles) {
        const QString canonical = QDir::cleanPath(QString::fromStdWString(file.canonicalPath.wstring()));
#ifdef Q_OS_WIN
        const QString key = canonical.toCaseFolded();
#else
        const QString key = canonical;
#endif
        known.insert(key, file);
    }
    watcher_.setFuture(QtConcurrent::run([roots, recursive, token, generation, known = std::move(known),
                                          reader = std::move(metadataReader)](
                                             QPromise<ScanBatchPtr>& promise) {
        if (!reader) {
            auto batch = std::make_shared<ScanBatch>();
            batch->error = QStringLiteral("Metadata reader is not configured.");
            batch->generation = generation;
            promise.addResult(std::move(batch));
            return;
        }

        const auto filters = musicFileFilters();

        auto batch = std::make_shared<ScanBatch>();
        batch->generation = generation;
        batch->tracks.reserve(scanBatchSize);
        QSet<QString> seen;
        const auto flush = [&] {
            if (batch->tracks.isEmpty()) return true;
            if (!promise.addResult(batch)) return false;
            batch = std::make_shared<ScanBatch>();
            batch->generation = generation;
            batch->tracks.reserve(scanBatchSize);
            return true;
        };

        try {
            for (const QString& root : roots) {
                const auto flags = recursive ? QDirIterator::Subdirectories : QDirIterator::NoIteratorFlags;
                QDirIterator it(root, filters, QDir::Files, flags);
                while (it.hasNext()) {
                    if (token->load() || promise.isCanceled()) return;
                    const QFileInfo file(it.next());
                    // Explicitly exclude links: a library scan must not escape a selected root
                    // or index the same target under both its real path and an alias.
                    if (file.isSymLink()) continue;
                    const QString canonical = QDir::cleanPath(file.canonicalFilePath());
                    if (canonical.isEmpty() || !file.isFile()) continue;
#ifdef Q_OS_WIN
                    const QString key = canonical.toCaseFolded();
#else
                    const QString key = canonical;
#endif
                    if (seen.contains(key)) continue;
                    seen.insert(key);
                    const auto knownFile = known.constFind(key);
                    if(knownFile != known.cend() && knownFile->excluded)continue;
                    if (knownFile != known.cend() &&
                        knownFile->sizeBytes == static_cast<quint64>(file.size()) &&
                        knownFile->modifiedMs == file.lastModified().toMSecsSinceEpoch()) {
                        if(knownFile->duplicateHash.empty()) continue;
                        const auto digest=[&](const QString& path) {
                            QFile input(path); QCryptographicHash hash(QCryptographicHash::Sha256);
                            if(!input.open(QIODevice::ReadOnly))return QByteArray{};
                            while(!input.atEnd()) {
                                if(token->load())return QByteArray{};
                                const auto bytes=input.read(1024*1024);if(bytes.isEmpty()&&input.error()!=QFile::NoError)return QByteArray{};
                                hash.addData(bytes);
                            }
                            return hash.result().toHex();
                        };
                        const auto expected=QByteArray::fromStdString(knownFile->duplicateHash);
                        if(digest(canonical)==expected && digest(QString::fromStdWString(knownFile->keeperPath.wstring()))==expected)continue;
                    }
                    const auto path = std::filesystem::path(canonical.toStdWString());
                    if (auto track = reader->read(path)) {
                        const QFileInfo after(canonical);
                        if (after.exists() && after.size() == file.size() && after.lastModified() == file.lastModified())
                            batch->tracks.push_back(std::move(*track));
                    }
                    if (batch->tracks.size() >= scanBatchSize && !flush()) return;
                }
            }
            flush();
        } catch (const std::exception& exception) {
            auto errorBatch = std::make_shared<ScanBatch>();
            errorBatch->error = QString::fromUtf8(exception.what());
            errorBatch->generation = generation;
            promise.addResult(std::move(errorBatch));
        } catch (...) {
            auto errorBatch = std::make_shared<ScanBatch>();
            errorBatch->error = QStringLiteral("Local library scan failed.");
            errorBatch->generation = generation;
            promise.addResult(std::move(errorBatch));
        }
    }));
}

void LibraryScanner::cancel() {
    ++generation_;
    if (cancelled_) cancelled_->store(true);
    if (watcher_.isRunning()) watcher_.cancel();
}

std::optional<domain::Track> BasicMetadataReader::read(const std::filesystem::path& path) {
    std::error_code error;
    const auto canonical = std::filesystem::weakly_canonical(path, error);
    if (error || canonical.empty() || !std::filesystem::is_regular_file(canonical, error) || error) {
        return std::nullopt;
    }
    domain::Track track;
    track.id = domain::TrackId(canonical.string());
    track.title = canonical.stem().string();
    track.localPath = canonical.string();
    return track;
}

std::optional<domain::Track> TagLibMetadataReader::read(const std::filesystem::path& path) {
    auto track = fallback_.read(path);
    if (!track) return std::nullopt;

    std::error_code error;
    const auto canonical = std::filesystem::weakly_canonical(path, error);
    if (error) return track;

#ifdef Q_OS_WIN
    TagLib::FileRef file(canonical.c_str(), true, TagLib::AudioProperties::Fast);
#else
    TagLib::FileRef file(canonical.string().c_str(), true, TagLib::AudioProperties::Fast);
#endif
    if (file.isNull()) return track;

    if (const auto* tag = file.tag()) {
        const auto title = tag->title().to8Bit(true);
        if (!title.empty()) track->title = title;

        const auto artist = tag->artist().to8Bit(true);
        if (!artist.empty()) track->artists = {{artist, artist}};

        const auto album = tag->album().to8Bit(true);
        if (!album.empty()) track->album = domain::Album{album, album, std::nullopt};
    }

    if (const auto* properties = file.audioProperties()) {
        const auto milliseconds = properties->lengthInMilliseconds();
        if (milliseconds > 0) track->duration = std::chrono::milliseconds(milliseconds);
    }

    return track;
}

LocalLibraryScannerAdapter::LocalLibraryScannerAdapter(
    std::unique_ptr<application::IMetadataReader> metadataReader, QObject* parent)
    : QObject(parent), scanner_(this), metadataReader_(std::move(metadataReader)) {
    if (!metadataReader_) metadataReader_ = std::make_unique<TagLibMetadataReader>();
    connect(&scanner_, &LibraryScanner::tracksFound, this, [this](QVector<domain::Track> tracks) {
        if (!activeScanId_ || !callbacks_.onBatch) return;
        std::vector<domain::Track> batch;
        batch.reserve(static_cast<std::size_t>(tracks.size()));
        for (auto& track : tracks) batch.push_back(std::move(track));
        try {
            callbacks_.onBatch(std::move(batch));
        } catch (const std::exception& exception) {
            failure_ = exception.what();
            scanner_.cancel();
        } catch (...) {
            failure_ = "library.scan-batch-callback-failed";
            scanner_.cancel();
        }
    });
    connect(&scanner_, &LibraryScanner::failed, this, [this](const QString& message) {
        if (activeScanId_) failure_ = message.toStdString();
    });
    connect(&scanner_, &LibraryScanner::finished, this, [this](bool cancelled) {
        if (!activeScanId_) return;
        if (!failure_.empty()) {
            finish({application::ScanStatus::Failed, std::move(failure_)});
        } else {
            finish({cancelled ? application::ScanStatus::Cancelled : application::ScanStatus::Completed, {}});
        }
    });
}

LocalLibraryScannerAdapter::~LocalLibraryScannerAdapter() {
    if (activeScanId_) cancel(*activeScanId_);
}

application::ScanId LocalLibraryScannerAdapter::start(const application::ScanRequest& request,
                                                      application::ScanCallbacks callbacks) {
    if (activeScanId_) cancel(*activeScanId_);
    const auto id = nextScanId_++;
    activeScanId_ = id;
    callbacks_ = std::move(callbacks);
    failure_.clear();
    QStringList roots;
    for (const auto& root : request.roots) roots.push_back(QString::fromStdWString(root.wstring()));
    scanner_.start(roots, metadataReader_, request.recursive, request.knownFiles);
    return id;
}

void LocalLibraryScannerAdapter::cancel(application::ScanId id) noexcept {
    if (!activeScanId_ || *activeScanId_ != id) return;
    scanner_.cancel();
    finish({application::ScanStatus::Cancelled, {}});
}

void LocalLibraryScannerAdapter::finish(application::ScanOutcome outcome) {
    auto callback = std::move(callbacks_.onFinished);
    callbacks_ = {};
    activeScanId_.reset();
    failure_.clear();
    if (!callback) return;
    try {
        callback(std::move(outcome));
    } catch (...) {
        // Terminal callbacks are isolated so cancel() remains noexcept and
        // scanner teardown cannot be interrupted by caller code.
    }
}

} // namespace listenfree::infrastructure::library
