#pragma once
#include "controllers.h"
#include "infrastructure/database/database.h"
#include <QFutureWatcher>
#include <atomic>

namespace listenfree::qmlbridge {
class DuplicateService final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString report READ report NOTIFY changed)
    Q_PROPERTY(QVariantList groups READ groups NOTIFY changed)
public:
    DuplicateService(const QString& databasePath,LibraryController& library,QObject* parent=nullptr);
    ~DuplicateService() override;
    bool busy() const { return busy_; }
    QString report() const { return report_; }
    QVariantList groups() const { return groups_; }
    Q_INVOKABLE void analyze();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void merge(bool recycle);
    static QVariantMap analyzeFiles(const QVariantList& files,const std::shared_ptr<std::atomic_bool>& cancel);
    // Caller supplies only rows from the last analysis snapshot.
    static bool unchanged(const QVariantMap& file,const QString& hash,const std::shared_ptr<std::atomic_bool>& cancel);
signals:
    void changed();
    void analysisReady();
    void merged(const QVariantList& redirects);
    void mergeStarting(const QVariantList& groups);
    void notice(const QString& message);
private:
    QString databasePath_,report_;
    LibraryController& library_;
    QVariantList groups_;
    bool busy_{false},merging_{false};
    std::shared_ptr<std::atomic_bool> cancelled_;
    QFutureWatcher<QVariantMap> work_;
};
}
