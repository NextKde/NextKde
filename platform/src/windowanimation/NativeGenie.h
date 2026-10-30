#pragma once

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusInterface>
#include <QDBusReply>
#include <QVariantMap>

namespace KOS::WindowAnimation {

inline QString selection(const KSharedConfigPtr &config)
{
    const KConfigGroup group(config, QStringLiteral("Effect-kos_dock_window_animation"));
    return group.readEntry("HideAnimationSelection",
        group.readEntry("HideAnimation", group.readEntry("AnimationStyle", QStringLiteral("scale"))));
}

inline bool nativeSupported()
{
    QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                           QStringLiteral("org.kde.kwin.Effects"));
    effects.setTimeout(1000);
    if (!effects.isValid()) return false;
    const QDBusReply<bool> reply = effects.call(QStringLiteral("isEffectSupported"), QStringLiteral("magiclamp"));
    return reply.isValid() && reply.value();
}

// Configuration transition shared by Settings and the legacy theme adapter.
// Keep UI selection separate from HideAnimation: even an older resident KOS
// plugin must see "none" and must not execute its removed water-drop mesh.
inline bool configure(const KSharedConfigPtr &config, const QString &style)
{
    if (style != QLatin1String("none") && style != QLatin1String("scale")
        && style != QLatin1String("genie")) return false;
    KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    KConfigGroup plugins(config, QStringLiteral("Plugins"));
    const QStringList effects{QStringLiteral("magiclamp"), QStringLiteral("squash")};
    if (style != QLatin1String("none")) {
        if (!animation.readEntry("NativeEffectsManaged", false)) {
            for (const QString &effect : effects) {
                const QString key = effect + QStringLiteral("Enabled");
                animation.writeEntry("Previous-" + key + "Present", plugins.hasKey(key));
                animation.writeEntry("Previous-" + key, plugins.readEntry(key, false));
            }
            animation.writeEntry("NativeEffectsManaged", true);
        }
        plugins.writeEntry("magiclampEnabled", style == QLatin1String("genie"));
        plugins.writeEntry("squashEnabled", false);
    } else if (animation.readEntry("NativeEffectsManaged", false)) {
        for (const QString &effect : effects) {
            const QString key = effect + QStringLiteral("Enabled");
            if (animation.readEntry("Previous-" + key + "Present", false))
                plugins.writeEntry(key, animation.readEntry("Previous-" + key, false));
            else
                plugins.deleteEntry(key);
            animation.deleteEntry("Previous-" + key + "Present");
            animation.deleteEntry("Previous-" + key);
        }
        animation.deleteEntry("NativeEffectsManaged");
    }
    animation.writeEntry("HideAnimationSelection", style);
    animation.writeEntry("HideAnimation", style == QLatin1String("genie") ? QStringLiteral("none") : style);
    return config->sync();
}

inline bool apply(const QString &style, QString &error)
{
    if (style == QLatin1String("genie") && !nativeSupported()) {
        error = QStringLiteral("KWin Magic Lamp is unavailable or unsupported");
        return false;
    }
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    KConfigGroup plugins(config, QStringLiteral("Plugins"));
    const auto previousAnimation = animation.entryMap();
    const auto previousPlugins = plugins.entryMap();
    if (!configure(config, style)) {
        error = QStringLiteral("Could not save the animation configuration");
        return false;
    }
    QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                           QStringLiteral("org.kde.kwin.Effects"));
    effects.setTimeout(1000);
    // Retire the KOS minimize path before KWin enables its built-in effect.
    if (effects.isValid())
        effects.call(QStringLiteral("reconfigureEffect"), QStringLiteral("kos_dock_window_animation"));
    QDBusInterface kwin(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"));
    kwin.setTimeout(1000);
    if (kwin.isValid()) kwin.call(QStringLiteral("reconfigure"));
    // KWin versions differ in whether /KWin.reconfigure updates the loaded
    // effect set. Use the normal built-in effect switch API as the KCM does;
    // no plugin binary is replaced or reloaded here.
    if (effects.isValid()) {
        const auto activate = [&](const QString &name, bool enabled) {
            const QDBusReply<bool> loaded = effects.call(QStringLiteral("isEffectLoaded"), name);
            if (!loaded.isValid() || loaded.value() == enabled) return;
            if (enabled) effects.call(QStringLiteral("loadEffect"), name);
            else effects.call(QStringLiteral("unloadEffect"), name);
        };
        activate(QStringLiteral("squash"), plugins.readEntry("squashEnabled", true));
        activate(QStringLiteral("magiclamp"), plugins.readEntry("magiclampEnabled", false));
    }
    if (style == QLatin1String("genie")) {
        const QDBusReply<bool> loaded = effects.call(QStringLiteral("isEffectLoaded"), QStringLiteral("magiclamp"));
        if (!loaded.isValid() || !loaded.value()) {
            // A present effect can still fail to load. Restore the exact
            // entries so a rejected selection does not leave two half-states.
            const auto restore = [](KConfigGroup &group, const QMap<QString, QString> &entries) {
                for (const QString &key : group.keyList())
                    if (!entries.contains(key)) group.deleteEntry(key);
                for (auto it = entries.cbegin(); it != entries.cend(); ++it)
                    group.writeEntry(it.key(), it.value());
            };
            restore(animation, previousAnimation);
            restore(plugins, previousPlugins);
            config->sync();
            effects.call(QStringLiteral("reconfigureEffect"), QStringLiteral("kos_dock_window_animation"));
            if (kwin.isValid()) kwin.call(QStringLiteral("reconfigure"));
            error = QStringLiteral("KWin Magic Lamp could not be enabled");
            return false;
        }
    }
    return true;
}

inline bool migrate(QString &error)
{
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    const KConfigGroup group(config, QStringLiteral("Effect-kos_dock_window_animation"));
    // Only the legacy water-drop choice migrates automatically. An explicit
    // None remains None, including users who already selected native effects.
    if (group.hasKey("HideAnimationSelection") || selection(config) != QLatin1String("genie")) return true;
    return apply(QStringLiteral("genie"), error);
}

} // namespace KOS::WindowAnimation
