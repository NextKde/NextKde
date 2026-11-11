import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

Item {
    id: root
    property string instanceId: ""
    property bool interactive: true
    readonly property var instance: PluginWidgetService.instance(instanceId)
    readonly property bool ready: PluginWidgetService.available
        && ["ready", "permission-required"].indexOf(instance?.state) >= 0
    readonly property var tree: boundedTree(ready ? instance?.view : null)
    clip: true

    // Independent frontend limits protect the scene graph even if the daemon
    // returns malformed data. Copy only supported fields into a new tree.
    function boundedTree(source) {
        let budget = 64
        function visit(node, depth) {
            if (!node || typeof node !== "object" || depth > 8 || --budget < 0) return null
            const type = String(node.type || "")
            if (["column", "row", "text", "value", "button"].indexOf(type) < 0) return null
            const safe = {type}
            if (type === "row" || type === "column") {
                if (!Array.isArray(node.children) || node.children.length > 64) return null
                safe.children = []
                for (const child of node.children) {
                    const accepted = visit(child, depth + 1)
                    if (!accepted) return null
                    safe.children.push(accepted)
                }
            } else if (type === "text") safe.text = String(node.text || "").slice(0, 4096)
            else if (type === "button") {
                safe.text = String(node.text || "").slice(0, 256)
                safe.actionId = String(node.actionId || "").slice(0, 128)
            } else {
                safe.label = String(node.label || "").slice(0, 256)
                safe.value = String(node.value || "").slice(0, 4096)
                safe.suffix = String(node.suffix || "").slice(0, 64)
                safe.available = node.available === true
            }
            return safe
        }
        return visit(source, 1)
    }
    Column {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
        Text {
            width: parent.width
            text: root.instance?.name || I18n.tr("Widget")
            textFormat: Text.PlainText
            color: AppearanceTokens.surface.widgetForeground
            font { pixelSize: 12; weight: Font.DemiBold }
            elide: Text.ElideRight
        }
    }
    Flickable {
        id: scroll
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; margins: 16; topMargin: 12 }
        clip: true
        contentWidth: width
        contentHeight: treeNode.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.interactive && contentHeight > height
        visible: root.ready && root.tree !== null
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        PluginViewNode {
            id: treeNode
            width: scroll.width
            node: root.tree || ({})
            interactive: root.interactive && !PluginWidgetService.mutating
            onActionRequested: actionId => PluginWidgetService.action(root.instanceId, actionId)
        }
    }
    Column {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 18 }
        spacing: 10
        visible: !root.ready || root.tree === null
        Text {
            width: parent.width
            text: root.instance?.message || (!PluginWidgetService.available
                ? I18n.tr("Plugin service is unavailable") : I18n.tr("This widget is unavailable"))
            textFormat: Text.PlainText
            color: AppearanceTokens.surface.widgetForeground
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }
        Controls.Button {
            text: I18n.tr("Plugin Center")
            width: Math.min(implicitWidth, parent.width)
            enabled: root.interactive
            onClicked: PluginWidgetService.openCenter()
        }
    }
}
