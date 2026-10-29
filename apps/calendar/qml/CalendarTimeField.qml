pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Kos.Ui

CalendarTextField {
    id: control
    property var parseTime: function(value) { return null }
    property var formatTime: function(value) { return Qt.formatTime(value, "HH:mm") }
    property int selectedHour: 0
    property int selectedMinute: 0
    signal timeSelected(int hour, int minute)
    rightPadding: 28
    CalendarStyle { id: design }
    function showPicker() {
        const parsed = parseTime(text)
        const now = new Date()
        const total = parsed !== null && isFinite(parsed) && parsed >= 0 && parsed < 1440
            ? parsed : now.getHours() * 60 + now.getMinutes()
        selectedHour = Math.floor(total / 60)
        selectedMinute = total % 60
        picker.open()
        Qt.callLater(function() {
            for (let i = 0; i < 2; ++i) columns.itemAt(i).scrollToSelection()
            columns.itemAt(0).focusList()
        })
    }
    function applyTime() {
        text = formatTime(new Date(2000, 0, 1, selectedHour, selectedMinute))
        timeSelected(selectedHour, selectedMinute)
        picker.close()
        forceActiveFocus()
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
        anchors.right: parent.right; anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        width: 24; height: 24
        Accessible.name: qsTr("Choose time")
        background: Rectangle { radius: 12; color: parent.hovered ? design.rowHoverFill : "transparent" }
        contentItem: Item {
            Rectangle {
                anchors.centerIn: parent; width: 12; height: 12; radius: 6
                color: "transparent"; border.width: 1; border.color: design.labelSecondary
                Rectangle { x: 5.5; y: 2.5; width: 1; height: 4; color: design.labelSecondary }
                Rectangle { x: 5.5; y: 6; width: 3.5; height: 1; color: design.labelSecondary }
            }
        }
        onClicked: control.showPicker()
    }
    Popup {
        id: picker
        parent: Overlay.overlay
        popupType: Popup.Item
        width: Math.min(220, parent ? parent.width - 16 : 220)
        height: contentItem.implicitHeight + topPadding + bottomPadding
        padding: 10; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onAboutToShow: {
            const p = control.mapToItem(parent, 0, 0)
            x = Math.max(8, Math.min(parent.width - width - 8, p.x))
            y = p.y + control.height + 4 + height <= parent.height - 8
                ? p.y + control.height + 4 : Math.max(8, p.y - height - 4)
        }
        background: Rectangle {
            radius: 14; color: AppTheme.dark ? "#303034" : "#F0F0F1"
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowOpacity: 0.16; shadowBlur: 0.5; autoPaddingEnabled: true }
        }
        contentItem: ColumnLayout {
            spacing: 8
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Repeater {
                    id: columns
                    model: [24, 60]
                    delegate: ColumnLayout {
                        id: column
                        required property int index
                        required property int modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 90
                        spacing: 6
                        function scrollToSelection() { values.positionViewAtIndex(Math.max(0, Math.min(values.count - 6, values.currentIndex - 2)), ListView.Beginning) }
                        function focusList() { values.forceActiveFocus() }
                        function select(value) {
                            if (index === 0) control.selectedHour = value
                            else control.selectedMinute = value
                        }
                        Label {
                            Layout.fillWidth: true
                            text: column.index === 0 ? qsTr("Hour") : qsTr("Minute")
                            color: design.labelPrimary; font.pixelSize: 12; font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                        ListView {
                            id: values
                            Layout.fillWidth: true; Layout.preferredHeight: 168
                            clip: true; model: column.modelData
                            snapMode: ListView.SnapToItem
                            currentIndex: column.index === 0 ? control.selectedHour : control.selectedMinute
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Up) column.select((currentIndex + count - 1) % count)
                                else if (event.key === Qt.Key_Down) column.select((currentIndex + 1) % count)
                                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab) columns.itemAt(1-column.index).focusList()
                                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) control.applyTime()
                                else return
                                column.scrollToSelection(); event.accepted = true
                            }
                            delegate: Button {
                                id: valueButton
                                required property int index
                                width: values.width - 8; height: 28
                                focusPolicy: Qt.NoFocus
                                Accessible.name: (column.index === 0 ? qsTr("Hour") : qsTr("Minute")) + " " + index
                                contentItem: Label {
                                    text: String(valueButton.index).padStart(2, "0")
                                    font.pixelSize: 13
                                    color: valueButton.index === values.currentIndex ? "white" : design.labelPrimary
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 14; color: valueButton.index === values.currentIndex ? design.workspaceActive : valueButton.hovered ? design.rowHoverFill : "transparent" }
                                onClicked: { column.select(index); values.forceActiveFocus() }
                            }
                        }
                    }
                }
            }
            Button {
                Layout.fillWidth: true; implicitHeight: 28
                text: qsTr("Done")
                contentItem: Label { text: parent.text; color: design.labelPrimary; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 14; color: parent.hovered ? design.rowHoverFill : design.controlFill }
                onClicked: control.applyTime()
            }
        }
    }
}
