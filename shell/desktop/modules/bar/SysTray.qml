import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import qs.desktop.modules.common
import qs.desktop.modules.dock

// StatusNotifierItem host. Referencing SystemTray claims and tracks tray items.
Item {
    id: root

    property int iconSize: 16
    property int iconSpacing: 6
    // Visual-only adjustment; transforms preserve the item's input region
    // and the menu anchor follows the transformed icon position.
    property int visualYOffset: 0
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    readonly property int popupEdge: !dockHosted ? Edges.Bottom
        : dockEdge === "left" ? Edges.Right
        : dockEdge === "right" ? Edges.Left : Edges.Top
    // BarStatusArea appends Wi-Fi, battery, settings and control-centre cells
    // here so native tray items and shell controls share one continuous grid.
    property var trailingComponents: []
    // Supplied by BarStatusArea. Keeping this separate from the tray's own
    // implicitHeight avoids a height/row-count binding cycle.
    property real availableHeight: 24
    readonly property int itemSize: iconSize + 8
    // UntypedObjectModel intentionally has no length/get API; Repeater.count
    // is the supported reactive item count for layout calculations.
    readonly property int itemCount: trayRepeater.count
        + (trailingComponents ? trailingComponents.length : 0)
    readonly property int twoRowThreshold: itemSize * 2
    readonly property bool twoRows: dockHosted && itemCount > 1
        && availableHeight >= twoRowThreshold
    readonly property int rowCount: twoRows ? 2 : 1
    readonly property real singleRowImplicitWidth: itemCount > 0
        ? itemCount * itemSize + (itemCount - 1) * iconSpacing : 0

    implicitWidth: trayGrid.implicitWidth
    implicitHeight: trayGrid.implicitHeight
    width: implicitWidth
    height: implicitHeight
    transform: Translate { y: root.visualYOffset }

    Grid {
        id: trayGrid
        anchors.centerIn: parent
        rows: root.rowCount
        flow: Grid.TopToBottom
        columnSpacing: root.iconSpacing
        rowSpacing: 0

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData
                width: root.itemSize
                height: root.itemSize
                readonly property string tooltip: modelData.tooltipTitle
                    || modelData.title || modelData.id
                readonly property bool isSymbolicMask: Boolean(modelData.isMask)
                    || (typeof modelData.icon === "string" && (
                        modelData.icon.indexOf("symbolic") !== -1
                        || modelData.icon.indexOf("-mask") !== -1
                    ))

                function openMenu() {
                    if (!modelData.hasMenu)
                        return

                    // QsMenuAnchor owns a native Qt menu. Release any
                    // self-drawn desktop popup first, then let it finish
                    // unmapping before Qt calculates this menu's anchor.
                    ContextMenuCoordinator.closeActive()
                    Qt.callLater(function() {
                        if (trayItem.modelData && trayItem.modelData.hasMenu)
                            trayMenu.open()
                    })
                }

                function activatePrimary() {
                    if (modelData.onlyMenu)
                        openMenu()
                    else
                        modelData.activate()
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                    visible: trayMouse.containsMouse || trayMenu.visible
                }

                AppIcon {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.centerIn: parent
                    source: trayItem.modelData.icon
                    opacityMultiplier: IconAppearanceService.mode !== "color"
                        ? IconAppearanceService.opacity : 1.0
                    saturation: IconAppearanceService.saturation
                    tintEnabled: IconAppearanceService.tintEnabled
                    tintColor: IconAppearanceService.tintColor
                    rotation: root.verticalDock ? -90 : 0
                    layer.enabled: trayItem.isSymbolicMask && IconAppearanceService.mode === "color"
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: ThemeService.foregroundColor
                    }
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                            return
                        }
                        if (mouse.button === Qt.RightButton) {
                            trayItem.openMenu()
                            return
                        }
                        trayItem.activatePrimary()
                    }
                }

                QsMenuAnchor {
                    id: trayMenu
                    menu: trayItem.modelData.menu
                    anchor {
                        item: trayItem
                        edges: root.popupEdge
                        gravity: root.popupEdge
                        margins.top: root.dockHosted
                            && root.dockEdge === "bottom" ? -4 : 0
                        margins.bottom: root.dockHosted ? 0 : -4
                        margins.left: root.dockHosted
                            && root.dockEdge === "right" ? -4 : 0
                        margins.right: root.dockHosted
                            && root.dockEdge === "left" ? -4 : 0
                    }
                }

                PopupWindow {
                    id: trayTooltip
                    visible: trayMouse.containsMouse && !trayMenu.visible
                        && trayItem.tooltip.length > 0
                    implicitWidth: tooltipText.implicitWidth + 16
                    implicitHeight: tooltipText.implicitHeight + 10
                    color: "transparent"

                    Connections {
                        target: ScreenLifecycle
                        function onOutputAvailableChanged() {
                            if (!ScreenLifecycle.outputAvailable)
                                trayTooltip.visible = false
                        }
                    }
                    anchor {
                        item: trayItem
                        edges: root.popupEdge
                        gravity: root.popupEdge
                        margins.top: root.dockHosted
                            && root.dockEdge === "bottom" ? -6 : 0
                        margins.bottom: root.dockHosted ? 0 : -6
                        margins.left: root.dockHosted
                            && root.dockEdge === "right" ? -6 : 0
                        margins.right: root.dockHosted
                            && root.dockEdge === "left" ? -6 : 0
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(0.18, 0.18, 0.20, 0.95)

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: trayItem.tooltip
                            color: "white"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        Repeater {
            id: trailingRepeater
            model: root.trailingComponents || []

            delegate: Loader {
                required property var modelData
                width: root.itemSize
                height: root.itemSize
                sourceComponent: modelData
            }
        }
    }

    function trailingItem(index) {
        const loader = trailingRepeater.itemAt(index)
        return loader?.item ?? null
    }
}
