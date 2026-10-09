#pragma once

#include <QObject>
#include <QThread>
#include <QStringList>

#include <atomic>
#include <memory>
#include <utility>
#include <vector>

#include "domain/domain.h"

namespace listenfree::infrastructure::database {
class Database;
class TrackRepository;
}

namespace listenfree::infrastructure::library {

// Mirrors fooyin's worker/scan-writer split (src/core/library/libraryscanwriter.cpp,
// src/utils/worker.cpp): scan batches are handed to a dedicated object living on
// its own thread which owns a secondary SQLite connection, so the GUI thread
// never executes scan SQL. Qt queued connections from the single GUI producer
// keep commit ordering; SQLite WAL (see Database::open) lets the GUI reader run
// concurrently with these writes.
class LibraryScanWriter final : public QObject {
    Q_OBJECT

public:
    explicit LibraryScanWriter(QObject* parent = nullptr);
    ~LibraryScanWriter() override;

    void setAcceptedGeneration(quint64 generation);
    void cancelReconciliation(quint64 generation);

public slots:
    // Queued onto the writer thread; the connection is created and used in
    // one thread, as QSqlDatabase requires. Must be invoked before the first
    // commit (queued invocations from the GUI preserve ordering).
    void initialize(const QString& databasePath);
    void commit(quint64 generation, std::shared_ptr<std::vector<domain::Track>> batch);
    void reconcile(quint64 generation, const QStringList& roots, bool recursive);
    void drain();

signals:
    void committed(quint64 generation, int count);
    void commitFailed(quint64 generation, QString reason);
    void drained();

private:
    bool ensureDatabase();
    QThread thread_;
    std::shared_ptr<std::atomic<quint64>> acceptedGeneration_;
    std::atomic<quint64> cancelledReconciliation_{0};
    quint64 failedGeneration_{0};
    QString databasePath_;
    std::unique_ptr<database::Database> database_;
    std::unique_ptr<database::TrackRepository> repository_;
};

} // namespace listenfree::infrastructure::library
