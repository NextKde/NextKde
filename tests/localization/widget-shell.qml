import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
    DeskCenterWindow { id: desktop; WlrLayershell.layer: WlrLayer.Overlay }
    Window {
        id: renderWindow
        visible: true
        width: Math.max(640, desktop.width); height: Math.max(480, desktop.height)
        color: "#303945"
        Item { id: renderRoot; anchors.fill: parent }
    }
    property int phase: 0
    property int pending: 0
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function capture(item, suffix) {
        pending++
        item.grabToImage(function(result) {
            const ok = result.saveToFile(Quickshell.env("LANGUAGE_SCREENSHOT").replace(".png", "-" + suffix + ".png"))
            console.log("LANGUAGE_CAPTURE", ok, suffix)
            if (--test.pending === 0 && test.phase >= 5) Qt.quit()
        })
    }
    function inspect(item, result) {
        if (!item.visible || item.opacity === 0) return
        if (item.text !== undefined && item.text.length && item.contentWidth !== undefined) {
            const bounds = item.mapToItem(renderRoot, 0, 0)
            if (bounds.x >= 0 && bounds.y >= 0 && bounds.x < desktop.width && bounds.y < desktop.height)
                result.push({text: item.text, x: bounds.x, y: bounds.y, width: item.width, height: item.height,
                             contentWidth: item.contentWidth, contentHeight: item.contentHeight, elide: item.elide})
        }
        for (const child of item.children || []) inspect(child, result)
    }
    Timer {
        interval: 600
        running: true
        repeat: true
        onTriggered: {
            if (!AppearanceConfigService.ready || !IconAppearanceService.ready) return
            if (test.phase++ === 0) {
                ScreenLifecycle.activeScreen = desktop.screen
                AppearanceConfigService.updateWidgetStyle("color")
                for (const id of DeskCenterConfigService.defaultOrder) {
                    AppearanceConfigService.setDeskCenterWidgetVisible(id, true)
                    if (Quickshell.env("LANGUAGE_WIDGET_SIZE"))
                        DeskCenterConfigService.setSize(id, Quickshell.env("LANGUAGE_WIDGET_SIZE"))
                }
                desktop.enterWidgetEditMode(true)
                return
            }
            if (test.phase === 2) {
                // ProxyWindow content has no QML engine for grabToImage. Render the
                // actual items in a regular Qt window, preserving their geometry.
                const children = Array.from(desktop.contentItem.children)
                for (const child of children) child.parent = renderRoot
                return
            }
            if (test.phase < 4) return
            if (test.phase === 4) {
                test.capture(test.find(renderRoot, "widget-library"), "library")
                desktop.editMode = false
                desktop.widgetLibraryOpen = false
                return
            }
            const rows = []
            test.inspect(renderRoot, rows)
            console.log("LANGUAGE_LAYOUT", JSON.stringify({chinese: I18n.chinese, rows: rows}))
            stop()
            const cards = test.find(renderRoot, "desktop-widget-repeater")
            for (let i = 0; i < cards.count; i++) {
                const card = cards.itemAt(i)
                if (card.visible) test.capture(card, card.modelData.id)
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: Qt.quit() }
}
