pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Demo.LiquidDialog {
    id: root
    CalendarStyle { id: design }
    property var sources: []
    property bool saving: false
    property string errorText: ""
    property string selectedPath: ""
    readonly property bool customSource: sourceSelect.currentIndex === 1
    readonly property bool fromFile: customSource && customSelect.currentIndex === 1
    readonly property var regionOptions: [{ id: "", label: qsTr("Choose a country or region") }].concat(
        sources.map(source => ({ id: source.id, label: qsTranslate("HolidayCalendarDialog", source.name) })))
    readonly property bool canAdd: nameField.text.trim().length > 0 && (customSource
        ? (fromFile ? selectedPath.length > 0 : addressField.text.trim().length > 0)
        : countrySelect.currentIndex > 0)
    signal addRequested(var source)
    title: qsTr("Add holiday calendar")
    modal: true
    popupType: Popup.Item
    closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
    width: Math.min(440, parent ? parent.width - 32 : 440)
    height: Math.min(customSource ? 390 : 330, parent ? parent.height - 32 : 390)
    anchors.centerIn: parent
    padding: 16
    header: Label {
        text: root.title
        color: design.labelPrimary
        font.pixelSize: 17
        font.weight: Font.DemiBold
        padding: 16
        bottomPadding: 8
    }
    function startAdding() {
        sourceSelect.currentIndex = 0
        customSelect.currentIndex = 0
        countrySelect.currentIndex = 0
        nameField.clear()
        addressField.clear()
        selectedPath = ""
        errorText = ""
        saving = false
        open()
    }
    function submit() {
        if (!canAdd || saving) return
        errorText = ""
        saving = true
        addRequested({ type: !customSource ? "country" : fromFile ? "file" : "url",
            name: nameField.text.trim(), region: regionOptions[countrySelect.currentIndex]?.id ?? "",
            url: addressField.text.trim(), path: selectedPath })
    }
    component SourceSelect: Demo.LiquidSelect {
        appearanceMode: AppTheme.dark ? "dark" : "light"
        plainTrigger: true
        indicatorStyle: "upDown"
        indicatorBackground: true
        materialForm: true
        popupMaterialForm: true
        sheetColor: AppTheme.dark ? "#303032" : "#f0f0f1"
        compactPopup: true
        popupBorderWidth: 0
        popupShadowEnabled: true
        popupFontWeight: Font.Normal
        neutralOptionHighlight: true
        onActivated: index => currentIndex = index
    }
    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 12
            enabled: !root.saving
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Source"); color: design.labelSecondary; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                SourceSelect { id: sourceSelect; objectName: "holidaySourceType"; model: [qsTr("Country or region"), qsTr("Custom")]; onCurrentIndexChanged: root.errorText = "" }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: !root.customSource
                Label { text: qsTr("Region"); color: design.labelSecondary; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                SourceSelect {
                    id: countrySelect
                    objectName: "holidayCountry"
                    model: root.regionOptions
                    textRole: "label"
                    onCurrentIndexChanged: {
                        const region = root.regionOptions[currentIndex]
                        if (currentIndex > 0 && region) nameField.text = qsTr("%1 holidays").arg(region.label)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.customSource
                Label { text: qsTr("Add using"); color: design.labelSecondary; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                SourceSelect { id: customSelect; objectName: "holidayCustomType"; model: [qsTr("Subscription address"), qsTr("Local file")] }
            }
            RowLayout {
                Layout.fillWidth: true
                Label { text: qsTr("Name"); color: design.labelSecondary; font.pixelSize: 12; Layout.preferredWidth: 56 }
                CalendarTextField {
                    id: nameField
                    objectName: "holidayCalendarName"
                    Layout.fillWidth: true
                    maximumLength: 128
                    placeholderText: qsTr("Calendar name")
                    Accessible.name: qsTr("Calendar name")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.customSource && !root.fromFile
                Label { text: qsTr("Address"); color: design.labelSecondary; font.pixelSize: 12; Layout.preferredWidth: 56 }
                CalendarTextField {
                    id: addressField
                    objectName: "holidaySubscriptionAddress"
                    Layout.fillWidth: true
                    placeholderText: "https://…"
                    maximumLength: 4096
                    Accessible.name: qsTr("Subscription address")
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.fromFile
                Label {
                    Layout.fillWidth: true
                    text: root.selectedPath.length ? decodeURIComponent(root.selectedPath.split("/").pop()) : qsTr("No file selected")
                    color: design.labelSecondary
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
                CalendarButton { objectName: "chooseHolidayFile"; text: qsTr("Choose file…"); onClicked: fileDialog.open() }
            }
            Label {
                Layout.fillWidth: true
                text: root.fromFile ? qsTr("Import holidays from an .ics file.")
                    : qsTr("Updates automatically each day. Saved holidays remain available offline.")
                color: design.labelSecondary
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Label {
                Layout.fillWidth: true
                visible: !root.customSource && countrySelect.currentIndex > 0
                text: qsTr("Source: Apple public holiday calendars")
                color: design.labelSecondary
                font.pixelSize: 10
            }
            Label {
                Layout.fillWidth: true
                visible: root.errorText.length > 0
                text: root.errorText
                color: design.statusWarning
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }
    footer: Item {
        implicitHeight: 62
        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8
            BusyIndicator { running: root.saving; visible: running; Layout.preferredWidth: 20; Layout.preferredHeight: 20 }
            Item { Layout.fillWidth: true }
            Demo.LiquidDialogButton { objectName: "cancelHolidayAdd"; text: qsTr("Cancel"); enabled: !root.saving; onClicked: root.close() }
            Demo.LiquidDialogButton { objectName: "confirmHolidayAdd"; text: root.saving ? qsTr("Adding…") : qsTr("Add"); primaryAction: true; enabled: root.canAdd && !root.saving; onClicked: root.submit() }
        }
    }
    FileDialog {
        id: fileDialog
        title: qsTr("Import holiday calendar")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("iCalendar files (*.ics)")]
        onAccepted: {
            root.selectedPath = selectedFile.toString()
            if (!nameField.text.trim().length)
                nameField.text = decodeURIComponent(root.selectedPath.split("/").pop()).replace(/\.ics$/i, "")
        }
    }
}
