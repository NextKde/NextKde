import QtQuick
import QtQuick.Effects

// 渐变羽化模糊：方向可调、半径沿方向连续变化的高斯模糊 + 跟随同一条斜坡的色调层。
//
// 用法：把要模糊的内容放进 sourceItem，把本组件盖在它上面。
//
//     Item {
//         id: page
//         Image { anchors.fill: parent; source: "壁纸.jpg" }
//     }
//     GradientBlur {
//         anchors.fill: page
//         sourceItem: page
//         startPoint: Qt.point(0, -0.5)   // 局部坐标：中心 (0,0)，±0.5 = 矩形边
//         endPoint: Qt.point(0, 0.25)
//         blurStart: 0.0                  // 起点处模糊占 maxRadius 的比例
//         blurEnd: 1.0                    // 终点处……
//         band: true                      // 越过终点后按 featherOut 淡回清晰
//         tintColor: "#000000"            // 色调层：继承同一条百分比剖面
//         tintOpacity: 0.16
//     }
//
// 约定与语义：
//
//  * **起点/终点是矩形局部坐标里的两个点**：中心 (0,0)，±0.5 就是该方向的边，
//    两者都可以落在矩形外（用来把渐变推到画面之外）。渐变方向 = 两点连线。
//  * **模糊量在两个点上的百分比可调**（例如起点 20%、终点 80%），中间按
//    feather 线性/平滑过渡；两点之外各自夹紧。
//  * **只有半径在渐变，绝不做"清晰图与模糊图按渐变混合"** —— 后者中段会出现
//    半透明重影；起点默认半径为 0，所以区域边缘天然无缝。
//  * **模糊由预模糊金字塔两级插值得到**：内部 5 级（12/26/48/80/130px）各渲染
//    一次后只当纹理用，着色器按当前半径取相邻两级插值。离散抽样（每个像素采
//    有限几个点）在锐利边缘上会露出多重影像，层级插值不会。
//  * **色调层直接继承模糊的百分比剖面**，它自己的量只有颜色与不透明度。
//    band 的远端淡出只作用于模糊，色调在终点之后保持满值。
//  * sourceItem 默认会被隐藏（hideSource），画面完全由本组件绘制；宿主想在模糊
//    之上再画东西，把内容放在本组件的兄弟层级即可（前景永远锐利）。
//  * 深浅色：followsAppearance 打开时按 appearanceIsDark 在 tintColorDark /
//    tintColorLight 之间取色（宿主绑定自己的主题即可），关闭时用 tintColor。
//
// 移植说明：合成器侧（kwin/glass-effect/src/）本来就维护着同结构的模糊金字塔，
// 同一套渐变数学搬过去时只需把"取相邻两级"换成从它自己的金字塔取；参数语义、
// 坐标归一化方式与这里完全一致。
Item {
    id: root

    // ---- 输入 -----------------------------------------------------------

    // 被模糊的内容。默认捕获后隐藏它，由本组件绘制。
    property Item sourceItem: null
    property bool hideSource: true
    property bool enabled: true

    // ---- 渐变：两个局部坐标点 -------------------------------------------

    // 起点（0% 端）与终点（100% 端）；中心 (0,0)，±0.5 = 矩形边，可为矩形外。
    property point startPoint: Qt.point(0, -0.5)
    property point endPoint: Qt.point(0, 0.5)
    // 两点处的模糊量，占 maxRadius 的比例；可做"起点 20% → 终点 80%"。
    property real blurStart: 0.0
    property real blurEnd: 1.0

    // ---- 模糊 -----------------------------------------------------------

    // 最大模糊半径（px），终点百分比乘在它上面。上限 130 = 金字塔最高一级。
    property real maxRadius: 46
    // 斜坡缓动：0 = 线性，1 = smoothstep。
    property real feather: 1.0
    // 圆角（px），作用于整个模糊区。
    property real cornerRadius: 0

    // ---- 收尾 -----------------------------------------------------------

    // band：越过终点后，模糊按 featherOut（局部单位，0.5 ≈ 半个矩形尺寸）淡回清晰。
    property bool band: false
    property real featherOut: 0.5
    // 垂直于渐变方向的两条边上的淡出距离（局部单位）：模糊与色调都受它影响。
    property real sideFeather: 0.0

    // ---- 色调层 ---------------------------------------------------------

    property bool tintEnabled: true
    property color tintColor: "#000000"
    property real tintOpacity: 0.0
    // 跟随深浅色：按 appearanceIsDark 在下面两色之间取；不跟随时用 tintColor。
    property bool followsAppearance: false
    property bool appearanceIsDark: true
    property color tintColorDark: "#000000"
    property color tintColorLight: "#ffffff"
    // true = 色调对每次采样着色（色调自身也被模糊）；false = 压在模糊结果上。
    property bool tintPerTap: false

    // ---- 开发用（正式使用保持关闭）--------------------------------------

    // 画出起点/终点与连线，只用于肉眼核对参数；不可交互（调参请用实验室）。
    property bool devGuides: false

    readonly property color effectiveTint: !followsAppearance ? tintColor
        : (appearanceIsDark ? tintColorDark : tintColorLight)
    readonly property real effectiveTintOpacity: tintEnabled ? tintOpacity : 0.0

    // ---- 金字塔 ---------------------------------------------------------
    //
    // 5 级预模糊，半径几何递增到 maxRadius 的上限。live:false + hideSource 让
    // 每级只渲染一次，之后作为纹理参与插值。多个实例想共享金字塔时，可以从
    // 这里把级别外置成参数（当前每个实例各建一份，够用且简单）。
    readonly property var levelRadii: [12, 26, 48, 80, 130]

    ShaderEffectSource {
        id: levelSharp
        sourceItem: root.sourceItem
        live: false
        hideSource: root.hideSource
    }
    MultiEffect { id: blurL1; anchors.fill: parent; source: root.sourceItem; visible: false
        blurEnabled: true; blur: 1.0; blurMax: root.levelRadii[0] }
    MultiEffect { id: blurL2; anchors.fill: parent; source: root.sourceItem; visible: false
        blurEnabled: true; blur: 1.0; blurMax: root.levelRadii[1] }
    MultiEffect { id: blurL3; anchors.fill: parent; source: root.sourceItem; visible: false
        blurEnabled: true; blur: 1.0; blurMax: root.levelRadii[2] }
    MultiEffect { id: blurL4; anchors.fill: parent; source: root.sourceItem; visible: false
        blurEnabled: true; blur: 1.0; blurMax: root.levelRadii[3] }
    MultiEffect { id: blurL5; anchors.fill: parent; source: root.sourceItem; visible: false
        blurEnabled: true; blur: 1.0; blurMax: root.levelRadii[4] }
    ShaderEffectSource { id: levelSrc1; sourceItem: blurL1; live: false; hideSource: true }
    ShaderEffectSource { id: levelSrc2; sourceItem: blurL2; live: false; hideSource: true }
    ShaderEffectSource { id: levelSrc3; sourceItem: blurL3; live: false; hideSource: true }
    ShaderEffectSource { id: levelSrc4; sourceItem: blurL4; live: false; hideSource: true }
    ShaderEffectSource { id: levelSrc5; sourceItem: blurL5; live: false; hideSource: true }

    // 源异步加载（图片等）完成后补一次捕获；live:false 只抓一次。
    Connections {
        target: root.sourceItem
        function onStatusChanged() { root.refreshLevels() }
    }
    function refreshLevels() {
        levelSharp.scheduleUpdate()
        levelSrc1.scheduleUpdate()
        levelSrc2.scheduleUpdate()
        levelSrc3.scheduleUpdate()
        levelSrc4.scheduleUpdate()
        levelSrc5.scheduleUpdate()
    }
    onSourceItemChanged: refreshLevels()

    // ---- 渲染 -----------------------------------------------------------

    ShaderEffect {
        id: fx
        anchors.fill: parent
        visible: root.enabled

        property var source: levelSharp
        property var level1: levelSrc1
        property var level2: levelSrc2
        property var level3: levelSrc3
        property var level4: levelSrc4
        property var level5: levelSrc5

        // 归一化：xy = 画布像素尺寸，zw = 1/尺寸。
        property vector4d canvasAndTexel: Qt.vector4d(
            Math.max(1, width), Math.max(1, height),
            1 / Math.max(1, width), 1 / Math.max(1, height))

        // 区域 0 = 本组件；区域 1..3 关闭（着色器支持 4 个区域，供实验室叠加用）。
        property vector4d z0Rect: Qt.vector4d(0, 0, width, height)
        property vector4d z0Ramp: Qt.vector4d(
            root.startPoint.x, root.startPoint.y, root.endPoint.x, root.endPoint.y)
        property vector4d z0Shape: Qt.vector4d(
            Math.min(root.maxRadius, root.levelRadii[4]), root.cornerRadius,
            root.feather, root.sideFeather)
        property vector4d z0Tint: Qt.vector4d(
            root.effectiveTint.r, root.effectiveTint.g, root.effectiveTint.b,
            root.effectiveTintOpacity)
        property vector4d z0Flags: Qt.vector4d(
            1, root.band ? 1 : 0, root.tintPerTap ? 1 : 0, root.featherOut)
        property vector4d z0Amount: Qt.vector4d(root.blurStart, root.blurEnd, 0, 0)

        property vector4d z1Rect: Qt.vector4d(0, 0, 0, 0)
        property vector4d z1Ramp: Qt.vector4d(0, 0, 0, 0)
        property vector4d z1Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d z1Tint: Qt.vector4d(0, 0, 0, 0)
        property vector4d z1Flags: Qt.vector4d(0, 0, 0, 0)
        property vector4d z1Amount: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Rect: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Ramp: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Tint: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Flags: Qt.vector4d(0, 0, 0, 0)
        property vector4d z2Amount: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Rect: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Ramp: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Shape: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Tint: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Flags: Qt.vector4d(0, 0, 0, 0)
        property vector4d z3Amount: Qt.vector4d(0, 0, 0, 0)

        property real globalStrength: 1

        fragmentShader: "gradient_blur.frag.qsb"
    }

    // ---- 开发用起点/终点指示（只读）-------------------------------------

    Item {
        anchors.fill: parent
        visible: root.devGuides
        z: 100

        readonly property real startPX: (0.5 + root.startPoint.x) * width
        readonly property real startPY: (0.5 + root.startPoint.y) * height
        readonly property real endPX: (0.5 + root.endPoint.x) * width
        readonly property real endPY: (0.5 + root.endPoint.y) * height

        Item {
            x: parent.startPX
            y: parent.startPY
            width: Math.hypot(parent.endPX - parent.startPX, parent.endPY - parent.startPY)
            height: 2
            rotation: Math.atan2(parent.endPY - parent.startPY,
                                 parent.endPX - parent.startPX) * 180 / Math.PI
            transformOrigin: Item.Left
            Rectangle { anchors.fill: parent; color: Qt.rgba(1, 1, 1, 0.75) }
        }
        Repeater {
            model: 2
            delegate: Rectangle {
                readonly property bool isEnd: index === 1
                width: 18
                height: 18
                radius: 9
                color: isEnd ? "#ff453a" : "#30d158"
                border.width: 2
                border.color: "#ffffff"
                x: (isEnd ? parent.endPX : parent.startPX) - width / 2
                y: (isEnd ? parent.endPY : parent.startPY) - height / 2
            }
        }
    }

    // ---- 色调层（不依赖任何主题服务：颜色由宿主给）----------------------
    //
    // 这里不额外画色块：着色器已经把色调合成进结果（见 z0Tint / tintPerTap），
    // 因此色调天然跟随模糊。需要"色调自己再被模糊一次"时用 tintPerTap。
}
