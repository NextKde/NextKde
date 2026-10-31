import QtQuick

// Static comparison of the same settings scene. The host owns the choice button.
// Flat QML artwork, without gradients, live controls, captures or platform effects.
Item {
    id: root
    property string form: "macos"
    property bool darkAppearance: AppTheme.dark
    property string windowTitle: "Settings"
    property string settingTitle: "Appearance"
    readonly property bool material: form === "material"
    readonly property color ink: material
        ? (darkAppearance ? "#eee7ff" : "#393047")
        : (darkAppearance ? "#eeeeef" : "#343437")
    readonly property color accent: material
        ? (darkAppearance ? "#cbb8f0" : "#766097") : "#007aff"
    implicitWidth: 240
    implicitHeight: 108
    Accessible.ignored: true

    Item {
        id: scene
        width: 240
        height: 108
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        scale: Math.max(0, Math.min(root.width / width, root.height / height))
        transformOrigin: Item.Center
        readonly property int barHeight: root.material ? 26 : 20
        readonly property int sidebarWidth: root.material ? 44 : 58

        Rectangle {
            anchors.fill: parent
            radius: root.material ? 12 : 7
            color: root.material
                ? (root.darkAppearance ? "#27222f" : "#f7f2fa")
                : (root.darkAppearance ? "#252527" : "#ffffff")
        }
        Rectangle {
            x: 0; y: scene.barHeight
            width: scene.sidebarWidth
            height: scene.height - y
            radius: root.material ? 10 : 5
            color: root.material
                ? (root.darkAppearance ? "#302937" : "#eee7f4")
                : (root.darkAppearance ? "#303033" : "#ececeb")
        }
        Rectangle {
            width: parent.width
            height: scene.barHeight
            radius: root.material ? 10 : 5
            color: root.material
                ? (root.darkAppearance ? "#44364f" : "#e1d5ef")
                : (root.darkAppearance ? "#343437" : "#f2f2f2")
        }
        Row {
            visible: !root.material
            x: 9; y: 8
            spacing: 4
            Repeater {
                model: ["#ff6058", "#ffbd2e", "#28c840"]
                Rectangle {
                    required property string modelData
                    width: 5; height: 5; radius: 2.5
                    color: modelData
                }
            }
        }
        Column {
            visible: root.material
            x: 11; y: 10
            spacing: 2
            Repeater {
                model: 3
                Rectangle { width: 9; height: 1; radius: .5; color: root.ink }
            }
        }
        Text {
            x: root.material ? 28 : 45
            y: root.material ? 8 : 5
            text: root.windowTitle
            color: root.ink
            font.pixelSize: 8
            font.weight: Font.Medium
        }
        Row {
            visible: !root.material
            x: scene.width - 45; y: 5
            spacing: 4
            Repeater {
                model: ["‹", "+"]
                Rectangle {
                    required property string modelData
                    width: 16; height: 10; radius: 5
                    color: root.darkAppearance ? "#626267" : "#ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: root.ink
                        font.pixelSize: 9
                    }
                }
            }
        }
        Repeater {
            model: root.material ? 4 : 5
            Item {
                required property int index
                x: 7
                y: scene.barHeight + 8 + index * (root.material ? 17 : 13)
                width: scene.sidebarWidth - 14
                height: root.material ? 16 : 11
                Rectangle {
                    anchors.fill: parent
                    radius: root.material ? height / 2 : 3
                    color: index !== 0 ? "transparent" : root.material
                        ? (root.darkAppearance ? "#665277" : "#d6c6e9") : root.accent
                }
                Rectangle {
                    x: root.material ? (parent.width - width) / 2 : 4
                    y: (parent.height - height) / 2
                    width: root.material ? 6 : 5
                    height: width
                    radius: root.material ? 2 : 1.5
                    color: !root.material && index === 0 ? "#ffffff" : root.ink
                    opacity: index === 0 ? 1 : .45
                }
                Rectangle {
                    visible: !root.material
                    x: 14; y: 4.5
                    width: 22 - index % 2 * 5
                    height: 2; radius: 1
                    color: index === 0 ? "#ffffff" : root.ink
                    opacity: index === 0 ? .95 : .38
                }
            }
        }
        Text {
            x: scene.sidebarWidth + 10
            y: scene.barHeight + 6
            text: root.settingTitle
            color: root.ink
            font.pixelSize: 8
            font.weight: Font.DemiBold
        }
        Rectangle {
            id: settings
            x: scene.sidebarWidth + 10
            y: scene.barHeight + 23
            width: scene.width - x - 10
            height: scene.height - y - 8
            radius: root.material ? 12 : 5
            color: root.material
                ? (root.darkAppearance ? "#3c3346" : "#eae0f2")
                : (root.darkAppearance ? "#38383b" : "#f7f7f7")

            Rectangle { x: 10; y: 9; width: 38; height: 3; radius: 1.5; color: root.ink; opacity: .8 }
            Rectangle { x: 10; y: 16; width: 25; height: 2; radius: 1; color: root.ink; opacity: .25 }
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 10
                y: 7
                width: root.material ? 24 : 22
                height: root.material ? 12 : 10
                radius: height / 2
                color: root.accent
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - 3; height: width; radius: width / 2
                    color: root.material && root.darkAppearance ? "#44364f" : "#ffffff"
                }
            }
            Rectangle {
                visible: !root.material
                x: 10; y: 27
                width: parent.width - 20; height: .5
                color: root.darkAppearance ? "#55555a" : "#dedee0"
            }
            Rectangle { x: 10; y: parent.height - 17; width: 25; height: 3; radius: 1.5; color: root.ink; opacity: .65 }
            Rectangle {
                x: 52; y: parent.height - 17
                width: parent.width - x - 10; height: root.material ? 4 : 3
                radius: height / 2
                color: root.material
                    ? (root.darkAppearance ? "#71637c" : "#c8b8d9")
                    : (root.darkAppearance ? "#626269" : "#d5d5da")
                Rectangle { width: parent.width * .62; height: parent.height; radius: parent.radius; color: root.accent }
                Rectangle {
                    x: parent.width * .62 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.material ? 7 : 11
                    height: root.material ? 9 : 6
                    radius: root.material ? 3.5 : 3
                    color: root.material ? root.accent : "#ffffff"
                }
            }
        }
    }
}
