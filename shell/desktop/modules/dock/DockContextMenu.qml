import QtQuick
import Qt.labs.platform as Platform

// A platform context menu: the window system owns pointer grabs and outside
// clicks, rather than a separate self-drawn PopupWindow surface.
Platform.Menu {
    id: menu

    property bool isWindow: false
    property bool isPinned: false
    property string appId: ""
    property string windowId: ""

    signal action(string name)

    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            menu.open()
        else
            menu.close()
    }

    function dismissDockPopupImmediately() {
        menu.close()
    }

    function trigger(name) {
        menu.close()
        menu.action(name)
    }

    Platform.MenuItem {
        icon.name: "window-restore"
        text: "激活窗口"
        visible: menu.isWindow
        onTriggered: menu.trigger("activate")
    }
    Platform.MenuItem {
        icon.name: "window-minimize"
        text: "最小化"
        visible: menu.isWindow
        onTriggered: menu.trigger("minimize")
    }
    Platform.MenuItem {
        icon.name: "window-close"
        text: "关闭窗口"
        visible: menu.isWindow
        onTriggered: menu.trigger("close")
    }
    Platform.MenuItem {
        icon.name: menu.isPinned ? "pin" : "list-add"
        text: menu.isPinned ? "取消固定" : "固定此应用"
        visible: menu.isWindow
        onTriggered: menu.trigger(menu.isPinned ? "unpin" : "pin")
    }
    Platform.MenuItem {
        icon.name: "document-open"
        text: "打开"
        visible: !menu.isWindow
        onTriggered: menu.trigger("open")
    }
    Platform.MenuItem {
        icon.name: "list-add"
        text: "固定此应用"
        visible: !menu.isWindow && !menu.isPinned
        onTriggered: menu.trigger("pin")
    }
    Platform.MenuItem {
        icon.name: "pin"
        text: "取消固定"
        visible: !menu.isWindow && menu.isPinned
        onTriggered: menu.trigger("unpin")
    }
}
