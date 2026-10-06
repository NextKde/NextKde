#include "buttonconfig.h"

#include <KConfig>
#include <KConfigGroup>

#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

#include <algorithm>

namespace KOS
{

namespace
{

// Reads one JSON object over the config it is given and reports which keys it
// named. Shared by `default`, `apps` and the hand-written `rules`, so the three
// accept exactly the same keys with exactly the same meanings.
AppFieldMask applyFields(AppConfig &config, const QJsonObject &object)
{
    AppFieldMask fields = AppFieldNone;

    if (object.contains("showButtons")) {
        config.showButtons = object["showButtons"].toBool();
        fields |= AppFieldShowButtons;
    }
    if (object.contains("position")) {
        // "right" is the layout every desktop these applications follow uses, so
        // anything else -- "auto" included, from a configuration written when
        // the side was detected rather than configured -- falls back to it.
        config.geometry.position =
            object["position"].toString() == QLatin1String("left")
            ? ButtonPosition::Left
            : ButtonPosition::Right;
        fields |= AppFieldPosition;
    }
    if (object.contains("offset")) {
        const QJsonObject offset = object["offset"].toObject();
        if (offset.contains("x")) {
            config.geometry.offset.x = offset["x"].toDouble();
            fields |= AppFieldOffsetX;
        }
        if (offset.contains("y")) {
            config.geometry.offset.y = offset["y"].toDouble();
            fields |= AppFieldOffsetY;
        }
    }
    if (object.contains("buttonSize")) {
        config.geometry.buttonSize = object["buttonSize"].toDouble();
        fields |= AppFieldButtonSize;
    }
    if (object.contains("buttonSpacing")) {
        config.geometry.buttonSpacing = object["buttonSpacing"].toDouble();
        fields |= AppFieldButtonSpacing;
    }
    if (object.contains("panelPadding")) {
        config.geometry.panelPadding = object["panelPadding"].toDouble();
        fields |= AppFieldPanelPadding;
    }
    if (object.contains("panelPaddingX")) {
        config.geometry.panelPaddingX = object["panelPaddingX"].toDouble();
        fields |= AppFieldPanelPaddingX;
    }
    if (object.contains("interceptMargin")) {
        config.interceptMargin = object["interceptMargin"].toDouble();
        fields |= AppFieldInterceptMargin;
    }
    if (object.contains("background")) {
        const QString background = object["background"].toString();
        if (background == QLatin1String("dark")) {
            config.background = PanelBackground::Dark;
        } else if (background == QLatin1String("light")) {
            config.background = PanelBackground::Light;
        } else {
            config.background = PanelBackground::Auto;
        }
        fields |= AppFieldBackground;
    }
    if (object.contains("drawOnDecoratedWindows")) {
        // The key is named for what it does to the panel and reads as a
        // sentence; the three values are what it can say.
        const QString value = object["drawOnDecoratedWindows"].toString();
        if (value == QLatin1String("always")) {
            config.decoratedWindows = DecoratedWindows::Always;
        } else if (value == QLatin1String("never")) {
            config.decoratedWindows = DecoratedWindows::Never;
        } else {
            config.decoratedWindows = DecoratedWindows::Auto;
        }
        fields |= AppFieldDecoratedWindows;
    }

    // Values from a hand-edited text file, through the same clamp the adjust
    // gesture goes through.
    config.geometry = clamped(config.geometry);
    return fields;
}

} // namespace

ButtonConfig::ButtonConfig()
{
    m_configPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/kos/window-buttons.json");
    m_kwinrcPath =
        QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kwinrc");
    load();
    armKwinrcWatch();
}

ButtonConfig::~ButtonConfig() = default;

void ButtonConfig::load()
{
    // Reloaded here rather than only in the constructor: the effect is
    // reconfigured on request, and a hand edit of either file should be picked
    // up by that too.
    m_store.load();

    m_default = AppConfig();
    m_apps.clear();
    m_rules.clear();

    // Read before the JSON, because resolving `decoratedWindows: "auto"` needs
    // it. Whether the file exists or not, the current value is what KWin has.
    m_kosDecorationSelected = readKosDecorationSelected();

    QFile file(m_configPath);
    if (!file.open(QIODevice::ReadOnly)) {
        qInfo() << "KOS: No config file found, using defaults";
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    if (!document.isObject()) {
        qWarning() << "KOS:" << m_configPath << "is not a JSON object, using"
                   << "defaults";
        return;
    }

    const QJsonObject root = document.object();

    if (root.contains("default")) {
        applyFields(m_default, root["default"].toObject());
    }

    if (root.contains("apps")) {
        const QJsonObject apps = root["apps"].toObject();
        for (auto it = apps.begin(); it != apps.end(); ++it) {
            AppEntry entry;
            entry.fields = applyFields(entry.config, it.value().toObject());
            m_apps[it.key()] = entry;
        }
    }

    if (root.contains("rules")) {
        const QJsonArray rules = root["rules"].toArray();
        for (const QJsonValue &value : rules) {
            const QJsonObject object = value.toObject();
            bool ok = false;
            const WindowMatcher matcher =
                WindowMatcher::fromJson(object["match"].toObject(), &ok);
            if (!ok || matcher.isEmpty()) {
                if (ok) {
                    qWarning() << "KOS: ignoring a rule in" << m_configPath
                               << "that matches nothing: a rule has to name at"
                               << "least one of class, title, titleRegex, role"
                               << "or type";
                }
                continue;
            }
            AppRule rule;
            rule.matcher = matcher;
            rule.fields = applyFields(rule.config, object);
            m_rules.append(rule);
        }
        // The same rule as the machine file's: the more keys a rule names about
        // a window, the more it knows about it, and the order within one
        // specificity is the order the file was written in.
        std::stable_sort(m_rules.begin(), m_rules.end(),
                         [](const AppRule &a, const AppRule &b) {
                             return moreSpecific(a.matcher, b.matcher);
                         });
    }

    qInfo() << "KOS: Loaded window button config from" << m_configPath << "-"
            << m_apps.size() << "app entries," << m_rules.size()
            << "hand-written rules, and" << m_store.count()
            << "machine-written rules from" << m_store.path();
}

AppConfig ButtonConfig::getAppConfig(const WindowQuery &query) const
{
    // 1. The default, carrying every key.
    AppConfig config = m_default;

    // 2. The app entry, key by key.
    if (const AppEntry *app = findApp(query.windowClass)) {
        mergeInto(config, app->config, app->fields);
    }

    // 3. The first matching hand-written rule, key by key.
    for (const AppRule &rule : m_rules) {
        if (rule.matcher.matches(query)) {
            mergeInto(config, rule.config, rule.fields);
            break;
        }
    }

    // 4. The first matching machine rule. The geometry is replaced whole rather
    // than merged: a machine rule is only ever written by a drag, and a drag
    // positions the whole panel. Merging would let a hand-written `buttonSize`
    // survive into a panel whose size was dragged, which is the one thing the
    // gesture is for. Nothing else is touched, so `showButtons`, `background`
    // and `interceptMargin` stay the user's.
    PanelGeometry geometry;
    if (m_store.found(query, &geometry)) {
        config.geometry = geometry;
    }

    config.kosDecorationSelected = m_kosDecorationSelected;
    config.drawOnDecoratedWindows =
        config.decoratedWindows == DecoratedWindows::Always ? true
        : config.decoratedWindows == DecoratedWindows::Never ? false
                                                            : m_kosDecorationSelected;
    return config;
}

bool ButtonConfig::storeGeometry(const WindowMatcher &matcher,
                                 const PanelGeometry &geometry)
{
    return m_store.store(matcher, geometry);
}

void ButtonConfig::setOnDecorationChanged(std::function<void()> callback)
{
    m_onDecorationChanged = std::move(callback);
}

const ButtonConfig::AppEntry *ButtonConfig::findApp(const QString &windowClass) const
{
    const auto exact = m_apps.constFind(windowClass);
    if (exact != m_apps.constEnd()) {
        return &exact.value();
    }
    const QStringList tokens =
        windowClass.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &token : tokens) {
        const auto token_it = m_apps.constFind(token);
        if (token_it != m_apps.constEnd()) {
            return &token_it.value();
        }
    }
    return nullptr;
}

void ButtonConfig::mergeInto(AppConfig &base, const AppConfig &overlay,
                             AppFieldMask fields)
{
    if (fields & AppFieldShowButtons) {
        base.showButtons = overlay.showButtons;
    }
    if (fields & AppFieldPosition) {
        base.geometry.position = overlay.geometry.position;
    }
    if (fields & AppFieldOffsetX) {
        base.geometry.offset.x = overlay.geometry.offset.x;
    }
    if (fields & AppFieldOffsetY) {
        base.geometry.offset.y = overlay.geometry.offset.y;
    }
    if (fields & AppFieldButtonSize) {
        base.geometry.buttonSize = overlay.geometry.buttonSize;
    }
    if (fields & AppFieldButtonSpacing) {
        base.geometry.buttonSpacing = overlay.geometry.buttonSpacing;
    }
    if (fields & AppFieldPanelPadding) {
        base.geometry.panelPadding = overlay.geometry.panelPadding;
    }
    if (fields & AppFieldPanelPaddingX) {
        base.geometry.panelPaddingX = overlay.geometry.panelPaddingX;
    }
    if (fields & AppFieldInterceptMargin) {
        base.interceptMargin = overlay.interceptMargin;
    }
    if (fields & AppFieldBackground) {
        base.background = overlay.background;
    }
    if (fields & AppFieldDecoratedWindows) {
        base.decoratedWindows = overlay.decoratedWindows;
    }
}

bool ButtonConfig::readKosDecorationSelected() const
{
    const KConfig config(QStringLiteral("kwinrc"));
    const KConfigGroup group(&config, QStringLiteral("org.kde.kdecoration2"));
    return group.readEntry("library", QString()) == QLatin1String("kos_decoration");
}

void ButtonConfig::armKwinrcWatch()
{
    // The file, and the directory it lives in: an editor (and kwriteconfig)
    // replaces the file rather than writing through it, which drops the watch on
    // the file itself. Re-arming on the directory catches that. A kwinrc that
    // does not exist yet is caught the same way.
    if (!m_watcher.files().contains(m_kwinrcPath)) {
        m_watcher.addPath(m_kwinrcPath);
    }
    const QString directory = QFileInfo(m_kwinrcPath).absolutePath();
    if (!m_watcher.directories().contains(directory)) {
        m_watcher.addPath(directory);
    }

    if (!m_watchingKwinrc) {
        m_watchingKwinrc = true;
        // KWin does not tell effects that the decoration changed: it only
        // re-reads `[Plugins] *Enabled` and the animation speed, and
        // `reconfigureEffect` has to be asked for by hand. Writing the choice in
        // System Settings changes kwinrc without any of that, so the file is
        // watched to notice.
        QObject::connect(&m_watcher, &QFileSystemWatcher::fileChanged,
                         &m_context, [this](const QString &) {
                             recheckDecoration();
                         });
        QObject::connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
                         &m_context, [this](const QString &) {
                             recheckDecoration();
                         });
    }
}

void ButtonConfig::recheckDecoration()
{
    // Re-armed first: the watch is on the file's inode, and whatever changed it
    // has most likely just replaced it.
    armKwinrcWatch();

    const bool selected = readKosDecorationSelected();
    if (selected == m_kosDecorationSelected) {
        return;
    }
    m_kosDecorationSelected = selected;
    qInfo() << "KOS: the window decoration changed, the KOS decoration is"
            << (selected ? "now selected" : "no longer selected");
    // Nothing else has to be reloaded: the flag is resolved per window for
    // `decoratedWindows: "auto"`, and read directly for the panel's own gate.
    // Only what is already on screen has to be repainted.
    if (m_onDecorationChanged) {
        m_onDecorationChanged();
    }
}

} // namespace KOS
