import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

Button {
    id: root
    checkable: true
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property string iconName: ""
    property url iconSource: ""
    property color iconColor: Foundation.AppTheme.accent
    property real cornerRadius: height / 2
    property color selectionColor: Foundation.AppTheme.accent
    property color hoverColor: Foundation.AppTheme.withAlpha(Foundation.AppTheme.text, 0.07)
    property color focusRingColor: Foundation.AppTheme.focusRing
    property bool keyboardFocusOnly: false
    property bool showIdleBackground: true
    // Opt-in pilot: plain rows inside a host-owned sidebar material.
    // Existing applications retain their current liquid navigation by default.
    property bool specificationForm: false
    readonly property QtObject specification: QtObject {
        readonly property int rowHeight: 30
        readonly property int radius: 8
        readonly property int fontSize: 14
        readonly property int focusWidth: 2
        readonly property int focusOffset: 2
        readonly property int pressDuration: 100
        readonly property int hoverDuration: 150
        readonly property real pressScale: .96
        readonly property real selectedAlpha: .13
        readonly property color hoverFill: Foundation.AppTheme.dark
            ? Qt.rgba(1, 1, 1, .08) : Qt.rgba(0, 0, 0, .06)
        readonly property color pressFill: Foundation.AppTheme.dark
            ? Qt.rgba(1, 1, 1, .12) : Qt.rgba(0, 0, 0, .10)
    }
    implicitHeight: specificationForm ? specification.rowHeight : 38
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    font.weight: checked ? Font.DemiBold : Font.Normal
    Binding {
        target: root
        property: "font.pixelSize"
        value: root.specification.fontSize
        when: root.specificationForm
        restoreMode: Binding.RestoreBindingOrValue
    }
    scale: specificationForm && down && !Foundation.AppTheme.reduceMotion ? specification.pressScale : 1
    Behavior on scale {
        NumberAnimation {
            duration: Foundation.AppTheme.reduceMotion ? 0 : root.specification.pressDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [.2, 0, 0, 1, 1, 1]
        }
    }
    contentItem: Item {
        implicitWidth: caption.implicitWidth + (root.iconName.length ? 26 : 0)
        implicitHeight: Math.max(caption.implicitHeight, 16)
        VectorIcon {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            visible: root.iconName.length > 0 && !root.iconSource.toString().length
            name: root.iconName; size: 16; color: root.iconColor
        }
        Image {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            visible: root.iconSource.toString().length > 0
            source: root.iconSource
            sourceSize: Qt.size(32, 32)
        }
        Text {
            id: caption
            anchors.fill: parent; anchors.leftMargin: root.iconName.length ? 26 : 0
            text: root.text
            color: root.specificationForm
                ? (Foundation.AppTheme.dark ? Qt.rgba(1, 1, 1, .92) : Qt.rgba(0, 0, 0, .92))
                : Foundation.AppTheme.text
            font: root.font
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
        }
    }
    background: Item {
        Rectangle {
            anchors.fill: parent
            visible: root.specificationForm
            radius: root.specification.radius
            color: root.checked
                ? Foundation.AppTheme.withAlpha(root.selectionColor, root.specification.selectedAlpha)
                : "transparent"
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: root.down ? root.specification.pressFill : root.hovered ? root.specification.hoverFill : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: Foundation.AppTheme.reduceMotion ? 0 : root.specification.hoverDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [.2, 0, 0, 1, 1, 1]
                    }
                }
            }
        }
        LiquidSurface {
            anchors.fill: parent
            visible: !root.specificationForm && (root.showIdleBackground || root.checked || root.hovered || root.down)
            scale: root.down ? 1.10 : 1
            Behavior on scale {
                NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast; easing.type: Easing.OutBack }
            }
            radius: root.cornerRadius
            backdrop: root.backdrop
            convexLens: true
            edgeShadeStrength: .08
            blurStrength: 0
            readability: 0
            edgeWidth: Math.min(10, height * .28)
            refractionStrength: root.hovered ? 4.5 : 3
            magnification: root.hovered ? 1.045 : 1.025
            reflectionStrength: root.hovered ? .72 : .50
            tintColor: root.down ? "#ffffff" : root.checked ? root.selectionColor : (Foundation.AppTheme.dark ? "#20252f" : "#ffffff")
            tintStrength: root.down ? .06 : root.checked ? .80 : .30
            Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: root.specificationForm ? -(root.specification.focusOffset + root.specification.focusWidth) : 0
            radius: root.specificationForm ? root.specification.radius + root.specification.focusOffset : root.cornerRadius
            color: "transparent"
            border.width: 2
            border.color: root.focusRingColor
            visible: root.specificationForm && root.visualFocus
        }
    }
    opacity: enabled ? 1 : 0.38
}
