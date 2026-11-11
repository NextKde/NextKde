import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"

Controls.Popup {
    id: root
    property string widgetId: ""
    property var draft: ({})
    property var schema: []
    property string error: ""
    property bool saving: false
    property bool timerSelected: false
    readonly property bool plugin: WidgetRegistry.isPlugin(widgetId)
    signal clockModeChanged(bool timer)
    width: Math.min(420, (parent?.width || 460) - 32)
    height: Math.min(480, (parent?.height || 540) - 32)
    x: ((parent?.width || width) - width) / 2
    y: ((parent?.height || height) - height) / 2
    padding: 18
    modal: true
    focus: true
    closePolicy: saving ? Controls.Popup.NoAutoClose : Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

    function openFor(id) {
        widgetId = id
        const instance = PluginWidgetService.instance(id)
        draft = PluginWidgetService.plain(instance?.settings, {})
        schema = PluginWidgetService.plain(instance?.settingsSchema, [])
        error = ""
        open()
    }
    function update(key, value) {
        const next = Object.assign({}, draft)
        next[key] = value
        draft = next
    }
    function validationError() {
        for (const field of schema) {
            const value = draft[field.key]
            if (field.type === "number" && (!Number.isInteger(value) || value < field.min || value > field.max))
                return I18n.tr("Enter a whole number within the allowed range.")
            if (field.type === "string" && (typeof value !== "string" || value.length > field.maxLength))
                return I18n.tr("The text is too long.")
            if (field.type === "boolean" && typeof value !== "boolean") return I18n.tr("Choose a valid setting.")
        }
        return ""
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
            anchors { left: parent.left; right: parent.right; top: heading.bottom; bottom: feedback.top; topMargin: 18; bottomMargin: 12 }
            clip: true
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
            Column {
                id: settingsColumn
                width: scroll.width
                spacing: 14
                Repeater {
                    model: root.schema
                    delegate: Column {
                        id: fieldRow
                        required property var modelData
                        width: settingsColumn.width
                        spacing: 6
                        Text {
                            width: parent.width
                            text: fieldRow.modelData.label
                            textFormat: Text.PlainText
                            color: ThemeService.foregroundColor
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                        Loader {
                            width: parent.width
                            sourceComponent: fieldRow.modelData.type === "boolean" ? booleanEditor
                                : fieldRow.modelData.type === "number" ? numberEditor : stringEditor
                        }
                        Component {
                            id: booleanEditor
                            Controls.Switch {
                                checked: !!root.draft[fieldRow.modelData.key]
                                onToggled: root.update(fieldRow.modelData.key, checked)
                            }
                        }
                        Component {
                            id: numberEditor
                            Column {
                                spacing: 4
                                Controls.TextField {
                                    width: parent.width
                                    text: String(root.draft[fieldRow.modelData.key] ?? fieldRow.modelData.default)
                                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                                    selectByMouse: true
                                    onTextEdited: root.update(fieldRow.modelData.key, text.trim().length ? Number(text) : NaN)
                                }
                                Text {
                                    text: String(fieldRow.modelData.min) + " – " + String(fieldRow.modelData.max)
                                    color: ThemeService.foregroundColor
                                    opacity: 0.65
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Component {
                            id: stringEditor
                            Controls.TextField {
                                text: String(root.draft[fieldRow.modelData.key] ?? fieldRow.modelData.default)
                                maximumLength: fieldRow.modelData.maxLength
                                selectByMouse: true
                                onTextEdited: root.update(fieldRow.modelData.key, text)
                            }
                        }
                    }
                }
                Column {
                    visible: !root.plugin
                    width: parent.width
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
        }
        Text {
            id: feedback
            anchors { left: parent.left; right: parent.right; bottom: actions.top; bottomMargin: 12 }
            text: root.error
            textFormat: Text.PlainText
            visible: text.length > 0
            color: ThemeService.foregroundColor
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
        Row {
            id: actions
            anchors { right: parent.right; bottom: parent.bottom }
            spacing: 8
            Controls.Button {
                text: I18n.tr("Cancel")
                visible: root.plugin
                enabled: !root.saving
                onClicked: root.close()
            }
            Controls.Button {
                text: root.saving ? I18n.tr("Saving…") : I18n.tr("Done")
                enabled: !root.saving
                onClicked: {
                    if (!root.plugin) { root.close(); return }
                    root.error = root.validationError()
                    if (root.error) return
                    root.saving = true
                    PluginWidgetService.configure(root.widgetId, {settings: root.draft}, function(ok) {
                        root.saving = false
                        if (ok) root.close()
                        else root.error = PluginWidgetService.error
                    })
                }
            }
        }
    }
}
