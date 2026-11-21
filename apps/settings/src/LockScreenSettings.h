#pragma once

#include "WallpaperLibrary.h"
#include <QObject>
#include <QVariantMap>

// Owns only the KOS skin and kscreenlockerrc appearance entries. Authentication,
// lock policy and plasmashell's ShellPackage selection are deliberately external.
class LockScreenSettings final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
public:
    struct Paths { QString config; QString data; QString resources; };
    explicit LockScreenSettings(QObject *parent = nullptr);
    explicit LockScreenSettings(const Paths &paths, QObject *parent = nullptr);
    QVariantMap state() const;
    QString error() const { return m_error; }
    Q_INVOKABLE void refresh() { emit changed(); }
    Q_INVOKABLE bool setTheme(const QString &theme);
    Q_INVOKABLE bool setWallpaper(const QString &urlOrPath);
    Q_INVOKABLE bool setShowMediaControls(bool enabled);
    Q_INVOKABLE bool setShowNotifications(bool enabled);
    Q_INVOKABLE void lockNow(); // Only the explicitly labelled UI button calls this.
    Q_INVOKABLE QStringList wallpaperImages() const;
    Q_INVOKABLE QString wallpaperThumbnail(const QString &path, int width, int height);
    // Installer-only: refresh stable resources and the desktop package without
    // opting into a lock skin or changing ShellPackage. No checkout at runtime.
    bool installShellPackage(const QString &source);
    static Paths defaultPaths();
signals:
    void changed();
    void thumbnailReady();
private:
    bool setPreference(const char *key, bool enabled);
    bool finish(bool success, const QString &error = {});
    QString shellPath() const;
    Paths m_paths;
    QString m_error;
    WallpaperLibrary m_library;
};
