import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

Button {
    id: root
    property string liquidIntensity: LiquidStyle.intensityLevel
    readonly property var _intensity: LiquidStyle.intensityProfile(liquidIntensity)
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property bool materialForm: ControlForm.materialForm
    property bool secondary: false
    property bool destructive: false
    // Compact glyph actions keep their content centered without label insets.
    property bool shadowEnabled: false
    property int shadowLevel: LiquidStyle.shadowLevel
    property real shadowOpacity: LiquidStyle.shadowProfile(shadowLevel).opacity
    property bool convexLens: true
    property bool iconOnly: false
    property string iconName: ""
    property bool iconFilled: false
    property real iconSize: 16
    property color textColor: destructive ? Foundation.AppTheme.destructive : Foundation.AppTheme.text
    property color iconColor: textColor
    property color surfaceColor: Foundation.AppTheme.dark ? "#20252f" : "#ffffff"
    property color accentColor: Foundation.AppTheme.accent
    property color focusRingColor: Foundation.AppTheme.focusRing
    property bool keyboardFocusOnly: false
    readonly property bool sampling: !materialForm && buttonGlass.sampling
    readonly property real opticalExpansion: buttonGlass.scale
    readonly property real opticalRefraction: buttonGlass.refractionStrength
    readonly property real opticalMagnification: buttonGlass.magnification
    readonly property real opticalReflection: buttonGlass.reflectionStrength
    hoverEnabled: true
    implicitHeight: 36
    implicitWidth: iconOnly ? 36 : Math.max(76, contentItem.implicitWidth + 28)
    leftPadding: iconOnly ? 0 : 14
    rightPadding: iconOnly ? 0 : 14
    scale: materialForm ? (down ? .98 : 1) : hovered ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast; easing.type: Easing.OutCubic } }
    opacity: enabled ? 1 : 0.38
    contentItem: Item {
        implicitWidth: root.iconName.length ? root.iconSize : caption.implicitWidth
        implicitHeight: Math.max(caption.implicitHeight, root.iconName.length ? root.iconSize : 0)
        Label {
            id: caption
            anchors.fill: parent
            visible: !root.iconName.length
            text: root.text
            font: root.font
            color: root.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: root.iconOnly ? Text.ElideNone : Text.ElideRight
        }
        VectorIcon {
            anchors.centerIn: parent
            visible: root.iconName.length > 0
            filled: root.iconFilled
            name: root.iconName
            size: root.iconSize
            color: root.iconColor
        }
    }
    background: Item {
        // Independent sibling behind the glass, never part of its material.
        LiquidOuterShadow {
            anchors.fill: parent
            z: -1
            radius: buttonGlass.radius
            outwardOffset: LiquidStyle.controlShadowOutset
            shadowLevel: root.shadowLevel
            visible: !root.materialForm && root.shadowEnabled
            shadowOpacity: root.shadowOpacity
        }
        Rectangle {
            anchors.fill: parent
            visible: root.materialForm
            radius: height / 2
            color: root.highlighted || root.checked ? root.accentColor
                : root.flat && !root.hovered && !root.down ? "transparent" : root.surfaceColor
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: Foundation.AppTheme.text
                opacity: root.down ? .13 : root.hovered ? .07 : 0
            }
        }
        LiquidSurface {
        id: buttonGlass
        anchors.fill: parent
        visible: !root.materialForm
        convexLens: root.convexLens
        edgeShadeStrength: 0
        fullHighlight: true
        gradientFill: true
        fillCenterExtent: LiquidStyle.controlFillCenterExtent
        fillWhiteRimX: LiquidStyle.controlFillWhiteRimX
        fillWhiteRimY: Foundation.AppTheme.dark ? 0 : LiquidStyle.controlFillWhiteRimY
        fillEdgeSpanY: Foundation.AppTheme.dark ? LiquidStyle.controlFillEdgeSpanDark : -1
        fillEdgeColor: root.highlighted || root.checked ? root.accentColor : Foundation.AppTheme.dark ? LiquidStyle.controlFillEdgeDark : LiquidStyle.controlFillEdge
        whiteEdgeDepth: 0
        whiteEdgeAlpha: 0
        // Preserve the actual sampled texture; the bezel supplies depth.
        blurStrength: root.convexLens ? root._intensity.blur : .45
        readability: 0
        edgeWidth: Math.min(10, height * .28)
        refractionStrength: root.hovered ? root._intensity.hoverRefraction : root._intensity.refraction
        magnification: root.hovered ? root._intensity.hoverMagnification : root._intensity.magnification
        Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        radius: height / 2
        backdrop: root.materialForm ? null : root.backdrop
        reflectionStrength: root.hovered ? root._intensity.hoverReflection : root._intensity.reflection
        Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        tintColor: root.highlighted || root.checked ? root.accentColor : Foundation.AppTheme.dark ? LiquidStyle.controlFillCenterDark : LiquidStyle.controlFillCenter
        tintStrength: root.highlighted || root.checked ? 0.24 : LiquidStyle.controlFillOpacity
        Behavior on tintStrength {
            NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast }
        }
        opacity: root.flat && !root.hovered && !root.checked && !root.visualFocus ? 0.45 : 1
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: root.focusRingColor
            visible: root.visualFocus
        }
    }
}
