import QtQuick

Item {
    id: control

    property bool checked: false
    property bool controlled: false
    property bool darkMode: false
    signal toggled(bool checked)

    implicitWidth: 48
    implicitHeight: 26
    activeFocusOnTab: enabled

    function toggle() {
        if (!enabled)
            return
        const next = !checked
        if (!controlled) checked = next
        toggled(next)
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: !control.enabled ? (control.darkMode ? "#45505a" : "#d8dadd")
                                : control.checked ? "#34c759"
                                                  : (control.darkMode ? "#59636c" : "#c7c9cc")
        border.width: control.activeFocus ? 2 : 0
        border.color: AppTheme.accent
        Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }

        Rectangle {
            width: 22
            height: 22
            radius: 11
            x: control.checked ? parent.width - width - 2 : 2
            y: 2
            color: "white"
            border.width: 1
            border.color: "#16000000"
            Behavior on x { NumberAnimation { duration: AppTheme.duration(150); easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler { id: hoverHandler }
    TapHandler { onPressedChanged: if (pressed) control.forceActiveFocus(); onTapped: control.toggle() }
    Keys.onSpacePressed: control.toggle()
    Keys.onReturnPressed: control.toggle()

    opacity: enabled ? (hoverHandler.hovered ? 1 : 0.96) : 0.48
}
