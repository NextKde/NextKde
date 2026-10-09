import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.applauncher
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// Lyrics pass clicks through except for the visible Move button. Placement
// mode temporarily accepts input over the card on the active output.
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
                    && DeskCenterConfigService.desktopLyricsActive
                    && DockMprisService.desktopLyricsAllowed
                    && modelData?.name === ScreenLifecycle.activeScreen?.name
                    && (currentLine.length > 0 || DeskCenterConfigService.desktopLyricsEditing)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "kos-desktop-lyrics"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors { left: true; right: true; top: true; bottom: true }
                readonly property real bottomInset: ConfigService.position === "bottom"
                    ? Math.max(104, AppLauncherService.dockHeight + 28) : 38
                mask: Region { item: DeskCenterConfigService.desktopLyricsEditing ? lyricCard : moveButton }

                Rectangle {
                    id: lyricCard
                    readonly property real travelX: Math.max(0, lyricWindow.width - width)
                    readonly property real travelY: Math.max(0, lyricWindow.height - lyricWindow.bottomInset - height)
                    x: DeskCenterConfigService.desktopLyricsX * travelX
                    y: DeskCenterConfigService.desktopLyricsY * travelY
                    width: Math.max(1, Math.min(lyricWindow.width - 24, 820))
                    height: (nextText.visible ? 76 : 54) + (DeskCenterConfigService.desktopLyricsEditing ? 34 : 0)
                    radius: 22
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.66)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.20)

                    MouseArea {
                        anchors.fill: parent
                        anchors.bottomMargin: 34
                        enabled: DeskCenterConfigService.desktopLyricsEditing
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        property point startPointer
                        property real startX
                        property real startY
                        onPressed: mouse => {
                            startPointer = mapToItem(lyricWindow.contentItem, mouse.x, mouse.y)
                            startX = DeskCenterConfigService.desktopLyricsX
                            startY = DeskCenterConfigService.desktopLyricsY
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return
                            const point = mapToItem(lyricWindow.contentItem, mouse.x, mouse.y)
                            DeskCenterConfigService.desktopLyricsX = Math.max(0, Math.min(1,
                                startX + (point.x - startPointer.x) / Math.max(1, lyricCard.travelX)))
                            DeskCenterConfigService.desktopLyricsY = Math.max(0, Math.min(1,
                                startY + (point.y - startPointer.y) / Math.max(1, lyricCard.travelY)))
                        }
                        onReleased: DeskCenterConfigService.updateDesktopLyricsPosition(
                            DeskCenterConfigService.desktopLyricsX, DeskCenterConfigService.desktopLyricsY)
                        onCanceled: DeskCenterConfigService.updateDesktopLyricsPosition(
                            DeskCenterConfigService.desktopLyricsX, DeskCenterConfigService.desktopLyricsY)
                    }
                    Rectangle {
                        id: moveButton
                        objectName: "desktop-lyrics-move"
                        visible: !DeskCenterConfigService.desktopLyricsEditing
                        anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 12 }
                        width: 62
                        height: 28
                        radius: 9
                        color: movePointer.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.12)
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("↔ 移动")
                            color: "white"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: movePointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DeskCenterConfigService.editDesktopLyrics()
                        }
                    }
                    Row {
                        visible: DeskCenterConfigService.desktopLyricsEditing
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 9 }
                        spacing: 28
                        Text {
                            text: qsTr("拖动歌词框调整位置")
                            color: Qt.rgba(1, 1, 1, 0.72)
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: [qsTr("恢复默认位置"), qsTr("完成")]
                            delegate: Text {
                                required property int index
                                required property string modelData
                                text: modelData
                                color: "white"
                                font.pixelSize: 12
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (index === 0) DeskCenterConfigService.updateDesktopLyricsPosition(0.5, 1)
                                        else DeskCenterConfigService.desktopLyricsEditing = false
                                    }
                                }
                            }
                        }
                    }

                    KosLyricLine {
                        id: currentText
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.leftMargin: DeskCenterConfigService.desktopLyricsEditing ? 22 : 84
                        anchors.rightMargin: DeskCenterConfigService.desktopLyricsEditing ? 22 : 84
                        anchors.topMargin: nextText.visible ? 13 : 14
                        text: lyricWindow.currentLine || (DeskCenterConfigService.desktopLyricsEditing ? qsTr("拖动这里调整歌词位置") : "")
                        color: "white"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font { pixelSize: 20; weight: Font.DemiBold }
                    }

                    KosLyricLine {
                        id: nextText
                        anchors { left: parent.left; right: parent.right; top: currentText.bottom }
                        anchors.leftMargin: DeskCenterConfigService.desktopLyricsEditing ? 22 : 84
                        anchors.rightMargin: DeskCenterConfigService.desktopLyricsEditing ? 22 : 84
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
