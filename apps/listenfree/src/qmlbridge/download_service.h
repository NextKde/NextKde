#pragma once
#include "controllers.h"
#include "infrastructure/database/database.h"
#include "source_controller.h"
#include <QAbstractListModel>
#include <QFile>
#include <QFutureWatcher>
#include <QPointer>
#include <QTimer>
#include <memory>

namespace listenfree::qmlbridge {
class DownloadService final : public QAbstractListModel {
  Q_OBJECT
  Q_PROPERTY(QVariantList tasks READ tasks NOTIFY changed)
  Q_PROPERTY(QAbstractItemModel *taskModel READ taskModel CONSTANT)
public:
  enum Role { TaskIdRole = Qt::UserRole + 1, TitleRole, ArtistRole,
              ArtworkRole, StateRole, ReceivedRole, TotalRole, ErrorRole };
  DownloadService(infrastructure::database::Database &db,
                  SourceController &source, SettingsController &settings,
                  QObject *parent = nullptr);
  ~DownloadService() override;
  QVariantList tasks() const;
  QAbstractItemModel *taskModel() { return this; }
  int rowCount(const QModelIndex &parent = {}) const override;
  QVariant data(const QModelIndex &index, int role) const override;
  QHash<int, QByteArray> roleNames() const override;
  Q_INVOKABLE QVariantList specifications(const QVariantList &tracks) const;
  Q_INVOKABLE void add(const QVariantList &tracks,
                       const QString &quality = "128k");
  Q_INVOKABLE void pause(const QString &id);
  Q_INVOKABLE void resume(const QString &id);
  Q_INVOKABLE void cancel(const QString &id);
  Q_INVOKABLE void pauseAll();
  Q_INVOKABLE void clearRecords();
  Q_INVOKABLE void locate(const QString &id);
  Q_INVOKABLE void deleteFile(const QString &id);
  Q_INVOKABLE void chooseFolder();
signals:
  void fileCompleted(const QString &path);
  void changed();
  void notice(const QString &text);

private:
  struct Task {
    QVariantMap data;
    QString resolution;
    QPointer<SourceController> alternative;
    std::shared_ptr<application::ISettingsRepository> alternativeSettings;
    QSet<QString> tried;
    quint64 attempt{0};
    QPointer<QNetworkReply> reply;
    QFile file;
    qint64 offset{0};
    bool checked{false};
    int row{-1};
    bool progressPending{false};
  };
  infrastructure::database::Database &db_;
  SourceController &source_;
  SettingsController &settings_;
  QNetworkAccessManager network_;
  QList<std::shared_ptr<Task>> jobs_;
  QTimer update_;
  QList<std::weak_ptr<Task>> progressUpdates_;
  std::shared_ptr<Task> find(const QString &id) const;
  void persist(const std::shared_ptr<Task> &task = {});
  void notifyTask(const std::shared_ptr<Task> &task);
  void flushProgress();
  void resolutionFailed(const std::shared_ptr<Task> &task,
                        const QString &reason);
  void pump();
  void start(const std::shared_ptr<Task> &task, const QVariantMap &resolved);
  void drain(const std::shared_ptr<Task> &task);
  void fail(const std::shared_ptr<Task> &task, const QString &reason);
  QList<QFutureWatcher<QString> *> writers_;
  void finalize(const std::shared_ptr<Task> &task);
  void fetchMetadata(const QUrl &url, int limit,
                     std::function<void(QByteArray)> done);
  void detach(const std::shared_ptr<Task> &task);
};
} // namespace listenfree::qmlbridge
