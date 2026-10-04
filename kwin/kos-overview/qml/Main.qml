import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

// KOS Overview · iPad 风概览场景(Phase 3)
//
// 交互约定(与 effect 侧约定一致):
//   四指上滑     → 打开(effect 侧 GestureSpy,跟手)
//   双指左右滚   → 翻页(页内窗口卡片,逐帧跟手 + 弹簧收敛)
//   双指上下滚   → 翻 space(阈值触发,带滑动过渡)
//   四指下滑     → 关闭(effect 侧,跟手)
//   点卡片       → 激活窗口并收起
//   Esc / 点背景 → 收起
Item {
    id: root

    // 由 KosOverviewEffect::initialProperties 注入
    property var effect: null

    readonly property real prog: effect ? effect.progress : 0

    // ── 数据 ────────────────────────────────────────────────────────────
    readonly property var spaceWindows: effect ? effect.windows : []
    readonly property int cardCols: 3
    readonly property int cardsPerPage: 6
    readonly property int pageCount: Math.max(1, Math.ceil(spaceWindows.length / cardsPerPage))
    property int currentPage: 0
    property real pageOffset: 0        // 跟手翻页位置(单位:页)
    property real pageTarget: 0
    property real spaceAccum: 0        // 翻 space 的纵向滚轮累积

    // ── 布局 ────────────────────────────────────────────────────────────
    readonly property real padX: width * 0.075
    readonly property real padY: height * 0.105
    readonly property real gap: Math.min(width, height) * 0.024
    readonly property real cellW: (width - 2 * padX - (cardCols - 1) * gap) / cardCols
    readonly property real cellH: Math.min(cellW * 0.68, (height - 2 * padY - gap) / 2)

    opacity: prog
    visible: prog > 0.001

    onSpaceWindowsChanged: {
        pageTarget = Math.min(pageTarget, pageCount - 1);
        pageOffset = Math.min(pageOffset, pageCount - 1);
        currentPage = Math.round(pageOffset);
    }

    // 翻页跟手:pageOffset 用弹簧追 pageTarget,滚轮期间连续跟随,
    // 停手后 idleTimer 把目标吸附到最近整页,弹簧自然收敛。
    Behavior on pageOffset {
        SpringAnimation { spring: 6; damping: 0.42; epsilon: 0.0008 }
    }

    // ── 背景 ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#12151c" }
            GradientStop { position: 1.0; color: "#0a0c10" }
        }
    }

    // 点空白收起(卡片在其上层,会拦截点击)
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: if (root.effect) root.effect.requestClose()
    }

    // ── 卡片页 ──────────────────────────────────────────────────────────
    Item {
        id: pagesRow
        anchors.fill: parent
        x: -root.pageOffset * root.width

        Repeater {
            model: root.spaceWindows

            Card {
                required property var modelData
                required property int index

                window: modelData
                effect: root.effect
                page: Math.floor(index / root.cardsPerPage)
                col: index % root.cardCols
                row: Math.floor((index % root.cardsPerPage) / root.cardCols)
                padX: root.padX
                padY: root.padY
                gap: root.gap
                cellW: root.cellW
                cellH: root.cellH
                pageWidth: root.width
                prog: root.prog
            }
        }
    }

    // ── 翻页圆点 ────────────────────────────────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        spacing: 8
        visible: root.pageCount > 1 && root.prog > 0.95

        Repeater {
            model: root.pageCount

            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: index === Math.round(root.pageOffset) ? "#e8eaf0" : "#4d525e"
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ── 空状态 ──────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 6
        visible: root.spaceWindows.length === 0
        opacity: root.prog

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "这个 Space 没有窗口"
            color: "#9aa0ad"
            font.pixelSize: 17
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "双指上下滚动切换 Space · 四指下滑收起"
            color: "#5a5f6b"
            font.pixelSize: 12
        }
    }

    // ── 输入 ────────────────────────────────────────────────────────────
    WheelHandler {
        id: wheelHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (!root.effect) {
                return;
            }
            const pd = event.pixelDelta;
            const ad = event.angleDelta;
            // 触摸板给像素增量;普通滚轮给角度增量,粗略折算成像素
            const dx = pd.x !== 0 ? pd.x : ad.x / 8;
            const dy = pd.y !== 0 ? pd.y : ad.y / 8;

            if (Math.abs(dx) > Math.abs(dy)) {
                // 横向:翻页,逐帧跟手
                root.pageTarget = Math.max(0, Math.min(root.pageCount - 1,
                    root.pageTarget + dx / root.width));
                idleTimer.restart();
            } else {
                // 纵向:累积到阈值后切换 Space(Phase 3 暂为阈值触发)
                root.spaceAccum += dy;
                spaceIdleTimer.restart();
                if (Math.abs(root.spaceAccum) > 140) {
                    root.effect.switchSpace(root.spaceAccum > 0 ? 1 : -1);
                    root.spaceAccum = 0;
                }
                if (Math.abs(dx) > 0.5) {
                    idleTimer.restart();
                }
            }
        }
    }

    Timer {
        id: idleTimer
        interval: 150
        onTriggered: {
            root.pageTarget = Math.round(root.pageOffset);
            root.currentPage = Math.round(root.pageOffset);
        }
    }

    Timer {
        id: spaceIdleTimer
        interval: 240
        onTriggered: root.spaceAccum = 0
    }

    // 调试徽标:进度条式 progress 指示,验证期用,后续删
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: 120
        height: 4
        radius: 2
        color: "#3a3f4a"
        visible: root.effect !== null
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            height: parent.height
            width: parent.width * root.prog
            radius: 2
            color: "#7aa2f7"
        }
    }
}
