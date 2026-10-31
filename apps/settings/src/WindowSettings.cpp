#include "WindowSettings.h"
#include "../../../platform/src/windowanimation/AnimationTask.h"
#include "../../../platform/src/windowanimation/NativeGenie.h"
#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusInterface>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
QString path(const QString &name) {
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kos/") + name;
}
QJsonObject read(const QString &filename, QString *error = nullptr) {
    QFile file(filename);
    if (!file.exists()) return {};
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) *error = file.errorString();
        return {};
    }
    QJsonParseError parse;
    const auto doc = QJsonDocument::fromJson(file.readAll(), &parse);
    if (parse.error != QJsonParseError::NoError || !doc.isObject()) {
        if (error) *error = QStringLiteral("The configuration file is corrupted; original left untouched: ") + filename;
        return {};
    }
    return doc.object();
}
bool write(const QString &filename, const QJsonObject &value, QString &error) {
    QDir().mkpath(QFileInfo(filename).absolutePath());
    QSaveFile file(filename);
    const auto bytes = QJsonDocument(value).toJson();
    if (!file.open(QIODevice::WriteOnly)
        || file.write(bytes) != bytes.size() || !file.commit()) {
        error = file.errorString();
        return false;
    }
    return true;
}
void reconfigure(const QString &effect) {
    auto message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
        QStringLiteral("/Effects"), QStringLiteral("org.kde.kwin.Effects"),
        QStringLiteral("reconfigureEffect"));
    message.setArguments({effect});
    QDBusConnection::sessionBus().asyncCall(message, 1000);
}
}

WindowSettings::WindowSettings(QObject *parent) : QObject(parent) {
    // Startup reconciliation belongs to the platform service, not page creation.
}

QVariantMap WindowSettings::state() const {
    const auto doc = read(path(QStringLiteral("window-appearance.json")));
    const auto defaults = doc.value(QStringLiteral("defaults")).toObject();
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    const KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    const KConfigGroup decoration(config, QStringLiteral("org.kde.kdecoration2"));
    const QString hide = KOS::WindowAnimation::selection(config);
    const auto buttonsDoc = read(path(QStringLiteral("window-buttons.json")));
    const auto buttonsDefault = buttonsDoc.value(QStringLiteral("default")).toObject();
    const QString buttonGlyphMode = buttonsDefault.value(QStringLiteral("glyphMode")).toString(QStringLiteral("always"));
    return {{"enabled", doc.value("enabled").toBool(true)},
            {"radius", defaults.value("corners").toObject().value("radius").toInt(20)},
            {"shadow", defaults.value("shadow").toObject().value("enabled").toBool(true)},
            {"hideAnimation", hide},
            {"nativeGenieFallback", animation.readEntry("NativeGenieFallback", QString())},
            {"closeAnimation", animation.readEntry("CloseAnimation", QStringLiteral("scale"))},
            {"decoration", decoration.readEntry("library", QStringLiteral("org.kde.breeze"))},
            {"buttonGlyphMode", buttonGlyphMode}};
}

bool WindowSettings::patchAppearance(const QString &section, const QString &key,
                                     const QJsonValue &value) {
    m_error.clear();
    const QString filename = path(QStringLiteral("window-appearance.json"));
    QDir().mkpath(QFileInfo(filename).absolutePath());
    QLockFile lock(filename + QStringLiteral(".lock"));
    if (!lock.tryLock(0)) { m_error = QStringLiteral("The configuration is being updated; please retry"); emit changed(); return false; }
    auto doc = read(filename, &m_error);
    if (!m_error.isEmpty()) { emit changed(); return false; }
    if (!doc.isEmpty() && doc.value("version").toInt() != 1 && doc.value("version").toInt() != 2) {
        m_error = QStringLiteral("Unsupported window configuration version"); emit changed(); return false;
    }
    if (doc.isEmpty()) doc.insert("version", 2);
    if (doc.contains("defaults") && !doc.value("defaults").isObject()) {
        m_error = QStringLiteral("defaults must be a configuration object"); emit changed(); return false;
    }
    if (section.isEmpty()) doc.insert(key, value);
    else {
        auto defaults = doc.value("defaults").toObject();
        auto part = defaults.value(section).toObject();
        part.insert(key, value);
        defaults.insert(section, part);
        doc.insert("defaults", defaults);
    }
    doc.insert("revision", doc.value("revision").toInt() + 1);
    const bool saved = write(filename, doc, m_error);
    emit changed();
    return saved;
}
bool WindowSettings::setRadius(int radius) {
    if (radius < 0 || radius > 200) return false;
    return patchAppearance("corners", "radius", radius);
}
bool WindowSettings::setShadow(bool enabled) {
    return patchAppearance("shadow", "enabled", enabled);
}
bool WindowSettings::setTakeover(bool enabled) {
    m_error.clear();
    const QString filename = path(QStringLiteral("window-integration.json"));
    QDir().mkpath(QFileInfo(filename).absolutePath());
    QLockFile lock(filename + QStringLiteral(".lock"));
    if (!lock.tryLock(0)) { m_error = QStringLiteral("Window takeover settings are being updated; please retry"); emit changed(); return false; }
    auto integration = read(filename, &m_error);
    if (!m_error.isEmpty()) { emit changed(); return false; }
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KConfigGroup decoration(config, QStringLiteral("org.kde.kdecoration2"));
    const QString selected = decoration.readEntry("library", QStringLiteral("org.kde.breeze"));
    if (!integration.contains("originalDecoration")
        || (enabled && !state().value("enabled").toBool() && selected != "kos_decoration")) {
        QString original = decoration.readEntry("library", QStringLiteral("org.kde.breeze"));
        if (original == "kos_decoration") original = QStringLiteral("org.kde.breeze");
        integration.insert("originalDecoration", original);
        integration.insert("originalTheme", decoration.readEntry("theme", QString()));
        if (!write(filename, integration, m_error)) { emit changed(); return false; }
    }
    if (!patchAppearance({}, "enabled", enabled)) return false;
    if (enabled || selected == "kos_decoration") {
        decoration.writeEntry("library", enabled ? QStringLiteral("kos_decoration")
            : integration.value("originalDecoration").toString(QStringLiteral("org.kde.breeze")));
        if (!enabled) decoration.writeEntry("theme", integration.value("originalTheme").toString());
    }
    KConfigGroup plugins(config, QStringLiteral("Plugins"));
    // Keep Bridge resident: its buttons are required until KWin switches away
    // from KOS decoration on the next login. JSON disables only its appearance.
    plugins.writeEntry("kos_bridgeEnabled", true);
    if (!config->sync()) { m_error = QStringLiteral("Could not save the KWin configuration"); emit changed(); return false; }
    emit changed();
    return true;
}
bool WindowSettings::requestAnimation(const QString &kind, const QString &style) {
    if (m_animationBusy) return false;
    if ((kind != "hide" && kind != "close") || (kind == "hide"
        ? style != "none" && style != "scale" && style != "genie"
        : style != "none" && style != "scale" && style != "fade")) return false;
    m_animationBusy = true;
    m_error.clear();
    emit changed();
    new KOS::WindowAnimation::AnimationTask(this, [kind, style] {
        // The synchronous entry point is also used by the CLI; keep all of its
        // configuration and D-Bus objects on this worker's thread.
        WindowSettings worker;
        const bool saved = worker.setAnimation(kind, style);
        return KOS::WindowAnimation::AnimationTask::Result{saved, worker.error()};
    }, [this](const auto &result) {
        m_animationBusy = false;
        m_error = result.second;
        emit changed();
    });
    return true;
}

bool WindowSettings::setAnimation(const QString &kind, const QString &style) {
    const bool close = kind == "close";
    if ((!close && kind != "hide") || (close
        ? style != "none" && style != "fade" && style != "scale"
        : style != "none" && style != "scale" && style != "genie")) return false;
    m_error.clear();
    if (!close) {
        const bool saved = KOS::WindowAnimation::apply(style, m_error);
        emit changed();
        return saved;
    }
    QLockFile lock(KOS::WindowAnimation::lockPath());
    if (!lock.tryLock(3000)) { m_error = QStringLiteral("The configuration is being updated; please retry"); emit changed(); return false; }
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    animation.writeEntry(close ? "CloseAnimation" : "HideAnimation", style);
    const bool saved = config->sync();
    if (!saved) m_error = QStringLiteral("Could not save the animation configuration");
    else reconfigure(QStringLiteral("kos_dock_window_animation"));
    emit changed();
    return saved;
}
bool WindowSettings::setButtonGlyphMode(const QString &mode) {
    if (mode != QLatin1String("always") && mode != QLatin1String("hover")) return false;
    m_error.clear();
    const QString filename = path(QStringLiteral("window-buttons.json"));
    QDir().mkpath(QFileInfo(filename).absolutePath());
    QLockFile lock(filename + QStringLiteral(".lock"));
    if (!lock.tryLock(0)) {
        m_error = QStringLiteral("The configuration is being updated; please retry");
        emit changed();
        return false;
    }
    auto doc = read(filename, &m_error);
    if (!m_error.isEmpty()) { emit changed(); return false; }
    auto defaultObj = doc.value(QStringLiteral("default")).toObject();
    defaultObj.insert(QStringLiteral("glyphMode"), mode);
    doc.insert(QStringLiteral("default"), defaultObj);
    const bool saved = write(filename, doc, m_error);
    if (saved) reconfigure(QStringLiteral("kos_bridge"));
    emit changed();
    return saved;
}
bool WindowSettings::installDefaults() {
    if (!KOS::WindowAnimation::migrate(m_error)) return false;
    QString error;
    const auto integration = read(path(QStringLiteral("window-integration.json")), &error);
    if (!error.isEmpty()) { m_error = error; return false; }
    // Never undo a saved opt-out on an upgrade or `kosctl start`.
    if (integration.contains("originalDecoration")) return true;
    return setTakeover(state().value("enabled").toBool());
}
bool WindowSettings::restoreAnimationDefaults() {
    const auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    const KConfigGroup animation(config, QStringLiteral("Effect-kos_dock_window_animation"));
    if (!animation.readEntry("NativeEffectsManaged", false)) return true;
    return KOS::WindowAnimation::apply(QStringLiteral("none"), m_error);
}
