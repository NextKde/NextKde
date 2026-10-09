import QtQuick
import QtQuick.Controls as Basic

Item {
    id: row

    property string title: ""
    property string detail: ""
    property string settingKey: ""
    property string controlType: "info"
    property string actionLabel: ""
    property var shortcutService: null
    readonly property bool recording: controlType === "shortcut" && shortcutService && shortcutService.recordingKey === settingKey
    readonly property bool shortcutConflict: controlType === "shortcut" && shortcutService && shortcutService.conflictKey === settingKey
    readonly property string shortcutText: {
        if (!shortcutService) return actionLabel
        const revision = shortcutService.revision
        return shortcutService.binding(settingKey) || qsTr("未设置")
    }
    property var options: []
    property var optionValue: undefined
    property int currentIndex: 0
    property bool checked: false
    property real numericValue: 0
    property real minimumValue: 0
    property real maximumValue: 1
    property real stepSize: 1
    property string valueSuffix: ""
    property string readOnlyValue: ""
    property string textValue: ""
    property string placeholderText: ""
    property bool darkMode: false
    property color primaryText: darkMode ? "#f2f5f7" : "#25272a"
    property color secondaryText: darkMode ? "#b6c0c8" : "#7d8186"
    readonly property bool menuOpen: selectControl.menuOpen

    signal settingChanged(string key, var value)
    signal actionTriggered(string key)

    implicitHeight: 50

    function clampAndStep(value) {
        const bounded = Math.max(minimumValue, Math.min(maximumValue, value))
        if (stepSize <= 0)
            return bounded
        return minimumValue + Math.round((bounded - minimumValue) / stepSize) * stepSize
    }

    Column {
        anchors.left: parent.left
        anchors.right: editor.left
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: row.title
            color: row.primaryText
            elide: Text.ElideRight
            font.family: AppTheme.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: row.recording ? (row.shortcutService.error || qsTr("Esc 取消；点击右侧 × 清空绑定")) : row.shortcutConflict ? qsTr("此项与刚录入的快捷键冲突") : row.detail
            textFormat: Text.PlainText
            HoverHandler { id: detailHover }
            Basic.ToolTip.visible: truncated && detailHover.hovered
            Basic.ToolTip.text: text
            Basic.ToolTip.delay: 500
            color: row.shortcutConflict || (row.recording && row.shortcutService.error.length) ? "#e46d69" : row.secondaryText
            elide: Text.ElideRight
            font.family: AppTheme.fontFamily
            font.pixelSize: 10
        }
    }

    Item {
        id: editor
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 206
        height: 32

        SettingsSwitch {
            objectName: "settingSwitch/" + row.settingKey
            controlled: row.settingKey.startsWith("shortcuts.")
            visible: row.controlType === "toggle"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: row.checked
            darkMode: row.darkMode
            enabled: row.enabled
            onToggled: value => {
                if (!row.settingKey.startsWith("shortcuts.")) row.checked = value
                row.settingChanged(row.settingKey, value)
            }
        }

        SettingsCheckBox {
            visible: row.controlType === "check"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: row.checked
            darkMode: row.darkMode
            enabled: row.enabled
            onToggled: value => {
                row.checked = value
                row.settingChanged(row.settingKey, row.optionValue === undefined
                                   ? value : ({ option: row.optionValue, checked: value }))
            }
        }

        SettingsSelect {
            id: selectControl
            visible: row.controlType === "select"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, implicitWidth)
            options: row.options
            currentIndex: row.currentIndex
            darkMode: row.darkMode
            enabled: row.enabled
            onValueSelected: (value, index) => {
                row.settingChanged(row.settingKey, value)
            }
        }

        Rectangle {
            visible: row.controlType === "text"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 30
            radius: 8
            color: row.darkMode ? "#35414b" : "#fbfbfc"
            border.width: textInput.activeFocus ? 2 : 1
            border.color: textInput.activeFocus ? AppTheme.accent : (row.darkMode ? "#59656e" : "#d5d9dd")

            TextInput {
                id: textInput
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 11
                verticalAlignment: TextInput.AlignVCenter
                text: row.textValue
                color: row.primaryText
                selectionColor: "#586b747d"
                selectedTextColor: row.darkMode ? "white" : "#16232d"
                clip: true
                enabled: row.enabled
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
                onEditingFinished: {
                    row.textValue = text
                    row.settingChanged(row.settingKey, text)
                }
            }

            Text {
                visible: textInput.text.length === 0 && !textInput.activeFocus
                anchors.left: parent.left
                anchors.leftMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                text: row.placeholderText
                color: row.secondaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
            }
        }

        Rectangle {
            id: actionButton
            visible: row.controlType === "action" || row.controlType === "shortcut"
            anchors.right: parent.right
            anchors.rightMargin: row.controlType === "shortcut" ? 28 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(68, actionText.implicitWidth + 26)
            height: 30
            radius: 15
            color: row.recording || (actionHover.hovered && row.enabled) ? AppTheme.accent : (row.darkMode ? "#3b4751" : "#f8fafb")
            border.width: 1
            border.color: row.shortcutConflict ? "#e46d69" : row.recording || (actionHover.hovered && row.enabled) ? AppTheme.accent : (row.darkMode ? "#59656e" : "#d5dde2")
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: row.title + "：" + actionText.text
            function activate() {
                if (row.controlType === "shortcut" && row.shortcutService) row.shortcutService.beginCapture(row.settingKey)
                else row.actionTriggered(row.settingKey)
            }
            Keys.onReturnPressed: activate()
            Keys.onSpacePressed: activate()

            Text {
                id: actionText
                objectName: "shortcutBindingLabel/" + row.settingKey
                anchors.centerIn: parent
                text: row.controlType === "shortcut" ? (row.recording ? qsTr("请按下你要设置的按键") : row.shortcutText) : row.actionLabel
                color: row.recording || (actionHover.hovered && row.enabled) ? "white" : row.primaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
            }
            HoverHandler { id: actionHover }
            TapHandler {
                enabled: row.enabled
                onTapped: { actionButton.forceActiveFocus(); actionButton.activate() }
            }
        }

        Item {
            visible: row.controlType === "shortcut"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 30
            activeFocusOnTab: visible
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("清空") + row.title + qsTr("快捷键")
            function clearBinding() {
                if (!row.shortcutService) return
                row.shortcutService.cancelCapture()
                row.shortcutService.setBinding(row.settingKey, "")
            }
            Keys.onReturnPressed: clearBinding()
            Keys.onSpacePressed: clearBinding()
            IconGlyph { anchors.centerIn: parent; width: 12; height: 12; kind: "close"; glyphColor: row.secondaryText }
            TapHandler { onTapped: parent.clearBinding() }
        }

        Item {
            visible: row.controlType === "slider"
            anchors.fill: parent

            ProgressBar {
                anchors.left: parent.left
                anchors.right: sliderValue.left
                anchors.rightMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                interactive: row.enabled
                value: row.maximumValue === row.minimumValue ? 0 : (row.numericValue - row.minimumValue) / (row.maximumValue - row.minimumValue)
                trackColor: row.darkMode ? "#55616b" : "#e5e7e9"
                fillColor: AppTheme.accent
                handleColor: "white"
                onValueChangedByUser: value => {
                    row.numericValue = row.clampAndStep(row.minimumValue + value * (row.maximumValue - row.minimumValue))
                    row.settingChanged(row.settingKey, row.numericValue)
                }
            }
            Text {
                id: sliderValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.numericValue + row.valueSuffix
                color: row.secondaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
            }
        }

        Item {
            visible: row.controlType === "progress"
            anchors.fill: parent

            Rectangle {
                anchors.left: parent.left
                anchors.right: progressValue.left
                anchors.rightMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                height: 5
                radius: height / 2
                color: row.darkMode ? "#55616b" : "#e5e7e9"
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, row.numericValue))
                    height: parent.height
                    radius: parent.radius
                    color: AppTheme.accent
                }
            }
            Text {
                id: progressValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.readOnlyValue
                color: row.secondaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
            }
        }

        Text {
            visible: row.controlType === "info"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: row.readOnlyValue
            color: row.secondaryText
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
        }
    }

    opacity: enabled ? 1 : 0.5
}
