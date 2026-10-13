import QtQuick
import Quickshell
import "."

ShellRoot {
    id: root
    property Item currentAnchor: first
    property Item replacement: null
    function require(condition, message) {
        if (!condition) { console.error(message); Qt.exit(1); }
    }
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 100; implicitHeight: 100
        Rectangle { id: first; width: 10; height: 10 }
    }
    Component { id: itemFactory; Item { width: 10; height: 10 } }
    PopupWindow {
        id: popup
        visible: false
        PopupAnchorBinding { popupAnchor: popup.anchor; sourceItem: root.currentAnchor }
    }
    Timer {
        interval: 150; running: true
        onTriggered: {
            root.require(popup.anchor.item === first, "initial item missing");
            root.currentAnchor = null;
            Qt.callLater(() => {
                root.require(popup.anchor.item === first, "null input must retain previous anchor");
                root.replacement = itemFactory.createObject(host.contentItem);
                root.currentAnchor = root.replacement;
                Qt.callLater(() => {
                    root.require(popup.anchor.item === root.replacement, "replacement item missing");
                    root.replacement.destroy();
                });
            });
        }
    }
    Timer {
        interval: 600; running: true
        onTriggered: {
            root.require(popup.anchor.item === null, "destroyed item must clear safely");
            console.info("PASS popup anchor null, replacement and destruction");
            Qt.quit();
        }
    }
}
