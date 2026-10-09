#include "online/platform_catalog.h"
#include "download_service.h"
#include "online/kuwo_lyrics.h"
#include <QDateTime>
#include <QCoreApplication>
#include <QDir>
#include <QFileDialog>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <QtConcurrentRun>
#include <map>
#include <taglib/attachedpictureframe.h>
#include <taglib/fileref.h>
#include <taglib/flacfile.h>
#include <taglib/flacpicture.h>
#include <taglib/id3v2tag.h>
#include <taglib/mpegfile.h>
#include <taglib/tag.h>
#include <taglib/tpropertymap.h>
#include <utility>

namespace listenfree::qmlbridge {
namespace {
class SourceSnapshot final : public application::ISettingsRepository {
public:
  std::map<std::string, std::string> values;
  std::optional<std::string> get(const std::string &key) override {
    auto it = values.find(key);
    return it == values.end() ? std::nullopt : std::optional(it->second);
  }
  bool set(const std::string &key, const std::string &value) override {
    values[key] = value;
    return true;
  }
};
QString filename(QString name) {
  name.replace(QRegularExpression("[<>:\"/\\\\|?*\\x00-\\x1f]"), "_");
  name = name.left(150).trimmed();
  while (name.endsWith('.') || name.endsWith(' '))
    name.chop(1);
  if (name.isEmpty())
    name = "音频";
  if (QRegularExpression("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\\.|$)",
                         QRegularExpression::CaseInsensitiveOption)
          .match(name)
          .hasMatch())
    name.prepend('_');
  return name;
}
bool active(const QString &state) {
  return state == "downloading" || state == "resolving";
}
} // namespace
DownloadService::DownloadService(infrastructure::database::Database &db,
                                 SourceController &source,
                                 SettingsController &settings, QObject *parent)
    : QAbstractListModel(parent), db_(db), source_(source), settings_(settings) {
  const auto saved = QJsonDocument::fromJson(
                         QByteArray::fromStdString(
                             db_.getSetting("downloads.v1").value_or("[]")))
                         .array();
  for (const auto &v : saved) {
    auto task = std::make_shared<Task>();
    task->data = v.toObject().toVariantMap();
    if (task->data.value("state") == "finalizing")
      task->data["state"] = "completed";
    if (active(task->data.value("state").toString()) ||
        task->data.value("state") == "queued")
      task->data["state"] = "paused";
    task->row = int(jobs_.size());
    jobs_.append(task);
  }
  update_.setInterval(250);
  connect(&update_, &QTimer::timeout, this, &DownloadService::flushProgress);
  connect(&source_, &SourceController::resolutionFinished, this,
          [this](const QString &id, const QString &, const QString &,
                 const QVariantMap &data, const QString &error) {
            for (const auto &task : jobs_)
              if (task->resolution == id) {
                task->resolution.clear();
                if (error.isEmpty())
                  start(task, data);
                else
                  resolutionFailed(task, error);
                return;
              }
          });
  connect(&settings_, &SettingsController::valueChanged, this,
          [this](const QString &key, const QVariant &value) {
            Q_UNUSED(value);
            if (key == "download.maxConcurrent")
              pump();
          });
}
DownloadService::~DownloadService() {
  for (auto *writer : writers_)
    writer->waitForFinished();
  pauseAll();
}
QVariantList DownloadService::tasks() const {
  QVariantList rows;
  rows.reserve(jobs_.size());
  for (const auto &t : jobs_)
    rows.append(t->data);
  return rows;
}
int DownloadService::rowCount(const QModelIndex &parent) const {
  return parent.isValid() ? 0 : int(jobs_.size());
}
QVariant DownloadService::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.model() != this || index.column() != 0 ||
      index.row() < 0 || index.row() >= jobs_.size())
    return {};
  const auto &row = jobs_.at(index.row())->data;
  switch (role) {
  case TaskIdRole: return row.value(QStringLiteral("id")).toString();
  case Qt::DisplayRole:
  case TitleRole: return row.value(QStringLiteral("title")).toString();
  case ArtistRole: return row.value(QStringLiteral("artist")).toString();
  case ArtworkRole: return row.value(QStringLiteral("artwork")).toString();
  case StateRole: return row.value(QStringLiteral("state")).toString();
  case ReceivedRole: return row.value(QStringLiteral("received")).toLongLong();
  case TotalRole: return row.value(QStringLiteral("total")).toLongLong();
  case ErrorRole: return row.value(QStringLiteral("error")).toString();
  default: return {};
  }
}
QHash<int, QByteArray> DownloadService::roleNames() const {
  return {{TaskIdRole,"taskId"}, {TitleRole,"title"}, {ArtistRole,"artist"},
          {ArtworkRole,"artwork"}, {StateRole,"taskState"},
          {ReceivedRole,"received"}, {TotalRole,"total"}, {ErrorRole,"errorMessage"}};
}
void DownloadService::notifyTask(const std::shared_ptr<Task> &task) {
  task->progressPending = false;
  // A tag writer can finish after the user cleared the history.
  if (task->row < 0 || task->row >= jobs_.size() || jobs_.at(task->row) != task)
    return;
  const auto row = index(task->row, 0);
  emit dataChanged(row, row);
}
void DownloadService::flushProgress() {
  const auto pending = std::exchange(progressUpdates_, {});
  bool updated = false;
  for (const auto &weak : pending) {
    const auto task = weak.lock();
    if (!task || !task->progressPending)
      continue;
    task->progressPending = false;
    if (task->row < 0 || task->row >= jobs_.size() || jobs_.at(task->row) != task)
      continue;
    const auto row = index(task->row, 0);
    emit dataChanged(row, row, {ReceivedRole, TotalRole});
    updated = true;
  }
  if (updated)
    emit changed(); // Compatibility snapshots; the view uses taskModel.
}
std::shared_ptr<DownloadService::Task>
DownloadService::find(const QString &id) const {
  for (const auto &t : jobs_)
    if (t->data.value("id") == id)
      return t;
  return {};
}
void DownloadService::persist(const std::shared_ptr<Task> &task) {
  if (task)
    notifyTask(task);
  db_.setSetting(
      "downloads.v1",
      QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(tasks()))
                            .toJson(QJsonDocument::Compact)));
  emit changed();
}
QVariantList DownloadService::specifications(const QVariantList &tracks) const {
  if (!tracks.isEmpty() && std::all_of(tracks.cbegin(),tracks.cend(),[](const QVariant& v) { return v.toMap().value("source")=="bili"; }))
    return {QVariantMap{{"value","auto"},{"label","原始音频 · 自动选择可用音质"}}};
  QVariantMap capabilities;
  for (const auto &v : source_.sources()) {
    const auto row = v.toMap();
    if (row.value("id") == source_.activeId() && row.value("hostReady").toBool())
      capabilities = row.value("capabilities").toMap();
  }
  QStringList common;
  bool first = true;
  for (const auto &v : tracks) {
    const auto info = online::sourceMusicInfo(v.toMap());
    const auto capability = capabilities.value(info.value("source").toString()).toMap();
    QStringList available;
    for (const auto &q : capability.value("qualitys").toList()) available.append(q.toString());
    if (first) { common = available; first = false; }
    else for (auto it=common.begin(); it!=common.end();) {
      if (!available.contains(*it)) it=common.erase(it); else ++it;
    }
  }
  QVariantList result;
  const QMap<QString, QString> labels{{"128k", "标准 · MP3 · 128 kbps"}, {"192k", "高音质 · MP3 · 192 kbps"},
    {"320k", "极高音质 · MP3 · 320 kbps"}, {"flac", "无损 · FLAC"}};
  for (const auto &quality : QStringList{"128k","192k","320k","flac"})
    if (common.contains(quality)) result.append(QVariantMap{{"value",quality},{"label",labels.value(quality)}});
  return result;
}
void DownloadService::add(const QVariantList &tracks, const QString &quality) {
  if (!settings_.value("download.enabled", true).toBool()) {
    emit notice("请先在设置中开启下载");
    return;
  }
  for (const auto &value : tracks) {
    auto track = value.toMap();
    if (track.value("rid").toString().isEmpty())
      continue;
    bool duplicate = false;
    for (const auto &t : jobs_)
      if (t->data.value("track").toMap().value("trackId") == track.value("trackId") &&
          t->data.value("state") != "completed" &&
          t->data.value("state") != "cancelled")
        duplicate = true;
    if (duplicate)
      continue;
    auto t = std::make_shared<Task>();
    track.remove("remoteUrl");
    track.remove("resolvedUrl");
    t->data = {{"id", QUuid::createUuid().toString(QUuid::WithoutBraces)},
               {"track", track},
               {"title", track.value("title")},
               {"artist", track.value("artist")},
               {"artwork", track.value("artwork")},
               {"quality", quality},
               {"state", "queued"},
               {"created", QDateTime::currentMSecsSinceEpoch()},
               {"received", 0},
               {"total", 0}};
    beginInsertRows({}, 0, 0);
    for (const auto &existing : jobs_)
      ++existing->row;
    t->row = 0;
    jobs_.prepend(t);
    endInsertRows();
  }
  persist();
  pump();
}
void DownloadService::pump() {
  int count = 0;
  for (const auto &t : jobs_)
    if (active(t->data.value("state").toString()))
      ++count;

  const int limit =
      qBound(1, settings_.value("download.maxConcurrent", 1).toInt(), 8);
  // Start oldest pending first while the visual history is newest first.
  for (auto it = jobs_.crbegin(); it != jobs_.crend() && count < limit; ++it) {
    auto t = *it;
    if (t->data.value("state") != "queued")
      continue;
    t->data["state"] = "resolving";
    t->data["error"] = "";
    notifyTask(t);
    t->tried.insert(source_.activeId());
    ++count;
    t->resolution = source_.resolveMusicUrl(
        source_.activeId(), t->data.value("quality").toString(),
        online::sourceMusicInfo(t->data.value("track").toMap()));
    if (t->resolution.isEmpty()) {
      const auto reason = source_.lastError();
      QTimer::singleShot(0, this, [this, t, reason] {
        if (t->data.value("state") == "resolving")
          resolutionFailed(t, reason);
      });
    }
  }
  if (count)
    update_.start();
  else {
    flushProgress();
    update_.stop();
  }
  persist();
}
void DownloadService::resolutionFailed(const std::shared_ptr<Task> &t,
                                       const QString &reason) {
  detach(t);
  if (t->data.value("track").toMap().value("source")=="bili" || !settings_.value("download.tryAlternateSource", true).toBool()) {
    fail(t, reason);
    return;
  }
  QVariantMap candidate;
  for (const auto &v : source_.sources()) {
    const auto row = v.toMap();
    if (!t->tried.contains(row.value("id").toString()) &&
        QFileInfo(row.value("path").toString()).isFile()) {
      candidate = row;
      break;
    }
  }
  if (candidate.isEmpty()) {
    fail(t, reason);
    return;
  }
  const auto id = candidate.value("id").toString();
  t->tried.insert(id);
  t->data["state"] = "resolving";
  t->data["error"] = "正在尝试备用音源";
  auto snapshot = std::make_shared<SourceSnapshot>();
  snapshot->set(
      "source.custom",
      QJsonDocument(QJsonArray{QJsonObject::fromVariantMap(candidate)})
          .toJson(QJsonDocument::Compact)
          .toStdString());
  snapshot->set("source.activeId", id.toStdString());
  t->alternativeSettings = snapshot;
  auto *alternative = new SourceController(
      snapshot.get(),
      QCoreApplication::applicationDirPath() + "/listenfree-sourcehost.exe",
      true, this);
  t->alternative = alternative;
  const auto attempt = t->attempt;
  connect(alternative, &QObject::destroyed, [snapshot] {
  }); // Keep the private settings alive through deferred destruction.
  connect(alternative, &SourceController::sourcesChanged, this,
          [this, t, alternative, attempt] {
            if (t->attempt != attempt || !t->resolution.isEmpty())
              return;
            const auto rows = alternative->sources();
            if (rows.isEmpty() || !rows[0].toMap().value("hostReady").toBool())
              return;
            t->resolution = alternative->resolveMusicUrl(
                alternative->activeId(), t->data.value("quality").toString(),
                online::sourceMusicInfo(t->data.value("track").toMap()));
            if (t->resolution.isEmpty())
              QTimer::singleShot(0, this, [this, t, attempt] {
                if (t->attempt == attempt)
                  resolutionFailed(t, "备用音源不支持此歌曲");
              });
          });
  connect(alternative, &SourceController::resolutionFinished, this,
          [this, t, attempt](const QString &request, const QString &,
                             const QString &, const QVariantMap &data,
                             const QString &error) {
            if (t->attempt != attempt || request != t->resolution)
              return;
            t->resolution.clear();
            if (error.isEmpty()) {
              detach(t);
              start(t, data);
            } else
              resolutionFailed(t, error);
          });
  QTimer::singleShot(25000, this, [this, t, attempt] {
    if (t->attempt == attempt && t->alternative)
      resolutionFailed(t, "备用音源请求超时");
  });
  persist(t);
}
void DownloadService::start(const std::shared_ptr<Task> &t,
                            const QVariantMap &resolved) {
  if (resolved.contains("quality")) t->data["quality"] = resolved.value("quality");
  const QUrl url(resolved.value("url").toString());
  if (url.scheme() != "https" && url.scheme() != "http") {
    fail(t, "音源未返回可下载地址");
    return;
  }
  if (t->data.value("path").toString().isEmpty()) {
    const auto folder =
        settings_
            .value("download.folder", QStandardPaths::writableLocation(
                                          QStandardPaths::MusicLocation) +
                                          "/ListenFree")
            .toString();
    if (folder.isEmpty() || !QDir().mkpath(folder)) {
      fail(t, "无法创建下载目录");
      return;
    }
    QString name =
        settings_.value("download.fileNameTemplate", "{name} - {artist}")
            .toString();
    const auto track = t->data.value("track").toMap();
    if (name == "TitleArtist")
      name = "{title} - {artist}";
    else if (name == "ArtistTitle")
      name = "{artist} - {title}";
    else if (name == "TitleOnly")
      name = "{title}";
    name.replace("{name}", track.value("title").toString());
    name.replace("{title}", track.value("title").toString());
    name.replace("{artist}", track.value("artist").toString());
    name.replace("{singer}", track.value("artist").toString());
    name.replace("{album}", track.value("album").toString());
    QString ext = t->data.value("quality").toString().startsWith("flac")
                            ? ".flac"
                            : ".mp3";
    if (track.value("source")=="bili" && QStringList{"m4a","mp4","flv"}.contains(resolved.value("extension").toString()))
      ext="."+resolved.value("extension").toString();
    const QString stem = filename(name);
    QString path = QDir(folder).absoluteFilePath(stem + ext);
    const auto policy =
        settings_.value("download.existingFilePolicy", "Skip").toString();
    if (QFile::exists(path) && policy == "Skip") {
      t->data["state"] = "completed";
      t->data["path"] = path;
      t->data["error"] = "文件已存在，已跳过";
      persist(t);
      pump();
      return;
    }
    // Reserve unique destinations among jobs as well as existing files.
    auto reserved = [&](const QString &p) {
      for (const auto &other : jobs_)
        if (other != t && other->data.value("path") == p)
          return true;
      return false;
    };
    int suffix = 2;
    while ((QFile::exists(path) && policy != "Overwrite") || reserved(path))
      path = QDir(folder).absoluteFilePath(
          stem + QString(" (%1)").arg(suffix++) + ext);
    t->data["overwrite"] = policy == "Overwrite";
    t->data["path"] = path;
    t->data["partial"] = path + "." + t->data.value("id").toString() + ".part";
  }
  t->file.setFileName(t->data.value("partial").toString());
  if (!t->file.open(QIODevice::ReadWrite)) {
    fail(t, "无法写入下载文件");
    return;
  }
  t->offset = t->file.size();
  t->file.seek(t->offset);
  t->checked = false;
  QNetworkRequest req(url);
  req.setTransferTimeout(30000);
  const auto headers = resolved.value("headers").toMap();
  for (auto i = headers.cbegin(); i != headers.cend(); ++i)
    req.setRawHeader(i.key().toUtf8(), i.value().toString().toUtf8());
  req.setRawHeader("Accept-Encoding", "identity");
  if (t->offset) {
    req.setRawHeader("Range", "bytes=" + QByteArray::number(t->offset) + "-");
    const auto validator = t->data.value("validator").toByteArray();
    if (!validator.isEmpty())
      req.setRawHeader("If-Range", validator);
  }
  t->reply = network_.get(req);
  t->reply->setReadBufferSize(256 * 1024);
  t->data["state"] = "downloading";
  connect(t->reply, &QNetworkReply::readyRead, this, [this, t] { drain(t); });
  connect(t->reply, &QNetworkReply::finished, this, [this, t] {
    auto reply = t->reply;
    if (!reply)
      return;
    drain(t);
    if (!t->reply)
      return;
    const auto err = reply->error();
    const auto total = t->data.value("total").toLongLong();
    const auto size = t->file.size();
    t->file.flush();
    t->file.close();
    reply->deleteLater();
    t->reply = nullptr;
    if (err != QNetworkReply::NoError || size == 0 ||
        (total > 0 && size != total)) {
      fail(t, "下载未完成，可重试继续");
      return;
    }
    const auto partial = t->data.value("partial").toString(),
               destination = t->data.value("path").toString();
    const QFileInfo target(destination);
    const bool replacing = t->data.value("overwrite").toBool() &&
                           target.isFile() && !target.isSymLink();
    const bool saved =
        replacing ? MoveFileExW(
                        reinterpret_cast<const wchar_t *>(partial.utf16()),
                        reinterpret_cast<const wchar_t *>(destination.utf16()),
                        MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)
                  : QFile::rename(partial, destination);
    if (!saved) {
      fail(t, "无法保存成品文件，目标可能已存在");
      return;
    }
    t->data["received"] = size;
    t->data["total"] = size;
    finalize(t);
  });
  persist(t);
}
void DownloadService::drain(const std::shared_ptr<Task> &t) {
  if (!t->reply)
    return;
  if (!t->checked) {
    const int status =
        t->reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (!status)
      return;
    if (status != 200 && status != 206) {
      fail(t, QString("下载服务返回 HTTP %1").arg(status));
      return;
    }
    if (status == 206) {
      const auto range = t->reply->rawHeader("Content-Range");
      const auto m = QRegularExpression("^bytes (\\d+)-(\\d+)/(\\d+)$")
                         .match(QString::fromLatin1(range));
      if (!m.hasMatch() || m.captured(1).toLongLong() != t->offset) {
        fail(t, "服务器返回了不匹配的续传范围");
        return;
      }
      t->data["total"] = m.captured(3).toLongLong();
    } else {
      if (t->offset) {
        t->file.resize(0);
        t->file.seek(0);
        t->offset = 0;
      }
      t->data["total"] =
          t->reply->header(QNetworkRequest::ContentLengthHeader).toLongLong();
    }
    const auto type =
        t->reply->header(QNetworkRequest::ContentTypeHeader).toString();
    if (type.contains("text/") || type.contains("json")) {
      fail(t, "下载地址返回的不是音频");
      return;
    }
    t->data["validator"] =
        QString::fromLatin1(t->reply->rawHeader("ETag").isEmpty()
                                ? t->reply->rawHeader("Last-Modified")
                                : t->reply->rawHeader("ETag"));
    t->checked = true;
  }
  const auto bytes = t->reply->readAll();
  if (t->file.write(bytes) != bytes.size()) {
    fail(t, "磁盘写入失败，请检查空间与权限");
    return;
  }
  t->data["received"] = t->file.size();
  if (!t->progressPending) {
    t->progressPending = true;
    progressUpdates_.append(t);
  }
}
void DownloadService::detach(const std::shared_ptr<Task> &t) {
  ++t->attempt;
  if (!t->resolution.isEmpty()) {
    const auto id = std::exchange(t->resolution, {});
    if (t->alternative)
      t->alternative->cancelResolution(id);
    else
      source_.cancelResolution(id);
  }
  if (t->reply) {
    t->reply->disconnect(this);
    t->reply->abort();
    t->reply->deleteLater();
    t->reply = nullptr;
  }
  t->file.close();
  if (t->alternative) {
    t->alternative->disconnect(this);
    t->alternative->deleteLater();
    t->alternative = nullptr;
  }
}
void DownloadService::fail(const std::shared_ptr<Task> &t,
                           const QString &reason) {
  detach(t);
  t->data["state"] = "error";
  t->data["error"] = reason;
  persist(t);
  QTimer::singleShot(0, this, [this] { pump(); });
}
void DownloadService::pause(const QString &id) {
  auto t = find(id);
  if (!t || t->data.value("state") == "completed" ||
      t->data.value("state") == "finalizing")
    return;
  detach(t);
  t->data["state"] = "paused";
  persist(t);
  pump();
}
void DownloadService::resume(const QString &id) {
  auto t = find(id);
  if (!t || active(t->data.value("state").toString()) ||
      t->data.value("state") == "completed" ||
      t->data.value("state") == "finalizing")
    return;
  t->tried.clear();
  t->data["state"] = "queued";
  persist(t);
  pump();
}
void DownloadService::cancel(const QString &id) {
  auto t = find(id);
  if (!t || t->data.value("state") == "completed" ||
      t->data.value("state") == "finalizing")
    return;
  detach(t);
  const auto partial = t->data.value("partial").toString();
  if (!partial.isEmpty())
    QFile::remove(partial);
  t->data["state"] = "cancelled";
  t->data["received"] = 0;
  persist(t);
  pump();
}
void DownloadService::pauseAll() {
  for (const auto &t : jobs_)
    if (active(t->data.value("state").toString()) ||
        t->data.value("state") == "queued") {
      detach(t);
      t->data["state"] = "paused";
      notifyTask(t);
    }
  update_.stop();
  progressUpdates_.clear();
  persist();
}
void DownloadService::clearRecords() {
  pauseAll();
  if (!jobs_.isEmpty()) {
    beginRemoveRows({}, 0, int(jobs_.size()) - 1);
    for (const auto &t : jobs_)
      t->row = -1;
    jobs_.clear();
    endRemoveRows();
  }
  persist();
}
void DownloadService::locate(const QString &id) {
  auto t = find(id);
  if (t)
    QProcess::startDetached(
        "explorer.exe", {"/select,", QDir::toNativeSeparators(
                                         t->data.value("path").toString())});
}
void DownloadService::deleteFile(const QString &id) {
  auto t = find(id);
  if (!t || t->data.value("state") != "completed")
    return;
  const auto path = t->data.value("path").toString();
  if (QFile::exists(path) && !QFile::moveToTrash(path)) {
    emit notice("无法移到回收站");
    return;
  }
  const int row = t->row;
  beginRemoveRows({}, row, row);
  t->row = -1;
  jobs_.removeAt(row);
  for (int i = row; i < jobs_.size(); ++i)
    jobs_.at(i)->row = i;
  endRemoveRows();
  persist();
}
void DownloadService::chooseFolder() {
  const auto folder =
      QFileDialog::getExistingDirectory(nullptr, "选择下载目录");
  if (!folder.isEmpty())
    settings_.setValue("download.folder", folder);
}
} // namespace listenfree::qmlbridge

namespace listenfree::qmlbridge {
void DownloadService::fetchMetadata(const QUrl &url, int limit,
                                    std::function<void(QByteArray)> done) {
  QNetworkRequest request(url);
  request.setTransferTimeout(12000);
  auto *reply = network_.get(request);
  reply->setReadBufferSize(limit + 1);
  connect(reply, &QNetworkReply::readyRead, this, [reply, limit] {
    if (reply->bytesAvailable() > limit)
      reply->abort();
  });
  connect(reply, &QNetworkReply::finished, this, [reply, done] {
    const auto bytes = reply->error() == QNetworkReply::NoError
                           ? reply->readAll()
                           : QByteArray{};
    reply->deleteLater();
    done(bytes);
  });
}
void DownloadService::finalize(const std::shared_ptr<Task> &t) {
  t->data["state"] = "finalizing";
  persist(t);
  QVariantMap options;
  for (const auto &key : {"Artwork", "Lyrics", "Artist", "Album"})
    options[key] = settings_.value("download.embedContent." + QString(key),
                                   QString(key) != "Album");
  for (const auto &key :
       {"Original", "Translation", "Romanization", "WordTiming"})
    options[key] = settings_.value("download.lyrics.content." + QString(key),
                                   QString(key) == "Original" ||
                                       QString(key) == "Translation");
  options["external"] = settings_.value("download.lyrics.externalFile", false);
  options["encoding"] = settings_.value("download.lyrics.encoding", "Utf8");
  const auto track = t->data.value("track").toMap();
  const auto path = t->data.value("path").toString();
  const auto write = [this, t, options, track, path](const QString &raw,
                                                     const QByteArray &cover) {
    auto *watcher = new QFutureWatcher<QString>(this);
    writers_.append(watcher);
    connect(watcher, &QFutureWatcher<QString>::finished, this,
            [this, t, watcher] {
              t->data["error"] = watcher->result();
              t->data["state"] = "completed";
              t->data["finished"] = QDateTime::currentMSecsSinceEpoch();
              emit fileCompleted(t->data.value("path").toString());
              writers_.removeAll(watcher);
              watcher->deleteLater();
              persist(t);
              pump();
            });
    watcher->setFuture(QtConcurrent::run([options, track, path, raw, cover] {
      QString warning;
      QString lrc;
      for (const auto &value : online::parseTimedLyrics(raw)) {
        const auto row = value.toMap();
        const auto ms = row.value("timeMs").toLongLong();
        const auto stamp = QString("[%1:%2.%3]")
                               .arg(ms / 60000, 2, 10, QChar('0'))
                               .arg(ms / 1000 % 60, 2, 10, QChar('0'))
                               .arg(ms % 1000 / 10, 2, 10, QChar('0'));
        if (options.value("Original").toBool())
          lrc += stamp + row.value("text").toString() + "\n";
        for (const auto &field : {"translation", "romanization"})
          if (options
                  .value(QString(field) == "translation" ? "Translation"
                                                         : "Romanization")
                  .toBool() &&
              !row.value(field).toString().isEmpty())
            lrc += stamp + row.value(field).toString() + "\n";
      }
      // Keep original real word timing in an auxiliary lyrics tag, never invent
      // timings.
      TagLib::FileRef file(reinterpret_cast<const wchar_t *>(path.utf16()));
      const auto text = [](const QString &s) {
        return TagLib::String(s.toUtf8().constData(), TagLib::String::UTF8);
      };
      if (file.isNull() || !file.tag())
        return QString("音频已完成，格式不支持标签写入");
      file.tag()->setTitle(text(track.value("title").toString()));
      if (options.value("Artist").toBool())
        file.tag()->setArtist(text(track.value("artist").toString()));
      if (options.value("Album").toBool())
        file.tag()->setAlbum(text(track.value("album").toString()));
      if (options.value("Lyrics").toBool() && !lrc.isEmpty()) {
        auto properties = file.file()->properties();
        properties.replace(
            "LYRICS", TagLib::StringList(text(
                          options.value("WordTiming").toBool() ? raw : lrc)));
        file.file()->setProperties(properties);
      }
      if (options.value("Artwork").toBool() && !cover.isEmpty() &&
          !QImage::fromData(cover).isNull()) {
        const auto mime =
            cover.startsWith("\x89PNG") ? "image/png" : "image/jpeg";
        if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(file.file())) {
          auto *picture = new TagLib::FLAC::Picture();
          picture->setType(TagLib::FLAC::Picture::FrontCover);
          picture->setMimeType(mime);
          picture->setData(
              TagLib::ByteVector(cover.constData(), unsigned(cover.size())));
          flac->addPicture(picture);
        } else if (auto *mp3 =
                       dynamic_cast<TagLib::MPEG::File *>(file.file())) {
          auto *picture = new TagLib::ID3v2::AttachedPictureFrame();
          picture->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
          picture->setMimeType(mime);
          picture->setPicture(
              TagLib::ByteVector(cover.constData(), unsigned(cover.size())));
          mp3->ID3v2Tag(true)->addFrame(picture);
        }
      }
      if (!file.save())
        warning = "音频已完成，部分标签未能保存";
      if (options.value("external").toBool() && !lrc.isEmpty()) {
        QByteArray bytes = lrc.toUtf8();
        if (options.value("encoding") == "Gbk") {
          const int size = WideCharToMultiByte(
              936, 0, reinterpret_cast<const wchar_t *>(lrc.utf16()),
              int(lrc.size()), nullptr, 0, nullptr, nullptr);
          bytes.resize(size);
          WideCharToMultiByte(
              936, 0, reinterpret_cast<const wchar_t *>(lrc.utf16()),
              int(lrc.size()), bytes.data(), size, nullptr, nullptr);
        } else
          bytes.prepend(QByteArray::fromHex("efbbbf"));
        QSaveFile lyric(QFileInfo(path).path() + "/" +
                        QFileInfo(path).completeBaseName() + ".lrc");
        if (!lyric.open(QIODevice::WriteOnly) ||
            lyric.write(bytes) != bytes.size() || !lyric.commit())
          warning = "音频已完成，独立歌词保存失败";
      }
      if ((options.value("Lyrics").toBool() ||
           options.value("external").toBool()) &&
          lrc.isEmpty())
        warning = "音频已完成，未获取到歌词";
      return warning;
    }));
  };
  const auto afterLyrics = [this, track, options,
                            write](const QByteArray &bytes) {
    const auto lyrics = online::decodeKuwoLyrics(bytes);
    const QUrl cover(track.value("artwork").toString());
    if (options.value("Artwork").toBool() &&
        (cover.scheme() == "http" || cover.scheme() == "https"))
      fetchMetadata(
          cover, 4 * 1024 * 1024,
          [write, lyrics](const QByteArray &image) { write(lyrics, image); });
    else
      write(lyrics, {});
  };
  if (track.value("source")!="bili" && (options.value("Lyrics").toBool() || options.value("external").toBool())) {
    const auto query =
        online::kuwoXor(
            "user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_" +
            track.value("rid").toString().toLatin1() + "&lrcx=1")
            .toBase64();
    fetchMetadata(QUrl("https://newlyric.kuwo.cn/newlyric.lrc?" +
                       QString::fromLatin1(query)),
                  2 * 1024 * 1024, afterLyrics);
  } else
    afterLyrics({});
}
} // namespace listenfree::qmlbridge
