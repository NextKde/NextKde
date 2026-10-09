#pragma once

#include "application/ports.h"
#include "domain/domain.h"

#include <QObject>
#include <QFutureWatcher>
#include <QStringList>
#include <atomic>
#include <cstdint>
#include <memory>

namespace listenfree::infrastructure::library {

QStringList musicFileFilters();

struct ScanBatch {
    QVector<domain::Track> tracks;
    QString error;
    std::uint64_t generation{0};
};

using ScanBatchPtr = std::shared_ptr<ScanBatch>;

class LibraryScanner final : public QObject {
    Q_OBJECT
public:
    explicit LibraryScanner(QObject* parent = nullptr);
    ~LibraryScanner() override;

    void start(const QStringList& roots, std::shared_ptr<application::IMetadataReader> metadataReader,
               bool recursive = true,
               std::vector<application::LocalFileFingerprint> knownFiles = {});
    void cancel();

signals:
    void tracksFound(QVector<domain::Track> tracks);
    void finished(bool cancelled);
    void failed(const QString& message);

private:
    QFutureWatcher<ScanBatchPtr> watcher_;
    std::shared_ptr<std::atomic_bool> cancelled_;
    std::uint64_t generation_{0};
};

class BasicMetadataReader final : public application::IMetadataReader {
public:
    std::optional<domain::Track> read(const std::filesystem::path& path) override;
};

class TagLibMetadataReader final : public application::IMetadataReader {
public:
    std::optional<domain::Track> read(const std::filesystem::path& path) override;

private:
    BasicMetadataReader fallback_;
};

class LocalLibraryScannerAdapter final : public QObject, public application::ILocalLibraryScanner {
    Q_OBJECT
public:
    explicit LocalLibraryScannerAdapter(std::unique_ptr<application::IMetadataReader> metadataReader = {},
                                        QObject* parent = nullptr);
    ~LocalLibraryScannerAdapter() override;

    application::ScanId start(const application::ScanRequest& request,
                              application::ScanCallbacks callbacks) override;
    void cancel(application::ScanId id) noexcept override;

private:
    void finish(application::ScanOutcome outcome);

    LibraryScanner scanner_;
    std::shared_ptr<application::IMetadataReader> metadataReader_;
    application::ScanCallbacks callbacks_;
    application::ScanId nextScanId_{1};
    std::optional<application::ScanId> activeScanId_;
    std::string failure_;
};

} // namespace listenfree::infrastructure::library
