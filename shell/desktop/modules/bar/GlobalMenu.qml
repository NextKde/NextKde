import QtQuick
import Quickshell
import qs.desktop
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform

// Native renderer for the active KDE AppMenu. The platform daemon translates
// the DBusMenu wire format to plain QML data; this keeps D-Bus parsing and
// trust boundaries out of the visual shell.
Item {
    id: root

    property int maximumWidth: 0
    readonly property string service: AppMenuService.dbusService
    readonly property string path: AppMenuService.dbusPath
    readonly property var items: AppMenuService.items
    property int popupRootId: 0
    property int visibleCount: 0

    readonly property bool available: service.length > 0 && path.length > 0
    readonly property var shownItems: items.slice(0, visibleCount)
    readonly property var overflowItems: items.slice(visibleCount)
    implicitHeight: 28
    implicitWidth: available && items.length > 0
        ? Math.min(maximumWidth, menuRow.implicitWidth + (overflowItems.length > 0 ? 34 : 0)) : 0
    width: implicitWidth
    visible: true

    FontMetrics {
        id: labelMetrics
        font.family: "SF Pro Display, Noto Sans CJK SC, sans-serif"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

    function itemWidth(item) {
        return Math.max(32, labelMetrics.advanceWidth(item?.label || "") + 18)
    }

    function updateVisibleCount() {
        let used = 0
        let count = 0
        const reserve = items.length > 0 ? 34 : 0
        for (let i = 0; i < items.length; ++i) {
            const next = itemWidth(items[i]) + (count > 0 ? 1 : 0)
            if (used + next + reserve > maximumWidth)
                break
            used += next
            count++
        }
        // Avoid an orphaned overflow button: if all entries fit, show them all.
        if (count === items.length)
            visibleCount = count
        else
            visibleCount = Math.max(0, count)
    }

    // ContextMenu has a synchronous page stack. Hydrate children before it is
    // shown, with a small depth limit to keep malformed menus bounded.
    function hydrate(itemsToHydrate, depth, done) {
        if (depth >= 4 || !itemsToHydrate || itemsToHydrate.length === 0) {
            done(itemsToHydrate || [])
            return
        }
        let pending = 0
        const finish = function() {
            pending--
            if (pending === 0)
                done(itemsToHydrate)
        }
        for (let i = 0; i < itemsToHydrate.length; ++i) {
            const item = itemsToHydrate[i]
            if (!item?.hasChildren) {
                item.children = []
                continue
            }
            pending++
            AppMenuService.requestLayout(item.id, function(children) {
                hydrate(children, depth + 1, function(result) {
                    item.children = result
                    finish()
                })
            })
        }
        if (pending === 0)
            done(itemsToHydrate)
    }

    function openItem(item) {
        if (!item || !item.enabled)
            return
        console.info("[GlobalMenu] click id=" + item.id + " children=" + item.hasChildren)
        if (!item.hasChildren) {
            PlatformClient.request("appmenu.trigger", { service, path, id: item.id })
            return
        }
        PlatformClient.request("appmenu.open", { service, path, id: item.id })
        AppMenuService.requestLayout(item.id, function(children) {
            hydrate(children, 0, function(result) {
                popupRootId = item.id
                menuPopup.setItems(result)
                console.info("[GlobalMenu] popup items=" + result.length)
                menuPopup.show()
            })
        })
    }

    onMaximumWidthChanged: updateVisibleCount()
    onItemsChanged: updateVisibleCount()

    Row {
        id: menuRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Repeater {
            model: root.shownItems
            delegate: Item {
                required property var modelData
                width: root.itemWidth(modelData)
                height: 28
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: pointer.containsMouse ? Qt.rgba(ThemeService.foregroundColor.r,
                        ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.16) : "transparent"
                }
                Text {
                    anchors.centerIn: parent
                    text: modelData.label || ""
                    color: ThemeService.foregroundColor
                    font: labelMetrics.font
                    elide: Text.ElideRight
                    width: parent.width - 14
                    horizontalAlignment: Text.AlignHCenter
                }
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.enabled !== false
                    onClicked: root.openItem(modelData)
                }
            }
        }
        Item {
            visible: root.overflowItems.length > 0
            width: visible ? 33 : 0
            height: 28
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: morePointer.containsMouse ? Qt.rgba(ThemeService.foregroundColor.r,
                    ThemeService.foregroundColor.g, ThemeService.foregroundColor.b, 0.16) : "transparent"
            }
            Text { anchors.centerIn: parent; text: "››"; color: ThemeService.foregroundColor; font.pixelSize: 16 }
            MouseArea {
                id: morePointer
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.hydrate(root.overflowItems, 0, function(result) {
                        root.popupRootId = 0
                        menuPopup.setItems(result)
                        menuPopup.show()
                    })
                }
            }
        }
    }

    ContextMenu {
        id: menuPopup
        anchorItem: root
        position: "bottom"
        placeBelow: true
        globalDismissGraceMs: 250
        dismissOnGlobalPointerPress: false
        onAction: function(cmd, item) {
            console.info("[GlobalMenu] trigger id=" + item.id)
            PlatformClient.request("appmenu.trigger", { service: root.service, path: root.path, id: item.id }, function(response) {
                console.info("[GlobalMenu] trigger result=" + (response?.ok ? "ok" : (response?.error?.code || "failed")))
            })
        }
        onAboutToHide: PlatformClient.request("appmenu.close", {
            service: root.service, path: root.path, id: root.popupRootId
        })
        onVisibleChanged: console.info("[GlobalMenu] popup visible=" + visible)
    }
}
