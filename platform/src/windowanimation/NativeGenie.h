#pragma once

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusInterface>
#include <QDBusReply>

namespace KOS::WindowAnimation {

inline QString selection(const KSharedConfigPtr &config)
{
    const KConfigGroup group(config, QStringLiteral("Effect-kos_dock_window_animation"));
    return group.readEntry("HideAnimationSelection",
        group.readEntry("HideAnimation", group.readEntry("AnimationStyle", QStringLiteral("scale"))));
}

// The small runtime interface also lets regressions exercise unavailable and
// failed KWin operations without touching a desktop or replacing the algorithm.
class EffectRuntime {
public:
    virtual ~EffectRuntime() = default;
    virtual bool available() = 0;
    virtual bool supported(const QString &name) = 0;
    virtual bool setEnabled(const QString &name, bool enabled) = 0;
    virtual bool reloadDock() = 0;
};

class KWinRuntime final : public EffectRuntime {
    QDBusInterface m_effects{QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                            QStringLiteral("org.kde.kwin.Effects")};
public:
    KWinRuntime() { m_effects.setTimeout(1000); }
    bool available() override { return m_effects.isValid(); }
    bool supported(const QString &name) override {
        const QDBusReply<bool> reply = m_effects.call(QStringLiteral("isEffectSupported"), name);
        return reply.isValid() && reply.value();
    }
    bool setEnabled(const QString &name, bool enabled) override {
        QDBusReply<bool> state = m_effects.call(QStringLiteral("isEffectLoaded"), name);
        if (!state.isValid()) return false;
        if (state.value() != enabled) {
            if (enabled) m_effects.call(QStringLiteral("loadEffect"), name);
            else m_effects.call(QStringLiteral("unloadEffect"), name);
            state = m_effects.call(QStringLiteral("isEffectLoaded"), name);
        }
        return state.isValid() && state.value() == enabled;
    }
    bool reloadDock() override {
        if (!setEnabled(QStringLiteral("kos_dock_window_animation"), true)) return false;
        const QDBusMessage reply = m_effects.call(QStringLiteral("reconfigureEffect"),
                                                QStringLiteral("kos_dock_window_animation"));
        return reply.type() != QDBusMessage::ErrorMessage;
    }
};

inline bool nativeSupported()
{
    KWinRuntime runtime;
    return runtime.available() && runtime.supported(QStringLiteral("magiclamp"));
}

// Preserve the requested Genie choice even when its effective backend is Scale.
// Writing none for native Genie also retires water-drop code in older plugins.
inline bool configure(const KSharedConfigPtr &config, const QString &style,
                      bool native = true, const QString &fallback = {})
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
        plugins.writeEntry("magiclampEnabled", style == QLatin1String("genie") && native);
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
    animation.writeEntry("HideAnimation", style == QLatin1String("genie")
        ? (native ? QStringLiteral("none") : QStringLiteral("scale")) : style);
    if (fallback.isEmpty()) animation.deleteEntry("NativeGenieFallback");
    else animation.writeEntry("NativeGenieFallback", fallback);
    return config->sync();
}

inline bool applyWithRuntime(const KSharedConfigPtr &config, const QString &style,
                             EffectRuntime &runtime, QString &error)
{
    const bool connected = runtime.available();
    const bool native = style == QLatin1String("genie") && connected
        && runtime.supported(QStringLiteral("magiclamp"));
    QString fallback;
    if (style == QLatin1String("genie") && !native)
        fallback = connected ? QStringLiteral("Magic Lamp unavailable; using Scale")
                             : QStringLiteral("KWin unavailable; Scale configured until reconnect");
    KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    KConfigGroup plugins(config, QStringLiteral("Plugins"));
    const auto previousAnimation = animation.entryMap();
    const auto previousPlugins = plugins.entryMap();
    if (!configure(config, style, native, fallback)) {
        error = QStringLiteral("Could not save the animation configuration");
        return false;
    }
    if (!connected) return true; // Persist a usable fallback for the next session.

    const auto synchronize = [&]() {
        // Disable first so a failed native load never runs beside Scale.
        if (!runtime.setEnabled(QStringLiteral("magiclamp"), false)
            || !runtime.setEnabled(QStringLiteral("squash"), false)) return false;
        if (!runtime.reloadDock()) return false;
        if (!runtime.setEnabled(QStringLiteral("squash"), plugins.readEntry("squashEnabled", true))) return false;
        return runtime.setEnabled(QStringLiteral("magiclamp"), plugins.readEntry("magiclampEnabled", false));
    };
    bool applied = synchronize();
    if (!applied && native) {
        // A supported effect may still fail to load. The old mesh is gone, so
        // settle on the project-provided Scale backend rather than no motion.
        fallback = QStringLiteral("Magic Lamp failed to load; using Scale");
        applied = configure(config, style, false, fallback) && synchronize();
    }
    if (applied) return true;
    const auto restore = [](KConfigGroup &group, const QMap<QString, QString> &entries) {
        for (const QString &key : group.keyList())
            if (!entries.contains(key)) group.deleteEntry(key);
        for (auto it = entries.cbegin(); it != entries.cend(); ++it)
            group.writeEntry(it.key(), it.value());
    };
    restore(animation, previousAnimation);
    restore(plugins, previousPlugins);
    config->sync();
    // Attempt every restoration step even if one backend is still broken.
    bool restored = runtime.setEnabled(QStringLiteral("magiclamp"), false);
    restored = runtime.setEnabled(QStringLiteral("squash"), false) && restored;
    restored = runtime.reloadDock() && restored;
    restored = runtime.setEnabled(QStringLiteral("squash"), plugins.readEntry("squashEnabled", true)) && restored;
    restored = runtime.setEnabled(QStringLiteral("magiclamp"), plugins.readEntry("magiclampEnabled", false)) && restored;
    error = restored ? QStringLiteral("Could not apply animation; previous settings restored")
                     : QStringLiteral("Could not apply animation; restart KWin to restore previous settings");
    return false;
}

inline bool apply(const QString &style, QString &error)
{
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KWinRuntime runtime;
    return applyWithRuntime(config, style, runtime, error);
}

inline bool reconcileWithRuntime(const KSharedConfigPtr &config, EffectRuntime &runtime, QString &error)
{
    // Revalidate saved Genie on startup too: a distro/driver upgrade can remove
    // support. Preserve None and Scale. A later startup can recover native Genie.
    if (selection(config) != QLatin1String("genie")) return true;
    return applyWithRuntime(config, QStringLiteral("genie"), runtime, error);
}

inline bool migrate(QString &error)
{
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KWinRuntime runtime;
    return reconcileWithRuntime(config, runtime, error);
}

} // namespace KOS::WindowAnimation
