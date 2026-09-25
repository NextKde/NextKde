import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.applauncher
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// A read-only, click-through lyric surface. One window exists per usable
// output, but only the active output maps it so lyrics never duplicate.
Scope {
    Variants {
        model: ScreenLifecycle.usableScreens

        delegate: Component {
            PanelWindow {
                id: lyricWindow

                required property var modelData
                readonly property string currentLine: DockMprisService.currentLyric
                readonly property string nextLine: DockMprisService.nextLyric

                screen: modelData
                visible: ScreenLifecycle.outputAvailable
                    && ConfigService.desktopLyricsEnabled
                    && modelData?.name === ScreenLifecycle.activeScreen?.name
                    && currentLine.length > 0
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "kos-desktop-lyrics"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors { left: true; right: true; bottom: true }
                margins.bottom: ConfigService.position === "bottom"
                    ? Math.max(104, AppLauncherService.dockHeight + 28) : 38
                implicitHeight: 112

                // No input region: every pixel, including the text, passes
                // through to the application or desktop underneath.
                mask: Region {}

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Math.min(parent.width - 80, 820)
                    height: nextText.visible ? 76 : 54
                    radius: 22
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.66)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.20)

                    KosLyricLine {
                        id: currentText
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.topMargin: nextText.visible ? 13 : 14
                        text: lyricWindow.currentLine
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font { pixelSize: 20; weight: Font.DemiBold }
                    }

                    KosLyricLine {
                        id: nextText
                        anchors { left: parent.left; right: parent.right; top: currentText.bottom }
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.topMargin: 5
                        visible: text.length > 0
                        text: lyricWindow.nextLine
                        color: Qt.rgba(1, 1, 1, 0.58)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
