#include "wallpaper_library.h"
#include "controllers.h"
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QSettings>
#include <QtConcurrentRun>
#include <algorithm>

namespace listenfree::qmlbridge {
namespace {
QByteArray readSmall(const QString& path, qint64 limit) {
    QFile file(path);
    return file.size() <= limit && file.open(QIODevice::ReadOnly) ? file.read(limit + 1) : QByteArray{};
}
QString key(const QString& path) { return QDir::cleanPath(path).toCaseFolded(); }
}
WallpaperLibrary::WallpaperLibrary(QObject* parent, const QStringList& steamRoots) : QObject(parent), roots_(steamRoots) {
    connect(&watcher_, &QFutureWatcher<WallpaperScan>::finished, this, [this] {
        busy_ = false;
        auto result = watcher_.future().takeResult();
        if (!cancelled_->load()) result_ = std::move(result);
        emit changed();
        if (rescan_) { rescan_ = false; scan(pending_); }
    });
}
WallpaperLibrary::~WallpaperLibrary() {
    if (cancelled_) *cancelled_ = true;
    watcher_.waitForFinished();
}
QString WallpaperLibrary::summary() const {
    if (busy_) return tr("正在查找已下载的视频壁纸…");
    if (result_.roots.isEmpty()) return tr("未找到壁纸目录，可手动指定 Steam 库或壁纸文件夹。");
    if (result_.items.isEmpty()) return tr("已找到壁纸目录，但没有可用的视频壁纸；场景、网页和未下载完整的项目不会显示。");
    return tr("找到 %1 个视频壁纸，已跳过 %2 个其他类型或不完整项目。%3")
        .arg(result_.items.size()).arg(result_.skipped)
        .arg(result_.limited ? tr("目录较大，请指定更具体的文件夹查看其余壁纸。") : QString{});
}
void WallpaperLibrary::scan(const QUrl& extraFolder) {
    if (busy_) { *cancelled_ = true; pending_ = extraFolder; rescan_ = true; return; }
    cancelled_ = std::make_shared<std::atomic_bool>(false);
    busy_ = true; result_ = {}; emit changed();
    const auto cancelled = cancelled_;
    const auto extra = extraFolder.isLocalFile() ? extraFolder.toLocalFile() : QString{};
    const auto roots = roots_;
    watcher_.setFuture(QtConcurrent::run([cancelled, extra, roots] { return discover(roots.isEmpty() ? steamRoots() : roots, extra, cancelled); }));
}
void WallpaperLibrary::cancel() {
    rescan_ = false;
    if (cancelled_) *cancelled_ = true;
    result_ = {}; emit changed();
}
QStringList WallpaperLibrary::steamRoots() {
    QStringList roots;
#ifdef Q_OS_WIN
    QSettings user("HKEY_CURRENT_USER\\Software\\Valve\\Steam", QSettings::NativeFormat);
    roots << user.value("SteamPath").toString();
    for (const auto* path : {"HKEY_LOCAL_MACHINE\\SOFTWARE\\Valve\\Steam", "HKEY_LOCAL_MACHINE\\SOFTWARE\\WOW6432Node\\Valve\\Steam"}) {
        QSettings machine(QString::fromLatin1(path), QSettings::NativeFormat);
        roots << machine.value("InstallPath").toString();
    }
    const auto programFiles = qEnvironmentVariable("ProgramFiles(x86)");
    if (!programFiles.isEmpty()) roots << QDir(programFiles).filePath("Steam");
#endif
    roots.removeAll(QString{}); roots.removeDuplicates(); return roots;
}
WallpaperScan WallpaperLibrary::discover(const QStringList& steam, const QString& extra,
                                        const std::shared_ptr<std::atomic_bool>& cancelled) {
    WallpaperScan result;
    QStringList libraries = steam;
    // Extract only the quoted path fields used by Steam's libraryfolders.vdf;
    // no need to interpret unrelated app IDs or implement a general VDF parser.
    const QRegularExpression pathField(QStringLiteral(R"vdf(^\s*"(?:path|\d+)"\s+"((?:\\.|[^"\\])*)"\s*$)vdf"), QRegularExpression::MultilineOption);
    for (const auto& root : steam) {
        if (*cancelled) return {};
        for (const auto* relative : {"steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"}) {
            auto matches = pathField.globalMatch(QString::fromUtf8(readSmall(QDir(root).filePath(relative), 4 * 1024 * 1024)));
            while (matches.hasNext()) {
                auto path = matches.next().captured(1);
                path.replace("\\\\", "\\"); path.replace("\\\"", "\"");
                if (QDir::isAbsolutePath(path)) libraries << QDir::fromNativeSeparators(path);
            }
        }
    }
    QStringList candidates;
    const auto appendRoot = [&](const QString& root) {
        const QDir directory(root);
        candidates << directory.filePath("steamapps/workshop/content/431960");
        for (const auto* name : {"myprojects", "defaultprojects", "backup"})
            candidates << directory.filePath("steamapps/common/wallpaper_engine/projects/" + QString::fromLatin1(name));
    };
    for (const auto& root : libraries) if (!root.isEmpty()) appendRoot(root);
    if (!extra.isEmpty()) {
        candidates << extra; appendRoot(extra);
        const QDir directory(extra);
        candidates << directory.filePath("workshop/content/431960") << directory.filePath("content/431960") << directory.filePath("431960");
        for (const auto* name : {"myprojects", "defaultprojects", "backup"})
            candidates << directory.filePath("projects/" + QString::fromLatin1(name)) << directory.filePath(name);
    }
    QSet<QString> roots, projects;
    SettingsController inspector;
    int inspected = 0;
    const auto inspect = [&](const QString& project) {
        if (*cancelled) return;
        const QFileInfo info(project);
        const auto canonical = info.canonicalFilePath();
        if (canonical.isEmpty() || projects.contains(key(canonical))) return;
        projects.insert(key(canonical));
        const auto object = QJsonDocument::fromJson(readSmall(canonical, 1024 * 1024)).object();
        if (object.value("type").toString().compare("video", Qt::CaseInsensitive) != 0) { ++result.skipped; return; }
        const auto media = inspector.resolveBackground(QUrl::fromLocalFile(canonical), true);
        if (media.value("kind") != "Video") { ++result.skipped; return; }
        QString title = object.value("title").toString().trimmed().left(512);
        if (title.isEmpty()) title = info.dir().dirName();
        QUrl preview;
        const auto previewName = object.value("preview").toString();
        const QFileInfo previewFile(info.dir().filePath(previewName));
        const auto previewPath = previewFile.canonicalFilePath();
        const QStringList images{"jpg", "jpeg", "png", "webp", "bmp", "gif"};
        if (!previewName.isEmpty() && previewFile.isFile() && images.contains(previewFile.suffix().toLower()) &&
            previewPath.startsWith(info.dir().canonicalPath() + '/', Qt::CaseInsensitive)) preview = QUrl::fromLocalFile(previewPath);
        result.items << QVariantMap{{"title", title}, {"project", QUrl::fromLocalFile(canonical)},
            {"preview", preview}, {"source", media.value("source")}, {"directory", QDir::toNativeSeparators(info.absolutePath())}};
    };
    for (const auto& candidate : candidates) {
        if (*cancelled) return {};
        const auto canonical = QFileInfo(candidate).canonicalFilePath();
        if (canonical.isEmpty() || !QFileInfo(canonical).isDir() || roots.contains(key(canonical))) continue;
        roots.insert(key(canonical)); result.roots << QDir::toNativeSeparators(canonical);
        inspect(QDir(canonical).filePath("project.json"));
        QDirIterator children(canonical, QDir::Dirs | QDir::NoDotAndDotDot | QDir::NoSymLinks);
        while (children.hasNext()) {
            if (*cancelled) return {};
            if (++inspected > 10000) { result.limited = true; break; }
            inspect(QDir(children.next()).filePath("project.json"));
        }
        if (result.limited) break;
    }
    std::sort(result.items.begin(), result.items.end(), [](const QVariant& a, const QVariant& b) {
        return QString::localeAwareCompare(a.toMap().value("title").toString(), b.toMap().value("title").toString()) < 0;
    });
    return result;
}
}
