import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// 液态/实色通用操作按钮 —— 按钮规则的唯一权威来源（Gallery 按钮页只做演示）。
//
// 用法按四步取值，顺序固定：
//   1) 材质  ：默认液态（悬浮在内容之上、采样背景折射）。
//              嵌在内容之内的按钮设 materialForm: true 切换实色。
//   2) 大小  ：按所在位置设 implicitHeight——
//              正文文字旁行内按钮暂用 20 / 非主 Dialog 底栏 24 /
//              工具栏 26（图标按钮）/ 内容区独立操作 28 /
//              重要液态 Dialog 的实色底部按钮 30 / 浮层 28。
//   3) 圆角  ：液态恒为胶囊，不要设置 cornerRadius。
//              实色 28、30 也是胶囊；实色 26、24、20、18 必须显式 cornerRadius: 6。
//              这是唯一允许覆盖 cornerRadius 的场景。
//   4) 颜色  ：一般不指定，组件按 AppTheme 自动取值——
//              highlighted/checked → accent 底白字；浅色普通实色 → 纯黑字；
//              浅色液态 → 较浅的深灰字；
//              destructive → 红字（底不变）；disabled → 淡字（底不变）。
//              覆盖 textColor/accentColor/surfaceColor 仅用于特殊场景，需在调用处注释原因。
//
// 常用属性：
//   materialForm  实色开关（见上）
//   secondary     次级样式（弱化底色）
//   destructive   危险操作（红字）
//   cornerRadius  圆角，默认胶囊；仅"实色+小尺寸"允许 6
//   iconOnly + iconName/iconFilled/iconSize  纯图标按钮（内容居中，无文字内边距）
//   adaptiveGlass / convexLens             透镜光学开关（默认凸面透镜）
Button {
    id: root
    property string liquidIntensity: LiquidStyle.intensityLevel
    readonly property var _intensity: LiquidStyle.intensityProfile(liquidIntensity)
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    property bool materialForm: ControlForm.materialForm
    property bool darkAppearance: Foundation.AppTheme.dark
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property bool secondary: false
    property bool destructive: false
    // Compact glyph actions keep their content centered without label insets.
    property bool shadowEnabled: false
    property int shadowLevel: LiquidStyle.shadowLevel
    property real shadowOpacity: LiquidStyle.shadowProfile(shadowLevel).opacity
    property bool adaptiveGlass: false
    property bool convexLens: !adaptiveGlass
    property real cornerRadius: materialForm && Foundation.AppTheme.compactDesign && height < 28
        ? 6 : height / 2
    property bool iconOnly: false
    property string iconName: ""
    property bool iconFilled: false
    property real iconSize: 16
    // 主操作（highlighted/checked）在强调色底上用白字，符合 macOS 惯例
    property color textColor: !enabled ? Foundation.AppTheme.disabledText
        : destructive ? Foundation.AppTheme.destructive
        : (highlighted || checked) ? "#FFFFFF"
        : root.materialForm
            ? (root.darkAppearance ? Foundation.AppTheme.text : "#000000")
            : (root.darkAppearance ? "#D6D6DA" : "#55555A")
    property color iconColor: textColor
    property color surfaceColor: Foundation.AppTheme.compactDesign ? Foundation.AppTheme.controlBackground
        : root.darkAppearance ? "#20252f" : "#ffffff"
    property color accentColor: Foundation.AppTheme.accent
    property color focusRingColor: Foundation.AppTheme.focusRing
    property bool keyboardFocusOnly: false
    readonly property bool sampling: !materialForm && buttonGlass.sampling
    readonly property real opticalExpansion: buttonGlass.scale
    readonly property real opticalRefraction: buttonGlass.refractionStrength
    readonly property real opticalMagnification: buttonGlass.magnification
    readonly property real opticalReflection: buttonGlass.reflectionStrength
    hoverEnabled: true
    implicitHeight: Foundation.AppTheme.compactDesign ? 28 : 36
    font.weight: Font.Medium
    Binding {
        target: root; property: "font.pixelSize"
        value: Foundation.AppTheme.compactControlFontSize; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root; property: "topPadding"
        value: 4; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: root; property: "bottomPadding"
        value: 4; when: Foundation.AppTheme.compactDesign
        restoreMode: Binding.RestoreBindingOrValue
    }
    implicitWidth: iconOnly ? implicitHeight : Math.max(76, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: iconOnly ? 0 : Foundation.AppTheme.compactDesign ? 12 : 14
    rightPadding: iconOnly ? 0 : Foundation.AppTheme.compactDesign ? 12 : 14
    scale: Foundation.AppTheme.compactDesign || adaptiveGlass ? 1 : materialForm ? (down ? .98 : 1) : hovered ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast; easing.type: Easing.OutCubic } }
    // 禁用靠文字色表达，不整块降透明度
    opacity: 1
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
            // 主操作与实色档都走实底：强调色要真蓝，不能被液态层洗淡
            visible: root.materialForm || root.highlighted || root.checked
            radius: root.cornerRadius
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
        visible: !root.materialForm && !root.highlighted && !root.checked
        darkAppearance: root.darkAppearance
        adaptiveGlass: root.adaptiveGlass
        convexLens: root.convexLens
        edgeShadeStrength: 0
        fullHighlight: !root.adaptiveGlass
        gradientFill: !root.adaptiveGlass
        fillCenterExtent: LiquidStyle.controlFillCenterExtent
        fillWhiteRimX: LiquidStyle.controlFillWhiteRimX
        fillWhiteRimY: root.darkAppearance ? 0 : LiquidStyle.controlFillWhiteRimY
        fillEdgeSpanY: root.darkAppearance ? LiquidStyle.controlFillEdgeSpanDark : -1
        fillEdgeColor: root.highlighted || root.checked ? root.accentColor : root.darkAppearance ? LiquidStyle.controlFillEdgeDark : LiquidStyle.controlFillEdge
        whiteEdgeDepth: 0
        whiteEdgeAlpha: 0
        // Preserve the actual sampled texture; the bezel supplies depth.
        blurStrength: root.convexLens ? root._intensity.blur : .45
        readability: 0
        edgeWidth: Math.min(10, height * .28)
        refractionStrength: root.adaptiveGlass ? .6 : root.hovered ? root._intensity.hoverRefraction : root._intensity.refraction
        magnification: root.adaptiveGlass ? 1 : root.hovered ? root._intensity.hoverMagnification : root._intensity.magnification
        Behavior on refractionStrength { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        Behavior on magnification { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        radius: root.cornerRadius
        backdrop: root.materialForm ? null : root.backdrop
        reflectionStrength: root.adaptiveGlass ? .12 : root.hovered ? root._intensity.hoverReflection : root._intensity.reflection
        Behavior on reflectionStrength { NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        tintColor: root.highlighted || root.checked ? root.accentColor : root.darkAppearance ? LiquidStyle.controlFillCenterDark : LiquidStyle.controlFillCenter
        tintStrength: root.highlighted || root.checked ? 0.24 : LiquidStyle.controlFillOpacity
        Behavior on tintStrength {
            NumberAnimation { duration: root.reduceMotion ? 0 : Foundation.AppTheme.motionFast }
        }
        opacity: root.flat && !root.hovered && !root.checked && !root.visualFocus ? 0.45 : 1
        }
        Rectangle {
            anchors.fill: parent
            visible: !root.materialForm && root.adaptiveGlass
            radius: root.cornerRadius
            color: root.checked ? root.accentColor : Foundation.AppTheme.text
            opacity: root.down ? .10 : root.hovered ? .06 : root.checked ? .13 : 0
            Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 150 } }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: root.cornerRadius + 2
            color: "transparent"
            border.width: 2
            border.color: root.focusRingColor
            visible: root.materialForm && root.visualFocus
        }
    }
}
