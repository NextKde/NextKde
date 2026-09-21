import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"

// The status area is edited where it is seen. Visibility is changed by the
// cards themselves and drag order is persisted by the same service used by
// Alt+drag on the live tray. Control Center remains the required end anchor.
PopupWindow {
    id: editor

    property Item anchorItem: null
    readonly property var ids: ["network", "battery", "settings", "controlcenter"]
    readonly property var labels: ({
        network: "网络", battery: "电池", settings: "设置", controlcenter: "控制中心"
    })
    readonly property var symbols: ({
        network: "⌁", battery: "▱", settings: "⚙", controlcenter: "◉"
    })
    readonly property var cellKeys: ids.map(id => "cell:" + id)
    readonly property var arrangedIds: {
        const arranged = SysTrayOrderService.arrange(cellKeys)
            .map(key => key.slice(5))
        for (const id of ids) {
            if (arranged.indexOf(id) < 0)
                arranged.push(id)
        }
        return arranged
    }

    visible: false
    implicitWidth: 424
    implicitHeight: 146
    color: "transparent"
    grabFocus: true
    anchor {
        item: editor.anchorItem
        edges: Edges.Bottom
        gravity: Edges.Bottom
        margins.bottom: 10
    }

    function openFor(item) {
        anchorItem = item
        visible = true
    }

    Item {
        anchors.fill: parent
        LiquidGlassPanel {
            anchors.fill: parent
            radius: AppearanceTokens.isMaterial ? 28 : 20
            cornerExponent: AppearanceTokens.isMaterial ? 2.0 : 2.35
            baseColor: ThemeService.backgroundColor
            surfaceOpacity: 1
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "subtle"
        }

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "状态栏"
                    color: ThemeService.foregroundColor
                    font { pixelSize: 14; weight: Font.DemiBold }
                }
                Text {
                    text: "拖动排序，点按显示或隐藏"
                    color: ThemeService.foregroundColor
                    opacity: 0.58
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true; height: 1 }
                Rectangle {
                    width: 48; height: 26; radius: AppearanceTokens.isMaterial ? 13 : 9
                    color: AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.primaryContainer,
                        Qt.rgba(ThemeService.foregroundColor.r,
                            ThemeService.foregroundColor.g,
                            ThemeService.foregroundColor.b, 0.10))
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
                id: cellRow
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Repeater {
                    model: editor.arrangedIds
                    delegate: Rectangle {
                        id: cellCard
                        required property string modelData
                        readonly property bool requiredCell: modelData === "controlcenter"
                        readonly property bool active:
                            !AppearanceConfigService.isStatusCellHidden(modelData)
                        readonly property int activeIndex: editor.arrangedIds.indexOf(modelData)
                        property real dragOffset: 0
                        width: 90; height: 66
                        radius: AppearanceTokens.isMaterial ? 18 : 14
                        color: active
                            ? AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.secondaryContainer,
                                Qt.rgba(ThemeService.foregroundColor.r,
                                    ThemeService.foregroundColor.g,
                                    ThemeService.foregroundColor.b, 0.10))
                            : "transparent"
                        border.width: active ? 2 : 1
                        border.color: active ? AppearanceTokens.colors.primary
                            : AppearanceTokens.colors.outlineVariant
                        opacity: active ? 1 : 0.58
                        z: cellDrag.active ? 10 : 0
                        transform: Translate { x: cellCard.dragOffset }
                        scale: cellDrag.active ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: editor.symbols[cellCard.modelData]
                                color: ThemeService.foregroundColor
                                font.pixelSize: 19
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: editor.labels[cellCard.modelData]
                                color: ThemeService.foregroundColor
                                font { pixelSize: 10; weight: Font.DemiBold }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cellCard.requiredCell ? "固定" : (cellCard.active ? "−" : "+")
                                color: cellCard.requiredCell ? ThemeService.foregroundColor
                                    : (cellCard.active ? "#ff453a" : ThemeService.accentColor)
                                opacity: cellCard.requiredCell ? 0.55 : 1
                                font { pixelSize: 10; weight: Font.Bold }
                            }
                        }

                        TapHandler {
                            enabled: !cellCard.requiredCell && !cellDrag.active
                            onTapped: AppearanceConfigService.setStatusCellVisible(
                                cellCard.modelData, !cellCard.active)
                        }
                        DragHandler {
                            id: cellDrag
                            target: null
                            enabled: cellCard.active && !cellCard.requiredCell
                            xAxis.enabled: true
                            yAxis.enabled: false
                            onTranslationChanged: if (active) cellCard.dragOffset = translation.x
                            onActiveChanged: {
                                if (active)
                                    return
                                if (Math.abs(cellCard.dragOffset) < 8) {
                                    cellCard.dragOffset = 0
                                    return
                                }
                                const delta = Math.round(cellCard.dragOffset
                                    / (cellCard.width + cellRow.spacing))
                                SysTrayOrderService.moveKey("cell:" + cellCard.modelData,
                                    Math.max(0, Math.min(editor.arrangedIds.length - 2,
                                        cellCard.activeIndex + delta)), editor.cellKeys)
                                cellCard.dragOffset = 0
                            }
                        }
                    }
                }
            }
        }
    }
}
