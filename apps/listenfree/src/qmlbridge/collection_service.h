#pragma once
#include "infrastructure/database/database.h"
#include "online/bilibili_client.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QSet>
#include <QDateTime>
#include <functional>

namespace listenfree::qmlbridge {
// LX metadata contract, adapted to Qt Network. SQLite snapshots preserve remote
// identities independently of the local scanner's foreign-keyed track table.
class CollectionService final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged)
  Q_PROPERTY(quint64 likedTracksRevision READ likedTracksRevision NOTIFY likedTracksChanged)
  Q_PROPERTY(
      QVariantList onlinePlaylists READ recommendations NOTIFY discoverChanged)
  Q_PROPERTY(
      QVariantList recommendations READ recommendations NOTIFY discoverChanged)
  Q_PROPERTY(QVariantList charts READ charts NOTIFY discoverChanged)
  Q_PROPERTY(QVariantList tags READ tags NOTIFY discoverChanged)
  Q_PROPERTY(QVariantMap detail READ detail NOTIFY detailChanged)
  Q_PROPERTY(bool busy READ busy NOTIFY discoverChanged)
  Q_PROPERTY(bool detailBusy READ detailBusy NOTIFY detailChanged)
  Q_PROPERTY(QString error READ error NOTIFY discoverChanged)
  Q_PROPERTY(QString platform READ platform WRITE setPlatform NOTIFY platformChanged)
  Q_PROPERTY(QStringList hotSearches READ hotSearches NOTIFY discoverChanged)
  Q_PROPERTY(QVariantList homeRecommendations READ homeRecommendations NOTIFY homeRecommendationsChanged)
  Q_PROPERTY(QVariantList homeCharts READ homeCharts NOTIFY homeChartsChanged)
  Q_PROPERTY(QVariantList homePreviews READ homePreviews NOTIFY homePreviewsChanged)
  Q_PROPERTY(QVariantList dailyTracks READ dailyTracks NOTIFY dailyTracksChanged)
  Q_PROPERTY(QString dailySource READ dailySource NOTIFY dailyTracksChanged)
  Q_PROPERTY(bool homeBusy READ homeBusy NOTIFY homeStateChanged)
  Q_PROPERTY(QString homeError READ homeError NOTIFY homeStateChanged)
public:
  explicit CollectionService(infrastructure::database::Database &db,
                             QObject *parent = nullptr,
                             QNetworkAccessManager *network = nullptr);
  void setBilibiliClient(online::BilibiliClient* client) { bilibili_=client; }
  QVariantList playlists() const { return lists_; }
  quint64 likedTracksRevision() const { return likedTracksRevision_; }
  QVariantList recommendations() const { return recommendations_; }
  QVariantList charts() const { return charts_; }
  QVariantList tags() const { return tags_; }
  QVariantMap detail() const { return detail_; }
  bool busy() const { return requests_ > 0; }
  bool detailBusy() const { return detailBusy_; }
  QString error() const { return error_; }
  QString platform() const { return platform_; }
  QStringList hotSearches() const { return hotSearches_; }
  QVariantList homeRecommendations() const { return homeRecommendations_; }
  QVariantList homeCharts() const { return homeCharts_; }
  QVariantList homePreviews() const { return homePreviews_; }
  QVariantList dailyTracks() const { return dailyTracks_; }
  QString dailySource() const { return dailySource_; }
  bool homeBusy() const { return homeRequests_ > 0; }
  QString homeError() const { return homeError_; }
  Q_INVOKABLE void refreshHome(bool force = false);
  void setPlatform(const QString& value);
  Q_INVOKABLE QString create(const QString &name,
                             const QVariantList &tracks = {});
  Q_INVOKABLE void rename(const QString &id, const QString &name);
  Q_INVOKABLE void remove(const QString &id);
  Q_INVOKABLE void clear();
  Q_INVOKABLE void addTracks(const QString &id, const QVariantList &tracks);
  Q_INVOKABLE void removeTrack(const QString &id, int index);
  Q_INVOKABLE void refresh(const QString &order = "hot");
  Q_INVOKABLE void filter(const QString &key, const QString &value);
  Q_INVOKABLE void open(const QVariantMap &collection);
  Q_INVOKABLE void openTitle(const QString &title);
  Q_INVOKABLE void openLink(const QString &link);
  Q_INVOKABLE void cancelDetail();
  Q_INVOKABLE void releaseDetail();
  Q_INVOKABLE bool isSaved(const QVariantMap &collection) const;
  Q_INVOKABLE void toggleSaved(const QVariantMap &collection);
  Q_INVOKABLE bool isTrackLiked(const QVariantMap &track) const;
  Q_INVOKABLE void toggleTrackLiked(const QVariantMap &track);
  void updateTrackMetadata(const QVariantMap& track);
  void reloadSaved();
signals:
  void homeRecommendationsChanged();
  void homeChartsChanged();
  void homePreviewsChanged();
  void dailyTracksChanged();
  void homeStateChanged();
  void platformChanged();
  void playlistsChanged();
  void likedTracksChanged();
  void discoverChanged();
  void detailChanged();
  void notice(const QString &message);

private:
  infrastructure::database::Database &db_;
  QNetworkAccessManager ownedNetwork_;
  QNetworkAccessManager *network_;
  QVariantList lists_, recommendations_, charts_, tags_;
  QSet<QString> likedTrackKeys_;
  quint64 likedTracksRevision_{0};
  void refreshLikedTrackIndex();
  QVariantList homeRecommendations_, homeCharts_, homePreviews_, dailyTracks_;
  QString homeError_, dailySource_{"网易云每日推荐"};
  QDateTime homeFetchedAt_;
  int homeRequests_{0};
  bool homeSucceeded_{false};
  void finishHomeRequest();
  void loadDailyTracks(bool fallback);
  QHash<QString, QString> tagIds_;
  QString activeTag_, order_{"hot"};
  QString platform_{"kw"};
  QStringList hotSearches_;
  QVariantMap detail_;
  QString error_;
  int requests_{0};
  quint64 discoveryGeneration_{0}, detailGeneration_{0};
  bool detailBusy_{false};
  QPointer<QNetworkReply> detailReply_;
  QStringList detailTrackIds_;
  QHash<QString, QVariantMap> detailTracksById_;
  QSet<QByteArray> detailPageDigests_;
  QPointer<online::BilibiliClient> bilibili_;
  QString bilibiliDetailId_;
  bool save(const QVariantList &lists);
  int index(const QString &id) const;
  void page(int number, quint64 generation);
  void albumPage(int number, quint64 generation);
  void remotePlaylist(quint64 generation);
  void neteaseTracks(int offset, quint64 generation);
  void kugouPage(int number, int received, quint64 generation);
  void finishRemoteDetail(const QString &error = {});
  QNetworkReply *get(const QUrl &url,
                     std::function<void(QJsonObject, QString)> done);
};
} // namespace listenfree::qmlbridge
