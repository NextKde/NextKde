#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QObject>
#include <QString>
#include <QVector>

#include <functional>

#include "panelgeometry.h"
#include "windowrules.h"

namespace KOS
{

// Controls the colour of the rounded panel drawn behind the traffic lights.
enum class PanelBackground {
    Auto,  // follow the window's own title bar pixels
    Dark,
    Light,
};

// Whether the panel is drawn over windows KWin decorates itself.
//
// `Auto`, the default, means "only under our own decoration". With Breeze
// selected KWin paints its own window controls, and stamping the panel over them
// would leave Breeze's title bar carrying both.
enum class DecoratedWindows {
    Auto,
    Always,
    Never,
};

// Which of AppConfig's keys a JSON object named. A config is built by merging
// one JSON object at a time over a base, so the keys an object set have to be
// recorded next to the values; a key that was not named must leave the base's
// value alone rather than reset it to a default.
using AppFieldMask = quint32;

enum AppField : AppFieldMask {
    AppFieldNone = 0,
    AppFieldShowButtons = 1u << 0,
    AppFieldPosition = 1u << 1,
    AppFieldOffsetX = 1u << 2,
    AppFieldOffsetY = 1u << 3,
    AppFieldButtonSize = 1u << 4,
    AppFieldButtonSpacing = 1u << 5,
    AppFieldPanelPadding = 1u << 6,
    AppFieldPanelPaddingX = 1u << 7,
    AppFieldInterceptMargin = 1u << 8,
    AppFieldBackground = 1u << 9,
    AppFieldDecoratedWindows = 1u << 10,
};

struct AppConfig {
    bool showButtons = true;
    // Where the panel is and how big it is: the part of this struct an adjust
    // session changes and a machine-written rule stores (WindowRuleStore).
    PanelGeometry geometry;
    // Extra logical pixels around the panel in which pointer events are taken
    // by the panel as well.
    //
    // An application draws its own window controls a little larger than the
    // panel that covers them, and highlights a padded area around them; a
    // pointer that reaches that area makes the control light up around the
    // panel's edge. This is the margin that has to be taken with the panel to
    // stop that, and it is per application because the controls are.
    qreal interceptMargin = 5.0;
    PanelBackground background = PanelBackground::Auto;
    // What was configured. Merged key by key like every other field.
    DecoratedWindows decoratedWindows = DecoratedWindows::Auto;
    // The above resolved against the decoration KWin is configured to use. Set
    // by getAppConfig() and meaningless before it -- the stored entries carry
    // `decoratedWindows`, and only the value handed out by getAppConfig() has
    // this filled in. The renderer reads this one and nothing else, so that
    // whether the panel is drawn over a decorated window is decided in one
    // place instead of at every use.
    bool drawOnDecoratedWindows = false;
    // Whether the decoration KWin is configured to use is ours. The panel is
    // that decoration's window controls -- the decoration itself draws buttons
    // for nobody -- so it is drawn only while it is selected. Selecting another
    // one gives every window its own controls back, server-side and
    // client-side alike, and the panel has no business covering either. Set by
    // getAppConfig() as well.
    bool kosDecorationSelected = false;
};

// The window button configuration: the user's hand-written file, the
// machine-written rules file, and which decoration is in use.
class ButtonConfig
{
public:
    ButtonConfig();
    ~ButtonConfig();

    void load();

    // The configuration for a window, resolved in four steps (README):
    // `default`, then `apps[class]`, then the first matching hand-written
    // `rules` entry, then the first matching machine-written rule -- which
    // replaces the geometry whole and touches nothing else.
    AppConfig getAppConfig(const WindowQuery &) const;

    // Writes an adjusted geometry as a machine rule. The user's own file is
    // never opened for writing.
    bool storeGeometry(const WindowMatcher &, const PanelGeometry &);

    QString rulesPath() const { return m_store.path(); }
    // Whether the decoration KWin is configured to use is ours, which is what
    // `decoratedWindows: "auto"` resolves against.
    bool kosDecorationSelected() const { return m_kosDecorationSelected; }

    // Called when the decoration in use changed, which KWin does not report to
    // effects. The effect repaints from this.
    void setOnDecorationChanged(std::function<void()> callback);

private:
    struct AppEntry {
        AppConfig config;
        AppFieldMask fields = AppFieldNone;
    };
    struct AppRule {
        WindowMatcher matcher;
        AppConfig config;
        AppFieldMask fields = AppFieldNone;
    };

    static void mergeInto(AppConfig &base, const AppConfig &overlay,
                          AppFieldMask fields);
    const AppEntry *findApp(const QString &windowClass) const;
    bool readKosDecorationSelected() const;
    void armKwinrcWatch();
    void recheckDecoration();

    AppConfig m_default;
    QHash<QString, AppEntry> m_apps;
    QVector<AppRule> m_rules;
    WindowRuleStore m_store;
    QString m_configPath;
    QString m_kwinrcPath;
    bool m_kosDecorationSelected = false;
    bool m_watchingKwinrc = false;

    // The watchers below are connected with this as the context object, so the
    // connections die with this class without it having to be a QObject.
    // Declared first so that it outlives them.
    QObject m_context;
    QFileSystemWatcher m_watcher;
    std::function<void()> m_onDecorationChanged;
};

} // namespace KOS
