#include "appearanceconfig.h"

#include <KConfig>
#include <KConfigGroup>

#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QPair>
#include <QStandardPaths>

#include <algorithm>
#include <limits>

namespace KOS::WindowAppearance
{

namespace
{

QString configPath()
{
    // The plan fixes the location: one file under the user's config
    // directory, written atomically by whoever edits it.
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kos/window-appearance.json");
}

// ---- small validation helpers ----------------------------------------------
//
// Every helper either writes a valid value into `into` or writes the field
// path into `error` and leaves `into` alone. A section with one bad field is
// a rejected document, not a partially applied one: the caller keeps the last
// good configuration in that case.

bool isColorString(const QString &value)
{
    // #AARRGGBB -- the plan is explicit that every colour carries its alpha.
    return value.size() == 9 && value.startsWith(u'#')
        && std::all_of(value.cbegin() + 1, value.cend(), [](QChar c) {
               return c.isDigit() || (c.toLower() >= u'a' && c.toLower() <= u'f');
           });
}

bool parseColor(const QJsonObject &object, const QString &key,
                QColor &into, QString *error)
{
    if (!object.contains(key)) {
        return true;
    }
    const QString value = object.value(key).toString();
    if (!isColorString(value)) {
        *error = key;
        return false;
    }
    into = QColor(value);
    return true;
}

bool parseDouble(const QJsonObject &object, const QString &key,
                 double minimum, double maximum, qreal &into, QString *error)
{
    if (!object.contains(key)) {
        return true;
    }
    const QJsonValue value = object.value(key);
    if (!value.isDouble()) {
        *error = key;
        return false;
    }
    const double number = value.toDouble();
    if (number < minimum || number > maximum) {
        *error = key;
        return false;
    }
    into = number;
    return true;
}

bool parseInt(const QJsonObject &object, const QString &key,
              int minimum, int maximum, int &into, QString *error)
{
    if (!object.contains(key)) {
        return true;
    }
    const QJsonValue value = object.value(key);
    if (!value.isDouble()) {
        *error = key;
        return false;
    }
    const int number = value.toInt(-1);
    if (number < minimum || number > maximum) {
        *error = key;
        return false;
    }
    into = number;
    return true;
}

bool parseBool(const QJsonObject &object, const QString &key, bool &into,
               QString *error)
{
    if (!object.contains(key)) {
        return true;
    }
    const QJsonValue value = object.value(key);
    if (!value.isBool()) {
        *error = key;
        return false;
    }
    into = value.toBool();
    return true;
}

template<typename Enum>
bool parseEnum(const QJsonObject &object, const QString &key,
               std::initializer_list<QPair<QString, Enum>> names, Enum &into,
               QString *error)
{
    if (!object.contains(key)) {
        return true;
    }
    const QString value = object.value(key).toString();
    for (const auto &[name, parsed] : names) {
        if (value == name) {
            into = parsed;
            return true;
        }
    }
    *error = key;
    return false;
}

} // namespace

// ---- the value types --------------------------------------------------------

qreal FrameSettings::width() const
{
    switch (mode) {
    case FrameMode::None:
        return 0.0;
    case FrameMode::Small:
        return smallWidth;
    case FrameMode::Thick:
        return thickWidth;
    }
    return 0.0;
}

QColor FillSettings::colorFor(bool sessionDark) const
{
    switch (mode) {
    case ColorMode::Theme:
        return sessionDark ? dark : light;
    case ColorMode::ThemePair:
        return sessionDark ? dark : light;
    case ColorMode::Fixed:
        return fixedColor;
    }
    return fixedColor;
}

QColor OutlineSettings::colorFor(bool sessionDark) const
{
    switch (mode) {
    case ColorMode::Theme:
    case ColorMode::ThemePair:
        return sessionDark ? dark : light;
    case ColorMode::Fixed:
        return fixedColor;
    }
    return fixedColor;
}

qreal ShadowSettings::tierAlpha(int tier) const
{
    // Tier 0 is the active window; every further tier is one layer of
    // background windows further back. The decay bottoms out at
    // minimumStrength so a window is never shadowless merely for sitting
    // deep in the stack.
    if (!dynamic) {
        return strength;
    }
    qreal alpha = strength;
    for (int i = 0; i < tier; ++i) {
        alpha *= depthDecay;
    }
    return std::max(std::min(minimumStrength, strength), alpha);
}

WindowAppearance::CornerRadii EffectiveAppearance::cornerRadii(
    const QSizeF &size) const
{
    WindowAppearance::CornerRadii radii;
    const qreal extent = corners.profile == CornerProfile::Continuous
        ? WindowAppearance::cornerExtent(corners.radius, corners.smoothness) : corners.radius;
    radii.topLeft = WindowAppearance::clampedRadius(size, extent);
    radii.topRight = radii.topLeft;
    radii.bottomRight = radii.topLeft;
    radii.bottomLeft = radii.topLeft;
    return radii;
}

// ---- the section parsers -----------------------------------------------------

void AppearanceConfig::applyCorners(const QJsonObject &object,
                                    CornerSettings &into, QString *error)
{
    if (!parseDouble(object, QStringLiteral("radius"), 0.0, 200.0,
                     into.radius, error)) {
        return;
    }
    if (!parseEnum(object, QStringLiteral("profile"),
                   {{QStringLiteral("arc"), CornerProfile::Arc},
                    {QStringLiteral("continuous"), CornerProfile::Continuous}},
                   into.profile, error)) {
        return;
    }
    parseDouble(object, QStringLiteral("smoothness"), 0.0, 1.0,
                into.smoothness, error);
}

void AppearanceConfig::applyFrame(const QJsonObject &object,
                                  FrameSettings &into, QString *error)
{
    if (!parseEnum(object, QStringLiteral("mode"),
                   {{QStringLiteral("none"), FrameMode::None},
                    {QStringLiteral("small"), FrameMode::Small},
                    {QStringLiteral("thick"), FrameMode::Thick}},
                   into.mode, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("smallWidth"), 0.0, 64.0,
                     into.smallWidth, error)) {
        return;
    }
    parseDouble(object, QStringLiteral("thickWidth"), 0.0, 64.0,
                into.thickWidth, error);
}

void AppearanceConfig::applyContent(const QJsonObject &object,
                                    ContentSettings &into, QString *error)
{
    // All three modes are carried in the file today; the effect currently
    // implements the compact behaviour for every window (see the plan,
    // section 4: the protected modes need the decoration-side geometry work
    // first and are not claimed done here).
    parseEnum(object, QStringLiteral("mode"),
              {{QStringLiteral("protect"), ContentMode::Protect},
               {QStringLiteral("compact"), ContentMode::Compact},
               {QStringLiteral("preserve"), ContentMode::Preserve}},
              into.mode, error);
}

void AppearanceConfig::applyFill(const QJsonObject &object, FillSettings &into,
                                 QString *error)
{
    if (!parseEnum(object, QStringLiteral("mode"),
                   {{QStringLiteral("theme"), ColorMode::Theme},
                    {QStringLiteral("themePair"), ColorMode::ThemePair},
                    {QStringLiteral("fixed"), ColorMode::Fixed}},
                   into.mode, error)) {
        return;
    }
    if (!parseColor(object, QStringLiteral("color"), into.fixedColor, error)) {
        return;
    }
    if (!parseColor(object, QStringLiteral("light"), into.light, error)) {
        return;
    }
    parseColor(object, QStringLiteral("dark"), into.dark, error);
}

void AppearanceConfig::applyOutline(const QJsonObject &object,
                                    OutlineSettings &into, QString *error,
                                    bool legacyWidth)
{
    // A width written by the old schema was logical. Do not silently change
    // the meaning of existing app/global overrides; opt into physical units.
    if (legacyWidth && object.contains(QStringLiteral("width"))
        && !object.contains(QStringLiteral("widthUnit"))) {
        into.widthUnit = OutlineSettings::WidthUnit::Logical;
    }
    if (!parseEnum(object, QStringLiteral("widthUnit"),
                   {{QStringLiteral("physical"), OutlineSettings::WidthUnit::Physical},
                    {QStringLiteral("logical"), OutlineSettings::WidthUnit::Logical}},
                   into.widthUnit, error)) {
        return;
    }
    if (!parseEnum(object, QStringLiteral("appearance"),
                   {{QStringLiteral("auto"), WindowTone::Auto},
                    {QStringLiteral("light"), WindowTone::Light},
                    {QStringLiteral("dark"), WindowTone::Dark}},
                   into.appearance, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("width"), 0.0, 16.0, into.width,
                     error)) {
        return;
    }
    if (!parseEnum(object, QStringLiteral("colorMode"),
                   {{QStringLiteral("theme"), ColorMode::Theme},
                    {QStringLiteral("themePair"), ColorMode::ThemePair},
                    {QStringLiteral("fixed"), ColorMode::Fixed}},
                   into.mode, error)) {
        return;
    }
    if (!parseColor(object, QStringLiteral("color"), into.fixedColor, error)) {
        return;
    }
    if (!parseColor(object, QStringLiteral("light"), into.light, error)) {
        return;
    }
    if (!parseColor(object, QStringLiteral("dark"), into.dark, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("activeOpacity"), 0.0, 1.0,
                     into.activeOpacity, error)) {
        return;
    }
    parseDouble(object, QStringLiteral("inactiveOpacity"), 0.0, 1.0,
                into.inactiveOpacity, error);
}

void AppearanceConfig::applyShadow(const QJsonObject &object,
                                   ShadowSettings &into, QString *error)
{
    if (!parseBool(object, QStringLiteral("enabled"), into.enabled, error)) {
        return;
    }
    if (!parseBool(object, QStringLiteral("dynamic"), into.dynamic, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("strength"), 0.0, 1.0,
                     into.strength, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("minimumStrength"), 0.0, 1.0,
                     into.minimumStrength, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("depthDecay"), 0.0, 1.0,
                     into.depthDecay, error)) {
        return;
    }
    if (!parseInt(object, QStringLiteral("transitionMs"), 0, 2000,
                  into.transitionMs, error)) {
        return;
    }
    if (!parseDouble(object, QStringLiteral("contactBlur"), 0.1, 16.0,
                     into.contactBlur, error)
        || !parseDouble(object, QStringLiteral("activeBlur"), 0.1, 64.0,
                        into.activeBlur, error)
        || !parseDouble(object, QStringLiteral("inactiveBlur"), 0.1, 64.0,
                        into.inactiveBlur, error)
        || !parseDouble(object, QStringLiteral("contactOpacity"), 0.0, 1.0,
                        into.contactOpacity, error)) {
        return;
    }
    parseDouble(object, QStringLiteral("ambientOpacity"), 0.0, 1.0,
                into.ambientOpacity, error);
}

void AppearanceConfig::applyStates(const QJsonObject &object,
                                   StateSettings &into, QString *error)
{
    using Policy = StateSettings::Policy;
    if (!parseEnum(object, QStringLiteral("fullscreen"),
                   {{QStringLiteral("off"), Policy::Off},
                    {QStringLiteral("square"), Policy::Square},
                    {QStringLiteral("inherit"), Policy::Inherit}},
                   into.fullscreen, error)) {
        return;
    }
    if (!parseEnum(object, QStringLiteral("maximized"),
                   {{QStringLiteral("off"), Policy::Off},
                    {QStringLiteral("square"), Policy::Square},
                    {QStringLiteral("inherit"), Policy::Inherit}},
                   into.maximized, error)) {
        return;
    }
    // "flattenTouchingEdges" is accepted as a synonym of the not-yet-decided
    // tiled behaviour so the documented file parses; it behaves as inherit
    // until real adjacency detection exists.
    parseEnum(object, QStringLiteral("tiled"),
              {{QStringLiteral("off"), Policy::Off},
               {QStringLiteral("square"), Policy::Square},
               {QStringLiteral("inherit"), Policy::Inherit},
               {QStringLiteral("flattenTouchingEdges"), Policy::Inherit}},
              into.tiled, error);
}

// ---- the file ----------------------------------------------------------------

AppearanceConfig::AppearanceConfig(QObject *parent)
    : QObject(parent)
{
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(20);
    connect(&m_reloadTimer, &QTimer::timeout, this, &AppearanceConfig::load);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        // A replaced file drops its own watch; ensureWatched() puts it back
        // and load() reads whatever replaced it.
        m_reloadTimer.start();
    });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        m_reloadTimer.start();
    });
    load();
}

void AppearanceConfig::ensureWatched()
{
    const QString path = configPath();
    const QString directory = QFileInfo(path).absolutePath();

    // Both the file and the directory are watched: writers replace the file
    // rather than writing through it, which drops the watch on the file
    // itself. This mirrors how buttonconfig watches kwinrc.
    if (QFileInfo::exists(path) && !m_watcher.files().contains(path)) {
        m_watcher.addPath(path);
    }
    if (!m_watcher.directories().contains(directory)) {
        m_watcher.addPath(directory);
    }

    // Re-establish the theme-file watch after replacement too. Native window
    // paletteChanged updates the appearance tone independently; unchanged
    // geometry configuration must not invalidate all content textures.
    const QString globals = QStandardPaths::writableLocation(
                                QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kdeglobals");
    if (QFileInfo::exists(globals) && !m_watcher.files().contains(globals)) {
        m_watcher.addPath(globals);
    }
}

void AppearanceConfig::load()
{
    m_reloadTimer.stop();
    const QString path = configPath();

    // Watch before anything else: even a file that fails to parse is a file
    // whose replacement should be picked up.
    ensureWatched();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (QFileInfo::exists(path)) {
            m_lastError = QStringLiteral("read: %1").arg(file.errorString());
            return;
        }
        if (m_usesBuiltinDefaults) {
            m_lastError.clear();
            return;
        }
        // No file: the built-in defaults stand. Not an error -- most
        // sessions will run on the defaults until the settings page exists.
        m_defaults = EffectiveAppearance();
        m_apps.clear();
        m_resolved.clear();
        m_enabled = true;
        m_revision = 0;
        m_schemaVersion = 2;
        m_usesBuiltinDefaults = true;
        m_lastAcceptedContents.clear();
        m_lastError.clear();
        emit changed();
        return;
    }

    const QByteArray contents = file.readAll();
    if (!m_usesBuiltinDefaults && contents == m_lastAcceptedContents) {
        m_lastError.clear();
        return;
    }
    QJsonParseError parseError;
    const QJsonDocument document =
        QJsonDocument::fromJson(contents, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        m_lastError = QStringLiteral("parse: %1")
                          .arg(parseError.errorString());
        return;
    }

    // The document is validated into a scratch copy first; only a complete,
    // valid read replaces the live configuration, so a bad write can never
    // take down the appearance that is on screen.
    const QJsonObject root = document.object();

    const int version = root.value(QStringLiteral("version")).toInt(-1);
    if (version != 1 && version != 2) {
        m_lastError = QStringLiteral("version");
        return;
    }

    EffectiveAppearance defaults;
    QString error;
    const QJsonObject defaultsObject =
        root.value(QStringLiteral("defaults")).toObject();
    applyCorners(defaultsObject.value(QStringLiteral("corners")).toObject(),
                 defaults.corners, &error);
    if (error.isEmpty()) {
        applyFrame(defaultsObject.value(QStringLiteral("frame")).toObject(),
                   defaults.frame, &error);
    }
    if (error.isEmpty()) {
        applyContent(defaultsObject.value(QStringLiteral("content")).toObject(),
                     defaults.content, &error);
    }
    if (error.isEmpty()) {
        applyFill(defaultsObject.value(QStringLiteral("fill")).toObject(),
                  defaults.fill, &error);
    }
    if (error.isEmpty()) {
        applyOutline(defaultsObject.value(QStringLiteral("outline")).toObject(),
                     defaults.outline, &error, version == 1);
    }
    if (error.isEmpty()) {
        applyShadow(defaultsObject.value(QStringLiteral("shadow")).toObject(),
                    defaults.shadow, &error);
    }
    if (error.isEmpty()) {
        applyStates(defaultsObject.value(QStringLiteral("states")).toObject(),
                    defaults.states, &error);
    }
    if (!error.isEmpty()) {
        m_lastError = QStringLiteral("defaults.%1").arg(error);
        return;
    }

    // The application overrides: the key is the application identifier as it
    // appears in the window class, the value is a sparse object with the same
    // sections as `defaults`.
    QHash<QString, QJsonObject> apps;
    const QJsonObject appsObject = root.value(QStringLiteral("apps")).toObject();
    for (auto it = appsObject.begin(); it != appsObject.end(); ++it) {
        if (!it.value().isObject()) {
            m_lastError = QStringLiteral("apps.%1").arg(it.key());
            return;
        }
        apps.insert(it.key(), it.value().toObject());
    }

    bool enabled = m_enabled;
    if (!parseBool(root, QStringLiteral("enabled"), enabled, &error)) {
        m_lastError = QStringLiteral("enabled");
        return;
    }
    int revision = m_revision;
    if (!parseInt(root, QStringLiteral("revision"), 0,
                  std::numeric_limits<int>::max(), revision, &error)) {
        m_lastError = QStringLiteral("revision");
        return;
    }

    // Everything is valid -- swap it all in at once.
    m_defaults = defaults;
    m_apps = apps;
    m_enabled = enabled;
    m_revision = revision;
    m_schemaVersion = version;
    m_usesBuiltinDefaults = false;
    m_lastAcceptedContents = contents;
    m_lastError.clear();
    m_resolved.clear();
    emit changed();
}

EffectiveAppearance AppearanceConfig::effectiveFor(const QString &appKey,
                                                   const QStringList &aliases) const
{
    QString key = appKey;
    if (!m_apps.contains(key)) {
        for (const QString &alias : aliases) {
            QString candidate = QFileInfo(alias).fileName();
            if (candidate.endsWith(QStringLiteral(".desktop"))) {
                candidate.chop(8);
            }
            if (m_apps.contains(candidate)) {
                key = candidate;
                break;
            }
        }
    }
    if (const auto it = m_resolved.constFind(key);
        it != m_resolved.constEnd()) {
        return it.value();
    }

    // No rule means exactly the defaults. Do not retain one identical copy
    // per historical WM_CLASS: applications may create arbitrarily many
    // classes during a long compositor session. Resolved entries are now
    // bounded by the application rules in the current configuration.
    if (!m_apps.contains(key)) {
        return m_defaults;
    }

    EffectiveAppearance merged = m_defaults;
    if (!key.isEmpty()) {
        if (const auto appOverride = m_apps.constFind(key);
            appOverride != m_apps.constEnd()) {
            QString error;
            const QJsonObject &object = appOverride.value();
            applyCorners(object.value(QStringLiteral("corners")).toObject(),
                         merged.corners, &error);
            if (error.isEmpty()) {
                applyFrame(object.value(QStringLiteral("frame")).toObject(),
                           merged.frame, &error);
            }
            if (error.isEmpty()) {
                applyContent(object.value(QStringLiteral("content")).toObject(),
                             merged.content, &error);
            }
            if (error.isEmpty()) {
                applyFill(object.value(QStringLiteral("fill")).toObject(),
                          merged.fill, &error);
            }
            if (error.isEmpty()) {
                applyOutline(object.value(QStringLiteral("outline")).toObject(),
                             merged.outline, &error, m_schemaVersion == 1);
            }
            if (error.isEmpty()) {
                applyShadow(object.value(QStringLiteral("shadow")).toObject(),
                            merged.shadow, &error);
            }
            if (error.isEmpty()) {
                applyStates(object.value(QStringLiteral("states")).toObject(),
                            merged.states, &error);
            }
            // An override with a bad field falls back to the defaults for
            // that application rather than poisoning the whole session; the
            // document was validated on load, so this is only reachable for
            // keys whose objects were mutated behind the reader's back, and
            // the safe answer is the defaults.
            if (!error.isEmpty()) {
                merged = m_defaults;
            }
        }
    }

    m_resolved.insert(key, merged);
    return merged;
}

bool AppearanceConfig::sessionIsDark()
{
    // kdeglobals is where the session's own colour scheme lives: the
    // window background colour decides light versus dark by luminance. This
    // is the project's theme source, not a heuristic about theme names.
    KConfig globals(QStringLiteral("kdeglobals"));
    const KConfigGroup colors(&globals, QStringLiteral("Colors:Window"));
    const QStringList rgb = colors
                                .readEntry("BackgroundNormal", QStringList())
                                .join(QLatin1Char(','))
                                .split(QLatin1Char(','));
    if (rgb.size() < 3) {
        return true;
    }
    bool okR = false, okG = false, okB = false;
    const int r = rgb[0].toInt(&okR);
    const int g = rgb[1].toInt(&okG);
    const int b = rgb[2].toInt(&okB);
    if (!okR || !okG || !okB) {
        return true;
    }
    // Rec. 601 luma; the same weighting everyone else uses for this test.
    const qreal luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return luma < 0.5;
}

} // namespace KOS::WindowAppearance
