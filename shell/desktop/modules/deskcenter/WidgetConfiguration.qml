import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"

Controls.Popup {
    id: root
    property string widgetId: ""
    property bool timerSelected: false
    signal clockModeChanged(bool timer)
    width: Math.min(420, (parent?.width || 460) - 32)
    height: Math.min(480, (parent?.height || 540) - 32)
    x: ((parent?.width || width) - width) / 2
    y: ((parent?.height || height) - height) / 2
    padding: 18
    modal: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

    function openFor(id) {
        widgetId = id
        open()
    }
    background: Rectangle {
        radius: 16
        color: ThemeService.backgroundColor
        border { width: 1; color: AppearanceTokens.colors.outlineVariant }
    }
    contentItem: Item {
        Text {
            id: heading
            width: parent.width
            text: WidgetRegistry.title(root.widgetId)
            textFormat: Text.PlainText
            color: ThemeService.foregroundColor
            font { pixelSize: 17; weight: Font.DemiBold }
            elide: Text.ElideRight
        }
        Flickable {
            id: scroll
            anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: actions.top; topMargin: 18; bottomMargin: 12 }
            clip: true
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
            Column {
                id: settingsColumn
                width: scroll.width
                spacing: 12
                Controls.ComboBox {
                    visible: root.widgetId === "clock"
                    width: parent.width
                    model: [I18n.tr("Clock"), I18n.tr("Timer")]
                    currentIndex: root.timerSelected ? 1 : 0
                    onActivated: root.clockModeChanged(currentIndex === 1)
                }
                Controls.Switch {
                    visible: root.widgetId === "music"
                    text: I18n.tr("Desktop Lyrics")
                    checked: DeskCenterConfigService.desktopLyricsEnabled
                    onToggled: DeskCenterConfigService.updateDesktopLyricsEnabled(checked)
                }
                Controls.Button {
                    visible: root.widgetId === "music"
                    text: I18n.tr("Move Desktop Lyrics")
                    onClicked: { DeskCenterConfigService.editDesktopLyrics(); root.close() }
                }
                Text {
                    width: parent.width
                    visible: ["weather", "calendar", "todo"].indexOf(root.widgetId) >= 0
                    text: I18n.tr("Choose locations, calendars and reminders in the application.")
                    color: ThemeService.foregroundColor
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                }
                Controls.Button {
                    visible: ["weather", "calendar", "todo"].indexOf(root.widgetId) >= 0
                    text: I18n.tr("Open Application")
                    onClicked: {
                        const app = root.widgetId === "weather" ? "weather" : "calendar"
                        IndependentAppWidgetService.open(app, root.widgetId === "todo" ? {view: "reminders"} : {})
                        root.close()
                    }
                }
            }
        }
        Row {
            id: actions
            anchors { right: parent.right; bottom: parent.bottom }
            spacing: 8
            Controls.Button {
                text: I18n.tr("Done")
                onClicked: root.close()
            }
        }
    }
}
