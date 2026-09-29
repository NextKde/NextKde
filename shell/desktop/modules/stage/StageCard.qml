import QtQuick
import Quickshell.Widgets
import org.kde.pipewire
import org.kde.taskmanager
import qs.desktop.modules.dock
import "stage-geometry.mjs" as StageGeo

// StageCard — 台前侧栏的单张应用卡片（同应用窗口堆叠在同一张卡上）。
// 纯展示组件：编排（快照/预测卡位/最小化派发）都在 StageSidebarWindow，
// 这里只发信号。ListModel 的角色名与 required property 一一对应自动绑定。
// 卡面玻璃质感（圆角/背板/受光/描边/辉光/纵深）全部走 StageConfigService，
// 设置应用「台前侧栏 → 玻璃质感」实时可调。
//
// 倾斜 = 真透视（shaders/stage_tilt.frag 针孔重投影）：所有卡片共享同一
// 台相机（竖轴 = 内容列中心线、地平线 = 滚动视口垂直中心，由 slot 下传
// perspectiveYOff），近缘放大、远缘缩小，整列读作一面同向微转的 3D 墙、
// 灭点唯一——QML Rotation 是仿射变换给不了这个（近远缘同高、各卡各自
// 为政的"假透视"）。纯函数孪生 tiltProject/tiltUnproject 在
// stage-geometry.mjs（node 单测）。
//
// 动效状态机：
//   入场 = 从窗口方向滑进侧栏（shown 翻转驱动一次）
//   悬停 = 放大 + 提亮 + 辉光 + 关闭钮浮现（放大是指向卡片的即时反馈）
//   点击 = engageClicked() → 窗口编排（入队 + 同拍收编）→ engaging 原地
//          淡出并保持倾斜，把姿态交棒给窗口动画（派发在窗口侧队列，
//          engageDelay 到点统一处理——见 StageSidebarWindow._engageQueue）
Item {
    id: card

    required property string appKey
    required property string targetId // 代表窗口（缩略图与激活目标）
    required property int pid
    required property string appName
    required property string title
    required property string iconSource
    required property int count // 组内窗口数（>1 显示角标）
    required property string idsJson // 组内全部窗口 id 的 JSON 数组

    // 共享透视：卡中心相对滚动视口中心（= 共享地平线）的 y 偏移，slot 下传
    property real perspectiveYOff: 0

    // 窗口侧聚焦键（hoveredKey 下传）：活体流判定与布局同源
    property string focusKey: ""

    // 点击（请求编排：入队，窗口侧 engageDelay 到点派发）
    signal engageClicked()
    // 悬停进出（窗口侧据此聚焦布局：悬停卡原位放大置顶、其余原位退避）
    signal hovered(bool over)
    // 关闭按钮：关闭组内全部窗口
    signal closeAllRequested()

    width: parent ? parent.width
                  : StageGeo.PANEL_WIDTH - StageGeo.CARD_WIDTH_INSET
    height: StageConfigService.cardHeight

    // ── 动效状态机：点击=原地淡出并保持倾斜（窗口从倾斜姿态旋转展开接管）──
    property bool shown: false
    property bool engaging: false
    // 同组换代表（点同应用的另一扇窗）时模型行不销毁，engaging 不会随
    // delegate 重建归零——必须在此显式交还卡片姿态，否则卡片永远停在
    // 透明态，看起来就是"卡片消失了"
    onTargetIdChanged: engaging = false
    x: StageGeo.CARD_X_INSET + (shown ? 0 : 70)
    opacity: engaging ? 0.0 : (shown ? 1.0 : 0.0)
    scale: shown ? (isHovered ? StageConfigService.hoverScale : 1.0) : 0.86
    // 悬停放大从左上角外扩（与 slot 的 TopLeft 缩放同向）：上边钉死、只向
    // 右/下生长——绕中心缩放会让四边同缩，压在边条上的指针被"缩出去"→
    // 悬停丢失（kill 循环的一环）。外扩区域内的指针不可能被挤出。
    transformOrigin: Item.TopLeft
    Component.onCompleted: shown = true
    Behavior on x { NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: engaging ? 180 : StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: StageConfigService.cardEnterDuration + 20; easing.type: Easing.OutCubic } }

    // 展开延迟派发改由窗口级队列 Timer 承担（round35 NEW-1/NEW-5：挂在
    // delegate 上的定时器会在派发窗口内随 delegate 销毁而丢派发），
    // 卡片淡出动画由 engaging 驱动的 opacity/tilt Behavior 承担。

    // ── 倾角状态机（角度交给着色器做真透视）：scroll = 静置统一倾角
    // （deckRestTilt，可调到 45°）、悬停聚焦放平便于阅读、交棒保持倾角
    //（kwinrc TiltAngle 同源投影给展开窗口动画）；adaptive = 平铺、
    // 悬停/点击才倾斜（tiltAngle）。
    readonly property bool deckMode: StageConfigService.layoutMode === "scroll"
    property real tiltCur: deckMode
        ? ((isHovered && !engaging) ? 0 : StageConfigService.deckRestTilt)
        : ((isHovered || engaging) ? StageConfigService.tiltAngle : 0)
    Behavior on tiltCur {
        NumberAnimation {
            duration: card.engaging ? 180 : StageConfigService.tiltAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // 悬停 = 整卡或关闭钮任一命中（合成）：关闭钮的 MouseArea 在最上层，
    // 指针移上去会让整卡 MouseArea 失去悬停——若只看后者，卡片会缩回
    // 1.0 → 按钮随 5% 缩放位移 → 指针脱出 → 再放大 = 抽搐循环（实测），
    // 且点击永远落空。合成后指针在卡内任何位置（含关闭钮）卡片姿态稳定。
    readonly property bool isHovered: cardMouse.containsMouse
        || closeMouse.containsMouse
    onIsHoveredChanged: card.hovered(card.isHovered)
    // 指针在卡内的位置（cards 坐标系）——排障日志用
    readonly property string mousePos: {
        const p = cardMouse.mapToItem(card, cardMouse.mouseX, cardMouse.mouseY)
        const g = card.mapToItem(null, 0, 0)
        return Math.round(p.x) + "," + Math.round(p.y) + "@card("
            + Math.round(g.x) + "," + Math.round(g.y) + " s"
            + card.scale.toFixed(2) + ")"
    }
    // 聚焦辉光：悬停/交棒时点亮（与聚焦放大同步）
    readonly property bool glowOn: card.isHovered || card.engaging

    // ── 卡面内容层（离屏）：背板/辉光/头部/缩略图全部渲染进 plane 的层
    // 纹理，再由 stage_tilt 着色器按共享透视重投影。plane 比卡面大一圈
    //（辉光外扩 ~14px 必须装进纹理，层纹理只渲染 item 尺寸内的内容）。
    Item {
        id: plane
        visible: false
        x: -16
        y: -22
        width: parent.width + 32
        height: parent.height + 44
        layer.enabled: true
        layer.smooth: true

        // 背板（原根 Rectangle 的颜色/描边/圆角，随卡面一起被透视投影）
        Rectangle {
            id: plate
            x: 16
            y: 22
            width: parent.width - 32
            height: parent.height - 44
            radius: StageConfigService.cardRadius
            // 背板浓度：静置 cardTint，悬停自动 ×1.3 提亮（上限 0.95）
            color: card.isHovered
                ? Qt.rgba(0.10, 0.13, 0.20,
                    Math.min(0.95, StageConfigService.cardTint * 1.3))
                : Qt.rgba(0.05, 0.07, 0.12, StageConfigService.cardTint)
            border.width: 1
            border.color: card.glowOn
                ? Qt.rgba(0.62, 0.80, 1.0, 0.85)
                : Qt.rgba(255, 255, 255, StageConfigService.cardBorder)
            Behavior on color { ColorAnimation { duration: 130 } }
        }

        // ── 聚焦辉光：多层薄步进衰减模拟柔和光晕。⚠️ 平色矩形层叠会出硬边
        //（在深色壁纸上呈"黑条"，实测踩过）——每层透明度减半、外扩小步长，
        // 层间差异小到不可辨。声明在内容之前 = 画在卡背之上、内容之下；
        // Rectangle 不裁剪子项，超出卡面的辉光进 plane 纹理 ──
        Repeater {
            model: 5
            Rectangle {
                required property int index
                anchors.centerIn: plate
                width: plate.width + 6 + index * 5
                height: plate.height + 8 + index * 7
                radius: plate.radius + 4 + index * 4
                color: Qt.rgba(0.55, 0.75, 1.0, 1.0)
                opacity: card.glowOn
                    ? StageConfigService.cardGlow / Math.pow(2, index) : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: StageConfigService.cardEnterDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── 玻璃质感：顶部受光渐变（悬停 ×2 提亮） ──
        Rectangle {
            anchors.fill: plate
            radius: plate.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, card.isHovered
                        ? Math.min(0.4, StageConfigService.cardTopLight * 2)
                        : StageConfigService.cardTopLight)
                }
                GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
            }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // 头部：名称（多窗带数量）+ 关闭。不放应用图标——卡面保持纯缩略图
        //（图标只在缩略图未就绪的占位里出现）
        // z:1 抬到整卡 cardMouse 之上（声明在后的 MouseArea 会盖住关闭钮，
        // 点关闭变成展开窗口——实测踩过）；红色悬停高亮随之恢复
        Item {
            id: cardHeader
            z: 1
            anchors {
                top: plate.top
                left: plate.left
                right: plate.right
                margins: 8
            }
            height: 24

            Text {
                anchors {
                    left: parent.left
                    right: cardClose.left
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                text: card.count > 1
                    ? (card.appName || card.title || "应用") + " ×" + card.count
                    : (card.appName || card.title || "应用")
                color: "white"
                font { pixelSize: 11; weight: Font.Bold }
                elide: Text.ElideRight
            }

            Rectangle {
                id: cardClose
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 20
                height: 20
                radius: 10
                color: closeMouse.containsMouse ? "#ef4444" : "transparent"
                opacity: card.isHovered ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 10
                    color: "white"
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.closeAllRequested()
                }
            }
        }

        // 缩略图视口
        Rectangle {
            id: thumbCard
            anchors {
                top: cardHeader.bottom
                topMargin: 6
                left: plate.left
                right: plate.right
                bottom: plate.bottom
                margins: 8
            }
            radius: 9
            color: Qt.rgba(0, 0, 0, 0.35)
            clip: true

            readonly property string thumbUrl: WindowService.thumbnailUrl(card.targetId)

            // ── 活体流（round30 迁移 / round36 占空比节流）──
            // ScreencastingRequest{uuid} 走 zkde_screencast 协议开单窗口
            // PipeWire 流；PipeWireSourceItem 渲染。悬停判定源 = 窗口侧
            // hoveredKey（聚焦布局同一来源；卡片自己的 MouseArea isHovered
            // 无头调试钩子触不到，且多卡瞬时命中会破"单流"约束，故不参与）。
            //
            // ⚠️ round36 占空比节流：kpipewire 无 fps 旋钮（API 只有
            // nodeId/allowDmaBuf/state），本机容器 GPU 预算红线（round31
            // 悬停即被宿主杀桌面）。nodeId 可运行时改写 = 消费者可拔插：
            // 连接 streamOnMs 抓新鲜帧（断开前 grabToImage 定格最后一帧，
            // 防闪烁）→ 断开 streamOffMs（无消费者 = WirePlumber 撤链 =
            // KWin 停止离屏渲染，源节点挂起零成本）。平均负载 ≈ 占空比 ×
            // 单流全速，GPUTotalUsed（/proc/meminfo）可实测对账。
            readonly property bool liveWanted:
                card.focusKey === card.appKey || card.engaging
            property bool streamOn: false     // 占空比相位：true=连接消费
            property string liveGrabUrl: ""   // 断开前定格的最后一帧

            ScreencastingRequest {
                id: streamRequest
                // ⚠️ uuid 口径 = KWin internalId（record.handleId）= PlasmaWindow
                // uuid；shell 句柄（window-N）直传会静默开不出流（实测）。
                // liveWanted 期间源常驻（无消费者时挂起，不渲染）。
                // ⚠️ 默认禁用（thumbLiveStream=false）：容器 GPU 预算红线
                uuid: thumbCard.liveWanted && StageConfigService.thumbLiveStream
                    ? WindowService.handleIdOf(card.targetId) : ""
                onNodeIdChanged: if (nodeId > 0)
                    console.info("[StageCard] stream node ready: " + nodeId
                        + " for " + card.appKey)
            }

            // 相位定时器：on 相位到期 → 抓帧定格 → 断开（off 相位）；
            // off 到期 → 重连。liveWanted 消失即停摆并复位。
            property Timer streamCycle: Timer {
                interval: thumbCard.streamOn
                    ? StageConfigService.streamCycleOnMs
                    : StageConfigService.streamCycleOffMs
                onTriggered: {
                    if (!thumbCard.liveWanted
                            || !StageConfigService.thumbLiveStream)
                        return
                    if (thumbCard.streamOn) {
                        // 断开前把活体帧定格进 preview（异步 grab，回调
                        // 晚于一拍也无碍——preview 旧帧兜底）
                        if (liveStream.ready)
                            liveStream.grabToImage(function(result) {
                                thumbCard.liveGrabUrl = result.url
                            })
                        thumbCard.streamOn = false
                    } else {
                        thumbCard.streamOn = true
                    }
                    restart()
                }
            }

            onLiveWantedChanged: {
                liveGrabUrl = ""
                if (liveWanted && StageConfigService.thumbLiveStream) {
                    streamOn = true   // 首相位即连接（别先空等 off 周期）
                    streamCycle.restart()
                } else {
                    streamOn = false
                    streamCycle.stop()
                }
            }

            PipeWireSourceItem {
                id: liveStream
                anchors.fill: parent
                visible: streamRequest.nodeId > 0 && ready && thumbCard.streamOn
                // 占空比消费：off 相位拔掉消费者（源保留挂起）
                nodeId: thumbCard.streamOn ? streamRequest.nodeId : 0
                // freedreno + 容器 GPU 栈 dmabuf 坑多（Chromium 纹理损坏
                // 同源），保守关闭；SHM 走系统内存，VRAM 占用最小
                allowDmaBuf: false
            }

            Image {
                id: preview
                anchors.fill: parent
                // 活体流就绪时让位（避免双绘）；流断开自动回来兜底。
                // 优先显示占空比断开前定格的活体帧（最小化窗口无人交互，
                // 内容不再变化，定格帧即最新），否则收编快照
                visible: !liveStream.visible
                    && !!(thumbCard.liveGrabUrl !== ""
                        ? thumbCard.liveGrabUrl : parent.thumbUrl)
                source: thumbCard.liveGrabUrl !== ""
                    ? thumbCard.liveGrabUrl : parent.thumbUrl
                // 同步解码 + 禁缓存：实时换帧时不留异步空白间隙（闪烁根源）
                asynchronous: false
                cache: false
                sourceSize: Qt.size(StageConfigService.thumbSize,
                    Math.round(StageConfigService.thumbSize * 0.7))
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }

            // 缩略图未就绪时的占位
            Column {
                anchors.centerIn: parent
                visible: !preview.visible && !liveStream.visible
                spacing: 6

                IconImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 30
                    height: 30
                    source: card.iconSource || ""
                    asynchronous: false
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 12
                    text: card.title || "窗口"
                    color: Qt.rgba(1, 1, 1, 0.40)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // 深度渐变：远侧压暗盖在内容之上，增强"退到侧边"的纵深（悬停/点击时淡出）
        Rectangle {
            anchors.fill: plate
            radius: plate.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0, 0, 0, StageConfigService.cardDepth)
                }
                GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.0) }
            }
            opacity: (card.isHovered || card.engaging) ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
    }

    // ── 真透视倾斜：把 plane 纹理按共享相机针孔模型重投影（逆映射逐像素
    // 采样）。相机 = 所有卡片共享：竖轴取本项中心（卡在内容列里居中），
    // 地平线 = 视口中心（camRel.y 由 perspectiveYOff 换算）——整列灭点唯一。
    // 尺寸余量：高度 ×1.3（远离地平线的卡随 k 偏移 ±3%）、宽度 ×1.1。
    ShaderEffect {
        anchors.centerIn: parent
        width: parent.width * 1.1
        height: parent.height * 1.3
        // uniform 显式声明（ShaderEffect 不自动创建属性；source 约定名，
        // plane 的 layer 纹理由此进 sampler）
        property variant source: plane
        property real angleRad: card.tiltCur * Math.PI / 180
        property real focal: StageGeo.TILT_FOCAL
        property size cardSize: Qt.size(plane.width, plane.height)
        property size camRel: Qt.size(width / 2,
            height / 2 - card.perspectiveYOff)
        property real yOff: card.perspectiveYOff
        property size itemSize: Qt.size(width, height)
        fragmentShader: Qt.resolvedUrl("../../shaders/stage_tilt.frag.qsb")
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.engageClicked()
    }
}
