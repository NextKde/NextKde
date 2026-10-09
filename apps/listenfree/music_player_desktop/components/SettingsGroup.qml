pragma ComponentBehavior: Bound

import QtQuick

Column {
    id: group

    property string section: ""
    property var rows: []
    property var settingsStore: null
    property var shortcutService: typeof backendShortcuts !== "undefined" ? backendShortcuts : null
    function stored(key, fallback) {
        if (!settingsStore) return fallback
        const revision = settingsStore.revision
        return settingsStore.value(key, fallback)
    }
    property int categoryIndex: -1
    property string categoryTitle: ""
    property string filterText: ""
    readonly property var filteredRows: {
        const words = filterText.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
        return rows.filter(function(row) {
            if(row.visible === false)return false
            const options = (row.options || []).map(function(option) { return option.label || option }).join(" ")
            const text = [categoryTitle, section, row.title, row.detail, row.actionLabel, options].join(" ").toLocaleLowerCase()
            return words.every(function(word) { return text.indexOf(word) >= 0 })
        })
    }
    readonly property bool hasMatches: filteredRows.length > 0
    property bool darkMode: false
    property color panelColor: darkMode ? "#2d3944" : "#fcffffff"
    property color primaryText: darkMode ? "#f2f5f7" : "#25272a"
    property color secondaryText: darkMode ? "#b6c0c8" : "#7d8186"
    property color sectionColor: secondaryText
    signal settingChanged(string key, var value)
    signal actionTriggered(string key)

    width: parent ? parent.width : implicitWidth
    spacing: 7

    Text {
        text: group.section.toUpperCase()
        color: group.sectionColor
        font.family: AppTheme.fontFamily
        font.pixelSize: 10
        font.letterSpacing: 0.3
    }

    Rectangle {
        width: parent.width
        height: group.filteredRows.length * 50 + 2
        radius: 14
        color: group.panelColor
        border.width: 1
        border.color: group.darkMode ? "#24ffffff" : "#70ffffff"

        Column {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 1

            Repeater {
                model: group.filteredRows
                delegate: SettingsRow {
                    id: settingRow
                    required property int index
                    required property var modelData

                    objectName: "settingRow/" + settingKey
                    width: parent.width
                    title: modelData.title || ""
                    detail: modelData.detail || ""
                    settingKey: modelData.key || "settings.unmapped"
                    controlType: modelData.type || "info"
                    shortcutService: group.shortcutService
                    actionLabel: modelData.actionLabel || modelData.value || ""
                    options: modelData.options || []
                    optionValue: modelData.optionValue
                    currentIndex: {
                        const fallback = modelData.currentIndex === undefined ? 0 : modelData.currentIndex
                        const saved = group.stored(settingKey, options[fallback] ? options[fallback].value : "")
                        for (let i = 0; i < options.length; ++i) if (options[i].value === saved) return i
                        return fallback
                    }
                    checked: {
                        if (group.shortcutService && (settingKey === "shortcuts.global.enabled" || settingKey === "shortcuts.application.enabled")) {
                            const revision = group.shortcutService.revision
                            return group.shortcutService.enabled(settingKey.split(".")[1])
                        }
                        return group.stored(settingKey + (modelData.optionValue === undefined ? "" : "." + modelData.optionValue), modelData.checked === undefined ? false : modelData.checked)
                    }
                    numericValue: Math.max(minimumValue, Math.min(maximumValue, group.stored(settingKey, modelData.numericValue === undefined ? 0 : modelData.numericValue)))
                    minimumValue: modelData.minimumValue === undefined ? 0 : modelData.minimumValue
                    maximumValue: modelData.maximumValue === undefined ? 1 : modelData.maximumValue
                    stepSize: modelData.stepSize === undefined ? 1 : modelData.stepSize
                    valueSuffix: modelData.valueSuffix || ""
                    readOnlyValue: modelData.readOnlyValue || modelData.value || ""
                    textValue: group.stored(settingKey, modelData.textValue || "")
                    placeholderText: modelData.placeholderText || ""
                    enabled: modelData.enabled === undefined ? true : modelData.enabled
                    darkMode: group.darkMode
                    primaryText: group.primaryText
                    secondaryText: group.secondaryText
                    z: settingRow.menuOpen ? group.filteredRows.length + 10 : group.filteredRows.length - settingRow.index

                    Rectangle {
                        visible: settingRow.index > 0
                        anchors.top: parent.top
                        objectName: "settingRow/" + settingKey
                    width: parent.width
                        height: 1
                        color: group.darkMode ? "#18ffffff" : "#12000000"
                    }

                    onSettingChanged: (key, value) => { if (value && typeof value === "object" && value.option !== undefined) group.settingChanged(key + "." + value.option, value.checked); else group.settingChanged(key, value) }
                    onActionTriggered: key => group.actionTriggered(key)
                }
            }
        }
    }
}
