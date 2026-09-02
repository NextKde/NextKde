import QtQuick
import QtQml.Models

// Literal adaptation of Qt's DragHandler/GridView ordering example.
// The surrounding panel only supplies its size: this component intentionally
// has no desktop-file, selection, menu, persistence, or folder-drop logic.
GridView {
    id: root

    cellWidth: 80
    cellHeight: 80
    interactive: false

    displaced: Transition {
        NumberAnimation {
            properties: "x,y"
            easing.type: Easing.OutQuad
        }
    }

    model: DelegateModel {
        id: visualModel
        model: 24

        delegate: DropArea {
            id: delegateRoot

            width: 80
            height: 80

            onEntered: drag => {
                visualModel.items.move(
                    drag.source.DelegateModel.itemsIndex,
                    icon.DelegateModel.itemsIndex)
            }

            Rectangle {
                id: icon

                objectName: DelegateModel.itemsIndex
                property string text
                width: 72
                height: 72
                radius: 3
                Component.onCompleted: {
                    color = Qt.rgba(
                        0.2 + (48 - DelegateModel.itemsIndex) * Math.random() / 48,
                        0.3 + DelegateModel.itemsIndex * Math.random() / 48,
                        0.4 * Math.random(),
                        1.0)
                    text = DelegateModel.itemsIndex
                }
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }

                states: [
                    State {
                        when: dragHandler.active
                        ParentChange {
                            target: icon
                            parent: root
                        }
                        AnchorChanges {
                            target: icon
                            anchors {
                                horizontalCenter: undefined
                                verticalCenter: undefined
                            }
                        }
                    }
                ]

                Text {
                    anchors.centerIn: parent
                    color: "white"
                    font.pointSize: 14
                    text: icon.text
                }

                DragHandler {
                    id: dragHandler
                }

                Drag.active: dragHandler.active
                Drag.source: icon
                Drag.hotSpot.x: 36
                Drag.hotSpot.y: 36
            }
        }
    }
}
