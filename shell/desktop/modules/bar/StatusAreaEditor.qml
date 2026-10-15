import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import "../../../Kos/Ui"
import "StatusAreaLayout.mjs" as EditorLayout

// The status area is edited where it is seen. Visibility is changed by the
// cards themselves and drag order is persisted by the same service used by
// Alt+drag on the live tray. Control Center remains the required end anchor.
AnimatedPopupWindow {
    id: editor

    property Item anchorItem: null
    readonly property color foregroundColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.surfaceForeground,
        AppearanceTokens.isDarkTheme ? "#f5f5f7" : "#1c1c1e")
    readonly property color backgroundColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.surfaceContainer,
        AppearanceTokens.isDarkTheme ? "#1c1c1e" : "#ffffff")
    readonly property color accentColor: AppearanceTokens.surface.pick(
        AppearanceTokens.colors.primary, "#0a84ff")
    readonly property var ids: AppearanceConfigService.statusCellIds
    readonly property var labels: ({
        tray: I18n.tr("Application Tray"),
        temperature: I18n.tr("Temperature"), traffic: I18n.tr("Network Traffic"),
        network: I18n.tr("Network"), battery: I18n.tr("Battery"),
        settings: I18n.tr("Settings"), notifications: I18n.tr("Notification History"), controlcenter: I18n.tr("Control Center")
    })
    readonly property var symbols: ({
        tray: "▦", temperature: "♨", traffic: "↕", network: "⌁", battery: "▱", settings: "⚙", notifications: "♧", controlcenter: "◉"
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

    // Wrap to the output's logical width; long lists scroll vertically.
    property real maximumWidth: Math.max(118,
        (editor.screen || ScreenLifecycle.activeScreen)?.width - 24 || 1000)
    readonly property int cardColumns: EditorLayout.columnsForWidth(maximumWidth, ids.length)
    implicitWidth: Math.min(maximumWidth,
        Math.max(cellGrid.implicitWidth, headerRow.implicitWidth) + 28)
    implicitHeight: Math.max(146, headerRow.implicitHeight + cardsViewport.implicitHeight + 38)
    color: "transparent"
    grabFocus: interactive
    PopupAnchorBinding { popupAnchor: editor.anchor; sourceItem: editor.anchorItem }

    anchor {
        edges: Edges.Bottom
        gravity: Edges.Bottom
        margins.bottom: 10
    }

    function toggle(item) {
        if (requestedOpen) {
            hide()
            return
        }
        anchorItem = item
        show()
    }

    Item {
        anchors.fill: parent
        LiquidGlassPanel {
            anchors.fill: parent
            radius: AppearanceTokens.isMaterial ? 28 : 20
            cornerExponent: AppearanceTokens.isMaterial ? 2.0 : 2.35
            baseColor: editor.backgroundColor
            surfaceOpacity: 1
            scrimEnabled: AppearanceTokens.surface.usesBackdrop
            scrimLevel: "subtle"
        }

        ColumnLayout {
            anchors { fill: parent; margins: 14 }
            spacing: 10
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                Text {
                    text: I18n.tr("Status Area")
                    color: editor.foregroundColor
                    font { pixelSize: 14; weight: Font.DemiBold }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: I18n.tr("Drag to reorder, tap to show or hide")
                    color: editor.foregroundColor
                    opacity: 0.58
                    font.pixelSize: 11
                }
                Item { Layout.fillWidth: true; height: 1 }
                Rectangle {
                    width: 48; height: 26; radius: AppearanceTokens.isMaterial ? 13 : 9
                    color: AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.primaryContainer,
                        Qt.rgba(editor.foregroundColor.r,
                            editor.foregroundColor.g,
                            editor.foregroundColor.b, 0.10))
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: AppearanceTokens.surface.pick(
                            AppearanceTokens.colors.primaryContainerForeground,
                            editor.foregroundColor)
                        font { pixelSize: 11; weight: Font.DemiBold }
                    }
                    TapHandler { onTapped: editor.hide() }
                }
            }

            Flickable {
                id: cardsViewport
                Layout.fillWidth: true
                implicitHeight: Math.min(cellGrid.implicitHeight,
                    Math.max(66, ((editor.screen || ScreenLifecycle.activeScreen)?.height || 800)
                        - headerRow.implicitHeight - 100))
                Layout.preferredHeight: implicitHeight
                contentWidth: width
                contentHeight: cellGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                clip: true
                Grid {
                    id: cellGrid
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: editor.cardColumns
                    columnSpacing: EditorLayout.spacing
                    rowSpacing: EditorLayout.spacing
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
                            property real dragOffsetY: 0
                            objectName: "status-card-" + modelData
                            width: EditorLayout.cardWidth; height: EditorLayout.cardHeight
                            radius: AppearanceTokens.isMaterial ? 18 : 14
                            color: active
                                ? AppearanceTokens.surface.pick(
                                    AppearanceTokens.colors.secondaryContainer,
                                    Qt.rgba(editor.foregroundColor.r,
                                        editor.foregroundColor.g,
                                        editor.foregroundColor.b, 0.10))
                                : "transparent"
                            border.width: active ? 2 : 1
                            border.color: active ? AppearanceTokens.colors.primary
                                : AppearanceTokens.colors.outlineVariant
                            opacity: active ? 1 : 0.58
                            z: cellDrag.active ? 10 : 0
                            transform: Translate { x: cellCard.dragOffset; y: cellCard.dragOffsetY }
                            scale: cellDrag.active ? 1.06 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: editor.symbols[cellCard.modelData]
                                    color: editor.foregroundColor
                                    font.pixelSize: 19
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: editor.labels[cellCard.modelData]
                                    color: editor.foregroundColor
                                    font { pixelSize: 10; weight: Font.DemiBold }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: cellCard.requiredCell
                                        ? I18n.tr("Pinned") : (cellCard.active ? "−" : "+")
                                    color: cellCard.requiredCell ? editor.foregroundColor
                                        : (cellCard.active ? "#ff453a" : editor.accentColor)
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
                                yAxis.enabled: true
                                onTranslationChanged: if (active) {
                                    cellCard.dragOffset = translation.x
                                    cellCard.dragOffsetY = translation.y
                                }
                                onActiveChanged: {
                                    if (active)
                                        return
                                    if (Math.hypot(cellCard.dragOffset, cellCard.dragOffsetY) < 8) {
                                        cellCard.dragOffset = 0
                                        cellCard.dragOffsetY = 0
                                        return
                                    }
                                    SysTrayOrderService.moveKey("cell:" + cellCard.modelData,
                                        EditorLayout.dragDestination(cellCard.activeIndex,
                                            cellCard.dragOffset, cellCard.dragOffsetY,
                                            editor.cardColumns, editor.arrangedIds.length), editor.cellKeys)
                                    cellCard.dragOffset = 0
                                    cellCard.dragOffsetY = 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
