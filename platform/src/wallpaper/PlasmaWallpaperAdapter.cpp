#include "PlasmaWallpaperAdapter.h"

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

QStringList savedImages()
{
    QFile file(backupPath());
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    QStringList images;
    for (const QJsonValue &value : document.object()
             .value(QStringLiteral("images")).toArray()) {
        const QString image = value.toString();
        if (image.isEmpty())
            return {};
        images.append(image);
    }
    return images;
}

bool saveCurrentImages(int screenCount, QString *error)
{
    if (savedImages().size() >= screenCount)
        return true;
    QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                          QStringLiteral("/PlasmaShell"),
                          QStringLiteral("org.kde.PlasmaShell"));
    if (!plasma.isValid()) {
        *error = QStringLiteral("Plasma 壁纸服务不可用");
        return false;
    }
    QJsonArray images;
    for (int screen = 0; screen < screenCount; ++screen) {
        const QDBusReply<QVariantMap> reply = plasma.call(
            QStringLiteral("wallpaper"), static_cast<quint32>(screen));
        if (!reply.isValid()) {
            *error = QStringLiteral("无法读取第 %1 块屏幕的原壁纸").arg(screen);
            return false;
        }
        QVariant image = reply.value().value(QStringLiteral("Image"));
        if (image.metaType() == QMetaType::fromType<QDBusVariant>())
            image = qvariant_cast<QDBusVariant>(image).variant();
        const QString path = image.toString();
        if (path.isEmpty()) {
            *error = QStringLiteral("第 %1 块屏幕没有可恢复的图片壁纸").arg(screen);
            return false;
        }
        images.append(path);
    }
    if (!QDir().mkpath(QFileInfo(backupPath()).absolutePath())) {
        *error = QStringLiteral("无法保存 Plasma 原壁纸");
        return false;
    }
    return writeFile(backupPath(), QJsonDocument(QJsonObject{
        {QStringLiteral("images"), images}}).toJson(), error);
}

bool setPlasmaWallpaper(const QString &image, int screenCount, QString *error)
{
    QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                          QStringLiteral("/PlasmaShell"),
                          QStringLiteral("org.kde.PlasmaShell"));
    if (!plasma.isValid()) {
        *error = QStringLiteral("Plasma 壁纸服务不可用");
        return false;
    }
    const QVariantMap options{{QStringLiteral("Image"), image}};
    for (int screen = 0; screen < screenCount; ++screen) {
        const QDBusReply<void> reply = plasma.call(
            QStringLiteral("setWallpaper"), QStringLiteral("org.kde.image"),
            options, static_cast<quint32>(screen));
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
    if (!saveCurrentImages(screenCount, error))
        return false;
    if (setPlasmaWallpaper(path, screenCount, error))
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
    const QStringList images = savedImages();
    if (images.size() < screenCount) {
        if (!QFileInfo::exists(imagePath)) {
            *error = QStringLiteral("原壁纸不可用");
            return false;
        }
        if (!setPlasmaWallpaper(imagePath, screenCount, error))
            return false;
    } else {
        QDBusInterface plasma(QStringLiteral("org.kde.plasmashell"),
                              QStringLiteral("/PlasmaShell"),
                              QStringLiteral("org.kde.PlasmaShell"));
        if (!plasma.isValid()) {
            *error = QStringLiteral("Plasma 壁纸服务不可用");
            return false;
        }
        for (int screen = 0; screen < screenCount; ++screen) {
            const QVariantMap options{{QStringLiteral("Image"), images.at(screen)}};
            const QDBusReply<void> reply = plasma.call(
                QStringLiteral("setWallpaper"), QStringLiteral("org.kde.image"),
                options, static_cast<quint32>(screen));
            if (!reply.isValid()) {
                *error = QStringLiteral("恢复第 %1 块屏幕失败：%2")
                    .arg(screen).arg(reply.error().message());
                return false;
            }
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
