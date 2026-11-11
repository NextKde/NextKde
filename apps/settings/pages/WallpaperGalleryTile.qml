import "../../../shared/qml/i18n"
import QtQuick
import Kos.Icons as Symbols

Rectangle {
    id: tile

    property string imagePath: ""
    property string swatchColor: ""
    property color accent: "#64d2ff"
    property color surroundingColor: "#1c1c1e"
    property bool selected: false
    property bool selectionMode: false
    // 缩略图缓存文件 URL;空 = 用原图直载(首开或缓存未生成时)。
    property string thumbSource: ""
    // 有对应图集条目(直入图片或所属文件夹)才显示移除;纯色与系统壁纸没有。
    property bool removable: false
    // 有路径可打开所在文件夹;纯色瓦片没有。
    property bool revealable: false
    readonly property bool isSwatch: swatchColor.length > 0

    signal activated()
    signal revealRequested()
    signal removeRequested()

    // 圆角由缩略图烘出(角外透明,瓦片背景透出),瓦片矩形保持 radius 15 让
    // 描边/选中高亮跟随;无 MultiEffect、无蒙版图层。原图回退加载是方角的
    // 短暂过渡态。缩略图未生成前由直角→圆角切换肉眼几乎不可见。
    radius: 15
    color: isSwatch ? swatchColor : surroundingColor
    border.width: selected ? 3 : 1
    border.color: selected ? accent
        : tileMouse.containsMouse ? "#80ffffff" : "#30ffffff"
    Behavior on border.color { ColorAnimation { duration: 150 } }

    // 缩略图直出:无 MultiEffect、无蒙版图层——圆角已按设备像素烘进缓存图
    // (角外透明),这是"展开全部"模型下免掉每瓦片一层 FBO 的关键。未命中
    // 缓存时退回原图直载(方角过渡态),解码由 sourceSize 限幅。
    Image {
        id: picture
        anchors.fill: parent
        anchors.margins: tile.border.width
        source: tile.isSwatch ? "" : (tile.thumbSource
            || (tile.imagePath.startsWith("/")
                ? "file://" + tile.imagePath : tile.imagePath))
        // 缩略图按原生尺寸直载(生成时已按 dpr 烘好);原图限幅到瓦片尺寸
        // (Qt 内部再乘 dpr,不手动 ×2 翻倍内存)。
        sourceSize: tile.thumbSource.length > 0
            ? Qt.size(0, 0)
            : Qt.size(Math.max(1, tile.width), Math.max(1, tile.height))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        visible: !tile.isSwatch && picture.status === Image.Ready
    }

    // 原文件被删除/不可读时的占位:不留纯空白瓦片,让人知道它为什么空着。
    // 去抖:异步加载被换源取消(缩略图生成完毕切源,首开导入必现)会被 Qt
    // 报告成一次瞬时 Error,直接显示会闪"图片不存在";滞留 600ms 仍是
    // Error 才是真死链。
    readonly property bool imageMissing: picture.status === Image.Error
        && missingLinger.expired
    Timer {
        id: missingLinger
        property bool expired: false
        interval: 600
        onTriggered: expired = true
        running: picture.status === Image.Error
        // 每轮新 Error 重新计时,上一次的 triggered 不许残留。
        onRunningChanged: if (running) missingLinger.expired = false
    }
    Text {
        anchors.centerIn: parent
        visible: !tile.isSwatch && tile.imageMissing
        text: I18n.tr("Image missing")
        color: "#8e8e93"
        font.pixelSize: 12
    }

    // 右上角一排悬停控件:打开文件夹 / 移除 / 选中或应用指示。z 必须高于
    // tileMouse(整瓦片点击=应用):QML 后声明者在上,tileMouse 声明更晚,
    // 不提 z 点击会先落到它上面直接应用壁纸。
    Row {
        z: 1
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        spacing: 6

        component HoverButton: Rectangle {
            id: hoverButton
            property string iconName: ""
            signal clicked()
            width: 22
            height: 22
            radius: 11
            // 实心黑 + 白描边:半透明底在浅色壁纸上不够显眼。
            color: "#000000"
            border.width: 1
            // 七成白,不刺眼但仍有描边感
            border.color: "#B3FFFFFF"
            visible: tileMouse.containsMouse && !tile.isSwatch
            Symbols.Icon {
                anchors.centerIn: parent
                size: 14
                name: hoverButton.iconName
                color: "white"
            }
            MouseArea {
                anchors.fill: parent
                // 不开 hoverEnabled:开了会把 hover 从 tileMouse 抢走,按钮一
                // 出现就把自己藏掉,再出现,无限闪烁。点击不受影响,手型光标
                // 由底下 tileMouse 提供。
                cursorShape: Qt.PointingHandCursor
                onClicked: hoverButton.clicked()
            }
        }

        HoverButton {
            iconName: "folder"
            visible: tileMouse.containsMouse && tile.revealable
            onClicked: tile.revealRequested()
        }
        HoverButton {
            iconName: "xmark"
            visible: tileMouse.containsMouse && tile.removable
            onClicked: tile.removeRequested()
        }
        Rectangle {
            width: 22
            height: 22
            radius: 11
            color: tile.selected ? tile.accent : "#88000000"
            visible: tile.selectionMode || tile.selected || tileMouse.containsMouse
            Symbols.Icon {
                anchors.centerIn: parent
                size: 14
                visible: !tile.selectionMode || tile.selected
                name: tile.selected ? "checkmark" : "arrow_up_right"
                color: tile.selected ? "#17202a" : "white"
            }
        }
    }

    MouseArea {
        id: tileMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
