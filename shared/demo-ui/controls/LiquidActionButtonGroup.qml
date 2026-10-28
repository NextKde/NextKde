import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// A shared surface for adjacent icon actions. The host owns each action.
Item {
    id: root

    property var icons: []
    property var labels: []
    property var enabledActions: []
    property int buttonSize: 26
    property bool materialForm: ControlForm.materialForm
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property color surfaceColor: Foundation.AppTheme.controlBackground
    property color dividerColor: Foundation.AppTheme.border

    signal triggered(int index)

    implicitWidth: icons.length * buttonSize
    implicitHeight: buttonSize
    clip: true

    // One shared material keeps the buttons visually joined.
    LiquidActionButton {
        anchors.fill: parent
        enabled: false
        Accessible.ignored: true
        materialForm: root.materialForm
        backdrop: root.backdrop
        surfaceColor: root.surfaceColor
        cornerRadius: root.materialForm ? 6 : height / 2
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: root.icons.length
            delegate: Item {
                required property int index
                width: root.buttonSize
                height: root.buttonSize

                LiquidActionButton {
                    id: action
                    anchors.fill: parent
                    enabled: root.enabledActions[index] !== false
                    materialForm: true
                    flat: true
                    surfaceColor: "transparent"
                    cornerRadius: 0
                    focusRingColor: "transparent"
                    iconOnly: true
                    iconName: root.icons[index]
                    iconSize: 16
                    iconColor: !enabled ? Foundation.AppTheme.disabledText : root.materialForm
                        ? (Foundation.AppTheme.dark ? Foundation.AppTheme.text : "#000000")
                        : (Foundation.AppTheme.dark ? "#D6D6DA" : "#55555A")
                    // Extend the inner end past its cell and clip it there:
                    // only the group's two outside ends remain rounded.
                    background: Item {
                        clip: true
                        Rectangle {
                            readonly property bool outerEnd: index === 0 || index === root.icons.length - 1
                            radius: outerEnd ? (root.materialForm ? 6 : height / 2) : 0
                            x: index > 0 && index === root.icons.length - 1 ? -radius : 0
                            width: parent.width + (outerEnd && root.icons.length > 1 ? radius : 0)
                            height: parent.height
                            color: Foundation.AppTheme.text
                            opacity: !action.enabled ? 0 : action.down ? .13 : action.hovered ? .07 : 0
                            antialiasing: true
                        }
                    }
                    Accessible.name: root.labels[index] || root.icons[index]
                    Foundation.KosToolTip { target: action; text: action.Accessible.name }
                    onClicked: root.triggered(index)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 4
                    color: "transparent"
                    border.width: 2
                    border.color: Foundation.AppTheme.focusRing
                    visible: root.materialForm && action.activeFocus
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height - 10
                    color: root.dividerColor
                    visible: index > 0
                }
            }
        }
    }
}
