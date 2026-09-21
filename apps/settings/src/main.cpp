#include <QGuiApplication>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QProcess>
#include <QStandardPaths>
#include <QSettings>
#include <QThread>
#include <QTimer>
#include <QVariantMap>

namespace {

// The 材质 group of the debug page is the editor for the shell's glass presets,
// not for raw kwinrc values. The shell re-writes every one of those keys from
// the active preset on each appearance sync (theme.sync-glass), so a direct
// kwinrc write here is reverted the moment any blur/liquid/style control moves;
// these rows therefore read and write the preset through the shell, which also
// reconfigures the effect, keeping the live feedback a raw write used to give.
//
// `toKwinrc` converts preset units into kwinrc units. Only Refraction differs:
// it lives as 0..1 in the preset and reaches kwinrc as RefractionStrength 0..20
// through round(globalLiquidStrength * Refraction * 20).
struct PresetDebugKey {
    const char *key;
    const char *parameter;
    double toKwinrc;
};

const PresetDebugKey kPresetDebugKeys[] = {
    {"RefractionStrength", "Refraction", 20.0},
    {"RefractionEdgeSize", "EdgeSize", 1.0},
    {"RefractionNormalPow", "NormalPow", 1.0},
    {"RefractionRGBFringing", "RGBFringing", 1.0},
    {"RefractionOffsetStrength", "OffsetStrength", 1.0},
    {"MaterialSoftness", "Softness", 1.0},
    {"MaterialReflectionStrength", "Reflection", 1.0},
};

const PresetDebugKey *presetDebugKey(const QString &key)
{
    for (const PresetDebugKey &candidate : kPresetDebugKeys) {
        if (key == QLatin1String(candidate.key))
            return &candidate;
    }
    return nullptr;
}

} // namespace

class SettingsBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit SettingsBridge(QObject *parent = nullptr) : QObject(parent) {}

    QString lastError() const { return m_lastError; }

    Q_INVOKABLE QVariantMap dockSnapshot() {
        return snapshotFromReply(callDock({QStringLiteral("snapshot")}));
    }

    Q_INVOKABLE QVariantMap updateDockLayout(double height) {
        return snapshotFromReply(callDock({QStringLiteral("updateLayout"),
                                           QString::number(height, 'f', 2)}));
    }

    Q_INVOKABLE QVariantMap updateDockPosition(const QString &position) {
        return snapshotFromReply(callDock({QStringLiteral("updatePosition"), position}));
    }

    Q_INVOKABLE QVariantMap updateDockIconMode(const QString &mode) {
        return snapshotFromReply(callDock({QStringLiteral("updateIconMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateDockIconOpacity(double opacity) {
        return snapshotFromReply(callDock({QStringLiteral("updateIconOpacity"), QString::number(opacity, 'f', 2)}));
    }

    Q_INVOKABLE QVariantMap updateDockIconTintColor(const QString &color) {
        return snapshotFromReply(callDock({QStringLiteral("updateIconTintColor"), color}));
    }

    Q_INVOKABLE QVariantMap updateDockVisibilityMode(const QString &mode) {
        return snapshotFromReply(callDock({QStringLiteral("updateVisibilityMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateDockWindowGrouping(const QString &mode) {
        return snapshotFromReply(callDock({QStringLiteral("updateWindowGrouping"), mode}));
    }

    Q_INVOKABLE QVariantMap appearanceSnapshot() {
        return appearanceSnapshotFromReply(callAppearance({QStringLiteral("snapshot")}));
    }

    Q_INVOKABLE QVariantMap updateBlurStrength(double strength) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap updateLiquidStrength(double strength) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap updateGlobalBlurStrength(double strength) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap updateGlobalLiquidStrength(double strength) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap updateGlassStyle(const QString &style) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlassStyle"), style}));
    }

    Q_INVOKABLE QVariantMap updateGlassPresetParameter(const QString &name, double value) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlassPresetParameter"), name,
            QString::number(value, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap resetGlassPreset(const QString &style) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("resetGlassPreset"), style}));
    }

    Q_INVOKABLE QVariantList glassDebugSnapshot() {
        // One round trip, shared: the 材质 rows below take their value from the
        // active preset carried in this snapshot, and glassPresetStyle() names
        // the style those values belong to. An unreachable shell leaves the
        // snapshot empty, so those rows fall back to reading kwinrc and a write
        // reports the shell error instead of silently doing nothing.
        m_appearanceSnapshot = fetchAppearanceSnapshot();
        return glassDebugSpecs();
    }

    // Which style's preset the debug page's 材质 rows edit, as of the last
    // glassDebugSnapshot() call. Shown next to them so a tuned value is not
    // mistaken for a global one.
    Q_INVOKABLE QString glassPresetStyle() const {
        return m_appearanceSnapshot.value(QStringLiteral("glassStyle"))
            .toString(QStringLiteral("liquid"));
    }

    // Helpers for glassDebugSnapshot(); not Q_INVOKABLE, QML reaches them only
    // through it.
    QJsonObject fetchAppearanceSnapshot() {
        const QByteArray payload = callAppearance({QStringLiteral("snapshot")}).toUtf8();
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject())
            return {};
        return document.object();
    }

    QVariantList glassDebugSpecs() const {
        const QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc");
        QSettings config(path, QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        QVariantList result;
        const auto add = [&](const char *key, const char *label, const char *section,
                             const char *type, double minimum, double maximum,
                             double step, const QVariant &fallback) {
            // Preset-backed rows report the preset's own value, converted into
            // kwinrc units so the ranges below stay meaningful, and are marked so
            // updateGlassDebugValue() knows to write the preset rather than kwinrc.
            bool presetBacked = false;
            QVariant value = config.value(QString::fromLatin1(key), fallback);
            if (const PresetDebugKey *preset = presetDebugKey(QString::fromLatin1(key))) {
                const QJsonValue stored = m_appearanceSnapshot.value(
                    QStringLiteral("activePreset") + QString::fromLatin1(preset->parameter));
                if (stored.isDouble()) {
                    presetBacked = true;
                    value = stored.toDouble() * preset->toKwinrc;
                }
            }
            result.append(QVariantMap{{QStringLiteral("key"), QString::fromLatin1(key)},
                {QStringLiteral("label"), QString::fromUtf8(label)},
                {QStringLiteral("section"), QString::fromUtf8(section)},
                {QStringLiteral("type"), QString::fromLatin1(type)},
                {QStringLiteral("min"), minimum}, {QStringLiteral("max"), maximum},
                {QStringLiteral("step"), step},
                {QStringLiteral("presetBacked"), presetBacked},
                {QStringLiteral("value"), value}});
        };
        add("BlurFinetune", "模糊精调", "模糊", "int", 0, 10, 1, 3);
        add("NoiseStrength", "内容噪点", "模糊", "int", 0, 100, 1, 5);
        add("DecorationNoiseStrength", "窗口装饰噪点", "模糊", "int", 0, 100, 1, 5);
        add("DockNoiseStrength", "Dock 噪点", "模糊", "int", 0, 100, 1, 5);
        add("BlurSaturationCompensation", "模糊饱和度补偿", "模糊", "bool", 0, 1, 1, true);
        add("Brightness", "亮度", "色彩", "real", 0, 2, .01, 1.0);
        add("Saturation", "饱和度", "色彩", "real", 0, 3, .01, 1.0);
        add("Contrast", "对比度", "色彩", "real", 0, 2, .01, 1.0);
        add("OklabSaturation", "使用 OKLab 饱和度", "色彩", "bool", 0, 1, 1, false);
        add("RefractionStrength", "折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("RefractionEdgeSize", "折射边缘范围", "材质", "real", 0, 50, .1, 20.0);
        add("RefractionNormalPow", "折射法线曲线", "材质", "real", .1, 10, .1, 2.0);
        add("RefractionRGBFringing", "RGB 色散", "材质", "real", 0, 20, .1, 1.0);
        add("RefractionOffsetStrength", "主体折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("MaterialSoftness", "柔和度", "材质", "real", 0, 1, .01, 0.0);
        add("MaterialReflectionStrength", "宽反射强度", "材质", "real", 0, 1, .01, 0.0);
        add("ExcludeDecorations", "窗口装饰不应用染色", "适用范围", "bool", 0, 1, 1, false);
        add("MenuCornerRadius", "菜单圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("DockCornerRadius", "Dock 圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("CornerExponent", "圆角连续度", "圆角", "real", 2, 8, .1, 3.0);
        add("UseDeclaredCornerRadius", "优先使用应用声明圆角", "圆角", "bool", 0, 1, 1, false);
        add("IgnoreContentBlurRegion", "忽略内容模糊区域", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCorners", "动态圆角", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeDocks", "动态圆角排除 Dock", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeTooltips", "动态圆角排除 Tooltip", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeMenus", "动态圆角排除菜单", "圆角", "bool", 0, 1, 1, false);
        add("OnlyQuickshell", "仅处理 Quickshell", "窗口匹配", "bool", 0, 1, 1, true);
        add("WindowClasses", "窗口类列表", "窗口匹配", "string", 0, 0, 0, QStringLiteral("quickshell"));
        add("BlurMatching", "匹配列表内窗口", "窗口匹配", "bool", 0, 1, 1, true);
        add("BlurDecorations", "强制模糊窗口装饰", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurMenus", "强制模糊菜单", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurDocks", "强制模糊 Dock", "窗口匹配", "bool", 0, 1, 1, false);
        add("SkipEmptyDockBlurRegions", "跳过空 Dock 模糊区域", "窗口匹配", "bool", 0, 1, 1, true);
        config.endGroup();
        return result;
    }

    Q_INVOKABLE bool updateGlassDebugValue(const QString &key, const QVariant &value) {
        // The spec table does not depend on the appearance snapshot, so this
        // reuses whatever the last glassDebugSnapshot() cached instead of paying
        // for another round trip per edit.
        const QVariantList specs = glassDebugSpecs();
        QVariantMap match;
        for (const QVariant &item : specs) {
            const QVariantMap spec = item.toMap();
            if (spec.value(QStringLiteral("key")).toString() == key) { match = spec; break; }
        }
        if (match.isEmpty()) return false;
        QVariant stored = value;
        const QString type = match.value(QStringLiteral("type")).toString();
        if (type == QStringLiteral("bool")) stored = value.toBool();
        else if (type != QStringLiteral("string")) {
            const double number = qBound(match.value(QStringLiteral("min")).toDouble(),
                value.toDouble(), match.value(QStringLiteral("max")).toDouble());
            stored = type == QStringLiteral("int") ? QVariant(qRound(number)) : QVariant(number);
        }
        // A preset-backed key belongs to the shell: writing kwinrc directly would
        // be undone by the next appearance sync. Hand it the value in preset units
        // and let it persist the preset and reconfigure the effect; the reply is a
        // full snapshot, so a rejected write (bad name, shell down) reports why.
        if (const PresetDebugKey *preset = presetDebugKey(key)) {
            const QString reply = callAppearance({QStringLiteral("updateGlassPresetParameter"),
                QString::fromLatin1(preset->parameter),
                QString::number(stored.toDouble() / preset->toKwinrc, 'f', 3)});
            return !appearanceSnapshotFromReply(reply).isEmpty();
        }
        QSettings config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc"), QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        config.setValue(key, stored); config.endGroup(); config.sync();
        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
            QStringLiteral("org.kde.kwin.Effects"));
        if (effects.isValid()) effects.call(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
        return config.status() == QSettings::NoError;
    }

    Q_INVOKABLE QVariantMap updateGlobalIconMode(const QString &mode) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalIconMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateGlobalIconOpacity(double opacity) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalIconOpacity"),
            QString::number(opacity, 'f', 3)}));
    }

    Q_INVOKABLE QVariantMap updateGlobalIconTintColor(const QString &color) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlobalIconTintColor"), color}));
    }

    Q_INVOKABLE QVariantMap updateShellStyle(const QString &style) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateShellStyle"), style}));
    }

    Q_INVOKABLE QVariantMap updateMaterialColorScheme(const QString &scheme) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateMaterialColorScheme"), scheme}));
    }

    Q_INVOKABLE QVariantMap updateBarIntegratedWithDock(bool enabled) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateBarIntegratedWithDock"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")}));
    }

    Q_INVOKABLE QVariantMap updateGlassFollowsAppearanceMode(bool enabled) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateGlassFollowsAppearanceMode"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")}));
    }

    Q_INVOKABLE QVariantMap updateBarVisibilityMode(const QString &mode) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateBarVisibilityMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateBarLayoutMode(const QString &mode) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateBarLayoutMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateDockWindowAnimationStyle(const QString &style) {
        return appearanceSnapshotFromReply(callAppearance({
            QStringLiteral("updateDockWindowAnimationStyle"), style}));
    }

    Q_INVOKABLE QVariantMap resetAppearanceStrengths() {
        return appearanceSnapshotFromReply(callAppearance({QStringLiteral("resetStrengths")}));
    }

    Q_INVOKABLE QVariantMap launcherSnapshot() {
        return launcherSnapshotFromReply(callLauncher({QStringLiteral("snapshot")}));
    }

    Q_INVOKABLE QVariantMap shortcutsSnapshot() {
        return shortcutsSnapshotFromReply(callShortcuts({QStringLiteral("snapshot")}));
    }

    Q_INVOKABLE QVariantMap updateShortcut(const QString &id, const QString &combo) {
        return shortcutsSnapshotFromReply(callShortcuts({QStringLiteral("updateShortcut"),
                                                         id, combo}));
    }

    Q_INVOKABLE QVariantMap resetShortcut(const QString &id) {
        return shortcutsSnapshotFromReply(callShortcuts({QStringLiteral("resetShortcut"), id}));
    }

    Q_INVOKABLE QVariantMap updateLauncherDisplayMode(const QString &mode) {
        return launcherSnapshotFromReply(callLauncher({
            QStringLiteral("updateDisplayMode"), mode}));
    }

    Q_INVOKABLE QVariantMap updateLauncherProfileIconSize(const QString &mode,
                                                           const QString &size) {
        return launcherSnapshotFromReply(callLauncher({
            QStringLiteral("updateProfileIconSize"), mode, size}));
    }

    Q_INVOKABLE QVariantMap updateLauncherProfileDensity(const QString &mode,
                                                          const QString &density) {
        return launcherSnapshotFromReply(callLauncher({
            QStringLiteral("updateProfileDensity"), mode, density}));
    }

    Q_INVOKABLE QVariantMap updateLauncherProfileFontWeight(const QString &mode,
                                                             const QString &weight) {
        return launcherSnapshotFromReply(callLauncher({
            QStringLiteral("updateProfileFontWeight"), mode, weight}));
    }

    Q_INVOKABLE QVariantMap resetLauncherLayoutProfile(const QString &mode) {
        return launcherSnapshotFromReply(callLauncher({
            QStringLiteral("resetProfile"), mode}));
    }

    Q_INVOKABLE bool applySystemAppearance(bool dark) {
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(
            callAppearance({QStringLiteral("applySystemAppearance"),
                            dark ? QStringLiteral("true") : QStringLiteral("false")})
                .toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject())
            return false;
        const QJsonObject response = document.object();
        const bool accepted = response.value(QStringLiteral("accepted")).toBool();
        if (!accepted && m_lastError.isEmpty())
            setLastError(QStringLiteral("桌面环境拒绝了主题切换请求"));
        return accepted;
    }

    Q_INVOKABLE QVariantMap integrationSnapshot() {
        QVariantMap result = integrationSnapshotFromReply(
            callIntegration({QStringLiteral("snapshot")}));

        const QDBusConnection sessionBus = QDBusConnection::sessionBus();
        auto *busInterface = sessionBus.interface();
        QString notificationProvider = QStringLiteral("none");
        QString notificationOwner;
        uint notificationPid = 0;
        if (busInterface) {
            const QDBusReply<QString> ownerReply = busInterface->serviceOwner(
                QStringLiteral("org.freedesktop.Notifications"));
            if (ownerReply.isValid() && !ownerReply.value().isEmpty()) {
                notificationOwner = ownerReply.value();
                const QDBusReply<uint> pidReply = busInterface->servicePid(notificationOwner);
                if (pidReply.isValid())
                    notificationPid = pidReply.value();

                QFile commandLine(QStringLiteral("/proc/%1/cmdline").arg(notificationPid));
                QString command;
                if (commandLine.open(QIODevice::ReadOnly)) {
                    QByteArray raw = commandLine.readAll();
                    raw.replace('\0', ' ');
                    command = QString::fromLocal8Bit(raw).trimmed();
                }
                if (command.contains(QStringLiteral("plasmashell"))) {
                    notificationProvider = QStringLiteral("plasma");
                } else if (command.contains(QStringLiteral("/qs"))
                           || command.contains(QStringLiteral("quickshell"))) {
                    notificationProvider = QStringLiteral("kos");
                } else {
                    notificationProvider = QStringLiteral("other");
                }
                result.insert(QStringLiteral("notificationCommand"), command);
            }
        }
        result.insert(QStringLiteral("notificationProvider"), notificationProvider);
        result.insert(QStringLiteral("notificationOwner"), notificationOwner);
        result.insert(QStringLiteral("notificationPid"), notificationPid);

        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                               QStringLiteral("org.kde.kwin.Effects"), sessionBus);
        const QStringList loadedEffects = effects.isValid()
            ? effects.property("loadedEffects").toStringList() : QStringList{};
        result.insert(QStringLiteral("kwinAvailable"), effects.isValid());
        result.insert(QStringLiteral("glassLoaded"),
                      loadedEffects.contains(QStringLiteral("glass")));
        result.insert(QStringLiteral("dockAnimationLoaded"),
                      loadedEffects.contains(QStringLiteral("kos_dock_window_animation")));
        result.insert(QStringLiteral("contextMenuInputLoaded"),
                      loadedEffects.contains(QStringLiteral("kos_context_menu_input")));
        result.insert(QStringLiteral("updatedAt"),
                      QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));
        return result;
    }

signals:
    void lastErrorChanged();

private:
    QVariantMap snapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的 Dock 配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("baseHeight"))
                || !object.contains(QStringLiteral("windowGrouping"))) {
            setLastError(QStringLiteral("桌面环境返回的 Dock 配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("baseHeight"), object.value(QStringLiteral("baseHeight")).toDouble()},
            {QStringLiteral("position"), object.value(QStringLiteral("position")).toString()},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString()},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble()},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString()},
            {QStringLiteral("visibilityMode"), object.value(QStringLiteral("visibilityMode")).toString()},
            {QStringLiteral("windowGrouping"), object.value(QStringLiteral("windowGrouping")).toString()},
        };
    }

    QVariantMap appearanceSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的外观配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if ((!object.contains(QStringLiteral("globalBlurStrength"))
                    && !object.contains(QStringLiteral("dockBlurStrength"))
                    && !object.contains(QStringLiteral("blurStrength")))
                || (!object.contains(QStringLiteral("globalLiquidStrength"))
                    && !object.contains(QStringLiteral("dockLiquidStrength"))
                    && !object.contains(QStringLiteral("liquidStrength")))
                || !object.contains(QStringLiteral("shellStyle"))
                || !object.contains(QStringLiteral("barIntegratedWithDock"))
                || !object.contains(QStringLiteral("dockWindowAnimationStyle"))) {
            setLastError(QStringLiteral("桌面环境返回的外观配置不完整"));
            return {};
        }

        const double globalBlur = object.contains(QStringLiteral("globalBlurStrength"))
            ? object.value(QStringLiteral("globalBlurStrength")).toDouble()
            : (object.contains(QStringLiteral("dockBlurStrength"))
                ? object.value(QStringLiteral("dockBlurStrength")).toDouble()
                : object.value(QStringLiteral("blurStrength")).toDouble());
        const double globalLiquid = object.contains(QStringLiteral("globalLiquidStrength"))
            ? object.value(QStringLiteral("globalLiquidStrength")).toDouble()
            : (object.contains(QStringLiteral("dockLiquidStrength"))
                ? object.value(QStringLiteral("dockLiquidStrength")).toDouble()
                : object.value(QStringLiteral("liquidStrength")).toDouble());

        const QString barVisibility = object.value(QStringLiteral("barVisibilityMode")).toString(QStringLiteral("always"));

        setLastError({});
        // Also the source glassDebugSpecs() reads the active preset from: this
        // object carries every preset field, while the map below hand-picks the
        // ones the appearance pages consume.
        m_appearanceSnapshot = object;
        return {
            {QStringLiteral("globalBlurStrength"), globalBlur},
            {QStringLiteral("globalLiquidStrength"), globalLiquid},
            {QStringLiteral("glassStyle"),
                object.value(QStringLiteral("glassStyle")).toString(QStringLiteral("liquid"))},
            {QStringLiteral("activePresetRefraction"),
                object.value(QStringLiteral("activePresetRefraction")).toDouble(1.0)},
            {QStringLiteral("activePresetSoftness"),
                object.value(QStringLiteral("activePresetSoftness")).toDouble()},
            {QStringLiteral("activePresetReflection"),
                object.value(QStringLiteral("activePresetReflection")).toDouble()},
            {QStringLiteral("effectiveDockBlur"), globalBlur},
            {QStringLiteral("effectiveDockLiquid"), globalLiquid},
            {QStringLiteral("effectiveBarBlur"), globalBlur},
            {QStringLiteral("effectiveBarLiquid"), globalLiquid},
            {QStringLiteral("effectiveLauncherBlur"), globalBlur},
            {QStringLiteral("effectiveLauncherLiquid"), globalLiquid},
            {QStringLiteral("blurStrength"), globalBlur},
            {QStringLiteral("liquidStrength"), globalLiquid},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString(QStringLiteral("color"))},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble(0.5)},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString(QStringLiteral("#a855f7"))},
            {QStringLiteral("shellStyle"), object.value(QStringLiteral("shellStyle")).toString()},
            {QStringLiteral("materialColorScheme"),
                object.value(QStringLiteral("materialColorScheme")).toString(QStringLiteral("monet"))},
            {QStringLiteral("materialAccentName"),
                object.value(QStringLiteral("materialAccentName")).toString()},
            // Swatch previews for the colour-source picker, as a JSON string.
            // The QML side parses it; passing the nested structure through
            // QVariantList/QVariantMap instead left the picker empty.
            {QStringLiteral("materialColorSwatches"),
                object.value(QStringLiteral("materialColorSwatches")).toString()},
            {QStringLiteral("barIntegratedWithDock"),
                object.value(QStringLiteral("barIntegratedWithDock")).toBool()},
            {QStringLiteral("glassFollowsAppearanceMode"),
                object.value(QStringLiteral("glassFollowsAppearanceMode")).toBool(true)},
            {QStringLiteral("barVisibilityMode"),
                barVisibility.isEmpty() ? QStringLiteral("always") : barVisibility},
            {QStringLiteral("barLayoutMode"),
                object.value(QStringLiteral("barLayoutMode")).toString(QStringLiteral("transparent"))},
            {QStringLiteral("dockWindowAnimationStyle"),
                object.value(QStringLiteral("dockWindowAnimationStyle")).toString()},
            {QStringLiteral("tokenVersion"), object.value(QStringLiteral("tokenVersion")).toInt()},
        };
    }

    QVariantMap launcherSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的启动台配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("displayMode"))) {
            setLastError(QStringLiteral("桌面环境返回的启动台配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("displayMode"), object.value(QStringLiteral("displayMode")).toString()},
            {QStringLiteral("layoutProfiles"),
                object.value(QStringLiteral("layoutProfiles")).toObject().toVariantMap()},
        };
    }

    QVariantMap integrationSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {{QStringLiteral("shellReady"), false}};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的接入状态"));
            return {{QStringLiteral("shellReady"), false}};
        }
        setLastError({});
        return document.object().toVariantMap();
    }

    QVariantMap shortcutsSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的快捷键配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("shortcuts"))) {
            setLastError(QStringLiteral("桌面环境返回的快捷键配置不完整"));
            return {};
        }

        QVariantList shortcuts;
        for (const QJsonValue &value : object.value(QStringLiteral("shortcuts")).toArray()) {
            const QJsonObject item = value.toObject();
            shortcuts.append(QVariantMap{
                {QStringLiteral("id"), item.value(QStringLiteral("id")).toString()},
                {QStringLiteral("description"), item.value(QStringLiteral("description")).toString()},
                {QStringLiteral("defaultCombo"), item.value(QStringLiteral("defaultCombo")).toString()},
                {QStringLiteral("combo"), item.value(QStringLiteral("combo")).toString()},
                {QStringLiteral("custom"), item.value(QStringLiteral("custom")).toBool()},
            });
        }

        // The Shell validates rebinding requests and reports rejections
        // (unknown id, malformed combo, duplicate binding) inline instead of
        // failing the IPC call, so surface it the same way as transport errors.
        const QString error = object.value(QStringLiteral("error")).toString();
        setLastError(error);
        return {
            {QStringLiteral("shortcuts"), shortcuts},
            {QStringLiteral("error"), error},
        };
    }

    QString callDock(const QStringList &arguments) {
        return callShell(QStringLiteral("dock-settings"), arguments,
                         QStringLiteral("Dock 设置请求失败"));
    }

    QString callAppearance(const QStringList &arguments) {
        return callShell(QStringLiteral("appearance-settings"), arguments,
                         QStringLiteral("外观设置请求失败"));
    }

    QString callLauncher(const QStringList &arguments) {
        return callShell(QStringLiteral("applauncher-settings"), arguments,
                         QStringLiteral("启动台设置请求失败"));
    }

    QString callShortcuts(const QStringList &arguments) {
        return callShell(QStringLiteral("shortcuts-settings"), arguments,
                         QStringLiteral("快捷键设置请求失败"));
    }

    QString callIntegration(const QStringList &arguments) {
        return callShell(QStringLiteral("integration-status"), arguments,
                         QStringLiteral("接入状态请求失败"));
    }

    static QString shellDirectory() {
        const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
        if (!configured.isEmpty())
            return configured;

        // Development desktop entries do not inherit the Shell environment.
        // Prefer the compile-time source tree when it still exists; this is
        // the same tree a locally built settings binary was compiled for.
        const QString source = QStringLiteral(SETTINGS_SHELL_DIR);
        if (QFileInfo::exists(QDir(source).filePath(QStringLiteral("shell.qml"))))
            return source;

        const QString installed = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/quickshell/kos");
        return installed;
    }

    QString callShell(const QString &target, const QStringList &arguments,
                      const QString &fallbackError) {
        const QString shellPath = shellDirectory();
        QString failure;
        // Quickshell tracks instances by how they identify their config: a
        // Shell launched as `-c kos` is NOT matched by `--path <same dir>`.
        // The installed session runs as `-c kos`, so address it by name;
        // development sessions (`-p <dir>`) take the explicit path.
        const QString installed = QStandardPaths::writableLocation(
            QStandardPaths::ConfigLocation) + QStringLiteral("/quickshell/kos");
        QStringList connectArgs;
        if (shellPath == installed)
            connectArgs = {QStringLiteral("-c"), QStringLiteral("kos")};
        else
            connectArgs = {QStringLiteral("--path"), shellPath};
        // The Shell can still be registering IPC targets during the first
        // moments of a development launch. Retry once instead of turning that
        // brief race into a permanent, opaque Settings error.
        for (int attempt = 0; attempt < 2; ++attempt) {
            QProcess process;
            QStringList command = connectArgs;
            command << QStringLiteral("ipc") << QStringLiteral("call") << target;
            command.append(arguments);
            process.start(QStringLiteral("quickshell"), command);
            if (!process.waitForStarted(1500)) {
                failure = QStringLiteral("无法启动 Quickshell IPC");
            } else if (!process.waitForFinished(5000)) {
                process.kill();
                process.waitForFinished();
                failure = QStringLiteral("桌面环境没有响应（超过 5 秒）");
            } else if (process.exitStatus() == QProcess::NormalExit
                       && process.exitCode() == 0) {
                return QString::fromUtf8(process.readAllStandardOutput()).trimmed();
            } else {
                failure = QString::fromUtf8(process.readAllStandardError()).trimmed();
                if (failure.isEmpty())
                    failure = fallbackError;
            }
            if (attempt == 0)
                QThread::msleep(120);
        }
        setLastError(QStringLiteral("%1（IPC：%2；Shell：%3）")
                         .arg(failure, target, shellPath));
        return {};
    }

    void setLastError(const QString &error) {
        if (m_lastError == error)
            return;
        m_lastError = error;
        emit lastErrorChanged();
    }

    QString m_lastError;
    // Last appearance snapshot the shell sent. Kept for glassDebugSpecs(), which
    // reads the active preset out of it, and refreshed on every glass debug
    // snapshot so the style it names is the one being edited right now.
    QJsonObject m_appearanceSnapshot;
};

int main(int argc, char *argv[]) {
    QGuiApplication application(argc, argv);
    // Keep this window out of the Shell's KWin rules. This must match the
    // installed desktop entry basename: kos-settings.desktop.
    application.setApplicationName(QStringLiteral("kos-settings"));
    application.setApplicationDisplayName(QStringLiteral(""));
    application.setDesktopFileName(QStringLiteral("kos-settings"));
    application.setOrganizationName(QStringLiteral("Quickshell"));

    SettingsBridge bridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBridge"), &bridge);
    QString settingsQml = QDir(QCoreApplication::applicationDirPath()).filePath(
        QStringLiteral("../share/kos/settings/main.qml"));
    if (!QFileInfo::exists(settingsQml))
        settingsQml = QDir(QStringLiteral(SETTINGS_QML_DIR)).filePath(
            QStringLiteral("main.qml"));
    const QUrl entrypoint = QUrl::fromLocalFile(settingsQml);
    engine.load(entrypoint);
    if (engine.rootObjects().isEmpty())
        return 1;
    // --smoke-test is the build-side check that the settings window loads:
    // run one event loop turn (as ApplicationRunner does for the apps) and
    // exit, so CI can prove main.qml instantiates without a display.
    if (application.arguments().contains(QStringLiteral("--smoke-test")))
        QTimer::singleShot(250, &application, &QCoreApplication::quit);
    return application.exec();
}

#include "main.moc"
