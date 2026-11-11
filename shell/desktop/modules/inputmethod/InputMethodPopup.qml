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

                readonly property bool isTargetScreen: {
                    if (!globalAnchor) return modelData?.name === ScreenLifecycle.activeScreen?.name;
                    return globalAnchor.x >= scrGeom.x
                        && globalAnchor.x < (scrGeom.x + scrGeom.width)
                        && globalAnchor.y >= scrGeom.y
                        && globalAnchor.y < (scrGeom.y + scrGeom.height);
                }

                function syncPresentation() {
                    presentation.update(InputMethodService.popupState, globalAnchor, isTargetScreen)
                }
                onGlobalAnchorChanged: syncPresentation()
                onIsTargetScreenChanged: syncPresentation()
                Component.onCompleted: syncPresentation()

                Connections {
                    target: InputMethodService
                    function onPopupStateChanged() { window.syncPresentation() }
                }

                InputMethodPresentation { id: presentation }

                // Keep the empty, input-transparent layer surface mapped.
                // Recreating a full-screen window lets KWin animate its entire
                // bounds, which makes a caret-sized card travel across screen.
                visible: ScreenLifecycle.outputAvailable
                mask: presentation.interactive ? cardInputRegion : emptyRegion

                Region { id: emptyRegion }
                Region { id: cardInputRegion; item: cardContainer }

                BackgroundEffect.blurRegion: (window.visible && presentation.mapped && AppearanceTokens.surface.usesKwinBlur)
                    ? glassPanel.blurRegion : null

                Item {
                    id: cardContainer
                    visible: presentation.mapped

                    readonly property bool isOnlyTip: presentation.isOnlyTip

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

                    x: placement.x - window.scrGeom.x
                    y: placement.y - window.scrGeom.y
                    width: cardW
                    height: cardH

                    // A tiny contraction toward the caret; no sliding text.
                    scale: presentation.scale
                    transformOrigin: presentation.anchor && placement.y < presentation.anchor.y
                        ? Item.BottomLeft : Item.TopLeft
                    enabled: presentation.interactive

                    Behavior on width {
                        enabled: presentation.interactive && presentation.progress > 0.99
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
                    }
                    Behavior on height {
                        enabled: presentation.interactive && presentation.progress > 0.99
                        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
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
                        useKwinEffect: AppearanceTokens.surface.usesKwinBlur
                        blurOverrideEnabled: true
                        blurStrength: AppearanceConfigService.globalBlurStrength
                        scrimEnabled: true
                        scrimLevel: "readable"
                        material: "thick"
                        baseColor: ThemeService.isDark
                            ? Qt.rgba(0.08, 0.09, 0.12, 0.50)
                            : Qt.rgba(0.95, 0.95, 0.98, 0.70)
                        ambientPrimary: WallpaperColorSource.primary
                        ambientSecondary: WallpaperColorSource.secondary
                        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier

                        // Inner plate for text contrast protection
                        Rectangle {
                            anchors.fill: parent
                            radius: glassPanel.contentRadius
                            color: ThemeService.isDark ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(1, 1, 1, 0.28)
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
                                    font.pixelSize: cardContainer.isOnlyTip ? 13 : 14
                                    font.weight: cardContainer.isOnlyTip ? Font.Bold : Font.Medium
                                    color: ThemeService.foregroundColor
                                }
                            }

                            // Subtle divider line
                            Rectangle {
                                visible: !cardContainer.isOnlyTip && preeditRow.visible && candidateArea.visible
                                width: Math.max(preeditRow.implicitWidth, candidateArea.implicitWidth)
                                height: 1
                                color: AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                            }

                            // 2. Candidate items (horizontal row or vertical column)
                            Item {
                                id: candidateArea
                                visible: presentation.state.lookupVisible && presentation.state.candidates.length > 0
                                width: implicitWidth
                                height: implicitHeight
                                implicitWidth: isVertical ? verticalCol.implicitWidth : horizontalRow.implicitWidth
                                implicitHeight: isVertical ? verticalCol.implicitHeight : horizontalRow.implicitHeight

                                readonly property bool isVertical: presentation.state.layout === 1

                                // Horizontal candidate row (default & Rime standard)
                                Row {
                                    id: horizontalRow
                                    visible: !candidateArea.isVertical
                                    spacing: 12

                                    Repeater {
                                        model: presentation.state.candidates

                                        delegate: Item {
                                            id: candItem
                                            readonly property bool isSelected: index === presentation.state.cursorIndex
                                            readonly property var dataItem: modelData

                                            width: implicitWidth
                                            height: implicitHeight
                                            implicitWidth: candRow.implicitWidth + 12
                                            implicitHeight: candRow.implicitHeight + 6

                                            // Highlight pill for active candidate
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 8
                                                color: isSelected
                                                    ? (AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09))
                                                    : candMouse.containsMouse
                                                        ? (AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                                                        : "transparent"
                                                Behavior on color {
                                                    ColorAnimation { duration: 120 }
                                                }
                                            }

                                            Row {
                                                id: candRow
                                                anchors.centerIn: parent
                                                spacing: 4

                                                GlassText {
                                                    text: String(dataItem.label || (index + 1) + ".")
                                                    font.pixelSize: 13
                                                    color: ThemeService.secondaryForegroundColor
                                                    opacity: isSelected ? 0.95 : 0.65
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                GlassText {
                                                    id: mainText
                                                    text: String(dataItem.text || "")
                                                    font.pixelSize: 15
                                                    color: ThemeService.foregroundColor
                                                    font.weight: isSelected ? Font.DemiBold : Font.Normal
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                GlassText {
                                                    visible: !!dataItem.comment
                                                    text: String(dataItem.comment || "")
                                                    font.pixelSize: 12
                                                    color: ThemeService.tertiaryForegroundColor
                                                    opacity: 0.65
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            MouseArea {
                                                id: candMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: InputMethodService.selectCandidate(index)
                                            }
                                        }
                                    }

                                    // Paging indicators
                                    Row {
                                        visible: presentation.state.hasPrev || presentation.state.hasNext
                                        spacing: 4
                                        anchors.verticalCenter: parent.verticalCenter

                                        GlassText {
                                            text: "<"
                                            visible: presentation.state.hasPrev
                                            color: ThemeService.secondaryForegroundColor
                                            opacity: prevMouse.containsMouse ? 0.9 : 0.45
                                            font.pixelSize: 12
                                            MouseArea {
                                                id: prevMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: InputMethodService.pageUp()
                                            }
                                        }

                                        GlassText {
                                            text: ">"
                                            visible: presentation.state.hasNext
                                            color: ThemeService.secondaryForegroundColor
                                            opacity: nextMouse.containsMouse ? 0.9 : 0.45
                                            font.pixelSize: 12
                                            MouseArea {
                                                id: nextMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: InputMethodService.pageDown()
                                            }
                                        }
                                    }
                                }

                                // Vertical candidate column (when layout === 1)
                                Column {
                                    id: verticalCol
                                    visible: candidateArea.isVertical
                                    spacing: 4

                                    Repeater {
                                        model: presentation.state.candidates

                                        delegate: Item {
                                            readonly property bool isSelected: index === presentation.state.cursorIndex
                                            readonly property var dataItem: modelData

                                            width: implicitWidth
                                            height: implicitHeight
                                            implicitWidth: vCandRow.implicitWidth + 16
                                            implicitHeight: vCandRow.implicitHeight + 4

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 6
                                                color: isSelected
                                                    ? (AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.09))
                                                    : vCandMouse.containsMouse
                                                        ? (AppearanceTokens.isDarkTheme ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.04))
                                                        : "transparent"
                                            }

                                            Row {
                                                id: vCandRow
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: 6
                                                spacing: 6

                                                GlassText {
                                                    text: String(dataItem.label || (index + 1) + ".")
                                                    font.pixelSize: 13
                                                    color: ThemeService.secondaryForegroundColor
                                                    opacity: isSelected ? 0.95 : 0.65
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                GlassText {
                                                    id: vMainText
                                                    text: String(dataItem.text || "")
                                                    font.pixelSize: 15
                                                    color: ThemeService.foregroundColor
                                                    font.weight: isSelected ? Font.DemiBold : Font.Normal
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                GlassText {
                                                    visible: !!dataItem.comment
                                                    text: String(dataItem.comment || "")
                                                    font.pixelSize: 12
                                                    color: ThemeService.tertiaryForegroundColor
                                                    opacity: 0.65
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            MouseArea {
                                                id: vCandMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: InputMethodService.selectCandidate(index)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
