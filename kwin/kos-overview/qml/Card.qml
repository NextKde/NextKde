import QtQuick
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami
import org.kde.kwin as KWinComponents

// 单张窗口卡片:实时缩略图 + 图标标题栏 + 悬停关闭按钮。
// 按页/列/行绝对定位在 Main.qml 的 pagesRow 内。
Rectangle {
    id: card

    property var window: null
    property var effect: null
    property int page: 0
    property int col: 0
    property int row: 0
    property real padX: 0
    property real padY: 0
    property real gap: 0
    property real cellW: 0
    property real cellH: 0
    property real pageWidth: 0
    property real prog: 0

    readonly property bool hovered: hoverHandler.hovering

    x: page * pageWidth + padX + col * (cellW + gap)
    y: padY + row * (cellH + gap)
    width: cellW
    height: cellH
    radius: Math.min(26, width * 0.09)
    color: "#171a21"
    border.width: hovered ? 1 : 0
    border.color: "#33ffffff"
    opacity: prog
    visible: prog > 0.01 && window !== null
    scale: 0.94 + 0.06 * prog

    // 圆角裁剪:层化后用同尺寸圆角矩形做透明度蒙版
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: card.width
            height: card.height
            radius: card.radius
        }
    }

    // 窗口缩略图按窗口原始宽高比 cover 式填充卡片,超出部分被圆角蒙版裁掉
    readonly property real winAspect: window ? window.width / Math.max(1.0, window.height) : 1.6

    Item {
        id: fit
        anchors.centerIn: parent
        width: card.winAspect >= card.width / card.height
               ? card.width
               : card.height * card.winAspect
        height: width / card.winAspect

        KWinComponents.WindowThumbnail {
            anchors.fill: parent
            wId: card.window ? card.window.internalId : undefined
            opacity: card.window && card.window.minimized ? 0.55 : 1.0
        }
    }

    // 顶部标题栏渐变,保证图标/文字可读
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 46
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#b3101218" }
            GradientStop { position: 1.0; color: "#00101218" }
        }
    }

    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: closeBtn.left
        anchors.margins: 10
        anchors.rightMargin: 4
        spacing: 8

        Kirigami.Icon {
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter
            source: card.window ? card.window.icon : ""
        }

        Text {
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            text: card.window ? card.window.caption : ""
            color: "#dfe3ea"
            font.pixelSize: 13
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    // 悬停关闭按钮
    Rectangle {
        id: closeBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: 24
        height: 24
        radius: 12
        color: hovered ? "#e8eaf0" : "#26101218"
        border.width: 1
        border.color: "#44ffffff"
        visible: card.window ? card.window.closeable : false
        opacity: hovered ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "×"
            color: closeBtn.hovered ? "#12151c" : "#dfe3ea"
            font.pixelSize: 16
        }

        TapHandler {
            onTapped: if (card.window) card.window.closeWindow()
        }
    }

    HoverHandler { id: hoverHandler }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: if (card.effect && card.window) card.effect.activateWindow(card.window)
    }
}
