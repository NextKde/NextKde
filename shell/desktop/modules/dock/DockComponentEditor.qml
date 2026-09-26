import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"
import "../../../shared/qml/controls" as LiquidControls

// Contextual editor for the information area. It edits the cards themselves:
// active cards are ordered at the front, unused cards remain available in the
// same visual tray, and dragging an active card changes the live Dock order.
PopupWindow {
    id: editor

    property Item anchorItem: null
    property bool pointerInside: false
    readonly property var labels: ({
        music: "音乐", weather: "天气", clock: "时钟", metrics: "系统"
    })
    readonly property var symbols: ({
        music: "♫", weather: "☀", clock: "◷", metrics: "⌁"
    })
    readonly property var displayIds: {
        const active = ConfigService.infoCardOrder.slice()
        for (const id of ConfigService.knownInfoCardIds) {
            if (active.indexOf(id) < 0)
                active.push(id)
        }
        return active
    }

    visible: false
    implicitWidth: 456
    implicitHeight: 204
    color: "transparent"
    grabFocus: true

    anchor {
        item: editor.anchorItem
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -12
    }

    function openFor(item) {
        anchorItem = item
        DockModelService.openDockPopup(editor)
    }

    onVisibleChanged: if (!visible) DockModelService.releaseDockPopup(editor)

    Item {
        anchors.fill: parent

        LiquidGlassPanel {
            id: editorSurface
            anchors.fill: parent
            radius: AppearanceTokens.isMaterial ? 28 : 20
            cornerExponent: AppearanceTokens.isMaterial ? 2.0 : 2.35
            baseColor: ThemeService.backgroundColor
            surfaceOpacity: 1.0
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "subtle"
        }

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Dock 组件"
                    color: ThemeService.foregroundColor
                    font { pixelSize: 14; weight: Font.DemiBold }
                }
                Text {
                    text: "拖动排序，点按添加或移除"
                    color: ThemeService.foregroundColor
                    opacity: 0.58
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true; height: 1 }
                Rectangle {
                    width: 48; height: 26; radius: AppearanceTokens.isMaterial ? 13 : 9
                    color: AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.primaryContainer,
                        Qt.rgba(1, 1, 1, ThemeService.isDark ? 0.13 : 0.72))
                    Text {
                        anchors.centerIn: parent
                        text: "完成"
                        color: AppearanceTokens.surface.pick(
                            AppearanceTokens.colors.primaryContainerForeground,
                            ThemeService.foregroundColor)
                        font { pixelSize: 11; weight: Font.DemiBold }
                    }
                    TapHandler { onTapped: editor.visible = false }
                }
            }

            Row {
                id: cardRow
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Repeater {
                    model: editor.displayIds

                    delegate: Rectangle {
                        id: card
                        required property string modelData
                        required property int index
                        readonly property bool active:
                            ConfigService.infoCardOrder.indexOf(modelData) >= 0
                        readonly property int activeIndex:
                            ConfigService.infoCardOrder.indexOf(modelData)
                        property real dragOffset: 0

                        width: 96
                        height: 72
                        radius: AppearanceTokens.isMaterial ? 18 : 14
                        color: active
                            ? AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.secondaryContainer,
                                ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14)
                                    : Qt.rgba(0, 0, 0, 0.06))
                            : AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.surfaceContainerLow,
                                ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.045)
                                    : Qt.rgba(0, 0, 0, 0.025))
                        border.width: active ? 2 : 1
                        border.color: active
                            ? AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.primary,
                                ThemeService.accentColor)
                            : AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.outlineVariant,
                                Qt.rgba(ThemeService.foregroundColor.r,
                                    ThemeService.foregroundColor.g,
                                    ThemeService.foregroundColor.b, 0.16))
                        opacity: active ? 1 : 0.62
                        z: reorderDrag.active ? 10 : 0
                        transform: Translate { x: card.dragOffset }
                        scale: reorderDrag.active ? 1.06 : 1

                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: editor.symbols[card.modelData]
                                color: ThemeService.foregroundColor
                                font.pixelSize: 22
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: editor.labels[card.modelData]
                                color: ThemeService.foregroundColor
                                font { pixelSize: 11; weight: Font.DemiBold }
                            }
                        }

                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 5 }
                            width: 20; height: 20; radius: 10
                            color: active ? "#ff453a" : ThemeService.accentColor
                            Text {
                                anchors.centerIn: parent
                                text: card.active ? "−" : "+"
                                color: "white"
                                font { pixelSize: 15; weight: Font.Bold }
                            }
                        }

                        TapHandler {
                            enabled: !reorderDrag.active
                            onTapped: {
                                if (card.active)
                                    ConfigService.removeInfoCard(card.modelData)
                                else
                                    ConfigService.addInfoCard(card.modelData,
                                        ConfigService.infoCardOrder.length)
                            }
                        }

                        DragHandler {
                            id: reorderDrag
                            target: null
                            enabled: card.active
                            xAxis.enabled: true
                            yAxis.enabled: false
                            onTranslationChanged: if (active) card.dragOffset = translation.x
                            onActiveChanged: {
                                if (active)
                                    return
                                if (Math.abs(card.dragOffset) < 8) {
                                    card.dragOffset = 0
                                    return
                                }
                                const step = card.width + cardRow.spacing
                                const delta = Math.round(card.dragOffset / step)
                                ConfigService.moveInfoCard(card.modelData,
                                    Math.max(0, Math.min(
                                        ConfigService.infoCardOrder.length - 1,
                                        card.activeIndex + delta)))
                                card.dragOffset = 0
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4

                ColumnLayout {
                    spacing: 1
                    Text {
                        text: "自动轮播"
                        color: ThemeService.foregroundColor
                        font { pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        text: "关闭后仍可悬停并使用滚轮切换"
                        color: ThemeService.foregroundColor
                        opacity: 0.58
                        font.pixelSize: 10
                    }
                }
                Item { Layout.fillWidth: true; height: 1 }
                LiquidControls.LiquidGlassSwitch {
                    id: autoRotateSwitch
                    implicitWidth: 58
                    implicitHeight: 28
                    checked: ConfigService.infoCardAutoRotate
                    accentColor: ThemeService.accentColor
                    trackColor: Qt.rgba(ThemeService.foregroundColor.r,
                        ThemeService.foregroundColor.g,
                        ThemeService.foregroundColor.b, 0.18)
                    onToggled: function(enabled) {
                        ConfigService.updateInfoCardAutoRotate(enabled)
                    }
                }
            }
        }
    }

    // Material paints its tonal fallback in QML. Glass themes delegate the
    // finish to KWin, so this standalone popup must publish its own shape.
    BackgroundEffect.blurRegion: editor.visible
        ? editorSurface.blurRegion : null

    HoverHandler { onHoveredChanged: editor.pointerInside = hovered }
}
