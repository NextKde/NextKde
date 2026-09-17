import QtQuick
import QtQuick.Effects

// 单个自带图标的渲染件。
//
// 数据来自 common/BundledIcons（内联 SVG，白色描边当 alpha 遮罩）。这里负责
// 三件事：把遮罩投成目标颜色、按需要补一圈暗描边、把尺寸对齐到调用方要的
// 像素数。零散调用点（桌面文件图标、锁屏、Overview、系统指标）统一走这个
// 组件，不必各自复制一份 MultiEffect。
//
// 尺寸说明：这里接收的是像素尺寸而非字号。原来这些位置用 Text 渲染字形，
// pixelSize 是字号；换成图标后同一个数值会显得略大，按视觉微调即可。
Item {
    id: root

    property string name: ""
    property color color: "#ffffff"
    property real size: 18
    // 单色遮罩图标（白描边）由 MultiEffect 投成 color；彩色原作（应用图标、
    // 封面图之类）设 colorized: false 原样呈现。
    property bool colorized: true
    // 桌面壁纸上的图标需要一圈暗边才能在浅色壁纸上站住（原来是
    // Text.Outline 的效果）。
    property bool outlined: false
    property color outlineColor: Qt.rgba(0, 0, 0, 0.5)

    implicitWidth: root.size
    implicitHeight: root.size

    readonly property string source: BundledIcons.source(root.name)

    Image {
        anchors.fill: parent
        source: root.source
        sourceSize.width: Math.max(8, Math.round(root.size * 2))
        sourceSize.height: Math.max(8, Math.round(root.size * 2))
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: false
        layer.enabled: root.colorized || root.outlined
        layer.effect: MultiEffect {
            colorization: root.colorized ? 1.0 : 0.0
            colorizationColor: root.color
            shadowEnabled: root.outlined
            shadowColor: root.outlineColor
            shadowBlur: 0.22
        }
    }
}
