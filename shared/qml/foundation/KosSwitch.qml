import QtQuick

Item {
    id: root

    property bool checked: false
    property string accessibleName: ""
    signal toggled(bool checked)

    implicitWidth: 48
    implicitHeight: 28
    opacity: enabled ? 1 : 0.48
    activeFocusOnTab: enabled

    Accessible.role: Accessible.CheckBox
    Accessible.name: accessibleName
    Accessible.checked: checked
    Accessible.focusable: enabled
    Accessible.focused: activeFocus
    Accessible.onPressAction: requestToggle()

    function requestToggle() {
        if (enabled)
            toggled(!checked)
    }

    Keys.onSpacePressed: requestToggle()
    Keys.onEnterPressed: requestToggle()
    Keys.onReturnPressed: requestToggle()

    SpringMotion {
        id: thumbMotion
        target: root.checked ? 1 : 0
        enabled: !AppTheme.reduceMotion && root.visible
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? AppTheme.accent
                            : AppTheme.mix(AppTheme.button, AppTheme.mutedText, 0.12)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus
            ? AppTheme.withAlpha(AppTheme.accent, 0.78) : AppTheme.border

        Behavior on color {
            ColorAnimation { duration: AppTheme.reduceMotion ? 0 : AppTheme.motionFast }
        }

        Rectangle {
            x: 3 + thumbMotion.value * (parent.width - width - 6)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - 6
            height: width
            radius: width / 2
            color: AppTheme.whiteSeed
            border.width: AppTheme.dark ? 0 : 1
            border.color: Qt.rgba(0, 0, 0, 0.10)
        }
    }

    HoverHandler { cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: root.enabled
        onTapped: {
            root.forceActiveFocus()
            root.requestToggle()
        }
    }
}
