import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common

// All component choices are compiled host components. node was bounded and
// copied by PluginWidgetView; no source/sourceComponent comes from the plugin.
Item {
    id: root
    property var node: ({})
    property bool interactive: true
    signal actionRequested(string actionId)
    implicitHeight: content.item?.implicitHeight || 0
    Loader {
        id: content
        width: parent.width
        sourceComponent: root.node.type === "column" ? columnNode
            : root.node.type === "row" ? rowNode
            : root.node.type === "text" ? textNode
            : root.node.type === "value" ? valueNode
            : root.node.type === "button" ? buttonNode : null
    }
    Component {
        id: columnNode
        Column {
            spacing: 8
            Repeater {
                model: root.node.children || []
                delegate: childNodeLoader
            }
        }
    }
    Component {
        id: rowNode
        Row {
            spacing: 8
            Repeater {
                model: root.node.children || []
                delegate: childNodeLoader
            }
        }
    }
    // Defer recursion until a bounded child exists. A static reference to this
    // QML type would make its type compilation recursively depend on itself.
    // This host-owned literal is never supplied or influenced by plugin data.
    Component {
        id: childNodeLoader
        Loader {
            id: child
            required property var modelData
            width: root.node.type === "row"
                ? Math.max(0, (parent.width - Math.max(0, (root.node.children?.length || 0) - 1) * 8)
                    / Math.max(1, root.node.children?.length || 0))
                : parent.width
            height: item?.implicitHeight || 0
            Component.onCompleted: setSource(Qt.resolvedUrl("PluginViewNode.qml"), {
                node: Qt.binding(function() { return child.modelData }),
                interactive: Qt.binding(function() { return root.interactive })
            })
            Connections {
                target: child.item
                function onActionRequested(actionId) { root.actionRequested(actionId) }
            }
        }
    }
    Component {
        id: textNode
        Text {
            text: root.node.text || ""
            textFormat: Text.PlainText
            color: AppearanceTokens.surface.widgetForeground
            font.pixelSize: 13
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }
    }
    Component {
        id: valueNode
        Column {
            spacing: 3
            Text {
                width: parent.width
                visible: text.length > 0
                text: root.node.label || ""
                textFormat: Text.PlainText
                color: AppearanceTokens.surface.widgetForeground
                opacity: 0.7
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.node.available ? String(root.node.value || "") + String(root.node.suffix || "") : "—"
                textFormat: Text.PlainText
                color: AppearanceTokens.surface.widgetForeground
                font { pixelSize: 21; weight: Font.DemiBold }
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
            }
        }
    }
    Component {
        id: buttonNode
        Controls.Button {
            implicitHeight: 34
            enabled: root.interactive && !!root.node.actionId
            focusPolicy: Qt.StrongFocus
            Accessible.name: String(root.node.text || "")
            contentItem: Text {
                text: root.node.text || ""
                textFormat: Text.PlainText
                color: AppearanceTokens.surface.widgetForeground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            background: Rectangle {
                radius: 8
                color: parent.down ? AppearanceTokens.colors.primaryContainer : AppearanceTokens.colors.layer2
                border.width: parent.activeFocus ? 2 : 1
                border.color: parent.activeFocus ? AppearanceTokens.colors.primary : AppearanceTokens.colors.outlineVariant
            }
            onClicked: root.actionRequested(String(root.node.actionId))
        }
    }
}
