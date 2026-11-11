import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"
import "InputMethodPlacement.mjs" as Placement

Scope {
    id: root
    property var _inspectors: new Map()
    function inspect() {
        const result = {}
        for (const [name, inspectPanel] of _inspectors) result[name] = inspectPanel()
        return result
    }

    Variants {
        model: ScreenLifecycle.usableScreens

        delegate: Component {
            PanelWindow {
                id: window

                required property var modelData

                screen: modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "kos-inputmethod-popup"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property var scrGeom: ({
                    x: Number(modelData?.x) || 0,
                    y: Number(modelData?.y) || 0,
                    width: Number(modelData?.width) || 1920,
                    height: Number(modelData?.height) || 1080
                })
                readonly property var globalAnchor: InputMethodService.globalAnchor

                readonly property bool isTargetScreen: modelData?.name === InputMethodService.targetScreenName

                function syncPresentation() {
                    presentation.update(InputMethodService.popupState, globalAnchor, isTargetScreen)
                }
                function inspect() {
                    return {
                            screen: scrGeom, anchor: globalAnchor, target: isTargetScreen,
                            requested: InputMethodService.popupState.visible,
                            candidates: InputMethodService.candidates.length,
                            mapped: presentation.mapped, progress: presentation.progress,
                            card: {x: cardContainer.x, y: cardContainer.y,
                                width: cardContainer.width, height: cardContainer.height},
                            layout: candidateArea.isVertical ? "vertical" : "horizontal",
                            preferences: InputMethodConfigService.snapshot(),
                            material: InputMethodConfigService.material,
                            glass: glassPanel.inspectGlass()
                    }
                }
                onGlobalAnchorChanged: syncPresentation()
                onIsTargetScreenChanged: syncPresentation()
                Component.onCompleted: {
                    root._inspectors.set(modelData.name, window.inspect)
                    syncPresentation()
                }
                Component.onDestruction: root._inspectors.delete(modelData.name)

                Connections {
                    target: InputMethodService
                    function onPopupStateChanged() { window.syncPresentation() }
                }

                InputMethodPresentation { id: presentation; reduceMotion: InputMethodConfigService.reduceMotion }

                // Keep the empty, input-transparent layer surface mapped.
                // Recreating a full-screen window lets KWin animate its entire
                // bounds, which makes a caret-sized card travel across screen.
                visible: ScreenLifecycle.outputAvailable
                mask: presentation.interactive ? cardInputRegion : emptyRegion

                Region { id: emptyRegion }
                Region { id: cardInputRegion; item: cardContainer }

                BackgroundEffect.blurRegion: (window.visible && presentation.mapped && !InputMethodConfigService.highContrast && AppearanceTokens.surface.usesKwinBlur)
                    ? glassPanel.blurRegion : null

                Item {
                    id: cardContainer
                    visible: presentation.mapped

                    readonly property bool isOnlyTip: presentation.isOnlyTip
                    readonly property bool frosted: InputMethodConfigService.material === "frosted"

                    readonly property string cleanTipText: {
                        const raw = presentation.state.auxText || presentation.state.preeditText;
                        return raw ? raw.replace(/\|/g, "").trim() : "";
                    }

                    // Layout placement calculation
                    readonly property real cardW: isOnlyTip
                        ? Math.max(26, contentColumn.implicitWidth + 12)
                        : Math.max(120, contentColumn.implicitWidth + 24)
                    readonly property real cardH: isOnlyTip
                        ? Math.max(22, contentColumn.implicitHeight + 6)
                        : Math.max(34, contentColumn.implicitHeight + 16)

                    readonly property var placement: Placement.placeCandidatePopup(
                        window.scrGeom,
                        presentation.anchor,
                        width,
                        height,
                        8
                    )

                    readonly property bool aboveAnchor: presentation.anchor && placement.y < presentation.anchor.y
                    x: placement.x - window.scrGeom.x
                    y: placement.y - window.scrGeom.y
                        + (aboveAnchor ? -1 : 1) * presentation.revealOffset
                    width: cardW
                    height: cardH

                    // Reveal from the caret without replaying on each keystroke.
                    scale: presentation.scale
                    transformOrigin: aboveAnchor ? Item.BottomLeft : Item.TopLeft
                    enabled: presentation.interactive

                    Behavior on width {
                        enabled: !InputMethodConfigService.reduceMotion && presentation.interactive && presentation.progress > 0.99
                        // motion-exception: preserve drag/physical or periodic response.
                        SmoothedAnimation { duration: 160; velocity: -1; maximumEasingTime: 80 }
                    }
                    Behavior on height {
                        enabled: !InputMethodConfigService.reduceMotion && presentation.interactive && presentation.progress > 0.99
                        // motion-exception: preserve drag/physical or periodic response.
                        SmoothedAnimation { duration: 160; velocity: -1; maximumEasingTime: 80 }
                    }

                    KosCardShadow {
                        cardWidth: glassPanel.width
                        cardHeight: glassPanel.height
                        cornerRadius: glassPanel.radius
                        cornerExponent: glassPanel.cornerExponent
                        x: glassPanel.x - margin
                        y: glassPanel.y - margin
                        offsetX: 0
                        offsetY: cardContainer.isOnlyTip ? 2 : 6
                        softness: cardContainer.isOnlyTip ? 8 : 20
                        spread: cardContainer.isOnlyTip ? 0 : 2
                        cutoutPadding: 0
                        opacity: (AppearanceTokens.isDarkTheme ? 0.45 : 0.22) * presentation.progress
                    }

                    LiquidGlassPanel {
                        id: glassPanel
                        anchors.fill: parent
                        // Fade QML paint here, while the compositor targets
                        // the opaque wrapper. SurfaceShape multiplies target
                        // ancestor opacity, so fading that too would square it.
                        opacity: presentation.progress
                        radius: cardContainer.isOnlyTip ? Math.round(cardContainer.cardH / 2) : 14
                        cornerExponent: cardContainer.isOnlyTip ? 2.0 : AppearanceTokens.shape.cornerExponent
                        blurAnchor: cardContainer
                        backdropScale: cardContainer.scale
                        effectOpacity: presentation.progress
                        useKwinEffect: !InputMethodConfigService.highContrast && AppearanceTokens.surface.usesKwinBlur
                        // Per-popup frost keeps its blur even when the desktop's
                        // liquid preset uses zero blur. It never changes that preset.
                        frostOnly: cardContainer.frosted
                        blurSigma: cardContainer.frosted ? 18 : -1
                        glass.liquidStrength: useKwinEffect || cardContainer.frosted
                            ? 0 : AppearanceTokens.glass.liquidStrength
                        glass.blurStrength: cardContainer.frosted ? 0.7
                            : useKwinEffect ? 1 : AppearanceTokens.glass.blurStrength
                        blurOverrideEnabled: true
                        blurStrength: AppearanceConfigService.globalBlurStrength
                        scrimEnabled: true
                        scrimLevel: "balanced"
                        material: "regular"
                        baseColor: InputMethodConfigService.highContrast
                            ? (ThemeService.isDark ? "#000000" : "#ffffff")
                            : ThemeService.isDark
                            ? Qt.rgba(0.08, 0.09, 0.12, 0.50)
                            : Qt.rgba(0.95, 0.95, 0.98, 0.70)
                        ambientPrimary: WallpaperColorSource.primary
                        ambientSecondary: WallpaperColorSource.secondary
                        ambientStrength: InputMethodConfigService.highContrast ? 0 : 0.35 * AppearanceTokens.glass.ambientMultiplier

                        Rectangle {
                            anchors.fill: parent
                            visible: InputMethodConfigService.highContrast
                            radius: glassPanel.radius
                            color: ThemeService.isDark ? "#000000" : "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0)
                                    InputMethodService.pageUp();
                                else if (wheel.angleDelta.y < 0)
                                    InputMethodService.pageDown();
                            }
                        }

                        Column {
                            id: contentColumn
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: cardContainer.isOnlyTip ? 6 : 12
                            anchors.topMargin: cardContainer.isOnlyTip ? 3 : 8
                            spacing: cardContainer.isOnlyTip ? 0 : 6

                            // 1. Preedit & Aux row
                            Row {
                                id: preeditRow
                                visible: presentation.state.preeditVisible || presentation.state.auxVisible
                                spacing: 4
                                anchors.horizontalCenter: cardContainer.isOnlyTip ? parent.horizontalCenter : undefined

                                GlassText {
                                    id: preeditLabel
                                    text: cardContainer.isOnlyTip
                                        ? cardContainer.cleanTipText
                                        : (presentation.state.auxText
                                            ? presentation.state.auxText
                                            : presentation.state.preeditText)
                                    width: Math.min(implicitWidth, window.scrGeom.width * 0.75 - 24)
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    font.pixelSize: InputMethodConfigService.fontSize - (cardContainer.isOnlyTip ? 2 : 1)
                                    font.weight: cardContainer.isOnlyTip ? Font.Bold : Font.Medium
                                    color: InputMethodConfigService.highContrast
                                        ? (ThemeService.isDark ? "#ffffff" : "#000000") : ThemeService.foregroundColor
                                }
                            }

                            // Subtle divider line
                            Rectangle {
                                visible: !cardContainer.isOnlyTip && preeditRow.visible && candidateArea.visible
                                width: Math.max(preeditRow.implicitWidth, candidateArea.implicitWidth)
                                height: 1
                                color: AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                            }

                            InputMethodCandidateList {
                                id: candidateArea
                                visible: presentation.state.lookupVisible && presentation.state.candidates.length > 0
                                width: implicitWidth
                                height: implicitHeight
                                candidates: presentation.state.candidates
                                cursorIndex: presentation.state.cursorIndex
                                engineLayout: presentation.state.layout
                                layoutPreference: InputMethodConfigService.layout
                                fontSize: InputMethodConfigService.fontSize
                                showAnnotations: InputMethodConfigService.showAnnotations
                                highContrast: InputMethodConfigService.highContrast
                                reduceMotion: InputMethodConfigService.reduceMotion
                                dark: AppearanceTokens.isDarkTheme
                                foreground: highContrast ? (dark ? "#ffffff" : "#000000") : ThemeService.foregroundColor
                                secondary: ThemeService.secondaryForegroundColor
                                maximumWidth: Math.max(80, window.scrGeom.width * 0.75 - 24)
                                maximumHeight: Math.max(60, window.scrGeom.height * 0.6 - preeditRow.height - 40)
                                hasPrev: presentation.state.hasPrev
                                hasNext: presentation.state.hasNext
                                onCandidateSelected: candidateIndex => InputMethodService.selectCandidate(candidateIndex)
                                onPreviousPage: InputMethodService.pageUp()
                                onNextPage: InputMethodService.pageDown()
                            }
                        }
                    }
                }
            }
        }
    }
}
