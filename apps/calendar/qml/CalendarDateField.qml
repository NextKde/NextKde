pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Kos.Ui

CalendarTextField {
    id: control
    property var parseDate: function(value) { return Date.fromLocaleDateString(Qt.locale(), value, Locale.ShortFormat) }
    property var formatDate: function(value) { return Qt.formatDate(value, Locale.ShortFormat) }
    property var calendarLocale: Qt.locale()
    property date cursorDate: new Date()
    property date displayedMonth: new Date()
    signal dateSelected(date value)
    rightPadding: 30
    CalendarStyle { id: design }

    function validDate(value) { return value && !isNaN(value.getTime()) }
    function sameDay(a, b) {
        return validDate(a) && validDate(b) && a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }
    function showPicker() {
        const parsed = parseDate(text)
        cursorDate = validDate(parsed) ? parsed : new Date()
        displayedMonth = new Date(cursorDate.getFullYear(), cursorDate.getMonth(), 1)
        picker.open()
        dayGrid.forceActiveFocus()
    }
    function selectDate(value) {
        text = formatDate(value)
        dateSelected(value)
        picker.close()
        forceActiveFocus()
    }
    function moveCursor(days) {
        cursorDate = new Date(cursorDate.getFullYear(), cursorDate.getMonth(), cursorDate.getDate() + days)
        displayedMonth = new Date(cursorDate.getFullYear(), cursorDate.getMonth(), 1)
    }
    function moveMonth(delta) {
        const next = new Date(displayedMonth.getFullYear(), displayedMonth.getMonth() + delta, 1)
        const last = new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate()
        displayedMonth = next
        cursorDate = new Date(next.getFullYear(), next.getMonth(), Math.min(cursorDate.getDate(), last))
    }
    // Observe taps without taking over text selection/drag handling.
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: if (!picker.visible) control.showPicker()
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down && (event.modifiers & Qt.AltModifier)) {
            showPicker(); event.accepted = true
        }
    }
    ToolButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 3
        width: 24; height: 24
        Accessible.name: qsTr("Choose date")
        background: Rectangle { radius: 12; color: parent.hovered ? design.rowHoverFill : "transparent" }
        contentItem: Item {
            Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 2
                color: "transparent"; border.width: 1; border.color: design.labelSecondary
                Rectangle { x: 1; y: 3; width: 10; height: 1; color: design.labelSecondary }
                Rectangle { x: 3; y: 6; width: 2; height: 2; radius: 0.5; color: design.labelSecondary }
                Rectangle { x: 7; y: 6; width: 2; height: 2; radius: 0.5; color: design.labelSecondary }
            }
        }
        onClicked: control.showPicker()
    }
    Popup {
        id: picker
        parent: Overlay.overlay
        popupType: Popup.Item
        width: Math.min(272, parent ? parent.width - 16 : 272)
        height: contentItem.implicitHeight + topPadding + bottomPadding
        padding: 10
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: {
            const p = control.mapToItem(parent, 0, 0)
            x = Math.max(8, Math.min(parent.width - width - 8, p.x))
            y = p.y + control.height + 4 + height <= parent.height - 8
                ? p.y + control.height + 4 : Math.max(8, p.y - height - 4)
        }
        background: Rectangle {
            radius: 14
            color: AppTheme.dark ? "#303034" : "#F0F0F1"
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.16; shadowBlur: 0.5; autoPaddingEnabled: true }
        }
        contentItem: ColumnLayout {
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                ToolButton { text: "‹"; implicitWidth: 28; implicitHeight: 28; Accessible.name: qsTr("Previous month"); background: Rectangle { radius: 14; color: parent.hovered ? design.rowHoverFill : "transparent" }
                    contentItem: Label { text: parent.text; color: design.labelPrimary; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: control.moveMonth(-1) }
                Label {
                    Layout.fillWidth: true
                    text: control.calendarLocale.toString(control.displayedMonth, control.calendarLocale.name.indexOf("zh") === 0 ? "yyyy年M月" : "MMMM yyyy")
                    color: design.labelPrimary; font.pixelSize: 13; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                ToolButton { text: "›"; implicitWidth: 28; implicitHeight: 28; Accessible.name: qsTr("Next month"); background: Rectangle { radius: 14; color: parent.hovered ? design.rowHoverFill : "transparent" }
                    contentItem: Label { text: parent.text; color: design.labelPrimary; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: control.moveMonth(1) }
            }
            GridLayout {
                id: dayGrid
                Layout.fillWidth: true
                columns: 7; rowSpacing: 2; columnSpacing: 2
                readonly property int firstDay: control.calendarLocale.firstDayOfWeek % 7
                readonly property int offset: (control.displayedMonth.getDay() - firstDay + 7) % 7
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left) control.moveCursor(-1)
                    else if (event.key === Qt.Key_Right) control.moveCursor(1)
                    else if (event.key === Qt.Key_Up) control.moveCursor(-7)
                    else if (event.key === Qt.Key_Down) control.moveCursor(7)
                    else if (event.key === Qt.Key_PageUp) control.moveMonth(-1)
                    else if (event.key === Qt.Key_PageDown) control.moveMonth(1)
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) control.selectDate(control.cursorDate)
                    else return
                    event.accepted = true
                }
                Repeater {
                    model: 7
                    Label {
                        required property int index
                        Layout.fillWidth: true
                        text: control.calendarLocale.standaloneDayName((dayGrid.firstDay + index) % 7 || 7, Locale.NarrowFormat)
                        color: design.labelSecondary; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Repeater {
                    model: 42
                    Button {
                        id: day
                        required property int index
                        readonly property date value: new Date(control.displayedMonth.getFullYear(), control.displayedMonth.getMonth(), index - dayGrid.offset + 1)
                        readonly property bool selected: control.sameDay(value, control.cursorDate)
                        Layout.fillWidth: true; implicitWidth: 32; implicitHeight: 28
                        focusPolicy: Qt.NoFocus
                        Accessible.name: control.calendarLocale.toString(value, Locale.LongFormat)
                        Accessible.role: Accessible.Button
                        Accessible.description: selected ? qsTr("Selected date") : ""
                        contentItem: Label {
                            text: day.value.getDate()
                            color: day.selected ? "white" : day.value.getMonth() === control.displayedMonth.getMonth() ? design.labelPrimary : design.labelSecondary
                            font.pixelSize: 12
                            font.bold: day.selected || control.sameDay(day.value, new Date())
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle { radius: 14; color: day.selected ? design.workspaceActive : day.hovered ? design.rowHoverFill : "transparent" }
                        onClicked: control.selectDate(value)
                    }
                }
            }
            Button {
                Layout.fillWidth: true; implicitHeight: 28
                text: qsTr("Today")
                contentItem: Label { text: parent.text; color: design.labelPrimary; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 14; color: parent.hovered ? design.rowHoverFill : design.controlFill }
                onClicked: control.selectDate(new Date())
            }
        }
    }
}
