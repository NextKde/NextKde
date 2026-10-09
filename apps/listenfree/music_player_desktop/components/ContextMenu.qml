pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Basic

FocusScope {
    id: menu

    property bool darkMode: AppTheme.darkMode
    property bool opened: false
    property real popupX: 0
    property real popupY: 0
    property real menuWidth: 218
    property var actions: []
    property var contextData: null

    signal commandTriggered(string command, var contextData)
    signal dismissed

    visible: opened
    focus: opened

    function openAt(x, y, data) {
        popupX = x
        popupY = y
        contextData = data
        opened = true
        forceActiveFocus()
    }

    function close() {
        if (!opened)
            return
        opened = false
        dismissed()
    }

    Keys.onEscapePressed: function(event) {
        close()
        event.accepted = true
    }

    Basic.Popup {
        id: popup
        objectName: "contextPopup"
        onOpened: AppTheme.presentPopup(popup)
        parent: Basic.Overlay.overlay
        popupType: Basic.Popup.Item
        visible: menu.opened
        modal: true
        dim: false
        focus: true
        padding: 0
        closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
        onClosed: {
            if (AppTheme.currentPopup === popup) AppTheme.currentPopup = null
            menu.close()
        }
        x: Math.max(8, Math.min(parent.width - width - 8, menu.mapToItem(parent, menu.popupX, menu.popupY).x))
        y: Math.max(8, Math.min(parent.height - height - 8, menu.mapToItem(parent, menu.popupX, menu.popupY).y))
        width: menu.menuWidth
        height: Math.max(0, Math.min(actionColumn.implicitHeight + 12, parent.height - 16))
        background: GlassSurface {
            cornerRadius: 14
            tint: AppTheme.cardStrong
            edgeColor: AppTheme.border
            shadowOpacity: .16
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: AppTheme.duration(120) } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: AppTheme.duration(100) } }

        Flickable {
            objectName: "contextMenuViewport"
            x: 6
            y: 6
            width: parent.width - 12
            height: Math.max(0, parent.height - 12)
            contentWidth: width
            contentHeight: actionColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: actionColumn
                width: parent.width

                Repeater {
                    model: menu.actions || []

                    delegate: Item {
                        id: actionItem
                        required property int index
                        required property var modelData

                        readonly property bool actionEnabled: modelData.enabled === undefined
                                                                      ? true : Boolean(modelData.enabled)
                        readonly property bool destructive: Boolean(modelData.destructive)
                        readonly property bool separatorBefore: Boolean(modelData.separatorBefore)

                        width: actionColumn.width
                        height: (separatorBefore ? 7 : 0) + 34

                        Rectangle {
                            visible: actionItem.separatorBefore
                            x: 8
                            y: 3
                            width: parent.width - 16
                            height: 1
                            color: AppTheme.divider
                        }

                        Rectangle {
                            x: 0
                            y: actionItem.separatorBefore ? 7 : 0
                            width: parent.width
                            height: 34
                            radius: 8
                            color: actionMouse.containsMouse && actionItem.actionEnabled
                                   ? (actionItem.destructive ? "#14d93025" : "#146b747d")
                                   : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: actionItem.modelData.label || actionItem.modelData.command || ""
                                color: !actionItem.actionEnabled ? AppTheme.textMuted
                                      : actionItem.destructive ? "#ff5f57" : AppTheme.textPrimary
                                font.family: AppTheme.fontFamily
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: actionItem.actionEnabled
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    const command = String(actionItem.modelData.command || "")
                                    const data = menu.contextData
                                    menu.opened = false
                                    if (command.length > 0)
                                        menu.commandTriggered(command, data)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
