#include "ApplicationPreferences.h"

#include <QByteArray>
#include <QStringList>
#include <QtGlobal>

namespace Kos::App {
namespace {

constexpr auto appearanceKey = "Appearance/mode";
constexpr auto materialKey = "Appearance/material";
constexpr auto materialOpacityKey = "Appearance/materialOpacity";
constexpr auto accentKey = "Appearance/accent";
constexpr auto reduceTransparencyKey = "Appearance/reduceTransparency";
constexpr auto reduceMotionKey = "Appearance/reduceMotion";

QString acceptedValue(const QString &candidate, const QStringList &accepted,
                      const QString &fallback)
{
    const QString normalized = candidate.trimmed().toLower();
    return accepted.contains(normalized) ? normalized : fallback;
}

bool environmentBool(const QString &value, bool fallback)
{
    if (value.isEmpty())
        return fallback;
    const QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("1") || normalized == QStringLiteral("true")
        || normalized == QStringLiteral("yes") || normalized == QStringLiteral("on"))
        return true;
    if (normalized == QStringLiteral("0") || normalized == QStringLiteral("false")
        || normalized == QStringLiteral("no") || normalized == QStringLiteral("off"))
        return false;
    return fallback;
}

} // namespace

ApplicationPreferences::ApplicationPreferences(QObject *parent)
    : QObject(parent)
    , m_settings(std::make_unique<QSettings>(QStringLiteral("NextKde"),
                                              QStringLiteral("KosApplications")))
{
    initializeWatcher();
}

ApplicationPreferences::ApplicationPreferences(const QString &settingsFile, QObject *parent)
    : QObject(parent)
    , m_settings(std::make_unique<QSettings>(settingsFile, QSettings::IniFormat))
{
    initializeWatcher();
}

QString ApplicationPreferences::appearanceMode() const
{
    const QString override = environmentOverride("KOS_APPEARANCE");
    return acceptedValue(override.isEmpty() ? value(QLatin1String(appearanceKey),
                                                     QStringLiteral("system")).toString()
                                             : override,
                         {QStringLiteral("system"), QStringLiteral("light"),
                          QStringLiteral("dark")},
                         QStringLiteral("system"));
}

QString ApplicationPreferences::materialMode() const
{
    const QString override = environmentOverride("KOS_MATERIAL");
    return acceptedValue(override.isEmpty() ? value(QLatin1String(materialKey),
                                                     QStringLiteral("auto")).toString()
                                             : override,
                         {QStringLiteral("auto"), QStringLiteral("glass"),
                          QStringLiteral("solid")},
                         QStringLiteral("auto"));
}

qreal ApplicationPreferences::materialOpacity() const
{
    bool ok = false;
    const QString override = environmentOverride("KOS_MATERIAL_OPACITY");
    const qreal stored = override.isEmpty()
        ? value(QLatin1String(materialOpacityKey), 0.86).toDouble(&ok)
        : override.toDouble(&ok);
    return qBound<qreal>(0.72, ok ? stored : 0.86, 0.98);
}

QString ApplicationPreferences::accentName() const
{
    const QString override = environmentOverride("KOS_ACCENT");
    return acceptedValue(override.isEmpty() ? value(QLatin1String(accentKey),
                                                     QStringLiteral("system")).toString()
                                             : override,
                         {QStringLiteral("system"), QStringLiteral("blue"),
                          QStringLiteral("purple"), QStringLiteral("green"),
                          QStringLiteral("orange")},
                         QStringLiteral("system"));
}

bool ApplicationPreferences::reduceTransparency() const
{
    return environmentBool(environmentOverride("KOS_REDUCE_TRANSPARENCY"),
                           value(QLatin1String(reduceTransparencyKey), false).toBool());
}

bool ApplicationPreferences::reduceMotion() const
{
    return environmentBool(environmentOverride("KOS_REDUCE_MOTION"),
                           value(QLatin1String(reduceMotionKey), false).toBool());
}

bool ApplicationPreferences::nativeBlurAvailable() const
{
    return m_nativeBlurAvailable;
}

bool ApplicationPreferences::nativeContrastAvailable() const
{
    return m_nativeContrastAvailable;
}

bool ApplicationPreferences::glassActive() const
{
    if (reduceTransparency() || materialMode() == QStringLiteral("solid"))
        return false;
    return materialMode() == QStringLiteral("glass")
        || (materialMode() == QStringLiteral("auto") && nativeBlurAvailable());
}

qreal ApplicationPreferences::effectiveMaterialOpacity() const
{
    if (!glassActive())
        return 1.0;
    // Forced glass still remains readable when the compositor cannot blur.
    return nativeBlurAvailable() ? materialOpacity()
                                 : qMax<qreal>(0.93, materialOpacity());
}

void ApplicationPreferences::setAppearanceMode(const QString &mode)
{
    setValue(QLatin1String(appearanceKey),
             acceptedValue(mode, {QStringLiteral("system"), QStringLiteral("light"),
                                  QStringLiteral("dark")}, QStringLiteral("system")));
}

void ApplicationPreferences::setMaterialMode(const QString &mode)
{
    setValue(QLatin1String(materialKey),
             acceptedValue(mode, {QStringLiteral("auto"), QStringLiteral("glass"),
                                  QStringLiteral("solid")}, QStringLiteral("auto")));
}

void ApplicationPreferences::setMaterialOpacity(qreal opacity)
{
    setValue(QLatin1String(materialOpacityKey), qBound<qreal>(0.72, opacity, 0.98));
}

void ApplicationPreferences::setAccentName(const QString &name)
{
    setValue(QLatin1String(accentKey),
             acceptedValue(name, {QStringLiteral("system"), QStringLiteral("blue"),
                                  QStringLiteral("purple"), QStringLiteral("green"),
                                  QStringLiteral("orange")}, QStringLiteral("system")));
}

void ApplicationPreferences::setReduceTransparency(bool reduce)
{
    setValue(QLatin1String(reduceTransparencyKey), reduce);
}

void ApplicationPreferences::setReduceMotion(bool reduce)
{
    setValue(QLatin1String(reduceMotionKey), reduce);
}

void ApplicationPreferences::setNativeEffectsAvailable(bool blur, bool contrast)
{
    if (m_nativeBlurAvailable == blur && m_nativeContrastAvailable == contrast)
        return;
    m_nativeBlurAvailable = blur;
    m_nativeContrastAvailable = contrast;
    Q_EMIT capabilitiesChanged();
    // glassActive and effectiveMaterialOpacity are derived from capability
    // state as well as user preferences.
    Q_EMIT preferencesChanged();
}

void ApplicationPreferences::resetAppearance()
{
    m_settings->remove(QStringLiteral("Appearance"));
    m_settings->sync();
    m_lastFingerprint = fingerprint();
    Q_EMIT preferencesChanged();
}

void ApplicationPreferences::initializeWatcher()
{
    m_lastFingerprint = fingerprint();
    m_reloadTimer.setInterval(1000);
    m_reloadTimer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_reloadTimer, &QTimer::timeout, this, [this] {
        m_settings->sync();
        const QString current = fingerprint();
        if (current == m_lastFingerprint)
            return;
        m_lastFingerprint = current;
        Q_EMIT preferencesChanged();
    });
    m_reloadTimer.start();
}

QString ApplicationPreferences::fingerprint() const
{
    return QStringList{
        appearanceMode(),
        materialMode(),
        QString::number(materialOpacity(), 'f', 3),
        accentName(),
        reduceTransparency() ? QStringLiteral("1") : QStringLiteral("0"),
        reduceMotion() ? QStringLiteral("1") : QStringLiteral("0"),
    }.join(QLatin1Char('|'));
}

QVariant ApplicationPreferences::value(const QString &key, const QVariant &fallback) const
{
    return m_settings->value(key, fallback);
}

void ApplicationPreferences::setValue(const QString &key, const QVariant &newValue)
{
    if (m_settings->value(key) == newValue)
        return;
    m_settings->setValue(key, newValue);
    m_settings->sync();
    m_lastFingerprint = fingerprint();
    Q_EMIT preferencesChanged();
}

QString ApplicationPreferences::environmentOverride(const char *name) const
{
    return QString::fromLocal8Bit(qgetenv(name));
}

} // namespace Kos::App
