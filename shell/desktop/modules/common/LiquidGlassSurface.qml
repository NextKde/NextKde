import QtQuick

// A QML-only liquid finish for surfaces that already use compositor blur.
// Keeping the material in Qt Quick preserves anti-aliased rounded corners.
Rectangle {
    id: root

    property color baseColor: Qt.rgba(0, 0, 0, 0.1)
    // Semantic material roles mirror the system vocabulary. They describe
    // readability intent, never a fixed light/dark paint colour.
    property string material: "regular" // "clear", "regular", "thick"
    property real surfaceOpacity: 1.0
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0.0
    // Opt in for text-dense popups. Unlike the base material, this is a
    // continuous dark scrim that becomes stronger only near white/black
    // wallpaper, keeping ordinary imagery visibly behind the glass.
    property bool adaptiveDarkScrim: false
    // Some lightweight surfaces (for example notification cards) should keep
    // the upper reflection without the heavier bottom inset edge.
    property bool bottomEdgeVisible: true
    property bool bottomShadeVisible: true
    // Wallpaper changes should feel like pigment slowly moving through the
    // glass rather than a theme colour snapping to its next value.
    property int ambientTransitionDuration: 2600
    property bool _ambientInitialized: false
    property real _ambientProgress: 1.0
    property color _ambientFromPrimary: ambientPrimary
    property color _ambientFromSecondary: ambientSecondary
    property color _displayAmbientPrimary: ambientPrimary
    property color _displayAmbientSecondary: ambientSecondary
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
    // QML is drawn after KWin's backdrop pass, so it cannot sample the exact
    // pixels below itself. Wallpaper pigments plus the base layer are a stable
    // local estimate for foreground selection; hysteresis prevents black/white
    // text flickering when an ambient palette animates.
    readonly property color estimatedMaterialColor: Qt.rgba(
        baseColor.r * 0.72 + _displayAmbientPrimary.r * 0.28,
        baseColor.g * 0.72 + _displayAmbientPrimary.g * 0.28,
        baseColor.b * 0.72 + _displayAmbientPrimary.b * 0.28,
        1.0)
    readonly property real estimatedMaterialLuminance:
        estimatedMaterialColor.r * 0.2126 + estimatedMaterialColor.g * 0.7152
        + estimatedMaterialColor.b * 0.0722
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
        if (!adaptiveDarkScrim)
            return 0.0
        const lightMix = Math.max(0.0, Math.min(1.0,
            (ambientLuminance - 0.30) / 0.40))
        const base = 0.04 + 0.035 * lightMix
        const protection = (0.035 + 0.07 * lightMix)
            * ambientExtremeProtection
        return Math.min(0.20, (base + protection)
            * (material === "thick" ? 1.18 : 1.0))
    }
    property bool _useDarkForeground: estimatedMaterialLuminance >= 0.58
    readonly property color foregroundColor: _useDarkForeground
        ? Qt.rgba(0.02, 0.025, 0.035, 1.0) : Qt.rgba(1, 1, 1, 1.0)
    readonly property color secondaryForegroundColor: _useDarkForeground
        ? Qt.rgba(0.02, 0.025, 0.035, 0.76) : Qt.rgba(1, 1, 1, 0.82)
    readonly property color tertiaryForegroundColor: _useDarkForeground
        ? Qt.rgba(0.02, 0.025, 0.035, 0.62) : Qt.rgba(1, 1, 1, 0.66)
    onEstimatedMaterialLuminanceChanged: {
        if (_useDarkForeground && estimatedMaterialLuminance < 0.42)
            _useDarkForeground = false
        else if (!_useDarkForeground && estimatedMaterialLuminance > 0.58)
            _useDarkForeground = true
    }
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
    readonly property real ambientBaseMix: Math.min(0.18, ambientStrength * 0.22)
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
            return
        }
        _ambientFromPrimary = _displayAmbientPrimary
        _ambientFromSecondary = _displayAmbientSecondary
        _ambientProgress = 0.0
        ambientColourFlow.restart()
    }

    onAmbientPrimaryChanged: _beginAmbientTransition()
    onAmbientSecondaryChanged: _beginAmbientTransition()
    on_AmbientProgressChanged: {
        _displayAmbientPrimary = _mixColor(_ambientFromPrimary, ambientPrimary, _ambientProgress)
        _displayAmbientSecondary = _mixColor(_ambientFromSecondary, ambientSecondary, _ambientProgress)
    }
    Component.onCompleted: {
        _displayAmbientPrimary = ambientPrimary
        _displayAmbientSecondary = ambientSecondary
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

    // A soft top reflection gives the surface depth without a hard border.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        opacity: root.normalizedLiquidStrength
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.32 * root.materialHighlightFactor * root.materialReflectionScale) }
            GradientStop { position: 0.12; color: Qt.rgba(0.88, 0.94, 1, 0.14 * root.materialHighlightFactor * root.materialReflectionScale) }
            GradientStop { position: 0.32; color: Qt.rgba(1, 1, 1, 0.06 * root.materialHighlightFactor * root.materialReflectionScale) }
            GradientStop { position: 0.60; color: Qt.rgba(0.86, 0.93, 1, 0.018 * root.materialHighlightFactor * root.materialReflectionScale) }
            GradientStop {
                position: 1.0
                color: Qt.rgba(0, 0, 0, root.bottomShadeVisible
                    ? (0.08 + Math.max(0.0, root.materialDepth) * 0.025)
                        * root.normalizedLiquidStrength : 0.0)
            }
        }
    }

    // Wallpaper-derived tint: it stays deliberately below the specular layer
    // so the material adapts to its environment without becoming a colour card.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        opacity: root.normalizedLiquidStrength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Qt.rgba(
                    root._displayAmbientPrimary.r, root._displayAmbientPrimary.g, root._displayAmbientPrimary.b,
                    root.ambientStrength * 0.26 * root.normalizedLiquidStrength
                )
            }
            GradientStop {
                position: 0.55
                color: Qt.rgba(
                    root._displayAmbientSecondary.r, root._displayAmbientSecondary.g, root._displayAmbientSecondary.b,
                    root.ambientStrength * 0.14 * root.normalizedLiquidStrength
                )
            }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    // A faint lateral tint makes the material feel thicker than a flat
    // vertical gradient, while remaining subtle over both light and dark
    // wallpapers.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        opacity: root.normalizedLiquidStrength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0.72, 0.88, 1, 0.045 * root.materialHighlightFactor) }
            GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 0.84, 0.92, 0.035 * root.materialHighlightFactor) }
        }
    }

    // Inset specular lines imply a glass edge without reintroducing a visible
    // outline. Their endpoints begin after the curved corners.
    Rectangle {
        opacity: root.normalizedLiquidStrength
        x: Math.min(parent.width / 2, root.radius + 3)
        y: 0.8
        width: Math.max(0, parent.width - x * 2)
        height: 0.8
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.22 * root.materialHighlightFactor) }
            GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.42 * root.materialHighlightFactor) }
            GradientStop { position: 0.82; color: Qt.rgba(1, 1, 1, 0.22 * root.materialHighlightFactor) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
    }

    Rectangle {
        visible: root.bottomEdgeVisible
        opacity: root.normalizedLiquidStrength
        x: Math.min(parent.width / 2, root.radius + 3)
        y: parent.height - 2
        width: Math.max(0, parent.width - x * 2)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
            GradientStop { position: 0.20; color: Qt.rgba(0, 0, 0, 0.15 * root.normalizedLiquidStrength) }
            GradientStop { position: 0.50; color: Qt.rgba(0, 0, 0, 0.28 * root.normalizedLiquidStrength) }
            GradientStop { position: 0.80; color: Qt.rgba(0, 0, 0, 0.15 * root.normalizedLiquidStrength) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }

}
