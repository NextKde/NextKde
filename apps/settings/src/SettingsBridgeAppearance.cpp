#include "SettingsBridge.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>

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
    const char* key;
    const char* parameter;
    double toKwinrc;
};

const PresetDebugKey kPresetDebugKeys[] = {
    { "RefractionStrength", "Refraction", 20.0 },
    { "RefractionEdgeSize", "EdgeSize", 1.0 },
    { "RefractionNormalPow", "NormalPow", 1.0 },
    { "RefractionRGBFringing", "RGBFringing", 1.0 },
    { "RefractionOffsetStrength", "OffsetStrength", 1.0 },
    { "MaterialSoftness", "Softness", 1.0 },
    { "MaterialReflectionStrength", "Reflection", 1.0 },
};

const PresetDebugKey* presetDebugKey(const QString& key)
{
    for (const PresetDebugKey& candidate : kPresetDebugKeys) {
        if (key == QLatin1String(candidate.key))
            return &candidate;
    }
    return nullptr;
}

// Rows that belong to neither side of this window: the shell rewrites them from
// a design value on every appearance sync, so a Settings edit would take effect
// and then silently revert. CornerExponent is the one such key today -- the
// shell writes it from AppearanceTokens.shape.cornerExponent, which is a source
// constant, not user configuration. Those rows are reported read-only so the UI
// stops offering a control that cannot hold its value; the write path is refused
// as well, so a stale UI cannot reintroduce the double write.
bool isReadOnlyDebugKey(const QString& key) { return key == QLatin1String("CornerExponent"); }

} // namespace

void SettingsBridge::appearanceSnapshot() { callAppearance({ QStringLiteral("snapshot") }); }

void SettingsBridge::updateBlurStrength(double strength)
{
    callAppearance(
        { QStringLiteral("updateGlobalBlurStrength"), QString::number(strength, 'f', 3) });
}

void SettingsBridge::updateLiquidStrength(double strength)
{
    callAppearance(
        { QStringLiteral("updateGlobalLiquidStrength"), QString::number(strength, 'f', 3) });
}

void SettingsBridge::updateGlobalBlurStrength(double strength)
{
    callAppearance(
        { QStringLiteral("updateGlobalBlurStrength"), QString::number(strength, 'f', 3) });
}

void SettingsBridge::updateGlobalLiquidStrength(double strength)
{
    callAppearance(
        { QStringLiteral("updateGlobalLiquidStrength"), QString::number(strength, 'f', 3) });
}

void SettingsBridge::updateGlassStyle(const QString& style)
{
    callAppearance({ QStringLiteral("updateGlassStyle"), style });
}

void SettingsBridge::updateWidgetStyle(const QString& style)
{
    callAppearance({ QStringLiteral("updateWidgetStyle"), style });
}

void SettingsBridge::updateGlassPresetParameter(const QString& name, double value)
{
    callAppearance(
        { QStringLiteral("updateGlassPresetParameter"), name, QString::number(value, 'f', 3) });
}

void SettingsBridge::resetGlassPreset(const QString& style)
{
    callAppearance({ QStringLiteral("resetGlassPreset"), style });
}

void SettingsBridge::glassDebugSnapshot()
{
    callShell(QStringLiteral("appearance-settings"), { QStringLiteral("snapshot") },
        QStringLiteral("Appearance settings request failed"), RequestKind::GlassDebug);
}

void SettingsBridge::updateGlassDebugValue(const QString& key, const QVariant& value)
{
    const QVariantMap match = glassDebugSpec(key);
    if (match.isEmpty()) {
        setLastError(QStringLiteral("Unknown KWin parameter: %1").arg(key));
        emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
        return;
    }
    QVariant stored = value;
    // A design-value row has no writable home: the shell re-derives it on
    // every appearance sync. Refuse the write rather than let the value
    // silently revert, and say why so the failure is not a mystery.
    if (match.value(QStringLiteral("readOnly")).toBool()) {
        setLastError(QStringLiteral(
            "This parameter is decided by the appearance design value and cannot be changed here"));
        emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
        return;
    }

    const QString type = match.value(QStringLiteral("type")).toString();
    if (type == QStringLiteral("bool"))
        stored = value.toBool();
    else if (type != QStringLiteral("string")) {
        const double number = qBound(match.value(QStringLiteral("min")).toDouble(),
            value.toDouble(), match.value(QStringLiteral("max")).toDouble());
        stored = type == QStringLiteral("int") ? QVariant(qRound(number)) : QVariant(number);
    }
    // A preset-backed key belongs to the shell: writing kwinrc directly
    // would be undone by the next appearance sync. Hand it the value in
    // preset units and let it persist the preset and reconfigure the
    // effect; the reply is a full snapshot, so a rejected write (bad name,
    // shell down) reports why.
    if (const PresetDebugKey* preset = presetDebugKey(key)) {
        callShell(QStringLiteral("appearance-settings"),
            { QStringLiteral("updateGlassPresetParameter"), QString::fromLatin1(preset->parameter),
                QString::number(stored.toDouble() / preset->toKwinrc, 'f', 3) },
            QStringLiteral("Appearance settings request failed"), RequestKind::GlassDebug);
        return;
    }
    QSettings config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc"),
        QSettings::IniFormat);
    config.beginGroup(QStringLiteral("Effect-blurplus"));
    config.setValue(key, stored);
    config.endGroup();
    config.sync();
    QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
        QStringLiteral("org.kde.kwin.Effects"));
    if (effects.isValid())
        effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
    if (config.status() != QSettings::NoError) {
        setLastError(QStringLiteral("Failed to write the KWin configuration"));
        emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
        return;
    }
    glassDebugSnapshot();
}

void SettingsBridge::updateGlobalIconMode(const QString& mode)
{
    callAppearance({ QStringLiteral("updateGlobalIconMode"), mode });
}

void SettingsBridge::updateGlobalIconOpacity(double opacity)
{
    callAppearance({ QStringLiteral("updateGlobalIconOpacity"), QString::number(opacity, 'f', 3) });
}

void SettingsBridge::updateGlobalIconTintColor(const QString& color)
{
    callAppearance({ QStringLiteral("updateGlobalIconTintColor"), color });
}

void SettingsBridge::updateShellStyle(const QString& style)
{
    callAppearance({ QStringLiteral("updateShellStyle"), style });
}

void SettingsBridge::updateMaterialColorScheme(const QString& scheme)
{
    callAppearance({ QStringLiteral("updateMaterialColorScheme"), scheme });
}

void SettingsBridge::updateBarIntegratedWithDock(bool enabled)
{
    callAppearance({ QStringLiteral("updateBarIntegratedWithDock"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateGlassFollowsAppearanceMode(bool enabled)
{
    callAppearance({ QStringLiteral("updateGlassFollowsAppearanceMode"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateSpatialWallpaperEnabled(bool enabled)
{
    callAppearance({ QStringLiteral("updateSpatialWallpaperEnabled"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateBarVisibilityMode(const QString& mode)
{
    callAppearance({ QStringLiteral("updateBarVisibilityMode"), mode });
}

void SettingsBridge::updateBarLayoutMode(const QString& mode)
{
    callAppearance({ QStringLiteral("updateBarLayoutMode"), mode });
}

void SettingsBridge::updateBarMacStyle(bool enabled)
{
    callAppearance({ QStringLiteral("updateBarMacStyle"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::updateBarMacTint(double tint)
{
    callAppearance({ QStringLiteral("updateBarMacTint"), QString::number(tint, 'f', 3) });
}

void SettingsBridge::updateDockWindowAnimationStyle(const QString& style)
{
    callAppearance({ QStringLiteral("updateDockWindowAnimationStyle"), style });
}

// 使用系统字体. One write, because one process owns the answer: the Shell draws
// every surface this option is about (Bar, Dock, launcher, desk widgets, menus,
// quick search), and the standalone applications never needed it -- they name no
// family and already draw with whatever Qt's platform theme applied, which the
// KDE platform theme fills from the same kdeglobals entry.
void SettingsBridge::updateUseSystemFont(bool enabled)
{
    callAppearance({ QStringLiteral("updateUseSystemFont"),
        enabled ? QStringLiteral("true") : QStringLiteral("false") });
}

void SettingsBridge::resetAppearanceStrengths()
{
    callAppearance({ QStringLiteral("resetStrengths") });
}

void SettingsBridge::applySystemAppearance(bool dark)
{
    callShell(QStringLiteral("appearance-settings"),
        { QStringLiteral("applySystemAppearance"),
            dark ? QStringLiteral("true") : QStringLiteral("false") },
        QStringLiteral("Appearance settings request failed"), RequestKind::ApplySystemAppearance);
}

QVariantMap SettingsBridge::appearanceSnapshotFromReply(const QString& payload)
{
    if (payload.isEmpty())
        return { };

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setLastError(
            QStringLiteral("The desktop environment returned an invalid appearance configuration"));
        return { };
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
        setLastError(QStringLiteral(
            "The appearance configuration from the desktop environment is incomplete"));
        return { };
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

    const QString barVisibility
        = object.value(QStringLiteral("barVisibilityMode")).toString(QStringLiteral("always"));

    setLastError({ });
    // Also the source glassDebugSpecs() reads the active preset from: this
    // object carries every preset field, while the map below hand-picks the
    // ones the appearance pages consume.
    m_appearanceSnapshot = object;
    return {
        { QStringLiteral("globalBlurStrength"), globalBlur },
        { QStringLiteral("globalLiquidStrength"), globalLiquid },
        { QStringLiteral("glassStyle"),
            object.value(QStringLiteral("glassStyle")).toString(QStringLiteral("liquid")) },
        { QStringLiteral("activePresetRefraction"),
            object.value(QStringLiteral("activePresetRefraction")).toDouble(1.0) },
        { QStringLiteral("activePresetSoftness"),
            object.value(QStringLiteral("activePresetSoftness")).toDouble() },
        { QStringLiteral("activePresetReflection"),
            object.value(QStringLiteral("activePresetReflection")).toDouble() },
        { QStringLiteral("effectiveDockBlur"), globalBlur },
        { QStringLiteral("effectiveDockLiquid"), globalLiquid },
        { QStringLiteral("effectiveBarBlur"), globalBlur },
        { QStringLiteral("effectiveBarLiquid"), globalLiquid },
        { QStringLiteral("effectiveLauncherBlur"), globalBlur },
        { QStringLiteral("effectiveLauncherLiquid"), globalLiquid },
        { QStringLiteral("blurStrength"), globalBlur },
        { QStringLiteral("liquidStrength"), globalLiquid },
        { QStringLiteral("iconMode"),
            object.value(QStringLiteral("iconMode")).toString(QStringLiteral("color")) },
        { QStringLiteral("iconOpacity"),
            object.value(QStringLiteral("iconOpacity")).toDouble(0.5) },
        { QStringLiteral("iconTintColor"),
            object.value(QStringLiteral("iconTintColor")).toString(QStringLiteral("#a855f7")) },
        { QStringLiteral("shellStyle"), object.value(QStringLiteral("shellStyle")).toString() },
        { QStringLiteral("widgetStyle"),
            object.value(QStringLiteral("widgetStyle")).toString(QStringLiteral("color")) },
        { QStringLiteral("materialColorScheme"),
            object.value(QStringLiteral("materialColorScheme")).toString(QStringLiteral("monet")) },
        { QStringLiteral("materialAccentName"),
            object.value(QStringLiteral("materialAccentName")).toString() },
        // Swatch previews for the colour-source picker, as a JSON string.
        // The QML side parses it; passing the nested structure through
        // QVariantList/QVariantMap instead left the picker empty.
        { QStringLiteral("materialColorSwatches"),
            object.value(QStringLiteral("materialColorSwatches")).toString() },
        { QStringLiteral("barIntegratedWithDock"),
            object.value(QStringLiteral("barIntegratedWithDock")).toBool() },
        { QStringLiteral("glassFollowsAppearanceMode"),
            object.value(QStringLiteral("glassFollowsAppearanceMode")).toBool(true) },
        { QStringLiteral("spatialWallpaperEnabled"),
            object.value(QStringLiteral("spatialWallpaperEnabled")).toBool(false) },
        { QStringLiteral("barVisibilityMode"),
            barVisibility.isEmpty() ? QStringLiteral("always") : barVisibility },
        { QStringLiteral("barLayoutMode"),
            object.value(QStringLiteral("barLayoutMode")).toString(QStringLiteral("transparent")) },
        // A shell older than this page has neither key; the fallbacks are
        // the off/30% values such a shell renders with, so the selector and
        // the slider agree with the Bar even before the first write.
        { QStringLiteral("barMacStyle"),
            object.value(QStringLiteral("barMacStyle")).toBool(false) },
        { QStringLiteral("barMacTint"), object.value(QStringLiteral("barMacTint")).toDouble(0.30) },
        { QStringLiteral("dockWindowAnimationStyle"),
            object.value(QStringLiteral("dockWindowAnimationStyle")).toString() },
        // A shell older than this page has neither key; "off" and an empty
        // family are exactly what such a shell draws with, so the row is
        // present but names no family instead of inventing one.
        { QStringLiteral("useSystemFont"),
            object.value(QStringLiteral("useSystemFont")).toBool(false) },
        { QStringLiteral("systemFontFamily"),
            object.value(QStringLiteral("systemFontFamily")).toString() },
        { QStringLiteral("tokenVersion"), object.value(QStringLiteral("tokenVersion")).toInt() },
    };
}

QVariantList SettingsBridge::glassDebugSpecs() const
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kwinrc");
    QSettings config(path, QSettings::IniFormat);
    config.beginGroup(QStringLiteral("Effect-blurplus"));
    QVariantList result;
    const auto add = [&](const char* key, const char* label, const char* section, const char* type,
                         double minimum, double maximum, double step, const QVariant& fallback) {
        // Preset-backed rows report the preset's own value, converted into
        // kwinrc units so the ranges below stay meaningful, and are marked so
        // updateGlassDebugValue() knows to write the preset rather than kwinrc.
        bool presetBacked = false;
        const bool readOnly = isReadOnlyDebugKey(QString::fromLatin1(key));
        QVariant value = config.value(QString::fromLatin1(key), fallback);
        if (const PresetDebugKey* preset = presetDebugKey(QString::fromLatin1(key))) {
            const QJsonValue stored = m_appearanceSnapshot.value(
                QStringLiteral("activePreset") + QString::fromLatin1(preset->parameter));
            if (stored.isDouble()) {
                presetBacked = true;
                value = stored.toDouble() * preset->toKwinrc;
            }
        }
        result.append(QVariantMap { { QStringLiteral("key"), QString::fromLatin1(key) },
            { QStringLiteral("label"), QString::fromUtf8(label) },
            { QStringLiteral("section"), QString::fromUtf8(section) },
            { QStringLiteral("type"), QString::fromLatin1(type) },
            { QStringLiteral("min"), minimum }, { QStringLiteral("max"), maximum },
            { QStringLiteral("step"), step }, { QStringLiteral("presetBacked"), presetBacked },
            { QStringLiteral("readOnly"), readOnly }, { QStringLiteral("value"), value } });
    };
    add("BlurFinetune", "Blur finetune", "Blur", "int", 0, 10, 1, 3);
    add("NoiseStrength", "Content noise", "Blur", "int", 0, 100, 1, 5);
    add("DecorationNoiseStrength", "Decoration noise", "Blur", "int", 0, 100, 1, 5);
    add("DockNoiseStrength", "Dock noise", "Blur", "int", 0, 100, 1, 5);
    add("BlurSaturationCompensation", "Blur saturation compensation", "Blur", "bool", 0, 1, 1,
        true);
    add("Brightness", "Brightness", "Colour", "real", 0, 2, .01, 1.0);
    add("Saturation", "Saturation", "Colour", "real", 0, 3, .01, 1.0);
    add("Contrast", "Contrast", "Colour", "real", 0, 2, .01, 1.0);
    add("OklabSaturation", "Use OKLab saturation", "Colour", "bool", 0, 1, 1, false);
    add("RefractionStrength", "Refraction strength", "Material", "real", 0, 20, .1, 0.0);
    add("RefractionEdgeSize", "Refraction edge range", "Material", "real", 0, 50, .1, 20.0);
    add("RefractionNormalPow", "Refraction normal curve", "Material", "real", .1, 10, .1, 2.0);
    add("RefractionRGBFringing", "RGB fringing", "Material", "real", 0, 20, .1, 1.0);
    add("RefractionOffsetStrength", "Subject refraction strength", "Material", "real", 0, 20, .1,
        0.0);
    add("MaterialSoftness", "Softness", "Material", "real", 0, 1, .01, 0.0);
    add("MaterialReflectionStrength", "Wide reflection strength", "Material", "real", 0, 1, .01,
        0.0);
    add("ExcludeDecorations", "Skip tint on decorations", "Scope", "bool", 0, 1, 1, false);
    add("MenuCornerRadius", "Menu corner radius", "Corners", "real", 0, 100, 1, 0.0);
    add("DockCornerRadius", "Dock corner radius", "Corners", "real", 0, 100, 1, 0.0);
    add("CornerExponent", "Corner continuity", "Corners", "real", 2, 8, .1, 3.0);
    add("UseDeclaredCornerRadius", "Prefer app-declared corner radius", "Corners", "bool", 0, 1, 1,
        false);
    add("IgnoreContentBlurRegion", "Ignore content blur region", "Corners", "bool", 0, 1, 1, false);
    add("DynamicCorners", "Dynamic corners", "Corners", "bool", 0, 1, 1, false);
    add("DynamicCornersExcludeDocks", "Dynamic corners exclude Dock", "Corners", "bool", 0, 1, 1,
        false);
    add("DynamicCornersExcludeTooltips", "Dynamic corners exclude tooltips", "Corners", "bool", 0,
        1, 1, false);
    add("DynamicCornersExcludeMenus", "Dynamic corners exclude menus", "Corners", "bool", 0, 1, 1,
        false);
    add("OnlyQuickshell", "Quickshell only", "Window matching", "bool", 0, 1, 1, true);
    add("WindowClasses", "Window class list", "Window matching", "string", 0, 0, 0,
        QStringLiteral("quickshell"));
    add("BlurMatching", "Match listed windows", "Window matching", "bool", 0, 1, 1, true);
    add("BlurDecorations", "Force blur decorations", "Window matching", "bool", 0, 1, 1, false);
    add("BlurMenus", "Force blur menus", "Window matching", "bool", 0, 1, 1, false);
    add("BlurDocks", "Force blur Dock", "Window matching", "bool", 0, 1, 1, false);
    add("SkipEmptyDockBlurRegions", "Skip empty Dock blur regions", "Window matching", "bool", 0, 1,
        1, true);
    config.endGroup();
    return result;
}

QString SettingsBridge::glassPresetStyle() const
{
    return m_appearanceSnapshot.value(QStringLiteral("glassStyle"))
        .toString(QStringLiteral("liquid"));
}

QVariantMap SettingsBridge::glassDebugSpec(const QString& key) const
{
    const QVariantList specs = glassDebugSpecs();
    for (const QVariant& item : specs) {
        const QVariantMap spec = item.toMap();
        if (spec.value(QStringLiteral("key")).toString() == key)
            return spec;
    }
    return { };
}

void SettingsBridge::callAppearance(const QStringList& arguments)
{
    callShell(QStringLiteral("appearance-settings"), arguments,
        QStringLiteral("Appearance settings request failed"), RequestKind::Appearance);
}
