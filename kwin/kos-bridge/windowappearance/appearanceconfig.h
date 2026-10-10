#pragma once

#include <QColor>
#include <QByteArray>
#include <QFileSystemWatcher>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

#include "contour.h"

namespace KOS::WindowAppearance
{

// ---- the configuration model ----------------------------------------------
//
// One file, `~/.config/kos/window-appearance.json`, describes the unified
// window appearance: the defaults, and sparse per-application overrides on
// top. The semantics follow the plan document: missing fields mean inherit,
// `0`/`false`/`"none"` are values like any other, and the merge order is
// product defaults -> global user settings -> application override. The state
// constraints (fullscreen, maximized) are applied later, per window, on top
// of the merged result.

enum class FrameMode { None, Small, Thick };
enum class ContentMode { Protect, Compact, Preserve };
enum class CornerProfile { Arc, Continuous };
// `Theme` and `ThemePair` select the light/dark colour using the window's
// declared palette (or app tone override); `Fixed` always uses one colour.
enum class ColorMode { Theme, ThemePair, Fixed };
enum class WindowTone { Auto, Light, Dark };

struct CornerSettings
{
    qreal radius = 20.0;
    CornerProfile profile = CornerProfile::Continuous;
    // The continuous amount in [0, 1]; meaningless for the arc profile.
    qreal smoothness = 0.6;
};

struct FrameSettings
{
    FrameMode mode = FrameMode::None;
    qreal smallWidth = 4.0;
    qreal thickWidth = 10.0;

    qreal width() const;
};

struct ContentSettings
{
    ContentMode mode = ContentMode::Compact;
};

struct FillSettings
{
    ColorMode mode = ColorMode::Theme;
    QColor fixedColor = QColor(0x33, 0x36, 0x3b);
    QColor light = QColor(0xf0, 0xf2, 0xf5);
    QColor dark = QColor(0x24, 0x26, 0x2a);

    // The colour for the resolved window tone; no framebuffer sampling.
    QColor colorFor(bool sessionDark) const;
};

struct OutlineSettings
{
    // Existing files keep logical units; the new default is one device pixel.
    enum class WidthUnit { Physical, Logical };
    qreal width = 1.0;
    WidthUnit widthUnit = WidthUnit::Physical;
    WindowTone appearance = WindowTone::Auto;
    ColorMode mode = ColorMode::Theme;
    QColor fixedColor = QColor(0x80, 0x80, 0x80);
    QColor light = QColor(Qt::black);
    QColor dark = QColor(Qt::white);
    qreal activeOpacity = 0.09;
    qreal inactiveOpacity = 0.045;

    QColor colorFor(bool sessionDark) const;
};

struct ShadowSettings
{
    bool enabled = true;
    bool dynamic = true;
    qreal strength = 0.32;
    qreal minimumStrength = 0.08;
    qreal depthDecay = 0.7;
    int transitionMs = 180;

    // Narrow contact layer and a broad ambient layer. Blur is the gaussian
    // sigma in logical pixels; no spread that would create a hard black rim.
    qreal contactBlur = 1.0;
    qreal activeBlur = 14.0;
    qreal inactiveBlur = 8.0;
    qreal contactOpacity = 0.22;
    qreal ambientOpacity = 0.28;

    // The alpha of each stacking tier: active window first, then the layers
    // of background windows fading by `depthDecay` down to `minimumStrength`.
    qreal tierAlpha(int tier) const;
};

struct StateSettings
{
    // `Off` restores the window's own contour/shadow and drops KOS chrome.
    // `Square` keeps the frame
    // and the shadow but squares the corners; `Inherit` applies the normal
    // contour. Tiled flattening needs real adjacency knowledge and is not
    // decided here (see the plan, section 10) -- the value is carried but the
    // effect currently behaves as `Inherit` for tiles.
    enum class Policy { Off, Square, Inherit };
    Policy fullscreen = Policy::Inherit;
    Policy maximized = Policy::Inherit;
    Policy tiled = Policy::Inherit;
};

// The fully merged appearance one window gets. This is the value everything
// downstream sees; nothing below this point re-consults the file.
struct EffectiveAppearance
{
    CornerSettings corners;
    FrameSettings frame;
    ContentSettings content;
    FillSettings fill;
    OutlineSettings outline;
    ShadowSettings shadow;
    StateSettings states;

    // Corner radii for a window of this size, clamped. The state constraints
    // are applied by the caller, which knows the window; this is only the
    // geometry clamp.
    WindowAppearance::CornerRadii cornerRadii(const QSizeF &size) const;
};

// ---- reading the file ------------------------------------------------------

// Reads, validates and watches the window appearance configuration. On any
// validation error the previous valid configuration stays in place and the
// field path is reported through lastError(); nothing half-valid is ever
// handed out. The file is replaced atomically by writers, which drops the
// watch, so both the file and its directory are watched and re-added.
class AppearanceConfig : public QObject
{
    Q_OBJECT

public:
    explicit AppearanceConfig(QObject *parent = nullptr);

    // (Re)read the file. Called by the watcher and by reconfigure().
    void load();

    bool enabled() const { return m_enabled; }
    int revision() const { return m_revision; }
    // The field path that made the last attempted read invalid, if it was.
    QString lastError() const { return m_lastError; }

    // The merged appearance for one application key. Results are cached per
    // key until the file (or the session theme) changes; resolution is a
    // per-frame call and must not re-walk JSON every time.
    EffectiveAppearance effectiveFor(const QString &appKey,
                                    const QStringList &aliases = {}) const;

    // Whether the session theme is the dark one, decided from kdeglobals --
    // the session's own theme store -- and not guessed from anything else.
    static bool sessionIsDark();

Q_SIGNALS:
    void changed();

private:
    void ensureWatched();
    void applyDocument(const QJsonObject &root);
    // Field patchers. Each validates its value and reports the field path on
    // failure through `error`; unknown fields are ignored.
    static void applyCorners(const QJsonObject &object, CornerSettings &into,
                             QString *error);
    static void applyFrame(const QJsonObject &object, FrameSettings &into,
                           QString *error);
    static void applyContent(const QJsonObject &object, ContentSettings &into,
                             QString *error);
    static void applyFill(const QJsonObject &object, FillSettings &into,
                          QString *error);
    static void applyOutline(const QJsonObject &object, OutlineSettings &into,
                             QString *error, bool legacyWidth);
    static void applyShadow(const QJsonObject &object, ShadowSettings &into,
                            QString *error);
    static void applyStates(const QJsonObject &object, StateSettings &into,
                            QString *error);

    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
    QByteArray m_lastAcceptedContents;
    bool m_usesBuiltinDefaults = true;

    bool m_enabled = true;
    int m_revision = 0;
    int m_schemaVersion = 2;
    QString m_lastError;

    EffectiveAppearance m_defaults;
    QHash<QString, QJsonObject> m_apps;
    // appKey -> merged result, dropped whenever anything it depends on does.
    mutable QHash<QString, EffectiveAppearance> m_resolved;
};

} // namespace KOS::WindowAppearance
