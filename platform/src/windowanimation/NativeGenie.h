#pragma once

#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusConnection>
#include <QDeadlineTimer>
#include <QDir>
#include <QLockFile>
#include <QStandardPaths>
#include <QUuid>
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

// Called only from a worker or the command-line installer. Raw messages avoid
// QDBusInterface's implicit, unbounded introspection on construction.
class KWinRuntime final : public EffectRuntime {
    const QString m_busName = QStringLiteral("kos-animation-") + QUuid::createUuid().toString();
    QDBusConnection m_bus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, m_busName);
    QDeadlineTimer m_deadline{4000};
    QDBusMessage call(const QString &method, const QVariantList &arguments = {}) {
        if (m_deadline.hasExpired())
            return QDBusMessage::createError(QStringLiteral("org.kos.Timeout"), QStringLiteral("Animation operation timed out"));
        auto message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
            QStringLiteral("/Effects"), QStringLiteral("org.kde.kwin.Effects"), method);
        message.setArguments(arguments);
        return m_bus.call(message, QDBus::Block, int(qMin<qint64>(1000, m_deadline.remainingTime())));
    }
public:
    ~KWinRuntime() override { QDBusConnection::disconnectFromBus(m_busName); }
    bool available() override {
        // This also verifies the effects endpoint without introspection.
        const QDBusReply<bool> reply = call(QStringLiteral("isEffectLoaded"), {QStringLiteral("magiclamp")});
        return reply.isValid();
    }
    bool supported(const QString &name) override {
        const QDBusReply<bool> reply = call(QStringLiteral("isEffectSupported"), {name});
        return reply.isValid() && reply.value();
    }
    bool setEnabled(const QString &name, bool enabled) override {
        QDBusReply<bool> state = call(QStringLiteral("isEffectLoaded"), {name});
        if (!state.isValid()) return false;
        if (state.value() != enabled) {
            const auto reply = call(enabled ? QStringLiteral("loadEffect") : QStringLiteral("unloadEffect"), {name});
            if (reply.type() == QDBusMessage::ErrorMessage) return false;
            state = call(QStringLiteral("isEffectLoaded"), {name});
        }
        return state.isValid() && state.value() == enabled;
    }
    bool reloadDock() override {
        if (!setEnabled(QStringLiteral("kos_dock_window_animation"), true)) return false;
        return call(QStringLiteral("reconfigureEffect"), {QStringLiteral("kos_dock_window_animation")}).type()
            != QDBusMessage::ErrorMessage;
    }
};

// Preserve the requested Genie choice even when its effective backend is Scale.
// Writing none for native Genie also retires water-drop code in older plugins.
inline bool configure(const KSharedConfigPtr &config, const QString &style,
                      bool native = true, const QString &fallback = {})
{
    if (style != QLatin1String("none") && style != QLatin1String("scale")
        && style != QLatin1String("genie")) return false;
    KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    KConfigGroup plugins(config, QStringLiteral("Plugins"));
    KConfigGroup lamp(config, QStringLiteral("Effect-magiclamp"));
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
    // One curated preset for minimize/restore. Save once, including an absent
    // key, so changing presets or uninstalling restores the user's exact value.
    const bool useLamp = style == QLatin1String("genie") && native;
    if (useLamp) {
        if (!animation.readEntry("NativeDurationManaged", false)) {
            animation.writeEntry("Previous-LampDurationPresent", lamp.hasKey("AnimationDuration"));
            animation.writeEntry("Previous-LampDuration", lamp.readEntry("AnimationDuration", 0));
            animation.writeEntry("NativeDurationManaged", true);
        }
        lamp.writeEntry("AnimationDuration", 250);
    } else if (animation.readEntry("NativeDurationManaged", false)) {
        if (animation.readEntry("Previous-LampDurationPresent", false))
            lamp.writeEntry("AnimationDuration", animation.readEntry("Previous-LampDuration", 0));
        else lamp.deleteEntry("AnimationDuration");
        animation.deleteEntry("NativeDurationManaged");
        animation.deleteEntry("Previous-LampDurationPresent");
        animation.deleteEntry("Previous-LampDuration");
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
    KConfigGroup lamp(config, QStringLiteral("Effect-magiclamp"));
    const auto previousLamp = lamp.entryMap();
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
    // Other desktop settings can change unrelated effect keys while KWin is
    // slow. Roll back only the entries owned by this transaction.
    const auto restoreKey = [](KConfigGroup &group, const QMap<QString, QString> &entries, const QString &key) {
        if (entries.contains(key)) group.writeEntry(key, entries.value(key));
        else group.deleteEntry(key);
    };
    restoreKey(lamp, previousLamp, QStringLiteral("AnimationDuration"));
    restore(animation, previousAnimation);
    restoreKey(plugins, previousPlugins, QStringLiteral("magiclampEnabled"));
    restoreKey(plugins, previousPlugins, QStringLiteral("squashEnabled"));
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

inline QString lockPath()
{
    const auto directory = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    QDir().mkpath(directory);
    return directory + QStringLiteral("/kos-window-animation.lock");
}

inline bool apply(const QString &style, QString &error)
{
    QLockFile lock(lockPath());
    if (!lock.tryLock(3000)) { error = QStringLiteral("The configuration is being updated; please retry"); return false; }
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

inline bool migrate(QString &error, const QString &legacyStyle = {})
{
    QLockFile lock(lockPath());
    if (!lock.tryLock(3000)) { error = QStringLiteral("The configuration is being updated; please retry"); return false; }
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    if (!legacyStyle.isEmpty()) {
        KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
        animation.writeEntry("AnimationStyle", legacyStyle);
        if (!config->sync()) { error = QStringLiteral("Could not save the animation configuration"); return false; }
    }
    if (selection(config) != QLatin1String("genie")) return true;
    KWinRuntime runtime;
    return reconcileWithRuntime(config, runtime, error);
}

} // namespace KOS::WindowAnimation
