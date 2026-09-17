import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"

// Reusable important-interaction surface. Backdrop and card deliberately live
// in separate layer-shell surfaces, so KWin samples a controlled backdrop below
// the upper card while retaining real blur, refraction and liquid edges.
Scope {
    id: root

    default property alias content: cardHost.data
    readonly property alias glass: cardPanel
    property real contentPadding: 20
    property Item anchorItem: null
    property var targetScreen: ScreenLifecycle.activeScreen
    property bool centerOnScreen: false
    property bool modal: false
    property int floatOffset: 12
    property string backdropMode: "none"
    property real backdropOpacity: -1
    property color backdropTint: AppearanceTokens.resolvedAppearanceIsDark
        ? "white" : "black"
    property bool dismissOnBackdrop: true
    property real radius: AppearanceTokens.shape.extraLarge
    property real cornerExponent: AppearanceTokens.shape.cornerExponent
    property int materialDepth: 1
    // "auto" follows appearance; important destructive prompts may request a
    // stable light or dark material independent of the desktop theme.
    property string materialTone: "auto" // "auto" | "light" | "dark"
    property string fixedScrimTone: "theme" // "theme" | "graphite"
    property real fixedScrimOpacity: -1
    readonly property bool finalGlassIsDark: materialTone === "dark" ? true
        : materialTone === "light" ? false
        : AppearanceTokens.resolvedAppearanceIsDark
    property color baseColor: AppearanceTokens.isMaterial
        ? AppearanceTokens.colors.surfaceContainer
        : (finalGlassIsDark ? "black" : "white")
    property real surfaceOpacity: AppearanceTokens.isMaterial
        ? AppearanceTokens.glass.materialOpacity : 1.0
    property color ambientPrimary: WallpaperColorSource.primary
    property color ambientSecondary: WallpaperColorSource.secondary
    property real ambientStrength: 0.30 * AppearanceTokens.glass.ambientMultiplier
    // Content follows the requested final glass tone, not the generic glass
    // surface's legacy "always white" foreground policy.
    readonly property color contentForegroundColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.075, 0.07, 0.09, 0.96)
    readonly property color contentSecondaryColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0.075, 0.07, 0.09, 0.70)
    readonly property color contentTertiaryColor: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.54) : Qt.rgba(0.075, 0.07, 0.09, 0.52)
    readonly property color contentControlFill: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.075)
    readonly property color contentControlBorder: finalGlassIsDark
        ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.14)
    property bool animateOnShow: AppearanceTokens.isMacos
    property real startScale: AppearanceTokens.motion.popupStartScale
    property real anchorOffset: AppearanceTokens.motion.popupAnchorOffset

    property alias visible: cardWindow.visible
    readonly property alias width: cardWindow.width
    readonly property alias height: cardWindow.height
    readonly property bool _centered: root.centerOnScreen || root.modal

    signal aboutToShow()
    signal aboutToHide()
    signal backdropClicked()

    function show() {
        if (root.anchorItem && !root._centered)
            root._placeAnchored()
        backdropWindow.visible = root.modal && root.backdropMode !== "none"
        cardWindow.visible = true
        if (root.animateOnShow && !popupMotion.mapped)
            popupMotion.open()
    }
    function hide() {
        if (root.animateOnShow && cardWindow.visible) {
            popupMotion.close()
            return
        }
        cardWindow.visible = false
        backdropWindow.visible = false
    }
    function open() { root.show() }
    function close() { root.hide() }
    function toggle() { root.visible ? root.hide() : root.show() }

    property real _anchorX: 0
    property real _anchorY: 0
    function _placeAnchored() {
        const g = root.anchorItem.mapToGlobal(0, 0)
        root._anchorX = Math.round(g.x - (cardWindow.x || 0))
        root._anchorY = Math.round(g.y - (cardWindow.y || 0)
                                   - cardPanel.height - root.floatOffset)
    }

    // The underlay is visual-only. Its tone is deliberately opposite to the
    // appearance's final glass tone, providing deterministic input to KWin's
    // one-polarity adaptive scrim.
    PanelWindow {
        id: backdropWindow
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-kosfloatpanel-backdrop"
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        visible: false

        Rectangle {
            id: backdrop
            anchors.fill: parent
            color: root.backdropOpacity >= 0
                ? Qt.rgba(root.backdropTint.r, root.backdropTint.g,
                    root.backdropTint.b, Math.min(1, root.backdropOpacity))
                : (AppearanceTokens.resolvedAppearanceIsDark
                    ? Qt.rgba(1, 1, 1, 0.38)
                    : Qt.rgba(0, 0, 0, 0.48))
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        Region { id: backdropBlurRegion; item: backdrop }
        BackgroundEffect.blurRegion: (backdropWindow.visible
                                      && root.backdropMode === "dimBlur")
            ? backdropBlurRegion : null
    }

    PanelWindow {
        id: cardWindow
        screen: root.targetScreen
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-kosfloatpanel-card"
        WlrLayershell.keyboardFocus: root.modal
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; left: true; right: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        visible: false

        MouseArea {
            anchors.fill: parent
            enabled: root.modal
            onClicked: {
                root.backdropClicked()
                if (root.dismissOnBackdrop)
                    root.close()
            }
        }

        LiquidGlassPanel {
            id: cardPanel
            z: 1
            radius: root.radius
            cornerExponent: root.cornerExponent
            materialDepth: root.materialDepth
            material: "thick"
            baseColor: root.baseColor
            surfaceOpacity: root.surfaceOpacity
            ambientPrimary: root.ambientPrimary
            ambientSecondary: root.ambientSecondary
            ambientStrength: root.ambientStrength
            useKwinEffect: true
            scrimEnabled: true
            scrimLevel: "custom"
            // Important interactions prioritize legibility. The host may make
            // the full-screen backdrop completely transparent; a strong
            // theme-polarized KWin scrim then carries the contrast contract.
            scrimCap: root.fixedScrimOpacity >= 0
                ? root.fixedScrimOpacity
                : (root.finalGlassIsDark ? 0.88 : 0.94)
            scrimDecay: 1.0
            scrimFixed: true
            scrimGraphite: root.fixedScrimTone === "graphite"
            scrimTintOverride: root.finalGlassIsDark ? 0 : 1

            width: cardHost.width + root.contentPadding * 2
            height: cardHost.height + root.contentPadding * 2
            x: root._centered
                ? Math.round((cardWindow.width - width) / 2) : root._anchorX
            y: root._centered
                ? Math.round((cardWindow.height - height) / 2) : root._anchorY
            scale: (root.animateOnShow && popupMotion.progress < 0.999)
                ? root.startScale + (1 - root.startScale) * popupMotion.progress : 1
            transformOrigin: Item.Top
            opacity: root.animateOnShow ? popupMotion.progress : 1
            enabled: !root.animateOnShow || popupMotion.interactive
            transform: Translate {
                y: (root.animateOnShow && popupMotion.progress < 0.999)
                    ? Math.round((1 - popupMotion.progress) * root.anchorOffset) : 0
            }

            Column {
                id: cardHost
                anchors.centerIn: parent
                width: childrenRect.width
                height: childrenRect.height
                spacing: 8
            }
        }

        mask: root.modal ? null : cardRegion
        Region { id: cardRegion; item: cardPanel }
        BackgroundEffect.blurRegion: (cardWindow.visible
                                      && !AppearanceTokens.isMaterial
                                      && cardPanel.useKwinEffect)
            ? cardPanel.blurRegion : null
    }

    PopupMotion {
        id: popupMotion
        onClosed: {
            if (!popupMotion.requestedOpen) {
                cardWindow.visible = false
                backdropWindow.visible = false
            }
        }
    }

    Connections {
        target: cardWindow
        function onVisibleChanged() {
            if (cardWindow.visible)
                root.aboutToShow()
            else
                root.aboutToHide()
        }
    }
}
