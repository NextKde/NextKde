import QtQuick
import org.kde.kwin as KWin
import org.kde.plasma.workspace.dbus as DBus

// KWin retains its grab, MRU order, wraparound and release-to-activate logic.
// Only presentation crosses the existing window bridge; no keys are rebound.
KWin.TabBoxSwitcher {
    id: tabbox

    item: Item {
        id: adapter
        property int sequence: 0
        property string session: ""

        function publish() {
            const ids = []
            for (let i = 0; i < windows.count; ++i) {
                const row = windows.objectAt(i)
                if (row)
                    ids.push(row.handle)
            }
            DBus.SessionBus.asyncCall({
                service: "org.kos.Platform", path: "/Platform", iface: "org.kos.Platform",
                member: "Publish", arguments: [JSON.stringify({
                    type: "switcher", session: session, sequence: ++sequence,
                    visible: tabbox.visible, handles: ids,
                    selected: ids[tabbox.currentIndex] || "",
                    screen: { x: tabbox.screenGeometry.x, y: tabbox.screenGeometry.y,
                        width: tabbox.screenGeometry.width, height: tabbox.screenGeometry.height }
                })]
            })
        }

        Instantiator {
            id: windows
            model: tabbox.model
            delegate: QtObject {
                required property var windowId
                readonly property string handle: String(windowId).replace(/[{}]/g, "")
            }
            onObjectAdded: Qt.callLater(adapter.publish)
            onObjectRemoved: Qt.callLater(adapter.publish)
        }
        Connections {
            target: tabbox
            function onVisibleChanged() {
                if (tabbox.visible)
                    adapter.session = String(Date.now())
                adapter.publish()
            }
            function onCurrentIndexChanged() { adapter.publish() }
        }
        // A lease lets the shell dismiss after a compositor/transport failure.
        Timer {
            interval: 200
            running: tabbox.visible
            repeat: true
            onTriggered: adapter.publish()
        }
    }
}
