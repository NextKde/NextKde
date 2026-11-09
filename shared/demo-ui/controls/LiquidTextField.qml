import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// Match action-button heights at the same placement: inline 20 (provisional),
// secondary Dialog 24, toolbar 26, ordinary content 28, important Dialog 30.
// Liquid fields stay capsules; compact solid fields below 28 use 6px corners.
TextField {
    id: root
    // Plain input inside a host-owned navigation material; opt-in only.
    property bool specificationForm: false
    property string liquidIntensity: LiquidStyle.intensityLevel
    readonly property var _intensity: LiquidStyle.intensityProfile(liquidIntensity)
    opacity: specificationForm && !enabled ? .38 : 1
    implicitHeight: Foundation.AppTheme.compactDesign ? 28 : 34
    Binding {
        target: root; property: "font.pixelSize"
        value: Foundation.AppTheme.compactControlFontSize; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root; property: "font.weight"
        value: Font.Normal; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root; property: "topPadding"
        value: root.height < 26 ? 2 : 4; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root; property: "bottomPadding"
        value: root.height < 26 ? 2 : 4; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    leftPadding: 12
    rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    property color glassColor: darkAppearance
        ? Qt.rgba(32 / 255, 37 / 255, 47 / 255, .20) : Qt.rgba(1, 1, 1, .20)
    property real cornerRadius: Foundation.AppTheme.compactDesign
        && (specificationForm || materialForm) && height < 28 ? 6 : height / 2
    property color outlineColor: Qt.rgba(1, 1, 1, 0.08)
    property color focusedOutlineColor: Foundation.AppTheme.focusRing
    property color textColor: _liquid
        ? (darkAppearance ? "#D6D6DA" : "#55555A")
        : (darkAppearance ? Foundation.AppTheme.text : "#000000")
    property color mutedTextColor: Foundation.AppTheme.mutedText
    property bool materialForm: ControlForm.materialForm
    property bool unfilteredBackdrop: false
    property bool shadowEnabled: false
    property int shadowLevel: LiquidStyle.shadowLevel
    property real shadowOpacity: LiquidStyle.shadowProfile(shadowLevel).opacity
    property bool convexLens: true
    property bool liquidFinish: false
    property real liquidStrength: 1
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property bool darkAppearance: Foundation.AppTheme.dark
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property real refractionStrength: _liquid && hover.hovered ? _intensity.hoverRefraction : _intensity.refraction
    property real magnification: _liquid && hover.hovered ? _intensity.hoverMagnification : _intensity.magnification
    property real blurStrength: convexLens ? _intensity.blur : 0.2
    property real readability: 0
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0
    readonly property bool sampling: _liquid && liquidSurface.sampling
    readonly property bool _liquid: liquidFinish && !materialForm && !specificationForm
    readonly property color _fill: specificationForm
        ? Foundation.AppTheme.controlBackground
        : Qt.rgba(glassColor.r, glassColor.g, glassColor.b,
        Math.min(1, glassColor.a + (_liquid ? (hover.hovered ? .05 : 0)
            : (hover.hovered ? .035 : 0))))

    color: textColor
    placeholderTextColor: mutedTextColor
    selectionColor: _liquid
        ? (darkAppearance ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(0, 0, 0, 0.16))
        : Foundation.AppTheme.accent
    selectedTextColor: _liquid ? textColor : Foundation.AppTheme.accentText
    scale: !Foundation.AppTheme.compactDesign && _liquid && hover.hovered ? 1.01 : 1
    Behavior on scale {
        NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast; easing.type: Easing.OutCubic }
    }
    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

    background: Item {
        LiquidOuterShadow {
            anchors.fill: parent; radius: root.cornerRadius
            outwardOffset: LiquidStyle.controlShadowOutset
            z: -1
            shadowLevel: root.shadowLevel
            visible: root._liquid && root.shadowEnabled; shadowOpacity: root.shadowOpacity
        }
        Rectangle {
            anchors.fill: parent
            visible: !root._liquid
            radius: root.cornerRadius
            color: root._fill
            border.width: root.specificationForm ? 0 : 1
            border.color: root.outlineColor
            Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 150 } }
            Behavior on border.color { ColorAnimation { duration: root.reduceMotion ? 0 : 150 } }
        }
        Rectangle {
            anchors.fill: parent
            // Solid fields show focus on the edge; liquid fields keep their glass edge.
            z: 2
            radius: root.cornerRadius
            color: "transparent"
            border.width: 2
            border.color: root.focusedOutlineColor
            visible: !root._liquid && root.activeFocus && root.enabled
        }
        LiquidSurface {
            id: liquidSurface
            convexLens: root.convexLens
            edgeShadeStrength: 0
            fullHighlight: true
            gradientFill: true
            fillCenterExtent: LiquidStyle.controlFillCenterExtent
            fillWhiteRimX: LiquidStyle.controlFillWhiteRimX
            fillWhiteRimY: root.darkAppearance ? 0 : LiquidStyle.controlFillWhiteRimY
            fillEdgeSpanY: root.darkAppearance ? LiquidStyle.controlFillEdgeSpanDark : -1
            fillEdgeColor: root.darkAppearance ? LiquidStyle.controlFillEdgeDark : LiquidStyle.controlFillEdge
            whiteEdgeDepth: 0
            whiteEdgeAlpha: 0
            unfilteredBackdrop: root.unfilteredBackdrop
            anchors.fill: parent
            visible: root._liquid
            radius: root.cornerRadius
            backdrop: root.backdrop
            darkAppearance: root.darkAppearance
            tintColor: root.darkAppearance ? LiquidStyle.controlFillCenterDark : LiquidStyle.controlFillCenter
            tintStrength: LiquidStyle.controlFillOpacity
            Behavior on tintStrength { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            blurStrength: root.blurStrength
            readability: root.readability
            refractionStrength: root.refractionStrength * Math.max(0, Math.min(1, root.liquidStrength))
            magnification: 1 + (root.magnification - 1) * Math.max(0, Math.min(1, root.liquidStrength))
            edgeWidth: Math.min(10, height * .28)
            reflectionStrength: root.liquidStrength * (hover.hovered ? root._intensity.hoverReflection : root._intensity.reflection)
            Behavior on reflectionStrength { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on refractionStrength { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            rimColor: root.outlineColor
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
