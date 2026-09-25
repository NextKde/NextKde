import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import qs.desktop.modules.common

AbstractButton {
    id: root

    property string iconName: "media-play"
    property bool primary: false
    property bool busy: false
    property real iconSize: primary ? 18 : 16
    property color glassInk: "white"
    readonly property color ink: AppearanceTokens.surface.pick(
        (primary || checked) ? AppearanceTokens.colors.primaryContainerForeground
                : AppearanceTokens.colors.secondaryContainerForeground, glassInk)
    readonly property color fill: AppearanceTokens.surface.pick(
        (primary || checked) ? AppearanceTokens.colors.primaryContainer
                : AppearanceTokens.colors.secondaryContainer,
        Qt.rgba(1, 1, 1, (primary || checked) ? 0.20 : 0.09))

    implicitWidth: 36
    implicitHeight: 36
    hoverEnabled: true
    padding: 0
    Accessible.name: text
    opacity: enabled ? 1 : 0.32
    Behavior on opacity { NumberAnimation { duration: 120 } }

    // The hit target stays fixed; the disc and icon move together, without a
    // circle-to-square morph or a font fallback changing the glyph's baseline.
    background: Item {}
    contentItem: Item {
        Item {
            anchors.centerIn: parent
            width: Math.max(16, Math.min(root.width, root.height) - (root.primary ? 2 : 6))
            height: width
            scale: root.down ? 0.94 : 1
            Behavior on scale {
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.fill
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: root.ink
                    opacity: root.down ? 0.14 : root.hovered ? 0.08 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                border.width: root.visualFocus ? 2 : 0
                border.color: root.ink
            }
            Basic.BusyIndicator {
                anchors.centerIn: parent
                width: parent.width; height: width
                running: root.busy
                visible: running
            }
            BundledIcon {
                anchors.centerIn: parent
                name: root.iconName
                color: root.ink
                size: root.iconSize
                visible: !root.busy
            }
        }
    }

    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    ToolTip.visible: hovered && enabled
    ToolTip.delay: 650
    ToolTip.text: text
}
