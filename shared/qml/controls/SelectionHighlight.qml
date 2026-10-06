import QtQuick

// A lightweight glass selection plate. All feedback changes paint/opacity;
// the owning control alone controls geometry and its stable hit-test area.
// No blur, shader, layer texture or continuous animation is needed here.
Item {
    id: plate

    property bool hovered: false
    property bool selected: false
    property bool pressed: false
    property bool dark: true
    property real cornerRadius: width * 0.30
    property int fadeDuration: 140
    property int pressDuration: 80
    // Overlay hosts can keep semantic state colours and text fully legible.
    property real fillStrength: 1.0

    readonly property bool highlighted: enabled && (hovered || selected || pressed)
    property real presence: highlighted ? 1 : 0
    property real hoverAmount: enabled && hovered ? 1 : 0
    property real selectionAmount: enabled && selected ? 1 : 0
    property real pressAmount: enabled && pressed ? 1 : 0

    // The active app has a quieter resting plate; hovering it adds a brighter
    // rim rather than stacking another opaque rectangle over its background.
    readonly property real topAlpha: (dark ? 0.08 : 0.28)
        + selectionAmount * 0.04 + hoverAmount * 0.10 + pressAmount * 0.10
    readonly property real bottomAlpha: (dark ? 0.02 : 0.06)
        + selectionAmount * 0.025 + hoverAmount * 0.025 + pressAmount * 0.045
    readonly property real rimAlpha: (dark ? 0.16 : 0.36)
        + selectionAmount * 0.08 + hoverAmount * 0.12 + pressAmount * 0.12

    opacity: presence
    visible: enabled && opacity > 0
    Behavior on presence {
        NumberAnimation { duration: plate.fadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on hoverAmount {
        NumberAnimation { duration: plate.fadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on selectionAmount {
        NumberAnimation { duration: plate.fadeDuration; easing.type: Easing.OutCubic }
    }
    Behavior on pressAmount {
        NumberAnimation { duration: plate.pressDuration; easing.type: Easing.OutCubic }
    }

    // A one-pixel lower contour keeps the white plate legible on light glass.
    // This is a border, not a blurred drop shadow or an offscreen pass.
    Rectangle {
        x: 0
        y: 1
        width: parent.width
        height: parent.height
        radius: plate.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, plate.dark ? 0.12 : 0.16)
    }
    Rectangle {
        anchors.fill: parent
        radius: plate.cornerRadius
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, plate.topAlpha * plate.fillStrength) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, plate.bottomAlpha * plate.fillStrength) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, (plate.bottomAlpha + 0.025) * plate.fillStrength) }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, plate.rimAlpha)
    }
    // Restrained specular reflection across the flat part of the top rim.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: Math.max(0, parent.width - plate.cornerRadius * 2)
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Math.min(0.8, plate.rimAlpha + 0.24)) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
