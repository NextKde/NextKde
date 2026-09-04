#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QTimer>

#include <memory>

class QQuickWindow;

namespace Kos::App {

class ApplicationPreferences final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString appearanceMode READ appearanceMode WRITE setAppearanceMode NOTIFY preferencesChanged)
    Q_PROPERTY(QString materialMode READ materialMode WRITE setMaterialMode NOTIFY preferencesChanged)
    Q_PROPERTY(qreal materialOpacity READ materialOpacity WRITE setMaterialOpacity NOTIFY preferencesChanged)
    Q_PROPERTY(QString accentName READ accentName WRITE setAccentName NOTIFY preferencesChanged)
    Q_PROPERTY(bool reduceTransparency READ reduceTransparency WRITE setReduceTransparency NOTIFY preferencesChanged)
    Q_PROPERTY(bool reduceMotion READ reduceMotion WRITE setReduceMotion NOTIFY preferencesChanged)
    Q_PROPERTY(bool nativeBlurAvailable READ nativeBlurAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool nativeContrastAvailable READ nativeContrastAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool glassActive READ glassActive NOTIFY preferencesChanged)
    Q_PROPERTY(qreal effectiveMaterialOpacity READ effectiveMaterialOpacity NOTIFY preferencesChanged)

public:
    explicit ApplicationPreferences(QObject *parent = nullptr);
    explicit ApplicationPreferences(const QString &settingsFile, QObject *parent = nullptr);

    QString appearanceMode() const;
    QString materialMode() const;
    qreal materialOpacity() const;
    QString accentName() const;
    bool reduceTransparency() const;
    bool reduceMotion() const;
    bool nativeBlurAvailable() const;
    bool nativeContrastAvailable() const;
    bool glassActive() const;
    qreal effectiveMaterialOpacity() const;

    void setAppearanceMode(const QString &mode);
    void setMaterialMode(const QString &mode);
    void setMaterialOpacity(qreal opacity);
    void setAccentName(const QString &name);
    void setReduceTransparency(bool reduce);
    void setReduceMotion(bool reduce);
    void setNativeEffectsAvailable(bool blur, bool contrast);

    Q_INVOKABLE void resetAppearance();

Q_SIGNALS:
    void preferencesChanged();
    void capabilitiesChanged();

private:
    void initializeWatcher();
    QString fingerprint() const;
    QVariant value(const QString &key, const QVariant &fallback) const;
    void setValue(const QString &key, const QVariant &value);
    QString environmentOverride(const char *name) const;

    std::unique_ptr<QSettings> m_settings;
    QTimer m_reloadTimer;
    QString m_lastFingerprint;
    bool m_nativeBlurAvailable = false;
    bool m_nativeContrastAvailable = false;
};

} // namespace Kos::App
