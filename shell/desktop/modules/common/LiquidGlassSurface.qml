import QtQuick

// A QML-only liquid finish for surfaces that already use compositor blur.
// Keeping the material in Qt Quick preserves anti-aliased rounded corners.
Rectangle {
    id: root

    property color baseColor: Qt.rgba(0, 0, 0, 0.1)
    // Semantic material roles mirror the system vocabulary. They describe
    // readability intent, never a fixed light/dark paint colour.
    property string material: "regular" // "clear", "regular", "thick"
    // Semantic readability role. "protected" is for text-dense transient
    // surfaces (menus and notifications): it trades a little transmission for
    // stable white ink without creating another user-facing tuning knob.
    property string readabilityProfile: "ambient" // "ambient", "protected"
    readonly property bool protectedReadability: readabilityProfile === "protected"
    // Internal semantic weighting for protected surfaces. Callers choose a
    // role-specific value; this is intentionally not a user configuration.
    property real readabilityStrength: 1.0
    // Optional QML interior relief for compact, control-like glass cards.
    // It is deliberately separate from KWin's optical rim: this is a soft
    // top-to-bottom body contour, not a second border or highlight renderer.
    property real reliefStrength: 0.0
    property real surfaceOpacity: 1.0
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property color ambientTertiary: ambientSecondary
    property real ambientSecondaryPosition: 0.52
    property real ambientStrength: 0.0
    // Opt in for text-dense popups. Unlike the base material, this is a
    // continuous dark scrim that becomes stronger only near white/black
    // wallpaper, keeping ordinary imagery visibly behind the glass.
    property bool adaptiveDarkScrim: material !== "clear"
    // One material contract: surfaces backed by KWin use KWin as the only
    // optical renderer. QML then supplies geometry, pigment and content only.
    // The local shader is reserved for real fallbacks that cannot publish a
    // compositor backdrop region (for example desktop widgets).
    property bool compositorManaged: true
    // Nested semantic cards share their parent's compositor backdrop but may
    // still need a coloured pigment layer. This stays independent so pigment
    // never enables a second QML refraction/highlight renderer.
    property bool ambientPigmentEnabled: !compositorManaged
    // Wallpaper changes should feel like pigment slowly moving through the
    // glass rather than a theme colour snapping to its next value.
    property int ambientTransitionDuration: 2600
    property bool _ambientInitialized: false
    property real _ambientProgress: 1.0
    property color _ambientFromPrimary: ambientPrimary
    property color _ambientFromSecondary: ambientSecondary
    property color _ambientFromTertiary: ambientTertiary
    property color _displayAmbientPrimary: ambientPrimary
    property color _displayAmbientSecondary: ambientSecondary
    property color _displayAmbientTertiary: ambientTertiary
    // 0 = dock/base surface, 1 = popup, 2 = contextual foreground menu.
    property real materialDepth: 0.0
    property real blurStrength: AppearanceConfigService.effectiveDockBlur
    readonly property real normalizedBlurStrength: Math.max(
        0.0, Math.min(1.0, blurStrength))
    property real liquidStrength: AppearanceConfigService.effectiveDockLiquid
    readonly property real normalizedLiquidStrength: Math.max(
        0.0, Math.min(1.0, liquidStrength))
    readonly property real materialOpacityScale: material === "clear" ? 0.58
        : (material === "thick" ? 1.28 : 1.0)
    readonly property real materialReflectionScale: material === "clear" ? 0.62
        : (material === "thick" ? 0.86 : 1.0)
    readonly property real materialPigmentScale: material === "clear" ? 0.52
        : (material === "thick" ? 1.32 : 1.0)
    readonly property real ambientLuminance: _displayAmbientPrimary.r * 0.2126
        + _displayAmbientPrimary.g * 0.7152 + _displayAmbientPrimary.b * 0.0722
    readonly property real ambientExtremeDistance: Math.min(
        ambientLuminance, 1.0 - ambientLuminance)
    readonly property real ambientExtremeProtection: {
        const t = Math.max(0.0, Math.min(1.0,
            (ambientExtremeDistance - 0.08) / 0.30))
        return 1.0 - t * t * (3.0 - 2.0 * t)
    }
    readonly property real adaptiveScrimOpacity: {
        // Compositor-backed surfaces must react to the actual framebuffer in
        // KWin. Keep this approximation only for genuine QML fallbacks that
        // cannot publish a backdrop region.
        if (!adaptiveDarkScrim || compositorManaged)
            return 0.0
        const lightMix = Math.max(0.0, Math.min(1.0,
            (ambientLuminance - 0.30) / 0.40))
        const base = 0.04 + 0.035 * lightMix
        const protection = (0.035 + 0.07 * lightMix)
            * ambientExtremeProtection
        return Math.min(0.18, (base + protection)
            * (material === "thick" ? 1.18 : 1.0))
    }
    // Shell chrome uses white ink in both themes. KWin protects it by
    // darkening only bright framebuffer content below the glass.
    readonly property bool _useDarkForeground: false
    readonly property color foregroundColor: Qt.rgba(1, 1, 1, 1.0)
    readonly property color secondaryForegroundColor: Qt.rgba(1, 1, 1, 0.82)
    readonly property color tertiaryForegroundColor: Qt.rgba(1, 1, 1, 0.66)
    readonly property color disabledForegroundColor: Qt.rgba(1, 1, 1, 0.50)
    readonly property color separatorColor: Qt.rgba(1, 1, 1, 0.20)
    readonly property real baseLuminance: baseColor.r * 0.2126
        + baseColor.g * 0.7152 + baseColor.b * 0.0722
    // Bright surfaces need less white overlay to remain translucent; darker
    // ones retain the stronger reflection that makes the material readable.
    readonly property real highlightFactor: baseLuminance > 0.6 ? 0.70 : 1.0
    readonly property real materialHighlightFactor: highlightFactor
        * (1.0 + Math.max(0.0, materialDepth) * 0.15)
        * normalizedLiquidStrength
    // Tint the glass body itself as well as its reflection overlay. This is
    // what makes wallpaper adaptation readable on dark desktops instead of
    // disappearing beneath the base surface.
    // A restrained tint keeps the Dock primarily neutral glass while still
    // letting its material pick up a little colour from the wallpaper.
    readonly property real ambientBaseMix: !ambientPigmentEnabled ? 0.0
        : Math.min(0.18, ambientStrength * 0.22)
        * materialPigmentScale
        * normalizedLiquidStrength

    function _mixColor(from, to, progress) {
        return Qt.rgba(
            from.r + (to.r - from.r) * progress,
            from.g + (to.g - from.g) * progress,
            from.b + (to.b - from.b) * progress,
            from.a + (to.a - from.a) * progress
        )
    }

    function _beginAmbientTransition() {
        if (!_ambientInitialized) {
            _displayAmbientPrimary = ambientPrimary
            _displayAmbientSecondary = ambientSecondary
            _displayAmbientTertiary = ambientTertiary
            return
        }
        _ambientFromPrimary = _displayAmbientPrimary
        _ambientFromSecondary = _displayAmbientSecondary
        _ambientFromTertiary = _displayAmbientTertiary
        _ambientProgress = 0.0
        ambientColourFlow.restart()
    }

    onAmbientPrimaryChanged: _beginAmbientTransition()
    onAmbientSecondaryChanged: _beginAmbientTransition()
    onAmbientTertiaryChanged: _beginAmbientTransition()
    on_AmbientProgressChanged: {
        _displayAmbientPrimary = _mixColor(_ambientFromPrimary, ambientPrimary, _ambientProgress)
        _displayAmbientSecondary = _mixColor(_ambientFromSecondary, ambientSecondary, _ambientProgress)
        _displayAmbientTertiary = _mixColor(_ambientFromTertiary, ambientTertiary, _ambientProgress)
    }
    Component.onCompleted: {
        _displayAmbientPrimary = ambientPrimary
        _displayAmbientSecondary = ambientSecondary
        _displayAmbientTertiary = ambientTertiary
        _ambientInitialized = true
    }

    NumberAnimation {
        id: ambientColourFlow
        target: root
        property: "_ambientProgress"
        to: 1.0
        duration: root.ambientTransitionDuration
        easing.type: Easing.InOutSine
    }
    Behavior on ambientStrength {
        NumberAnimation { duration: 420; easing.type: Easing.InOutCubic }
    }

    color: Qt.rgba(
        baseColor.r * (1.0 - ambientBaseMix) + _displayAmbientPrimary.r * ambientBaseMix,
        baseColor.g * (1.0 - ambientBaseMix) + _displayAmbientPrimary.g * ambientBaseMix,
        baseColor.b * (1.0 - ambientBaseMix) + _displayAmbientPrimary.b * ambientBaseMix,
        Math.min(1.0, baseColor.a * root.materialOpacityScale)
            * surfaceOpacity * root.normalizedBlurStrength
    )

    // Reinforce the side of the material opposite its foreground ink. A light
    // lift supports dark labels; a dark scrim supports white labels. This is
    // the static QML counterpart of Liquid Glass's dynamic-range adaptation.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.adaptiveScrimOpacity > 0.001
        color: root._useDarkForeground
            ? Qt.rgba(1, 1, 1, root.adaptiveScrimOpacity * 0.72)
            : Qt.rgba(0.018, 0.028, 0.052, root.adaptiveScrimOpacity)
        Behavior on color {
            ColorAnimation { duration: root.ambientTransitionDuration; easing.type: Easing.InOutSine }
        }
    }

    // KWin continues to own sampling, refraction and edge optics. This calm,
    // neutral veil is intentionally QML-only: it gives high-density popups a
    // consistent luminance floor while avoiding a second highlight or a
    // wallpaper-palette approximation. It is below content and has no border,
    // so it reads as thicker glass rather than an outline.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.protectedReadability
        color: Qt.rgba(0.012, 0.020, 0.042,
                       (0.075 + 0.055 * root.normalizedLiquidStrength)
                       * root.surfaceOpacity
                       * Math.max(0.0, Math.min(1.0, root.readabilityStrength)))
    }

    // Raised-card interior, retained from the original control-center
    // material. The broad vertical transition makes a small card feel like a
    // coherent piece of glass without turning its outline into an embossed
    // white stroke. It is opt-in because large chrome (Dock, search) should
    // stay optically flatter and let KWin's live backdrop dominate.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.compositorManaged && root.reliefStrength > 0.001
        opacity: Math.max(0.0, Math.min(1.0, root.reliefStrength))
            * root.normalizedLiquidStrength * root.surfaceOpacity
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.115) }
            GradientStop { position: 0.16; color: Qt.rgba(0.88, 0.94, 1, 0.055) }
            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.76; color: Qt.rgba(0.015, 0.025, 0.050, 0.018) }
            GradientStop { position: 1.0; color: Qt.rgba(0.005, 0.012, 0.030, 0.080) }
        }
    }

    // A static, shape-aware reflection. The fragment shader derives a bevel
    // normal from the rounded-rectangle SDF, so the glint follows both straight
    // edges and corners instead of reading as a white vertical wash.
    ShaderEffect {
        anchors.fill: parent
        visible: !root.compositorManaged
        blending: true
        property real u_radius: root.radius
        property real u_strength: root.materialHighlightFactor * 0.42
        property real u_reflectionScale: root.materialReflectionScale
        property real u_depth: root.materialDepth
        property real u_bottomShade: 0.0
        property vector2d u_size: Qt.vector2d(width, height)
        vertexShader: Qt.resolvedUrl("../../shaders/glass_highlight.vert.qsb")
        fragmentShader: Qt.resolvedUrl("../../shaders/glass_highlight.frag.qsb")
    }

    // Optional semantic pigment for nested cards. Colour alpha belongs to the
    // caller so weather, thermal, clock and artwork palettes retain their
    // established visual weight while sharing the same material component.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.ambientPigmentEnabled
        opacity: root.normalizedLiquidStrength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Qt.rgba(
                    root._displayAmbientPrimary.r, root._displayAmbientPrimary.g, root._displayAmbientPrimary.b,
                    root._displayAmbientPrimary.a * root.ambientStrength
                        * root.normalizedLiquidStrength
                )
            }
            GradientStop {
                position: root.ambientSecondaryPosition
                color: Qt.rgba(
                    root._displayAmbientSecondary.r, root._displayAmbientSecondary.g, root._displayAmbientSecondary.b,
                    root._displayAmbientSecondary.a * root.ambientStrength
                        * root.normalizedLiquidStrength
                )
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(
                    root._displayAmbientTertiary.r, root._displayAmbientTertiary.g, root._displayAmbientTertiary.b,
                    root._displayAmbientTertiary.a * root.ambientStrength
                        * root.normalizedLiquidStrength
                )
            }
        }
    }

    // A faint lateral tint makes the material feel thicker than a flat
    // vertical gradient, while remaining subtle over both light and dark
    // wallpapers.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.compositorManaged
        opacity: root.normalizedLiquidStrength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0.72, 0.88, 1, 0.045 * root.materialHighlightFactor) }
            GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 0.84, 0.92, 0.035 * root.materialHighlightFactor) }
        }
    }

}
