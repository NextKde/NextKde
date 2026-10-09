#pragma once

#include "application/ports.h"
#include "online/bilibili_client.h"
#include "sourcehost/source_protocol.h"
#include "sourcehost/sourcehost_client.h"

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

namespace listenfree::qmlbridge {

class SourceController final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantList sources READ sources NOTIFY sourcesChanged)
  Q_PROPERTY(QString activeId READ activeId NOTIFY activeChanged)
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString lastError READ lastError NOTIFY errorChanged)
  Q_PROPERTY(bool hostAvailable READ hostAvailable NOTIFY hostChanged)
  Q_PROPERTY(bool hostReady READ hostReady NOTIFY hostChanged)
  Q_PROPERTY(QString hostState READ hostState NOTIFY hostChanged)

public:
  explicit SourceController(application::ISettingsRepository *settings = nullptr,
                            QObject *parent = nullptr);
  // Production startup passes the adjacent SourceHost executable and enables
  // the isolated JavaScript runtime.  The two-argument constructor remains a
  // persistence-only controller for tests and demo/capture runs.
  explicit SourceController(application::ISettingsRepository *settings,
                            const QString &hostExecutablePath,
                            bool enableHost,
                            QObject *parent = nullptr);
  ~SourceController() override;

  QVariantList sources() const { return sources_; }
  online::BilibiliClient& bilibili() { return bilibili_; }
  QString activeId() const { return activeId_; }
  bool busy() const noexcept { return busy_; }
  QString status() const { return status_; }
  QString lastError() const { return error_; }
  bool hostAvailable() const noexcept { return hostAvailable_; }
  bool hostReady() const noexcept;
  QString hostState() const;

  Q_INVOKABLE bool selectSource(const QString &id);
  Q_INVOKABLE bool removeSource(const QString &id);
  Q_INVOKABLE bool setUpdatePrompt(const QString &id, bool enabled);
  Q_INVOKABLE bool importLocalFile(const QString &path);
  Q_INVOKABLE bool importUrl(const QUrl &url);

  // Resolve requests are asynchronous because a source may perform network
  // I/O inside SourceHost.  The returned id is emitted with the resulting
  // payload through resolutionFinished.
  Q_INVOKABLE QString resolveMusicUrl(const QString &sourceId,
                                      const QString &quality,
                                      const QVariantMap &musicInfo);
  Q_INVOKABLE QString resolveLyric(const QString &sourceId,
                                   const QVariantMap &musicInfo);
  Q_INVOKABLE QString resolvePic(const QString &sourceId,
                                 const QVariantMap &musicInfo);
  Q_INVOKABLE bool cancelResolution(const QString &requestId);
  Q_INVOKABLE void restartHost();
  Q_INVOKABLE void refresh();

signals:
  void updateAvailable(const QString &sourceName, const QString &log, const QUrl &url);
  void sourcesChanged();
  void activeChanged();
  void busyChanged();
  void statusChanged();
  void errorChanged();
  void hostChanged();
  void resolutionFinished(const QString &requestId, const QString &sourceId,
                          const QString &action, const QVariantMap &data,
                          const QString &error);

private slots:
  void finishUrlImport();

private:
  struct PendingResolution {
    QString sourceId;
    QString action;
    QString quality;
  };

  void load();
  void persist();
  void setStatus(const QString &value);
  void setError(const QString &value);
  void initializeHost();
  void loadActivePlugin();
  void handleHostMessage(const sourcehost::SourceMessage &message);
  void handleHostTerminal(
      const QString &requestId,
      sourcehost::SourceHostClient::RequestTerminal terminal);
  void handleHostFailure(const QString &message);
  void updateCustomStatuses();
  void updateSource(const QString &id, const QVariantMap &updates);
  QString hostProviderFor(const QString &sourceId, const QString &action,
                          QString *quality) const;
  QString resolve(const QString &sourceId, const QString &action,
                  const QString &quality, const QVariantMap &musicInfo);
  int indexOf(const QString &id) const;
  QString sourceDirectory() const;

  application::ISettingsRepository *settings_{nullptr};
  QVariantList sources_;
  QString activeId_;
  QString status_;
  QString error_;
  bool busy_{false};
  QNetworkAccessManager network_;
  online::BilibiliClient bilibili_;

  QString hostExecutablePath_;
  bool hostEnabled_{false};
  bool hostAvailable_{false};
  bool restartRequested_{false};
  QString pendingLoadId_;
  QString pendingLoadSourceId_;
  QHash<QString, PendingResolution> pendingResolutions_;
  QHash<QString, QVariantMap> hostSourceInfo_;
  std::unique_ptr<sourcehost::SourceHostClient> host_;
};

} // namespace listenfree::qmlbridge
