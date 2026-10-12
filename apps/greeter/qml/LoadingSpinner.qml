import QtQuick

Item {
    id: root
    property bool running: true
    property bool reducedMotion: false
    implicitWidth: 28
    implicitHeight: 28
    Accessible.name: "正在加载"
    Accessible.role: Accessible.Indicator
    Item {
        id: wheel
        anchors.fill: parent
        Repeater {
            model: 12
            Rectangle {
                required property int index
                width: 2.5; height: 6; radius: 1.25
                x: (wheel.width - width) / 2; y: 1
                color: "white"; opacity: 0.2 + index / 15
                transform: Rotation {
                    origin.x: 1.25; origin.y: wheel.height / 2 - 1
                    angle: index * 30
                }
            }
        }
        NumberAnimation on rotation {
            from: 0; to: 360; duration: 900; loops: Animation.Infinite
            running: root.running && root.visible && !root.reducedMotion
        }
    }
}
