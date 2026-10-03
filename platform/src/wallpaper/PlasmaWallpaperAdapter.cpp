#include "PlasmaWallpaperAdapter.h"

#include <cstddef>

#include <QCryptographicHash>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QVariantMap>

namespace KosPlatform {
namespace {

bool writeFile(const QString &path, const QByteArray &contents, QString *error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(contents) != contents.size()
        || !file.commit()) {
        *error = QStringLiteral("无法写入 Plasma 壁纸占位资源");
        return false;
    }
    return true;
}

QString backupPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/kos/plasma-wallpaper-backup.json");
}

// One screen's pre-takeover Plasma wallpaper. The takeover replaces every
// screen with the KOS backdrop, so what has to be put back is whatever plugin
// the desktop was running -- not only the image plugin. A Picture of the Day,
// slideshow or solid-colour screen carries no `Image` path at all, and
// rejecting those screens made the takeover impossible on a desktop that is
// otherwise perfectly valid.
struct SavedWallpaper {
    QString plugin;
    QVariantMap config;
};

// Plasma wraps some values in a variant inside the variant the map is made of
// (its `*Default` keys, for instance), so unwrap until the value is plain.
// QtDBus aborts the whole process on a value it cannot marshal, and a
// wallpaper configuration that travelled through a JSON backup can carry one:
// a null in the file turns into std::nullptr_t. Such keys are dropped rather
// than allowed to take the daemon down.
bool isMarshallable(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return false;
    const int id = value.metaType().id();
    return id != QMetaType::UnknownType
        && id != QMetaType::fromType<std::nullptr_t>().id();
}

QVariant unwrapDBusValue(const QVariant &value)
{
    QVariant current = value;
    for (int depth = 0; depth < 4
            && current.metaType() == QMetaType::fromType<QDBusVariant>(); depth++)
        current = qvariant_cast<QDBusVariant>(current).variant();
    return current;
}

QList<SavedWallpaper> savedWallpapers()
{
    QList<SavedWallpaper> saved;
    QFile file(backupPath());
    if (!file.open(QIODevice::ReadOnly))
        return saved;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());

    const QJsonArray screens = document.object()
        .value(QStringLiteral("screens")).toArray();
    if (!screens.isEmpty()) {
        for (const QJsonValue &value : screens) {
            const QJsonObject entry = value.toObject();
            QVariantMap config = entry.value(QStringLiteral("config"))
                .toObject().toVariantMap();
            for (auto key = config.begin(); key != config.end();) {
                if (isMarshallable(*key))
                    ++key;
                else
                    key = config.erase(key);
            }
            saved.append(SavedWallpaper{
                entry.value(QStringLiteral("plugin")).toString(), config});
        }
        return saved;
    }

    // Backup files written before the plugin was recorded hold image paths
    // only, one per screen.
    for (const QJsonValue &value : document.object()
             .value(QStringLiteral("images")).toArray()) {
        const QString image = value.toString();
        if (image.isEmpty())
            continue;
        saved.append(SavedWallpaper{QStringLiteral("org.kde.image"),
            QVariantMap{{QStringLiteral("Image"), image}}});
    }
    return saved;
}

bool writeBackup(const QList<SavedWallpaper> &saved, QString *error)
{
    QJsonArray screens;
    for (const SavedWallpaper &wallpaper : saved) {
        QJsonObject config;
        for (auto entry = wallpaper.config.begin();
                entry != wallpaper.config.end(); ++entry) {
            // A few Plasma values (the wallpaper colour, for one) arrive as a
            // QDBusArgument, whose D-Bus struct has no Qt metatype and cannot
            // survive a JSON round trip. Storing the null that conversion
            // produces would only abort the daemon when the file is read back,
            // so those keys are dropped instead.
            const QJsonValue value = QJsonValue::fromVariant(entry.value());
            if (!value.isNull() && !value.isUndefined())
                config.insert(entry.key(), value);
        }
        screens.append(QJsonObject{
            {QStringLiteral("plugin"), wallpaper.plugin},
            {QStringLiteral("config"), config},
        });
    }
    if (!QDir().mkpath(QFileInfo(backupPath()).absolutePath())) {
        *error = QStringLiteral("无法保存 Plasma 原壁纸");
        return false;
    }
    return writeFile(backupPath(), QJsonDocument(QJsonObject{
        {QStringLiteral("screens"), screens}}).toJson(), error);
}

bool saveCurrentWallpapers(int screenCount, QString *error)
{
    QList<SavedWallpaper> saved = savedWallpapers();
    if (saved.size() >= screenCount)
        return true;

    QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                          QStringLiteral("/PlasmaShell"),
                          QStringLiteral("org.kde.PlasmaShell"));
    if (!plasma.isValid()) {
        *error = QStringLiteral("Plasma 壁纸服务不可用");
        return false;
    }
    // Only the screens the backup does not cover yet are read back: re-entering
    // the takeover after a screen was added must not record the KOS backdrop
    // that is on screen at that moment as the wallpaper to restore.
    for (int screen = saved.size(); screen < screenCount; ++screen) {
        const QDBusReply<QVariantMap> reply = plasma.call(
            QStringLiteral("wallpaper"), static_cast<quint32>(screen));
        if (!reply.isValid()) {
            *error = QStringLiteral("无法读取第 %1 块屏幕的原壁纸").arg(screen);
            return false;
        }
        // The reply is the plugin's live configuration plus the defaults its
        // editor knows. Replaying all of it restores the same wallpaper
        // without guessing which keys a plugin needs.
        QVariantMap config = reply.value();
        const QString plugin = unwrapDBusValue(
            config.take(QStringLiteral("wallpaperPlugin"))).toString();
        for (auto entry = config.begin(); entry != config.end(); ++entry)
            *entry = unwrapDBusValue(*entry);
        saved.append(SavedWallpaper{plugin, config});
    }
    return writeBackup(saved, error);
}

bool setPlasmaWallpaper(const QString &plugin, const QVariantMap &parameters,
                        int screenCount, QString *error)
{
    QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                          QStringLiteral("/PlasmaShell"),
                          QStringLiteral("org.kde.PlasmaShell"));
    if (!plasma.isValid()) {
        *error = QStringLiteral("Plasma 壁纸服务不可用");
        return false;
    }
    for (int screen = 0; screen < screenCount; ++screen) {
        const QDBusReply<void> reply = plasma.call(
            QStringLiteral("setWallpaper"), plugin, parameters,
            static_cast<quint32>(screen));
        if (!reply.isValid()) {
            *error = QStringLiteral("Plasma 未接受第 %1 块屏幕的壁纸：%2")
                .arg(screen).arg(reply.error().message());
            return false;
        }
    }
    return true;
}

} // namespace

bool PlasmaWallpaperAdapter::applyProxy(const QString &accent, bool dark,
                                         int screenCount, QString *error)
{
    const QRegularExpression colorPattern(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    if (!colorPattern.match(accent).hasMatch() || screenCount < 1 || screenCount > 8) {
        *error = QStringLiteral("壁纸占位参数无效");
        return false;
    }

    const QByteArray key = (accent.toLower() + (dark ? QStringLiteral("-dark")
        : QStringLiteral("-light"))).toUtf8();
    const QString id = QStringLiteral("KOS-Backdrop-")
        + QString::fromLatin1(QCryptographicHash::hash(key,
            QCryptographicHash::Sha256).toHex().left(12));
    const QString path = QStandardPaths::writableLocation(
        QStandardPaths::GenericDataLocation) + QStringLiteral("/wallpapers/") + id;
    const QString images = path + QStringLiteral("/contents/images");
    if (!QDir().mkpath(images)) {
        *error = QStringLiteral("无法创建 Plasma 壁纸占位目录");
        return false;
    }

    QSaveFile picture(images + QStringLiteral("/1920x1080.png"));
    QImage pixel(16, 16, QImage::Format_RGB32);
    pixel.fill(dark ? Qt::black : Qt::white);
    if (!picture.open(QIODevice::WriteOnly) || !pixel.save(&picture, "PNG")
        || !picture.commit()) {
        *error = QStringLiteral("无法生成 Plasma 纯色占位图");
        return false;
    }

    const QJsonObject metadata{
        {QStringLiteral("KPackageStructure"), QStringLiteral("Plasma/Wallpaper")},
        {QStringLiteral("KPlugin"), QJsonObject{
            {QStringLiteral("Id"), id},
            {QStringLiteral("Name"), QStringLiteral("KOS Backdrop")},
            {QStringLiteral("License"), QStringLiteral("CC0-1.0")},
        }},
        {QStringLiteral("X-KDE-PlasmaImageWallpaper-AccentColor"), accent},
    };
    if (!writeFile(path + QStringLiteral("/metadata.json"),
                   QJsonDocument(metadata).toJson(), error))
        return false;
    if (!saveCurrentWallpapers(screenCount, error))
        return false;
    if (setPlasmaWallpaper(QStringLiteral("org.kde.image"),
            QVariantMap{{QStringLiteral("Image"), path}}, screenCount, error))
        return true;
    const QString applyError = *error;
    QString restoreError;
    restoreImage(QString(), screenCount, &restoreError);
    *error = restoreError.isEmpty() ? applyError
        : applyError + QStringLiteral("；回退失败：") + restoreError;
    return false;
}

bool PlasmaWallpaperAdapter::restoreImage(const QString &imagePath,
                                           int screenCount, QString *error)
{
    if (screenCount < 1 || screenCount > 8) {
        *error = QStringLiteral("原壁纸不可用");
        return false;
    }
    const QList<SavedWallpaper> saved = savedWallpapers();
    const bool haveFallback = QFileInfo::exists(imagePath);
    if (saved.isEmpty() && !haveFallback) {
        *error = QStringLiteral("原壁纸不可用");
        return false;
    }
    QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                          QStringLiteral("/PlasmaShell"),
                          QStringLiteral("org.kde.PlasmaShell"));
    if (!plasma.isValid()) {
        *error = QStringLiteral("Plasma 壁纸服务不可用");
        return false;
    }
    // Screens the backup covers get their own plugin and configuration back;
    // anything past it falls back to the image the Shell is displaying.
    for (int screen = 0; screen < screenCount; ++screen) {
        QString plugin;
        QVariantMap parameters;
        if (screen < saved.size()
                && (!saved.at(screen).plugin.isEmpty()
                    || !saved.at(screen).config.isEmpty())) {
            plugin = saved.at(screen).plugin;
            parameters = saved.at(screen).config;
            if (plugin.isEmpty())
                plugin = QStringLiteral("org.kde.image");
        } else if (haveFallback) {
            plugin = QStringLiteral("org.kde.image");
            parameters = QVariantMap{{QStringLiteral("Image"), imagePath}};
        } else {
            *error = QStringLiteral("第 %1 块屏幕的原壁纸不可用").arg(screen);
            return false;
        }
        const QDBusReply<void> reply = plasma.call(
            QStringLiteral("setWallpaper"), plugin, parameters,
            static_cast<quint32>(screen));
        if (!reply.isValid()) {
            *error = QStringLiteral("恢复第 %1 块屏幕失败：%2")
                .arg(screen).arg(reply.error().message());
            return false;
        }
    }
    QFile::remove(backupPath());
    return true;
}

void PlasmaWallpaperAdapter::showDesktop(bool showing,
        std::function<void(bool, bool, const QString &)> completion)
{
    auto get = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/KWin"), QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    get << QStringLiteral("org.kde.KWin") << QStringLiteral("showingDesktop");
    auto *read = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(get, 2000), QCoreApplication::instance());
    QObject::connect(read, &QDBusPendingCallWatcher::finished, read,
        [read, showing, completion] {
            const QDBusPendingReply<QDBusVariant> reply = *read;
            read->deleteLater();
            if (reply.isError()) {
                completion(false, false, QStringLiteral("无法读取桌面状态：") + reply.error().message());
                return;
            }
            const bool previous = reply.value().variant().toBool();
            auto set = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("showDesktop"));
            set << showing;
            // KWin marks showDesktop as NoReply. A pending call would wait for
            // a reply that the server intentionally never sends.
            const bool queued = QDBusConnection::sessionBus().send(set);
            completion(queued, previous, queued ? QString()
                : QStringLiteral("无法向 KWin 发送桌面预览请求"));
        });
}

} // namespace KosPlatform
