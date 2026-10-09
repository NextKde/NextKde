#include "qmlbridge/source_controller.h"
#include "sourcehost/script_metadata.h"
#include "online/track_origin.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>

#include <algorithm>

namespace listenfree::qmlbridge {
namespace {

// Keep a small lifecycle journal so an intermittent startup failure survives
// a restart. Only fixed event names are passed here; never URLs or script data.
void recordHostEvent(const QString &event) {
  const auto dataDir = QCoreApplication::instance()->property("listenfreeDataDir").toString();
  if (dataDir.isEmpty()) return;
  QDir directory(QDir(dataDir).filePath(QStringLiteral("logs")));
  if (!directory.mkpath(QStringLiteral("."))) return;
  const auto path = directory.filePath(QStringLiteral("sourcehost.log"));
  if (QFileInfo(path).size() >= 128 * 1024) {
    QFile::remove(path + QStringLiteral(".1"));
    if (!QFile::rename(path, path + QStringLiteral(".1"))) return;
  }
  QFile file(path);
  if (file.open(QIODevice::WriteOnly | QIODevice::Append))
    file.write(QStringLiteral("%1 pid=%2 %3\n")
        .arg(QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs))
        .arg(QCoreApplication::applicationPid()).arg(event).toUtf8());
}

constexpr qsizetype kMaxPluginBytes = 1024 * 1024;

QString terminalName(sourcehost::SourceHostClient::RequestTerminal terminal) {
  using Terminal = sourcehost::SourceHostClient::RequestTerminal;
  switch (terminal) {
  case Terminal::TimedOut:
    return QStringLiteral("请求超时");
  case Terminal::Cancelled:
    return QStringLiteral("请求已取消");
  case Terminal::HostStopped:
    return QStringLiteral("音源宿主已停止");
  case Terminal::HostCrashed:
    return QStringLiteral("音源宿主异常退出");
  case Terminal::WriteFailed:
    return QStringLiteral("无法写入音源宿主");
  case Terminal::RemoteError:
    return QStringLiteral("音源请求失败");
  case Terminal::Succeeded:
    break;
  }
  return QStringLiteral("音源请求失败");
}

QString errorMessage(const QJsonObject &payload) {
  const auto code = payload.value(QStringLiteral("code")).toString().trimmed();
  const auto message =
      payload.value(QStringLiteral("message")).toString().trimmed();
  if (!message.isEmpty() && !code.isEmpty())
    return QStringLiteral("%1（%2）").arg(message, code);
  return message.isEmpty() ? (code.isEmpty() ? QStringLiteral("音源请求失败")
                                               : code)
                           : message;
}

QString hostStateLabel(const sourcehost::SourceHostClient *host,
                       bool enabled, bool available) {
  if (!enabled)
    return QStringLiteral("未启用");
  if (!available)
    return QStringLiteral("宿主缺失");
  if (!host)
    return QStringLiteral("未启动");
  using State = sourcehost::SourceHostClient::HostState;
  switch (host->state()) {
  case State::Starting:
    return QStringLiteral("启动中");
  case State::Ready:
    return QStringLiteral("已就绪");
  case State::RestartWaiting:
    return QStringLiteral("重启中");
  case State::Stopping:
    return QStringLiteral("停止中");
  case State::Stopped:
    return QStringLiteral("已停止");
  }
  return QStringLiteral("未知状态");
}

QString safeBaseName(const QFileInfo &info) {
  QString name = info.completeBaseName().trimmed();
  if (name.isEmpty())
    name = QStringLiteral("source");
  name.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_\\-.\\x{4e00}-\\x{9fff}]")),
               QStringLiteral("_"));
  return name.left(96);
}

QString importStorageName(const QFileInfo& info, const QString& identity) {
  return safeBaseName(info) + QStringLiteral("-") + QString::fromLatin1(
      QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex().left(16));
}

bool hasString(const QVariant &value, const QString &needle) {
  const auto values = value.toList();
  return std::any_of(values.cbegin(), values.cend(),
                     [&needle](const QVariant &item) {
                       return item.toString() == needle;
                     });
}

QVariantList stringListToVariant(const QJsonArray &array) {
  QVariantList result;
  result.reserve(array.size());
  for (const auto &value : array)
    if (value.isString())
      result.push_back(value.toString());
  return result;
}

} // namespace

SourceController::SourceController(application::ISettingsRepository *settings,
                                   QObject *parent)
    : SourceController(settings, QString{}, false, parent) {}

SourceController::SourceController(application::ISettingsRepository *settings,
                                   const QString &hostExecutablePath,
                                   bool enableHost, QObject *parent)
    : QObject(parent), settings_(settings), hostExecutablePath_(hostExecutablePath),
      hostEnabled_(enableHost) {
  load();
  if (hostEnabled_)
    initializeHost();
}

SourceController::~SourceController() {
  const auto requests = scriptRequests_; scriptRequests_.clear();
  for (auto host : requests) if (host) { host->disconnect(this); host->stop(); }
  if (host_)
    host_->stop();
}

void SourceController::load() {
  sources_ = {};

  if (settings_) {
    if (const auto raw = settings_->get("source.custom")) {
      QJsonParseError parseError;
      const auto document = QJsonDocument::fromJson(
          QByteArray::fromStdString(*raw), &parseError);
      if (parseError.error == QJsonParseError::NoError && document.isArray()) {
        for (const auto &value : document.array()) {
          if (!value.isObject())
            continue;
          auto map = value.toObject().toVariantMap();
          const auto id = map.value(QStringLiteral("id")).toString().trimmed();
          const auto path = map.value(QStringLiteral("path")).toString().trimmed();
          if (id.isEmpty() || path.isEmpty())
            continue;
          map.insert(QStringLiteral("id"), id);
          map.insert(QStringLiteral("kind"),
                     map.value(QStringLiteral("kind"), QStringLiteral("custom")));
          map.insert(QStringLiteral("origin"),
                     map.value(QStringLiteral("origin"), QStringLiteral("local")));
          map.insert(QStringLiteral("enabled"), true);
          map.insert(QStringLiteral("removable"), true);
          map.insert(QStringLiteral("updatePrompt"),
                     map.value(QStringLiteral("updatePrompt"), true));
          map.insert(QStringLiteral("status"),
                     map.value(QStringLiteral("status"), QStringLiteral("已导入")));
          map.insert(QStringLiteral("path"), QDir(sourceDirectory()).filePath(QFileInfo(path).fileName()));
          QFile scriptFile(map.value("path").toString());
          if (scriptFile.open(QIODevice::ReadOnly)) {
            const auto metadata = sourcehost::scriptMetadata(scriptFile.read(kMaxPluginBytes));
            for (auto it = metadata.cbegin(); it != metadata.cend(); ++it) map[it.key()] = it.value();
          }
          map.insert(QStringLiteral("availabilityStatus"), QStringLiteral("待检测"));
          map.insert(QStringLiteral("hostReady"), false);
          sources_.append(map);
        }
      }
    }
    defaultId_ = QString::fromStdString(settings_->get("source.defaultId")
        .value_or(settings_->get("source.activeId").value_or("")));
  }
  if (indexOf(defaultId_) < 0)
    defaultId_ = sources_.isEmpty() ? QString{} : sources_.first().toMap().value("id").toString();
  activeId_ = defaultId_;
  emit defaultChanged();
  emit sourcesChanged();
  emit activeChanged();
}

void SourceController::persist() {
  if (!settings_)
    return;
  QJsonArray custom;
  for (const auto &value : sources_) {
    const auto map = value.toMap();
    if (map.value(QStringLiteral("origin")).toString() !=
        QStringLiteral("builtin"))
      custom.append(QJsonObject::fromVariantMap(map));
  }
  settings_->set("source.custom",
                 QJsonDocument(custom).toJson(QJsonDocument::Compact).toStdString());
  settings_->set("source.defaultId", defaultId_.toStdString());
  settings_->set("source.activeId", defaultId_.toStdString()); // Legacy readers keep the startup preference.
}

int SourceController::indexOf(const QString &id) const {
  for (int index = 0; index < sources_.size(); ++index) {
    if (sources_.at(index).toMap().value(QStringLiteral("id")).toString() ==
        id)
      return index;
  }
  return -1;
}

void SourceController::updateSource(const QString &id,
                                    const QVariantMap &updates) {
  const int index = indexOf(id);
  if (index < 0 || updates.isEmpty())
    return;
  auto map = sources_.at(index).toMap();
  bool changed = false;
  for (auto it = updates.cbegin(); it != updates.cend(); ++it) {
    if (map.value(it.key()) != it.value()) {
      map.insert(it.key(), it.value());
      changed = true;
    }
  }
  if (!changed)
    return;
  sources_[index] = map;
  emit sourcesChanged();
}

bool SourceController::selectSource(const QString &id) {
  const auto normalized = id.trimmed();
  if (indexOf(normalized) < 0)
    return false;
  if (activeId_ != normalized) {
    hostSourceInfo_.clear();
    activeId_ = normalized;
    emit activeChanged();
  }
  setError({});
  if (hostEnabled_ && !sources_.at(indexOf(normalized))
                          .toMap()
                          .value(QStringLiteral("removable"))
                          .toBool()) {
    setStatus(QStringLiteral("已切换到内置音源"));
  } else if (hostEnabled_) {
    loadActivePlugin();
  }
  return true;
}

bool SourceController::setDefaultSource(const QString &id) {
  const auto normalized = id.trimmed();
  if (indexOf(normalized) < 0) return false;
  if (defaultId_ != normalized) {
    defaultId_ = normalized;
    persist();
    emit defaultChanged();
  }
  return true;
}

bool SourceController::useDefaultSource() { return selectSource(defaultId_); }

bool SourceController::removeSource(const QString &id) {
  const int index = indexOf(id.trimmed());
  if (index < 0 ||
      !sources_.at(index).toMap().value(QStringLiteral("removable")).toBool())
    return false;
  const auto map = sources_.at(index).toMap();
  const auto removedId = map.value(QStringLiteral("id")).toString();
  const auto path = QFileInfo(map.value(QStringLiteral("path")).toString());
  sources_.removeAt(index);
  if (defaultId_ == removedId) {
    defaultId_ = sources_.isEmpty() ? QString{} : sources_.first().toMap().value("id").toString();
    emit defaultChanged();
  }
  if (path.isFile() &&
      QDir::cleanPath(path.absolutePath()) == QDir::cleanPath(sourceDirectory()))
    QFile::remove(path.absoluteFilePath());
  if (activeId_ == removedId) {
    activeId_ = defaultId_;
    emit activeChanged();
  }
  persist();
  hostSourceInfo_.clear();
  emit sourcesChanged();
  setStatus(QStringLiteral("已移除音源"));
  setError({});
  if (hostEnabled_ && hostReady() && indexOf(activeId_) >= 0 &&
      sources_.at(indexOf(activeId_)).toMap().value(QStringLiteral("removable"))
          .toBool())
    loadActivePlugin();
  else
    updateCustomStatuses();
  return true;
}

bool SourceController::setUpdatePrompt(const QString &id, bool enabled) {
  const int index = indexOf(id.trimmed());
  if (index < 0)
    return false;
  auto map = sources_.at(index).toMap();
  map.insert(QStringLiteral("updatePrompt"), enabled);
  sources_[index] = map;
  persist();
  emit sourcesChanged();
  return true;
}

QString SourceController::sourceDirectory() const {
  return QCoreApplication::instance()->property("listenfreeDataDir").toString() + QStringLiteral("/sources");
}

bool SourceController::importLocalFile(const QString &path) {
  const QFileInfo info(path);
  const auto extension = info.suffix().toLower();
  if (!info.isFile() || info.size() <= 0 || info.size() > kMaxPluginBytes ||
      (extension != QStringLiteral("js") &&
       extension != QStringLiteral("mjs"))) {
    setError(QStringLiteral("音源文件必须是 1 MiB 以内的 .js/.mjs 文件"));
    return false;
  }
  if (!QDir().mkpath(sourceDirectory())) {
    setError(QStringLiteral("无法创建音源目录"));
    return false;
  }
  const auto displayName = safeBaseName(info);
  const auto name = importStorageName(info, info.canonicalFilePath());
  const auto target = QDir(sourceDirectory()).filePath(name +
                                                       QStringLiteral(".") +
                                                       extension);
  QFile original(info.absoluteFilePath());
  if (!original.open(QIODevice::ReadOnly)) { setError(QStringLiteral("无法读取音源文件")); return false; }
  const auto script = original.readAll();
  QSaveFile saved(target);
  if (!saved.open(QIODevice::WriteOnly) || saved.write(script) != script.size() || !saved.commit()) {
    setError(QStringLiteral("无法复制音源文件"));
    return false;
  }
  const auto id = QStringLiteral("custom.") + name;
  QVariantMap map{{QStringLiteral("id"), id},
                  {QStringLiteral("name"), displayName},
                  {QStringLiteral("kind"), QStringLiteral("custom")},
                  {QStringLiteral("description"), QStringLiteral("本地 JavaScript 音源")},
                  {QStringLiteral("version"), QStringLiteral("本地文件")},
                  {QStringLiteral("origin"), QStringLiteral("local")},
                  {QStringLiteral("path"), target},
                  {QStringLiteral("enabled"), true},
                  {QStringLiteral("removable"), true},
                  {QStringLiteral("updatePrompt"), true},
                  {QStringLiteral("status"), QStringLiteral("已导入")}};
  const auto metadata = sourcehost::scriptMetadata(script);
  for (auto it = metadata.cbegin(); it != metadata.cend(); ++it) map[it.key()] = it.value();
  map["availabilityStatus"] = "待检测";
  const int old = indexOf(id);
  if (old >= 0)
    sources_.removeAt(old);
  sources_.append(map);
  activeId_ = id;
  if (defaultId_.isEmpty()) { defaultId_ = id; emit defaultChanged(); }
  persist();
  emit sourcesChanged();
  emit activeChanged();
  setStatus(QStringLiteral("已导入并切换到本地音源"));
  setError({});
  if (hostEnabled_)
    loadActivePlugin();
  return true;
}

bool SourceController::importUrl(const QUrl &url) {
  if (!url.isValid() || url.scheme().compare(QStringLiteral("https"),
                                              Qt::CaseInsensitive) != 0 ||
      url.host().isEmpty()) {
    setError(QStringLiteral("音源地址必须是 HTTPS"));
    return false;
  }
  if (busy_)
    return false;
  busy_ = true;
  emit busyChanged();
  setStatus(QStringLiteral("正在下载音源…"));
  setError({});
  QNetworkRequest request(url);
  request.setTransferTimeout(15000);
  auto *reply = network_.get(request);
  reply->setProperty("sourceImportUrl", url);
  connect(reply, &QIODevice::readyRead, reply, [reply] { if (reply->bytesAvailable() > kMaxPluginBytes) reply->abort(); });
  connect(reply, &QNetworkReply::finished, this,
          &SourceController::finishUrlImport);
  return true;
}

void SourceController::finishUrlImport() {
  auto *reply = qobject_cast<QNetworkReply *>(sender());
  busy_ = false;
  emit busyChanged();
  if (!reply)
    return;
  const auto data = reply->readAll();
  const auto url = reply->property("sourceImportUrl").toUrl();
  const auto networkError = reply->error();
  reply->deleteLater();
  if (networkError != QNetworkReply::NoError || data.isEmpty() ||
      data.size() > kMaxPluginBytes) {
    setError(QStringLiteral("下载音源失败或文件超过 1 MiB"));
    return;
  }
  if (!QDir().mkpath(sourceDirectory())) {
    setError(QStringLiteral("无法创建音源目录"));
    return;
  }
  QString name = QFileInfo(url.path()).completeBaseName().trimmed();
  if (name.isEmpty())
    name = QStringLiteral("remote-source");
  name = safeBaseName(QFileInfo(name + QStringLiteral(".js")));
  const auto storageName = importStorageName(QFileInfo(name + QStringLiteral(".js")), url.toString(QUrl::FullyEncoded));
  const auto target = QDir(sourceDirectory()).filePath(storageName +
                                                       QStringLiteral(".js"));
  QSaveFile file(target);
  if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
    setError(QStringLiteral("无法保存远程音源"));
    return;
  }
  const auto id = QStringLiteral("custom.") + storageName;
  QVariantMap map{{QStringLiteral("id"), id},
                  {QStringLiteral("name"), name},
                  {QStringLiteral("kind"), QStringLiteral("custom")},
                  {QStringLiteral("description"), QStringLiteral("HTTPS JavaScript 音源")},
                  {QStringLiteral("version"), QStringLiteral("远程文件")},
                  {QStringLiteral("origin"), QStringLiteral("url")},
                  {QStringLiteral("url"), url.toString()},
                  {QStringLiteral("path"), target},
                  {QStringLiteral("enabled"), true},
                  {QStringLiteral("removable"), true},
                  {QStringLiteral("updatePrompt"), true},
                  {QStringLiteral("status"), QStringLiteral("已导入")}};
  const auto metadata = sourcehost::scriptMetadata(data);
  for (auto it = metadata.cbegin(); it != metadata.cend(); ++it) map[it.key()] = it.value();
  map["availabilityStatus"] = "待检测";
  const int old = indexOf(id);
  if (old >= 0)
    sources_.removeAt(old);
  sources_.append(map);
  activeId_ = id;
  if (defaultId_.isEmpty()) { defaultId_ = id; emit defaultChanged(); }
  persist();
  emit sourcesChanged();
  emit activeChanged();
  setStatus(QStringLiteral("已导入并切换到远程音源"));
  setError({});
  if (hostEnabled_)
    loadActivePlugin();
}

bool SourceController::hostReady() const noexcept {
  return host_ && host_->state() == sourcehost::SourceHostClient::HostState::Ready;
}

QString SourceController::hostState() const {
  return hostStateLabel(host_.get(), hostEnabled_, hostAvailable_);
}

void SourceController::initializeHost() {
  if (!hostEnabled_)
    return;
  if (hostExecutablePath_.isEmpty()) {
    QString fileName = QStringLiteral("listenfree-sourcehost");
#ifdef Q_OS_WIN
    fileName += QStringLiteral(".exe");
#endif
    hostExecutablePath_ = QDir(QCoreApplication::applicationDirPath())
                              .filePath(fileName);
  }
  hostAvailable_ = QFileInfo(hostExecutablePath_).isFile() &&
                   QFileInfo(hostExecutablePath_).isExecutable();
  emit hostChanged();
  updateCustomStatuses();
  if (!hostAvailable_) {
    setStatus(QStringLiteral("自定义音源宿主未找到，本地音乐仍可使用"));
    return;
  }
  host_ = std::make_unique<sourcehost::SourceHostClient>(hostExecutablePath_);
  host_->setAutoRestart(true);
  connect(host_.get(), &sourcehost::SourceHostClient::ready, this, [this] {
    emit hostChanged();
    updateCustomStatuses();
    setError({});
    setStatus(QStringLiteral("音源宿主已就绪，正在验证当前音源…"));
    loadActivePlugin();
  });
  connect(host_.get(), &sourcehost::SourceHostClient::stateChanged, this,
          [this](sourcehost::SourceHostClient::HostState state) {
            recordHostEvent(QStringLiteral("state=%1").arg(hostState()));
            emit hostChanged();
            updateCustomStatuses();
            if (state == sourcehost::SourceHostClient::HostState::Stopped && restartRequested_) {
              QTimer::singleShot(0, this, [this] {
                if (!restartRequested_ || !host_ ||
                    host_->state() != sourcehost::SourceHostClient::HostState::Stopped)
                  return;
                restartRequested_ = false;
                host_->start();
              });
            }
          });
  connect(host_.get(), &sourcehost::SourceHostClient::messageReceived, this,
          &SourceController::handleHostMessage);
  connect(host_.get(), &sourcehost::SourceHostClient::requestFinished, this,
          &SourceController::handleHostTerminal);
  connect(host_.get(), &sourcehost::SourceHostClient::protocolError, this,
          [this](const QString &message) {
            recordHostEvent(message == QStringLiteral("sourcehost-handshake-timeout") ||
                            message == QStringLiteral("invalid-sourcehost-handshake") ||
                            message == QStringLiteral("sourcehost-hello-write-failed")
                                ? message : QStringLiteral("protocol-error"));
            if (!message.trimmed().isEmpty())
              setError(QStringLiteral("音源宿主：%1").arg(message.left(512)));
          });
  connect(host_.get(), &sourcehost::SourceHostClient::crashed, this,
          [this] { handleHostFailure(QStringLiteral("音源宿主异常退出")); });
  if (!host_->start()) {
    handleHostFailure(QStringLiteral("无法启动音源宿主"));
    return;
  }
  emit hostChanged();
}

void SourceController::loadActivePlugin() {
  if (!hostEnabled_ || !hostAvailable_)
    return;
  if (!hostReady()) {
    if (host_ && host_->state() == sourcehost::SourceHostClient::HostState::Stopped)
      host_->start();
    return;
  }
  const int index = indexOf(activeId_);
  if (index < 0)
    return;
  const auto map = sources_.at(index).toMap();
  if (!map.value(QStringLiteral("removable")).toBool()) {
    hostSourceInfo_.clear();
    updateCustomStatuses();
    return;
  }
  const auto path = map.value(QStringLiteral("path")).toString().trimmed();
  if (path.isEmpty() || !QFileInfo(path).isFile()) {
    updateSource(activeId_, {{QStringLiteral("status"), QStringLiteral("文件不存在")},
                             {QStringLiteral("hostReady"), false}});
    setError(QStringLiteral("音源脚本文件不存在"));
    return;
  }
  if (!pendingLoadId_.isEmpty())
    return;
  hostSourceInfo_.clear();
  sourcehost::SourceMessage request;
  request.type = sourcehost::MessageType::LoadPlugin;
  request.requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  request.payload.insert(QStringLiteral("path"), path);
  pendingLoadId_ = request.requestId;
  pendingLoadSourceId_ = activeId_;
  updateSource(activeId_, {{QStringLiteral("status"), QStringLiteral("验证中")},
                           {QStringLiteral("hostReady"), false}});
  setStatus(QStringLiteral("正在验证音源脚本…"));
  setError({});
  if (!host_->request(request, sourcehost::PluginClientTimeoutMs)) {
    const auto failedId = pendingLoadSourceId_;
    pendingLoadId_.clear();
    pendingLoadSourceId_.clear();
    updateSource(failedId, {{QStringLiteral("status"), QStringLiteral("验证失败")},
                            {QStringLiteral("hostReady"), false}});
    setError(QStringLiteral("无法向音源宿主发送验证请求"));
  }
}

void SourceController::handleHostMessage(
    const sourcehost::SourceMessage &message) {
  if (message.type == sourcehost::MessageType::UpdateAlert) {
    const int index = indexOf(pendingLoadSourceId_.isEmpty() ? activeId_ : pendingLoadSourceId_);
    if (index >= 0) {
      const auto map = sources_[index].toMap();
      if (map.value("updatePrompt", true).toBool())
        emit updateAvailable(map.value("name").toString(), message.payload.value("log").toString(),
                             QUrl(message.payload.value("updateUrl").toString()));
    }
    return;
  }
  if (message.type != sourcehost::MessageType::Result &&
      message.type != sourcehost::MessageType::Error)
    return;

  const auto code = message.payload.value(QStringLiteral("code")).toString();
  if (message.type == sourcehost::MessageType::Error &&
      (code == QStringLiteral("plugin.runtime-failed") || code == QStringLiteral("plugin.not-loaded"))) {
    hostSourceInfo_.clear();
    updateSource(activeId_, {{QStringLiteral("status"), QStringLiteral("音源运行失败，请重新连接")},
                            {QStringLiteral("hostReady"), false}});
    setError(errorMessage(message.payload));
  }

  if (!pendingLoadId_.isEmpty() && message.requestId == pendingLoadId_) {
    const auto sourceId = pendingLoadSourceId_;
    pendingLoadId_.clear();
    pendingLoadSourceId_.clear();
    if (sourceId != activeId_) { hostSourceInfo_.clear(); loadActivePlugin(); return; }
    if (message.type == sourcehost::MessageType::Error ||
        !message.payload.value(QStringLiteral("ok")).toBool()) {
      const auto reason = message.type == sourcehost::MessageType::Error
                              ? errorMessage(message.payload)
                              : QStringLiteral("脚本没有报告成功状态");
      updateSource(sourceId, {{QStringLiteral("status"), QStringLiteral("验证失败")},
                              {QStringLiteral("hostReady"), false}});
      setError(reason);
      setStatus(QStringLiteral("音源验证失败"));
      return;
    }

    hostSourceInfo_.clear();
    recordCapabilities(sourceId, message.payload.value("sources").toObject());
    const auto sourceObject =
        message.payload.value(QStringLiteral("sources")).toObject();
    QVariantList providerIds;
    QVariantMap capabilities;
    for (auto it = sourceObject.begin(); it != sourceObject.end(); ++it) {
      if (!it.value().isObject())
        continue;
      const auto info = it.value().toObject();
      QVariantMap mapped = info.toVariantMap();
      mapped.insert(QStringLiteral("id"), it.key());
      mapped.insert(QStringLiteral("actions"),
                    stringListToVariant(info.value(QStringLiteral("actions"))
                                            .toArray()));
      mapped.insert(QStringLiteral("qualitys"),
                    stringListToVariant(info.value(QStringLiteral("qualitys"))
                                            .toArray()));
      hostSourceInfo_.insert(it.key(), mapped);
      providerIds.push_back(it.key());
      capabilities.insert(it.key(), mapped);
    }
    if (providerIds.isEmpty()) {
      updateSource(sourceId, {{QStringLiteral("status"), QStringLiteral("未声明可用源")},
                              {QStringLiteral("hostReady"), false}});
      setError(QStringLiteral("音源脚本未声明可用源"));
      return;
    }
    QString provider;
    for (const auto &value : providerIds) {
      const auto info = hostSourceInfo_.value(value.toString());
      if (hasString(info.value(QStringLiteral("actions")),
                    QStringLiteral("musicUrl")) ||
          hasString(info.value(QStringLiteral("actions")),
                    QStringLiteral("lyric"))) {
        provider = value.toString();
        break;
      }
    }
    if (provider.isEmpty())
      provider = providerIds.first().toString();
    updateSource(sourceId,
                 {{QStringLiteral("status"), QStringLiteral("已加载")},
                  {QStringLiteral("hostReady"), true},
                  {QStringLiteral("hostSourceId"), provider},
                  {QStringLiteral("providerIds"), providerIds},
                  {QStringLiteral("capabilities"), capabilities}});
    setError({});
    setStatus(QStringLiteral("音源已加载：%1").arg(provider));
    return;
  }

  const auto pending = pendingResolutions_.find(message.requestId);
  if (pending == pendingResolutions_.end())
    return;
  const auto requestInfo = pending.value();
  pendingResolutions_.erase(pending);
  if (message.type == sourcehost::MessageType::Error) {
    const auto reason = errorMessage(message.payload);
    setError(reason);
    emit resolutionFinished(message.requestId, requestInfo.sourceId,
                            requestInfo.action, {}, reason);
    return;
  }
  QVariantMap data;
  const auto value = message.payload.value(QStringLiteral("data"));
  if (value.isObject())
    data = value.toObject().toVariantMap();
  else if (value.isString())
    data.insert(QStringLiteral("url"), value.toString());
  const auto resultSource = message.payload.value(QStringLiteral("source"))
                                .toString();
  if (!resultSource.isEmpty())
    data.insert(QStringLiteral("source"), resultSource);
  data.insert(QStringLiteral("action"), requestInfo.action);
  if (requestInfo.action == "musicUrl") data.insert("quality", requestInfo.quality);
  emit resolutionFinished(message.requestId, requestInfo.sourceId,
                          requestInfo.action, data, {});
}

void SourceController::handleHostTerminal(
    const QString &requestId,
    sourcehost::SourceHostClient::RequestTerminal terminal) {
  // Remote responses carry the specific plugin failure. The terminal signal
  // arrives before messageReceived, so consuming it here discards that reason.
  if (terminal == sourcehost::SourceHostClient::RequestTerminal::RemoteError ||
      terminal == sourcehost::SourceHostClient::RequestTerminal::Succeeded) return;
  if (requestId == pendingLoadId_ && terminal !=
                                            sourcehost::SourceHostClient::RequestTerminal::Succeeded) {
    const auto sourceId = pendingLoadSourceId_;
    pendingLoadId_.clear();
    pendingLoadSourceId_.clear();
    const auto reason = terminalName(terminal);
    updateSource(sourceId, {{QStringLiteral("status"), QStringLiteral("验证失败")},
                            {QStringLiteral("hostReady"), false}});
    setError(reason);
    setStatus(QStringLiteral("音源验证失败"));
    return;
  }
  if (terminal == sourcehost::SourceHostClient::RequestTerminal::Succeeded)
    return;
  const auto pending = pendingResolutions_.find(requestId);
  if (pending == pendingResolutions_.end())
    return;
  const auto requestInfo = pending.value();
  pendingResolutions_.erase(pending);
  const auto reason = terminalName(terminal);
  emit resolutionFinished(requestId, requestInfo.sourceId, requestInfo.action,
                          {}, reason);
  setError(reason);
}

void SourceController::handleHostFailure(const QString &message) {
  hostSourceInfo_.clear();
  if (!pendingLoadId_.isEmpty()) {
    const auto sourceId = pendingLoadSourceId_;
    pendingLoadId_.clear();
    pendingLoadSourceId_.clear();
    updateSource(sourceId, {{QStringLiteral("status"), QStringLiteral("宿主不可用")},
                            {QStringLiteral("hostReady"), false}});
  }
  const auto pending = pendingResolutions_;
  pendingResolutions_.clear();
  for (auto it = pending.cbegin(); it != pending.cend(); ++it)
    emit resolutionFinished(it.key(), it.value().sourceId, it.value().action,
                            {}, message);
  setStatus(message);
  setError(message);
  updateCustomStatuses();
  emit hostChanged();
}

void SourceController::updateCustomStatuses() {
  bool changed = false;
  for (int index = 0; index < sources_.size(); ++index) {
    auto map = sources_.at(index).toMap();
    if (!map.value(QStringLiteral("removable")).toBool())
      continue;
    const auto id = map.value(QStringLiteral("id")).toString();
    QString status;
    bool ready = false;
    if (!hostEnabled_ || !hostAvailable_)
      status = QStringLiteral("待验证");
    else if (!hostReady()) {
      const auto state = host_ ? host_->state() : sourcehost::SourceHostClient::HostState::Stopped;
      status = state == sourcehost::SourceHostClient::HostState::Stopped
                   ? QStringLiteral("连接已断开，请重新连接")
                   : state == sourcehost::SourceHostClient::HostState::RestartWaiting
                         ? QStringLiteral("正在重新连接")
                         : QStringLiteral("正在连接音源");
    }
    else if (id == activeId_ && hostSourceInfo_.isEmpty())
      status = QStringLiteral("待验证");
    else if (id == activeId_ && !hostSourceInfo_.isEmpty()) {
      status = QStringLiteral("已加载");
      ready = true;
    } else {
      status = map.value("availabilityStatus", QStringLiteral("待检测")).toString();
    }
    if (map.value(QStringLiteral("status")).toString() != status) {
      map.insert(QStringLiteral("status"), status);
      changed = true;
    }
    if (map.value(QStringLiteral("hostReady")).toBool() != ready) {
      map.insert(QStringLiteral("hostReady"), ready);
      changed = true;
    }
    sources_[index] = map;
  }
  if (changed)
    emit sourcesChanged();
}

QString SourceController::hostProviderFor(const QString &sourceId,
                                          const QString &action,
                                          QString *quality) const {
  if (!hostReady())
    return {};
  const int index = indexOf(sourceId);
  if (index < 0 ||
      !sources_.at(index).toMap().value(QStringLiteral("removable")).toBool())
    return {};
  const auto map = sources_.at(index).toMap();
  const auto preferred = map.value(QStringLiteral("hostSourceId"))
                             .toString()
                             .trimmed();
  auto accepts = [action, quality](const QVariantMap &info) {
    if (!hasString(info.value(QStringLiteral("actions")), action))
      return false;
    if (action != QStringLiteral("musicUrl"))
      return true;
    auto qualities = info.value(QStringLiteral("qualitys")).toList();
    if (qualities.isEmpty())
      return false;
    if (quality && !quality->isEmpty()) {
      for (const auto &value : qualities) {
        if (value.toString() == *quality)
          return true;
      }
    }
    if (quality && !qualities.isEmpty())
      *quality = qualities.first().toString();
    return true;
  };
  if (!preferred.isEmpty() && hostSourceInfo_.contains(preferred)) {
    auto info = hostSourceInfo_.value(preferred);
    if (accepts(info))
      return preferred;
  }
  for (auto it = hostSourceInfo_.cbegin(); it != hostSourceInfo_.cend(); ++it) {
    auto info = it.value();
    if (accepts(info))
      return it.key();
  }
  return {};
}

QString SourceController::resolve(const QString &sourceId,
                                  const QString &action,
                                  const QString &quality,
                                  const QVariantMap &musicInfo) {
  const auto normalizedSource =
      sourceId.trimmed().isEmpty() ? activeId_ : sourceId.trimmed();
  if (indexOf(normalizedSource) < 0) {
    setError(QStringLiteral("音源不存在"));
    return {};
  }
  if (!hostReady()) {
    loadActivePlugin();
    setError(hostAvailable_ ? QStringLiteral("音源正在连接，请稍后重试播放")
                            : QStringLiteral("音源宿主不可用"));
    return {};
  }
  if (musicInfo.isEmpty()) {
    setError(QStringLiteral("缺少歌曲信息"));
    return {};
  }
  QString selectedQuality = quality.trimmed();
  const auto requestedProvider = musicInfo.value("source").toString();
  const auto provider = requestedProvider.isEmpty() ? hostProviderFor(normalizedSource, action, &selectedQuality)
      : (hostSourceInfo_.contains(requestedProvider) ? requestedProvider : QString{});
  if (provider.isEmpty()) {
    setError(QStringLiteral("当前音源不支持 %1").arg(action));
    return {};
  }
  if (!pendingLoadId_.isEmpty() || hostSourceInfo_.isEmpty()) {
    setError(QStringLiteral("音源正在初始化，请稍后重试播放"));
    return {};
  }
  const auto info = hostSourceInfo_.value(provider);
  if (normalizedSource != activeId_ || !hasString(info.value("actions"), action)) {
    setError(QStringLiteral("当前音源不支持此平台的请求"));return {};
  }
  if (action == "musicUrl" && !hasString(info.value("qualitys"), selectedQuality)) {
    const auto choices=info.value("qualitys").toList();
    if(choices.isEmpty()){setError(QStringLiteral("当前音源未声明可用音质"));return {};}
    selectedQuality=hasString(info.value("qualitys"),"320k")?QString("320k"):choices.first().toString();
  }
  sourcehost::SourceMessage request;
  request.type = action == QStringLiteral("musicUrl")
                     ? sourcehost::MessageType::ResolveMusicUrl
                     : action == QStringLiteral("lyric")
                           ? sourcehost::MessageType::ResolveLyric
                           : sourcehost::MessageType::ResolvePic;
  request.requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  request.payload.insert(QStringLiteral("source"), provider);
  request.payload.insert(QStringLiteral("type"),
                         action == QStringLiteral("musicUrl")
                             ? selectedQuality
                             : action);
  request.payload.insert(QStringLiteral("musicInfo"),
                         QJsonObject::fromVariantMap(musicInfo));
  pendingResolutions_.insert(request.requestId,
                             {normalizedSource, action, selectedQuality});
  if (!host_->request(request, sourcehost::PluginClientTimeoutMs)) {
    pendingResolutions_.remove(request.requestId);
    setError(QStringLiteral("无法向音源宿主发送请求"));
    return {};
  }
  setError({});
  setStatus(QStringLiteral("正在请求音源…"));
  return request.requestId;
}

void SourceController::recordCapabilities(const QString &id, const QJsonObject &providers) {
  QStringList actions, names;
  for (auto it = providers.begin(); it != providers.end(); ++it) {
    const auto provider = it.value().toObject();
    names.append(provider.value("name").toString(it.key()));
    for (const auto &action : provider.value("actions").toArray()) actions.append(action.toString());
  }
  actions.removeDuplicates();
  const bool useful = actions.contains("musicUrl") || actions.contains("search");
  updateSource(id, {{"capabilities", providers.toVariantMap()},
      {"providerNames", names.join(" / ")}, {"searchSupported", actions.contains("search")},
      {"capabilityText", actions.contains("search") ? (actions.contains("musicUrl") ? QStringLiteral("脚本搜索 · 播放解析") : QStringLiteral("仅脚本搜索"))
                            : actions.contains("musicUrl") ? QStringLiteral("仅播放解析") : QStringLiteral("无可用动作")},
      {"availabilityStatus", useful ? QStringLiteral("初始化通过") : QStringLiteral("无可用能力")},
      {"lastCheck", QDateTime::currentDateTime().toString(Qt::ISODate)}, {"checkError", QString{}}});
}

QString SourceController::checkSource(const QString &id) { return requestScript(id, "check"); }

QString SourceController::searchScript(const QString &id, const QString &keyword, int page) {
  return requestScript(id, "search", {{"keyword", keyword.trimmed().left(1024)},
                                    {"page", qMax(1, page)}, {"limit", 30}});
}

QString SourceController::requestScript(const QString &id, const QString &action,
                                        const QVariantMap &info, const QString &quality) {
  const auto index = indexOf(id);
  if (index < 0 || !hostAvailable_ || scriptRequests_.size() >= 8) {
    setError(index < 0 ? QStringLiteral("该曲目的洛雪音源已移除，请重新导入")
        : !hostAvailable_ ? QStringLiteral("音源宿主不可用") : QStringLiteral("音源请求过多，请稍后重试"));
    return {};
  }
  const auto source = sources_.at(index).toMap();
  const auto operationId = QUuid::createUuid().toString(QUuid::WithoutBraces);
  auto *client = new sourcehost::SourceHostClient(hostExecutablePath_, this);
  client->setAutoRestart(false);
  scriptRequests_.insert(operationId, client);
  // Each pinned operation has a bounded isolated host. Loading/searching a
  // different source never unloads the source serving the current player.
  struct State {
    QHash<QString, QString> providers;
    QVariantList rows;
    QStringList errors;
    int total = 0;
    int pages = 1;
  };
  auto state = std::make_shared<State>();
  const auto loadId = operationId + ".load";
  auto finish = [this, client, operationId, id, action](QVariantMap data, const QString &error) {
    if (!scriptRequests_.remove(operationId)) return;
    if (action == "check") updateSource(id, {{"status", error.isEmpty() ? QStringLiteral("初始化通过") : QStringLiteral("检测失败")},
        {"availabilityStatus", error.isEmpty() ? QStringLiteral("初始化通过") : QStringLiteral("检测失败")},
        {"checkError", error}, {"lastCheck", QDateTime::currentDateTime().toString(Qt::ISODate)}});
    if (action != "check") updateSource(id, {{"lastRequestStatus", error.isEmpty() ? QStringLiteral("最近请求成功") : QStringLiteral("最近请求失败")},
        {"checkError", error}});
    client->disconnect(this);
    client->stop();
    client->deleteLater();
    emit resolutionFinished(operationId, id, action, data, error);
  };
  if (action == "check") updateSource(id, {{"status", QStringLiteral("检测中…")}, {"checkError", QString{}}});
  connect(client, &sourcehost::SourceHostClient::ready, this, [client, source, loadId, finish] {
    sourcehost::SourceMessage request;
    request.type = sourcehost::MessageType::LoadPlugin;
    request.requestId = loadId;
    request.payload = {{"path", source.value("path").toString()}};
    if (!client->request(request, sourcehost::PluginClientTimeoutMs)) finish({}, QStringLiteral("无法加载音源"));
  });
  connect(client, &sourcehost::SourceHostClient::requestFinished, this,
      [finish](const QString &, sourcehost::SourceHostClient::RequestTerminal terminal) {
    using Terminal = sourcehost::SourceHostClient::RequestTerminal;
    if (terminal != Terminal::Succeeded && terminal != Terminal::RemoteError)
      finish({}, terminalName(terminal));
  });
  connect(client, &sourcehost::SourceHostClient::crashed, this,
      [finish] { finish({}, QStringLiteral("音源宿主异常退出")); });
  connect(client, &sourcehost::SourceHostClient::protocolError, this,
      [finish](const QString &error) { finish({}, error); });
  connect(client, &sourcehost::SourceHostClient::messageReceived, this,
      [this, client, operationId, id, source, action, info, quality, state, loadId, finish]
      (const sourcehost::SourceMessage &message) {
    using Type = sourcehost::MessageType;
    if (message.type != Type::Result && message.type != Type::Error) return;
    if (message.requestId == loadId) {
      if (message.type == Type::Error || !message.payload.value("ok").toBool()) {
        const auto error = errorMessage(message.payload);
        updateSource(id, {{"availabilityStatus", QStringLiteral("初始化失败")}, {"checkError", error}});
        finish({}, error); return;
      }
      const auto providers = message.payload.value("sources").toObject();
      recordCapabilities(id, providers);
      if (action == "check") {
        if (providers.isEmpty()) finish({}, QStringLiteral("脚本未声明可用能力"));
        else finish({{"capabilities", providers.toVariantMap()}}, {});
        return;
      }
      QStringList selected;
      for (auto it = providers.begin(); it != providers.end(); ++it) {
        if (!hasString(it.value().toObject().value("actions").toVariant(), action)) continue;
        if (action == "search" || it.key() == info.value("source").toString()) selected.append(it.key());
      }
      if (selected.isEmpty()) {
        finish({}, action == "search" ? QStringLiteral("该脚本仅支持播放解析，未提供搜索。请使用平台搜索。")
                                      : QStringLiteral("该脚本不支持此曲目的请求")); return;
      }
      // Register all IDs before sending: a failed write can complete inline.
      for (const auto &provider : selected) state->providers.insert(operationId + "." + provider, provider);
      for (const auto &provider : selected) {
        QString requestedQuality = quality;
        const auto qualities = providers.value(provider).toObject().value("qualitys").toArray();
        if (action == "musicUrl" && !hasString(qualities.toVariantList(), requestedQuality)) {
          if (qualities.isEmpty()) { finish({}, QStringLiteral("音源未声明可用音质")); return; }
          requestedQuality = hasString(qualities.toVariantList(), "320k") ? QStringLiteral("320k") : qualities.first().toString();
        }
        sourcehost::SourceMessage request;
        request.requestId = operationId + "." + provider;
        request.type = action == "search" ? Type::Search : action == "lyric" ? Type::ResolveLyric
                     : action == "pic" ? Type::ResolvePic : Type::ResolveMusicUrl;
        request.payload = {{"source", provider}, {"type", action == "musicUrl" ? requestedQuality : action},
                           {"musicInfo", QJsonObject::fromVariantMap(info)}};
        if (!client->request(request, sourcehost::PluginClientTimeoutMs)) { finish({}, QStringLiteral("无法发送音源请求")); return; }
      }
      return;
    }
    if (!state->providers.contains(message.requestId)) return;
    const auto provider = state->providers.take(message.requestId);
    const auto error = message.type == Type::Error ? errorMessage(message.payload) : QString{};
    auto data = message.payload.value("data").toObject().toVariantMap();
    if (action != "search") {
      if (message.payload.value("data").isString()) data["url"] = message.payload.value("data").toString();
      data["source"] = provider;
      finish(data, error); return;
    }
    if (!error.isEmpty()) state->errors.append(error);
    else {
      const auto rows = data.value("rows", data.value("list", data.value("songs"))).toList();
      for (const auto &value : rows.mid(0, 100)) {
        auto row = value.toMap();
        const auto rid = row.value("rid", row.value("songmid", row.value("id", row.value("hash")))).toString();
        const auto title = row.value("title", row.value("name")).toString();
        if (rid.isEmpty() || title.isEmpty()) continue;
        // Keep the script's native metadata intact for later resolution.
        row["scriptMusicInfo"] = row;
        row["rid"] = rid; row["title"] = title;
        row["artist"] = row.value("artist", row.value("singer"));
        row["album"] = row.value("album", row.value("albumName"));
        row["artwork"] = row.value("artwork", row.value("img", row.value("pic")));
        qint64 durationMs = row.value("durationMs").toLongLong();
        if (durationMs <= 0) {
          const auto duration = row.value("duration", row.value("interval")).toString();
          const auto parts = duration.split(':');
          double seconds = 0;
          bool valid = parts.size() <= 3;
          for (const auto &part : parts) {
            bool numeric = false;
            const auto number = part.toDouble(&numeric);
            valid = valid && numeric && number >= 0 && number <= 31536000;
            seconds = seconds * 60 + number;
          }
          if (valid && seconds <= 31536000) durationMs = qint64(seconds * 1000);
        }
        row["durationMs"] = qMax<qint64>(0, durationMs);
        row["duration"] = QStringLiteral("%1:%2").arg(qMax<qint64>(0, durationMs) / 60000)
            .arg(qMax<qint64>(0, durationMs) / 1000 % 60, 2, 10, QChar('0'));
        row["source"] = provider; row["originKind"] = "lx";
        row["originSourceId"] = id; row["originSourceName"] = source.value("name");
        row["trackId"] = online::scriptTrackKey(row);
        // A result cannot inject a local file or bypass its script resolver.
        row.remove("localPath"); row.remove("remoteUrl"); row.remove("radioId"); row.remove("radioProvider");
        state->rows.append(row);
      }
      const int total = data.value("total", rows.size()).toInt();
      state->total += qMax(0, total);
      state->pages = qMax(state->pages, data.value("pages", qMax(1, (total + 29) / 30)).toInt());
    }
    if (state->providers.isEmpty()) finish({{"rows", state->rows}, {"total", state->total},
        {"pages", state->pages}, {"warning", state->errors.join("；")}},
        state->rows.isEmpty() ? state->errors.join("；") : QString{});
  });
  // Defer so the caller can store its request ID before even an immediate
  // launch failure emits the completion signal.
  QTimer::singleShot(0, client, [this, client, operationId, finish] {
    if (!scriptRequests_.contains(operationId)) return;
    if (!client->start()) finish({}, QStringLiteral("无法启动音源宿主"));
  });
  return operationId;
}

QString SourceController::resolveMusicUrl(const QString &sourceId,
                                           const QString &quality,
                                           const QVariantMap &musicInfo) {
  if (online::isScriptTrack(musicInfo))
    return requestScript(musicInfo.value("originSourceId").toString(), "musicUrl", musicInfo, quality);
  if (musicInfo.value("source") == "bili") {
    auto requestId = std::make_shared<QString>();
    *requestId = bilibili_.audio(musicInfo, quality, this,
        [this, requestId](QVariantMap data, QString error) {
          emit resolutionFinished(*requestId, "bili", "musicUrl", data, error);
        });
    return *requestId;
  }
  return resolve(sourceId, QStringLiteral("musicUrl"), quality, musicInfo);
}

QString SourceController::resolveLyric(const QString &sourceId,
                                       const QVariantMap &musicInfo) {
  if (online::isScriptTrack(musicInfo))
    return requestScript(musicInfo.value("originSourceId").toString(), "lyric", musicInfo);
  return resolve(sourceId, QStringLiteral("lyric"), QStringLiteral("lyric"),
                 musicInfo);
}

QString SourceController::resolvePic(const QString &sourceId,
                                     const QVariantMap &musicInfo) {
  if (online::isScriptTrack(musicInfo))
    return requestScript(musicInfo.value("originSourceId").toString(), "pic", musicInfo);
  return resolve(sourceId, QStringLiteral("pic"), QStringLiteral("pic"),
                 musicInfo);
}

bool SourceController::cancelResolution(const QString &requestId) {
  const auto normalized = requestId.trimmed();
  if (auto requestHost = scriptRequests_.take(normalized)) {
    requestHost->disconnect(this); requestHost->stop(); requestHost->deleteLater();
    return true;
  }
  if (bilibili_.cancel(normalized)) return true;
  if (normalized.isEmpty() || !pendingResolutions_.contains(normalized) ||
      !host_)
    return false;
  host_->cancel(normalized.toStdString());
  return true;
}

void SourceController::restartHost() {
  if (!hostEnabled_)
    return;
  if (!hostAvailable_) {
    initializeHost();
    return;
  }
  if (!host_) {
    initializeHost();
    return;
  }
  if (host_->state() == sourcehost::SourceHostClient::HostState::Stopped) {
    restartRequested_ = false;
    host_->start();
    return;
  }
  if (restartRequested_) return;
  restartRequested_ = true;
  hostSourceInfo_.clear();
  host_->stop();
}

void SourceController::refresh() {
  if (hostEnabled_)
    loadActivePlugin();
  else
    updateCustomStatuses();
  setStatus(QStringLiteral("音源列表已刷新"));
  emit sourcesChanged();
}

void SourceController::setStatus(const QString &value) {
  if (status_ == value)
    return;
  status_ = value;
  emit statusChanged();
}

void SourceController::setError(const QString &value) {
  if (error_ == value)
    return;
  error_ = value;
  emit errorChanged();
}

} // namespace listenfree::qmlbridge
