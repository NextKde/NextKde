#include "settings_transfer.h"
#include "settings_schema.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <cmath>

namespace listenfree::qmlbridge {
namespace {
bool validValue(const QJsonObject& rule, const QJsonValue& value) {
    const auto fallback = rule.value("default");
    if (fallback.type() != value.type()) return false;
    if (value.isString() && (value.toString().size() > 4096 || value.toString().contains(QChar::Null))) return false;
    if (rule.contains("values") && !rule.value("values").toArray().contains(value)) return false;
    if (value.isDouble()) {
        const auto n = value.toDouble();
        if (!std::isfinite(n) || n < rule.value("min").toDouble(-1e9) || n > rule.value("max").toDouble(1e9)) return false;
    }
    return true;
}
QString localPath(const QUrl& url) { return url.isLocalFile() ? url.toLocalFile() : QString{}; }
}
SettingsTransfer::SettingsTransfer(infrastructure::database::Database& db, SettingsController& settings,
                                 LibraryController& library, QObject* parent)
    : QObject(parent), db_(db), settings_(settings), library_(library) {
    connect(&settings_, &SettingsController::valueChanged, this, [this](const QString& key, const QVariant&) {
        if (key == "ui.language") QMetaObject::invokeMethod(this, [this] { emit categoriesChanged(); }, Qt::QueuedConnection);
    });
}
QJsonObject SettingsTransfer::schema() {
    auto rules=QJsonDocument::fromJson(settingsSchema).object();
    auto folder=rules.value("download.folder").toObject();folder["default"]=QStandardPaths::writableLocation(QStandardPaths::MusicLocation)+"/ListenFree";
    rules["download.folder"]=folder;return rules;
}
QVariantList SettingsTransfer::categories() const {
    return {QVariantMap{{"id","general"},{"name",tr("基本")}}, QVariantMap{{"id","library"},{"name",tr("资料库")}},
        QVariantMap{{"id","playback"},{"name",tr("播放")}}, QVariantMap{{"id","appearance"},{"name",tr("外观")}},
        QVariantMap{{"id","download"},{"name",tr("下载")}}, QVariantMap{{"id","source"},{"name",tr("音源")}},
        QVariantMap{{"id","shortcuts"},{"name",tr("快捷键")}}, QVariantMap{{"id","backup"},{"name",tr("备份与恢复")}},
        QVariantMap{{"id","other"},{"name",tr("其他")}}};
}
bool SettingsTransfer::exportFile(const QUrl& url, const QStringList& selected) {
    if (selected.isEmpty() || localPath(url).isEmpty()) return false;
    QJsonObject values;
    const auto rules = schema();
    const bool paths = settings_.value("settingsBackup.includeDevicePaths",false).toBool();
    for (auto it=rules.begin(); it!=rules.end(); ++it) {
        const auto rule=it.value().toObject();
        if (!selected.contains(rule.value("category").toString()) || (rule.value("path").toBool() && !paths)) continue;
        const auto value=QJsonValue::fromVariant(settings_.value(it.key(),rule.value("default").toVariant()));
        if (validValue(rule,value)) values.insert(it.key(),value);
    }
    QJsonObject document{{"format","ListenFree.Settings"},{"version",1},
        {"appVersion",QCoreApplication::applicationVersion()}, {"exportedAt",QDateTime::currentDateTimeUtc().toString(Qt::ISODate)},
        {"categories",QJsonArray::fromStringList(selected)}, {"settings",values}};
    if (paths && selected.contains("library")) document.insert("libraryFolders",QJsonArray::fromStringList(library_.roots()));
    QSaveFile file(localPath(url));
    const auto bytes=QJsonDocument(document).toJson();
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes)!=bytes.size() || !file.commit()) {
        emit notice(tr("设置导出失败，请检查目标目录权限。")); return false;
    }
    emit notice(tr("设置已导出。")); return true;
}
bool SettingsTransfer::inspectFile(const QUrl& url) {
    pending_={}; pendingRoots_.clear(); previewReady_=false; preview_.clear(); emit previewChanged();
    QFile file(localPath(url));
    if (!file.open(QIODevice::ReadOnly) || file.size()>2*1024*1024) { emit notice(tr("无法读取设置备份。")); return false; }
    QJsonParseError error;
    const auto json=QJsonDocument::fromJson(file.readAll(),&error);
    const auto doc=json.object();
    if (error.error!=QJsonParseError::NoError || doc.value("format")!="ListenFree.Settings" || doc.value("version")!=1 || !doc.value("settings").isObject() || !doc.value("categories").isArray()) {
        emit notice(tr("不是受支持的 ListenFree 设置备份，未修改任何设置。")); return false;
    }
    const auto rules=schema(); const auto values=doc.value("settings").toObject(); int ignored=0;
    QStringList lines;
    createPaths_=settings_.value("settingsBackup.devicePathHandling","Ignore")=="Create";
    for (auto it=values.begin(); it!=values.end(); ++it) {
        const auto rule=rules.value(it.key()).toObject();
        if (rule.isEmpty()) { ++ignored; continue; }
        if (!validValue(rule,it.value()) || !doc.value("categories").toArray().contains(rule.value("category"))) {
            emit notice(tr("备份包含无效设置，未修改任何设置：%1").arg(it.key())); pending_={}; return false;
        }
        if (rule.value("path").toBool()) {
            if (!createPaths_) { ++ignored; continue; }
            QString path=it.value().toString();
            if (it.key()=="background.image" || it.key()=="background.video" || it.key()=="background.wallpaper" || it.key()=="background.wallpaperFolder") {
                const QUrl url(path);
                if (!path.isEmpty() && !url.isLocalFile()) { emit notice(tr("备份中的背景必须是本地文件。")); pending_={}; return false; }
                path=url.toLocalFile();
            }
            if (!path.isEmpty() && !QDir::isAbsolutePath(path)) { emit notice(tr("备份中的本机路径无效。")); pending_={}; return false; }
        }
        pending_.insert(it.key(),it.value());
        lines.append(it.key()+" = "+it.value().toVariant().toString());
    }
    if (createPaths_ && doc.contains("libraryFolders")) {
        if (!doc.value("libraryFolders").isArray() || !doc.value("categories").toArray().contains("library")) return false;
        for (const auto& value: doc.value("libraryFolders").toArray()) {
            if (!value.isString() || !QDir::isAbsolutePath(value.toString()) || value.toString().contains(QChar::Null)) {
                emit notice(tr("备份中的音乐目录无效。")); pending_={}; return false;
            }
            pendingRoots_.append(QDir::cleanPath(value.toString()));
            lines.append(tr("音乐目录：%1").arg(value.toString()));
        }
    }
    preview_=tr("可导入 %1 项设置；忽略 %2 项。确认后应用所选分类。\n").arg(pending_.size()).arg(ignored)+lines.join('\n');
    previewReady_=true; emit previewChanged(); return true;
}
bool SettingsTransfer::apply(const QJsonObject& values, const QStringList& roots) {
    if (library_.scanning() || library_.maintenance()) { emit notice(tr("请先结束资料库扫描或重复歌曲处理。")); return false; }
    // Creation is explicitly selected in the preview; never remove existing folders.
    for (const auto& path:roots) if (!QDir().mkpath(path)) { emit notice(tr("无法创建音乐目录：%1").arg(path)); return false; }
    if (values.contains("download.folder")) {
        const auto path=values.value("download.folder").toString();
        if (!path.isEmpty() && !QDir().mkpath(path)) { emit notice(tr("无法创建下载目录。")); return false; }
    }
    QVariantMap changes;
    for (auto it=values.begin();it!=values.end();++it) changes.insert(it.key(),it.value().toVariant());
    QVariantMap previous;
    for(auto it=changes.begin();it!=changes.end();++it)previous.insert(it.key(),settings_.value(it.key(),schema().value(it.key()).toObject().value("default").toVariant()));
    if (!db_.applySettings(changes, roots, [&]{return settings_.reloadValues(changes);})) {
        settings_.reloadValues(previous);emit notice(tr("设置保存失败，原设置保持不变。")); return false;
    }
    library_.reloadRoots();
    emit notice(tr("设置已应用。")); return true;
}
bool SettingsTransfer::applyImport(const QStringList& selected) {
    if (!previewReady_ || selected.isEmpty()) return false;
    const auto rules=schema(); QJsonObject values;
    for (auto it=pending_.begin();it!=pending_.end();++it)
        if (selected.contains(rules.value(it.key()).toObject().value("category").toString())) values.insert(it.key(),it.value());
    if (!apply(values,selected.contains("library")?pendingRoots_:QStringList{})) return false;
    previewReady_=false; pending_={}; pendingRoots_.clear(); return true;
}
bool SettingsTransfer::resetDefaults(const QStringList& selected) {
    if (selected.isEmpty()) return false;
    const auto rules=schema(); QJsonObject values;
    for (auto it=rules.begin();it!=rules.end();++it) {
        const auto rule=it.value().toObject();
        // Library roots live outside public preferences and are preserved.
        if (selected.contains(rule.value("category").toString())) values.insert(it.key(),rule.value("default"));
    }
    return apply(values,{});
}
}
