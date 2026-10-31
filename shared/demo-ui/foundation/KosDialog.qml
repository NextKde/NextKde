import QtQuick
import QtQuick.Controls

Dialog {
    id: root

    property real revealProgress: 0
    property bool closing: false
    opacity: revealProgress
    scale: AppTheme.reduceMotion ? 1 : 0.96 + 0.04 * revealProgress
    enabled: !closing
    onAboutToShow: closing = false
    onAboutToHide: closing = true

    enter: Transition {
        NumberAnimation {
            target: root
            property: "revealProgress"
            to: 1
            duration: AppTheme.motionNormal
            easing.type: Easing.OutCubic
        }
    }
    exit: Transition {
        NumberAnimation {
            target: root
            property: "revealProgress"
            to: 0
            duration: AppTheme.motionFast
            easing.type: Easing.InCubic
        }
    }
}
