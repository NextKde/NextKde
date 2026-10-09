import QtQuick

Item {
    id: control

    property bool checked: false
    property bool darkMode: false
    signal toggled(bool checked)

    implicitWidth: 20
    implicitHeight: 20
    activeFocusOnTab: enabled

    function toggle() {
        if (!enabled)
            return
        checked = !checked
        toggled(checked)
    }

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: control.checked ? AppTheme.accent : (control.darkMode ? "#46515a" : "#f7f7f8")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? AppTheme.accent : (control.checked ? AppTheme.accent : "#b7bbc0")
        Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }

        Text {
            anchors.centerIn: parent
            text: "✓"
            visible: control.checked
            color: "white"
            font.family: AppTheme.fontFamily
            font.pixelSize: 14
            font.weight: Font.Bold
        }
    }

    HoverHandler { id: hoverHandler }
    TapHandler { onPressedChanged: if (pressed) control.forceActiveFocus(); onTapped: control.toggle() }
    Keys.onSpacePressed: control.toggle()
    Keys.onReturnPressed: control.toggle()

    opacity: enabled ? (hoverHandler.hovered ? 1 : 0.96) : 0.48
}
