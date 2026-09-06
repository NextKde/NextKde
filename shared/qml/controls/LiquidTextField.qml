import QtQuick
import QtQuick.Controls

// A compact glass field for search and inline text entry. It avoids a bright
// desktop-style focus outline; focus is communicated by a lifted material, a
// thin tinted inner edge and a gentle liquid scale-up instead. The launcher
// already owns the backdrop material, so this control must not paint a dark
// client-side shadow behind the field.
TextField {
    id: root

    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    property color glassColor: Qt.rgba(1, 1, 1, 0.10)
    property color textColor: "#f5f5f7"
    property color mutedTextColor: "#98989d"
    // Opt-in material finish for glass surfaces that already have compositor
    // backdrop sampling. Keep it off for ordinary application text fields.
    property bool liquidFinish: false
    property real liquidStrength: 1.0
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0.0

    color: textColor
    placeholderTextColor: mutedTextColor

    // Liquid focus expansion, matching the reference's
    // cubic-bezier(0.25, 0.8, 0.25, 1) over 300ms.
    scale: activeFocus ? 1.02 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 300
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.25, 0.8, 0.25, 1, 1, 1]
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.IBeamCursor
    }

    background: Rectangle {
        id: fieldSurface
        // A full-height radius produces the continuous pill silhouette used
        // by the launcher search field; Qt clamps it to a half-circle endcap.
        radius: height
        color: root.activeFocus
            ? Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b,
                      Math.min(1.0, root.glassColor.a + 0.08))
            : (hover.hovered
               ? Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b,
                         Math.min(1.0, root.glassColor.a + 0.035))
               : root.glassColor)
        border.width: 1
        border.color: root.activeFocus
            ? Qt.rgba(1, 1, 1, root.liquidFinish ? 0.38 : 0.24)
            : Qt.rgba(1, 1, 1, root.liquidFinish
                ? (hover.hovered ? 0.25 : 0.19) : (hover.hovered ? 0.13 : 0.08))

        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.activeFocus ? 0.16 : 0.10) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        // The launcher uses the same QML material vocabulary as the Control
        // Center cards: a broad upper reflection, restrained colour pickup,
        // and two narrow specular edges. KWin still supplies the real scene
        // blur/refraction beneath this visual finish.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.liquidFinish
            opacity: Math.max(0.0, Math.min(1.0, root.liquidStrength))
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.activeFocus ? 0.42 : 0.32) }
                GradientStop { position: 0.12; color: Qt.rgba(0.88, 0.94, 1, root.activeFocus ? 0.20 : 0.14) }
                GradientStop { position: 0.40; color: Qt.rgba(1, 1, 1, 0.035) }
                GradientStop { position: 0.72; color: Qt.rgba(0.86, 0.93, 1, 0.018) }
                GradientStop { position: 1.0; color: Qt.rgba(0.03, 0.06, 0.12, 0.08) }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.liquidFinish && root.ambientStrength > 0
            opacity: Math.max(0.0, Math.min(1.0, root.liquidStrength))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(root.ambientPrimary.r, root.ambientPrimary.g, root.ambientPrimary.b, root.ambientStrength * 0.28) }
                GradientStop { position: 0.56; color: Qt.rgba(root.ambientSecondary.r, root.ambientSecondary.g, root.ambientSecondary.b, root.ambientStrength * 0.16) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Rectangle {
            visible: root.liquidFinish
            x: Math.min(parent.width / 2, parent.radius + 3)
            y: 0.8
            width: Math.max(0, parent.width - x * 2)
            height: 0.9
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 0.18; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, root.activeFocus ? 0.62 : 0.48) }
                GradientStop { position: 0.82; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }

        Rectangle {
            visible: root.liquidFinish
            x: Math.min(parent.width / 2, parent.radius + 3)
            y: parent.height - 1.5
            width: Math.max(0, parent.width - x * 2)
            height: 0.8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.20; color: Qt.rgba(0.02, 0.05, 0.10, 0.10) }
                GradientStop { position: 0.50; color: Qt.rgba(0.02, 0.05, 0.10, 0.18) }
                GradientStop { position: 0.80; color: Qt.rgba(0.02, 0.05, 0.10, 0.10) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.0) }
            }
        }
    }
}
