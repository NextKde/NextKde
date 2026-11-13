#include "LockScreenSettings.h"

#include <KConfig>
#include <KConfigGroup>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>

namespace {
const QString shellId = QStringLiteral("org.kos.desktop");
const QByteArray ownership = "KOS lockscreen v1\n";

// Reject links at every ancestor, including dangling links and links nested in
// the package. Never recursively delete/copy through a user's development link.
bool safePath(const QString &path)
{
    QString current = QDir::cleanPath(QFileInfo(path).absoluteFilePath());
    while (!current.isEmpty()) {
        const QFileInfo info(current);
        if (info.isSymLink()) return false;
        const QString parent = info.absolutePath();
        if (parent == current) break;
        current = parent;
    }
    return true;
}
bool safeTree(const QString &path)
{
    if (!safePath(path) || !QFileInfo(path).isDir()) return false;
    for (const auto &entry : QDir(path).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System)) {
        if (entry.isSymLink() || (!entry.isFile() && !entry.isDir())) return false;
        if (entry.isDir() && !safeTree(entry.absoluteFilePath())) return false;
    }
    return true;
}
QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}
bool validPackage(const QString &path, bool skinRequired)
{
    if (!safeTree(path)) return false;
    const auto metadata = QJsonDocument::fromJson(readFile(path + "/metadata.json")).object();
    return metadata.value("KPlugin").toObject().value("Id").toString() == shellId
        && metadata.value("X-Plasma-APIVersion").toString() == "2"
        && QFileInfo(path + "/contents/defaults").isFile()
        && (!skinRequired || (QFileInfo(path + "/contents/lockscreen/LockScreen.qml").isFile()
            && !readFile(path + "/contents/lockscreen/LockScreen.qml").isEmpty()));
}
bool ownedSkin(const QString &path)
{
    if (!safeTree(path) || !QFileInfo(path + "/LockScreen.qml").isFile()
        || readFile(path + "/LockScreen.qml").isEmpty()) return false;
    if (readFile(path + "/.kos-lockscreen") == ownership) return true;
    // Upgrade the shipped pre-marker skin only, never an arbitrary replacement.
    return QCryptographicHash::hash(readFile(path + "/LockScreen.qml"), QCryptographicHash::Sha256).toHex()
        == "1345ca7a349c8d6774566426a73bf82ddf90f6cc622db4ac39c1799fb5ed9029";
}
bool copyTree(const QString &source, const QString &destination)
{
    if (!safeTree(source) || !QDir().mkpath(destination)) return false;
    for (const auto &entry : QDir(source).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System)) {
        const QString target = destination + '/' + entry.fileName();
        if (entry.isDir() ? !copyTree(entry.absoluteFilePath(), target) : !QFile::copy(entry.absoluteFilePath(), target)) return false;
    }
    return true;
}
bool markSkin(const QString &path)
{
    QFile file(path + "/.kos-lockscreen");
    return file.open(QIODevice::WriteOnly | QIODevice::Truncate) && file.write(ownership) == ownership.size();
}
// Stage on the same filesystem. Linux rename exchange guarantees the old entry
// remains usable on every failure, and readers never observe a half-copied skin.
bool publish(const QString &staged, const QString &target, QString &error)
{
    if (!safePath(target)) { error = QStringLiteral("Refusing a symlinked lock screen path"); return false; }
    int result;
    if (QFileInfo::exists(target)) {
#ifdef SYS_renameat2
        result = syscall(SYS_renameat2, AT_FDCWD, QFile::encodeName(staged).constData(),
                         AT_FDCWD, QFile::encodeName(target).constData(), 2 /* RENAME_EXCHANGE */);
#else
        errno = ENOSYS;
        result = -1;
#endif
    } else {
        result = ::rename(QFile::encodeName(staged).constData(), QFile::encodeName(target).constData());
    }
    if (result != 0) error = QStringLiteral("Could not switch the lock screen safely: %1").arg(QString::fromLocal8Bit(std::strerror(errno)));
    return result == 0;
}
QString selectedShell(const QString &configDir)
{
    KConfig config(configDir + "/plasmashellrc", KConfig::SimpleConfig);
    return KConfigGroup(&config, "Shell").readEntry("ShellPackage", QString());
}
QString mutationLock(const QString &data)
{
    return data + "/kos/lockscreen-theme.lock";
}
bool prepareLock(const QString &data)
{
    return safePath(data + "/kos") && QDir().mkpath(data + "/kos")
        && safePath(mutationLock(data));
}
}

LockScreenSettings::Paths LockScreenSettings::defaultPaths()
{
    const QString data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    QString resource = QStandardPaths::locate(QStandardPaths::GenericDataLocation,
        QStringLiteral("kos/lockscreen"), QStandardPaths::LocateDirectory);
    if (resource.isEmpty()) resource = QDir::cleanPath(QCoreApplication::applicationDirPath() + "/../share/kos/lockscreen");
    // Use the effective package, not a hidden user copy behind a different root.
    const QString shell = QStandardPaths::locate(QStandardPaths::GenericDataLocation,
        QStringLiteral("plasma/shells/org.kos.desktop"), QStandardPaths::LocateDirectory);
    const QString shellData = shell.isEmpty() ? data : QDir::cleanPath(shell + "/../../..");
    return {QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation), shellData, resource};
}
LockScreenSettings::LockScreenSettings(QObject *parent) : LockScreenSettings(defaultPaths(), parent) {}
LockScreenSettings::LockScreenSettings(const Paths &paths, QObject *parent)
    : QObject(parent), m_paths(paths), m_library(this)
{
    connect(&m_library, &WallpaperLibrary::thumbnailReady, this, &LockScreenSettings::thumbnailReady);
}
QString LockScreenSettings::shellPath() const { return m_paths.data + "/plasma/shells/" + shellId; }
bool LockScreenSettings::finish(bool success, const QString &error)
{
    m_error = success ? QString() : error;
    emit changed();
    return success;
}
QVariantMap LockScreenSettings::state() const
{
    KConfig config(m_paths.config + "/kscreenlockerrc", KConfig::SimpleConfig);
    const KConfigGroup greeter(&config, "Greeter");
    const auto wallpaper = greeter.group("Wallpaper").group("org.kde.image").group("General");
    const auto appearance = greeter.group("LnF").group("General");
    const bool available = validPackage(m_paths.resources, true);
    const bool packageValid = validPackage(shellPath(), false);
    const bool installed = packageValid && ownedSkin(shellPath() + "/contents/lockscreen");
    const bool selected = selectedShell(m_paths.config) == shellId;
    const bool active = selected && installed;
    QString statusError = m_error;
    if (statusError.isEmpty() && !selected) statusError = QStringLiteral("Select the KOS desktop before changing its lock screen");
    if (statusError.isEmpty() && !packageValid) statusError = QStringLiteral("The installed KOS desktop package is missing or unsafe");
    if (statusError.isEmpty() && QFileInfo::exists(shellPath() + "/contents/lockscreen") && !installed)
        statusError = QStringLiteral("An unrecognized lock screen is installed; it will not be replaced");
    if (statusError.isEmpty() && !available) statusError = QStringLiteral("KOS lock screen resources are unavailable; reinstall KOS");
    return {{"available", available}, {"installed", installed}, {"active", active},
        {"canChangeTheme", selected && packageValid}, {"theme", active ? "kos" : "system"},
        {"error", statusError}, {"wallpaper", wallpaper.readEntry("Image", QString())},
        {"showMediaControls", appearance.readEntry("showMediaControls", true)},
        {"kosShowNotifications", appearance.readEntry("kosShowNotifications", false)}};
}
bool LockScreenSettings::setTheme(const QString &theme)
{
    if (theme != "kos" && theme != "system") return finish(false, QStringLiteral("Unknown lock screen theme"));
    if (!prepareLock(m_paths.data)) return finish(false, QStringLiteral("Refusing a symlinked or unwritable lock screen path"));
    QLockFile lock(mutationLock(m_paths.data));
    if (!lock.tryLock(0)) return finish(false, QStringLiteral("Lock screen settings are being updated; please retry"));
    if (selectedShell(m_paths.config) != shellId)
        return finish(false, QStringLiteral("Select the KOS desktop before changing its lock screen"));
    if (!validPackage(shellPath(), false))
        return finish(false, QStringLiteral("The installed KOS desktop package is missing or unsafe"));
    const QString target = shellPath() + "/contents/lockscreen";
    if (QFileInfo::exists(target) && !ownedSkin(target))
        return finish(false, QStringLiteral("An unrecognized lock screen is installed; it will not be replaced"));
    if (theme == "system") {
        if (!QFileInfo::exists(target)) return finish(true);
        // Removing just this registered entry invokes Plasma's native fallback.
        QTemporaryDir retired(shellPath() + "/contents/.kos-retired-XXXXXX");
        if (!retired.isValid() || !QDir().rename(target, retired.path() + "/lockscreen"))
            return finish(false, QStringLiteral("Could not remove the KOS lock screen"));
        return finish(true);
    }
    if (!validPackage(m_paths.resources, true))
        return finish(false, QStringLiteral("KOS lock screen resources are unavailable; reinstall KOS"));
    QTemporaryDir staging(shellPath() + "/contents/.kos-stage-XXXXXX");
    const QString staged = staging.path() + "/lockscreen";
    if (!staging.isValid() || !copyTree(m_paths.resources + "/contents/lockscreen", staged) || !markSkin(staged))
        return finish(false, QStringLiteral("Could not stage the KOS lock screen"));
    QString error;
    const bool saved = publish(staged, target, error);
    return finish(saved, error);
}

bool LockScreenSettings::installShellPackage(const QString &source)
{
    if (!validPackage(source, true)) return finish(false, QStringLiteral("KOS lock screen resources are unavailable; reinstall KOS"));
    if (!prepareLock(m_paths.data) || !safePath(shellPath()) || !safePath(m_paths.resources)
        || (QFileInfo::exists(m_paths.resources) && !safeTree(m_paths.resources)))
        return finish(false, QStringLiteral("Refusing a symlinked or unwritable lock screen path"));
    QLockFile lock(mutationLock(m_paths.data));
    if (!lock.tryLock(0)) return finish(false, QStringLiteral("Lock screen settings are being updated; please retry"));
    if (QFileInfo::exists(shellPath()) && !validPackage(shellPath(), false))
        return finish(false, QStringLiteral("The installed KOS desktop package is missing or unsafe"));
    const QString skin = shellPath() + "/contents/lockscreen";
    const bool keepSkin = QFileInfo::exists(skin);
    if (keepSkin && !ownedSkin(skin))
        return finish(false, QStringLiteral("An unrecognized lock screen is installed; it will not be replaced"));
    if (!QDir().mkpath(QFileInfo(m_paths.resources).absolutePath())
        || !QDir().mkpath(QFileInfo(shellPath()).absolutePath()))
        return finish(false, QStringLiteral("Could not stage the KOS lock screen"));
    QTemporaryDir resources(QFileInfo(m_paths.resources).absolutePath() + "/.kos-resources-XXXXXX");
    QTemporaryDir desktop(QFileInfo(shellPath()).absolutePath() + "/.kos-shell-XXXXXX");
    const QString staged = resources.path() + "/package";
    // Only runtime assets: do not ship tests, build inputs or source docs.
    if (!resources.isValid() || !desktop.isValid() || !QDir().mkpath(staged)
        || !QFile::copy(source + "/metadata.json", staged + "/metadata.json")
        || !copyTree(source + "/contents", staged + "/contents")
        || !markSkin(staged + "/contents/lockscreen")
        || !copyTree(staged, desktop.path() + "/package"))
        return finish(false, QStringLiteral("Could not stage the KOS lock screen"));
    if (!keepSkin && !QDir(desktop.path() + "/package/contents/lockscreen").removeRecursively())
        return finish(false, QStringLiteral("Could not stage the KOS lock screen"));
    QString error;
    if (!publish(staged, m_paths.resources, error)) return finish(false, error);
    // If this fails, the old shell entry still exists. Updated stable resources
    // can be used by a later retry; no enabled-state change has been committed.
    const bool saved = publish(desktop.path() + "/package", shellPath(), error);
    return finish(saved, error);
}

bool LockScreenSettings::setWallpaper(const QString &urlOrPath)
{
    const QUrl url(urlOrPath);
    const QString path = url.isLocalFile() ? url.toLocalFile() : urlOrPath;
    QImageReader reader(path);
    if ((!url.scheme().isEmpty() && !url.isLocalFile()) || !QFileInfo(path).isFile() || !reader.canRead())
        return finish(false, QStringLiteral("Select an image readable on this machine"));
    const QString filename = m_paths.config + "/kscreenlockerrc";
    if (!safePath(filename) || !safePath(filename + ".kos.lock") || !QDir().mkpath(m_paths.config))
        return finish(false, QStringLiteral("Refusing a symlinked or unwritable lock screen configuration"));
    QLockFile lock(filename + ".kos.lock");
    if (!lock.tryLock(0)) return finish(false, QStringLiteral("Lock screen settings are being updated; please retry"));
    KConfig config(filename, KConfig::SimpleConfig);
    KConfigGroup greeter(&config, "Greeter");
    auto wallpaper = greeter.group("Wallpaper").group("org.kde.image").group("General");
    const QString image = QUrl::fromLocalFile(QFileInfo(path).absoluteFilePath()).toString();
    wallpaper.writeEntry("Image", image);
    wallpaper.writeEntry("PreviewImage", image);
    greeter.writeEntry("WallpaperPlugin", "org.kde.image");
    return finish(config.sync(), QStringLiteral("Could not save the lock screen configuration"));
}
bool LockScreenSettings::setPreference(const char *key, bool enabled)
{
    const QString filename = m_paths.config + "/kscreenlockerrc";
    if (!safePath(filename) || !safePath(filename + ".kos.lock") || !QDir().mkpath(m_paths.config))
        return finish(false, QStringLiteral("Refusing a symlinked or unwritable lock screen configuration"));
    QLockFile lock(filename + ".kos.lock");
    if (!lock.tryLock(0)) return finish(false, QStringLiteral("Lock screen settings are being updated; please retry"));
    KConfig config(filename, KConfig::SimpleConfig);
    auto appearance = KConfigGroup(&config, "Greeter").group("LnF").group("General");
    appearance.writeEntry(key, enabled);
    return finish(config.sync(), QStringLiteral("Could not save the lock screen configuration"));
}
bool LockScreenSettings::setShowMediaControls(bool enabled) { return setPreference("showMediaControls", enabled); }
bool LockScreenSettings::setShowNotifications(bool enabled) { return setPreference("kosShowNotifications", enabled); }
QStringList LockScreenSettings::wallpaperImages() const
{
    auto images = m_library.galleryImages() + m_library.wallpaperCatalog();
    images.removeDuplicates();
    return images;
}
QString LockScreenSettings::wallpaperThumbnail(const QString &path, int width, int height)
{
    return m_library.wallpaperThumbnail(path, width, height, 10);
}
void LockScreenSettings::lockNow()
{
    const auto message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("/ScreenSaver"), QStringLiteral("org.freedesktop.ScreenSaver"), QStringLiteral("Lock"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 3000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher] {
        const auto reply = watcher->reply();
        finish(reply.type() != QDBusMessage::ErrorMessage,
            QStringLiteral("The session could not be locked: %1").arg(reply.errorMessage()));
        watcher->deleteLater();
    });
}
