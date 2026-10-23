import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

TextField {
    id: root
    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    property color glassColor: Qt.rgba(1, 1, 1, 0.10)
    property real cornerRadius: height
    property color outlineColor: Qt.rgba(1, 1, 1, 0.08)
    property color focusedOutlineColor: Qt.rgba(1, 1, 1, 0.24)
    property color textColor: "#f5f5f7"
    property color mutedTextColor: "#98989d"
    property bool materialForm: ControlForm.materialForm
    property bool liquidFinish: false
    property real liquidStrength: 1
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    property bool darkAppearance: Foundation.AppTheme.dark
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property real refractionStrength: 3
    property real magnification: 1.035
    property real blurStrength: 0.2
    property real readability: 0.15
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0
    readonly property bool sampling: _liquid && liquidSurface.sampling
    readonly property bool _liquid: liquidFinish && !materialForm
    readonly property color _fill: Qt.rgba(glassColor.r, glassColor.g, glassColor.b,
        Math.min(1, glassColor.a + (activeFocus ? 0.08 : hover.hovered ? 0.035 : 0)))

    color: textColor
    placeholderTextColor: mutedTextColor
    scale: activeFocus && !materialForm && !reduceMotion ? 1.02 : 1
    Behavior on scale {
        NumberAnimation {
            duration: root.reduceMotion ? 0 : 300
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.25, 0.8, 0.25, 1, 1, 1]
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

    background: Item {
        Rectangle {
            anchors.fill: parent
            visible: !root._liquid
            radius: root.cornerRadius
            color: root._fill
            border.width: 1
            border.color: root.activeFocus ? root.focusedOutlineColor : root.outlineColor
            Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 150 } }
            Behavior on border.color { ColorAnimation { duration: root.reduceMotion ? 0 : 150 } }
        }
        LiquidSurface {
            id: liquidSurface
            anchors.fill: parent
            visible: root._liquid
            radius: root.cornerRadius
            backdrop: root.backdrop
            darkAppearance: root.darkAppearance
            tintColor: Qt.rgba(root._fill.r, root._fill.g, root._fill.b, 1)
            tintStrength: root._fill.a
            blurStrength: root.blurStrength
            readability: root.readability
            refractionStrength: root.refractionStrength * Math.max(0, Math.min(1, root.liquidStrength))
            magnification: 1 + (root.magnification - 1) * Math.max(0, Math.min(1, root.liquidStrength))
            edgeWidth: Math.min(12, height / 2)
            reflectionStrength: root.liquidStrength
            rimColor: root.activeFocus ? root.focusedOutlineColor : root.outlineColor
        }
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            visible: root._liquid && root.ambientStrength > 0
            opacity: Math.max(0, Math.min(1, root.liquidStrength))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(root.ambientPrimary.r, root.ambientPrimary.g, root.ambientPrimary.b, root.ambientStrength * 0.28) }
                GradientStop { position: 0.56; color: Qt.rgba(root.ambientSecondary.r, root.ambientSecondary.g, root.ambientSecondary.b, root.ambientStrength * 0.16) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
