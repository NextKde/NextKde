import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls

Dialog {
    id: dialog
    property var colors
    property string fitMode: "crop"
    property string transition: "cinematic"
    property bool takeoverEnabled: false
    property bool takeoverAvailable: false
    property bool takeoverPending: false
    signal fitChosen(string mode)
    signal transitionChosen(string style)
    signal takeoverChosen(bool enabled)
    title: "壁纸选项"
    background: Rectangle {
        radius: 22
        color: dialog.colors.dark ? "#ed25282e" : "#f8f9fbfd"
        border.color: dialog.colors.dark ? "#62ffffff" : "#aaffffff"
        border.width: 1
    }
    header: Text {
        text: dialog.title
        color: dialog.colors.primaryText
        font.pixelSize: 16
        font.weight: Font.DemiBold
        leftPadding: 18
        topPadding: 17
        bottomPadding: 12
    }
    modal: true
    width: 420
    anchors.centerIn: Overlay.overlay
    footer: Item {
        implicitHeight: 48
        WallpaperTextButton {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            label: "完成"
            colors: dialog.colors
            emphasized: true
            onClicked: dialog.close()
        }
    }
    contentItem: ColumnLayout {
        spacing: 8
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: rows.implicitHeight
            radius: 18
            color: dialog.colors.card
            Column {
                id: rows
                width: parent.width
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: "填充方式"
                    separator: true
                    WallpaperValueMenu {
                        width: 142
                        objectName: "wallpaperFitMenu"
                        colors: dialog.colors
                        backdropSource: dialog.contentItem
                        model: ["填满屏幕", "完整显示", "拉伸", "居中"]
                        currentIndex: Math.max(0, ["crop", "fit", "stretch", "center"].indexOf(dialog.fitMode))
                        onActivated: function(index) {
                            dialog.fitChosen(["crop", "fit", "stretch", "center"][index])
                        }
                    }
                }
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: "切换效果"
                    separator: true
                    WallpaperValueMenu {
                        width: 142
                        objectName: "wallpaperTransitionMenu"
                        colors: dialog.colors
                        backdropSource: dialog.contentItem
                        model: ["柔和揭幕", "淡入淡出", "关闭"]
                        currentIndex: Math.max(0, ["cinematic", "fade", "none"].indexOf(dialog.transition))
                        onActivated: function(index) {
                            dialog.transitionChosen(["cinematic", "fade", "none"][index])
                        }
                    }
                }
                WallpaperSettingsRow {
                    width: parent.width
                    colors: dialog.colors
                    label: "由 KOS 显示壁纸"
                    LiquidControls.LiquidGlassSwitch {
                        id: toggle
                        enabled: dialog.takeoverAvailable && !dialog.takeoverPending
                        checked: dialog.takeoverEnabled
                        accentColor: dialog.colors.accent
                        trackColor: dialog.colors.divider
                        onToggled: function(checked) {
                            dialog.takeoverChosen(checked)
                            toggle.checked = Qt.binding(() => dialog.takeoverEnabled)
                        }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: dialog.takeoverAvailable
                ? "关闭 KOS 壁纸后恢复 Plasma 壁纸。开启空间壁纸会暂停自动切换。"
                : "当前平台服务版本不支持壁纸接管，请更新后再使用。"
            color: dialog.colors.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
}
