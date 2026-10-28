import QtQuick
import QtQuick.Controls
import Kos.Ui

ToolTip {
    id: root
    popupType: Popup.Item
    delay: 500
    timeout: 5000
    margins: 8
    padding: 8
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? parent.height + 6 : 0
    font.pixelSize: 12
    contentItem: Label {
        text: root.text
        font: root.font
        color: AppTheme.text
        wrapMode: Text.Wrap
    }
    background: CalendarPopupSurface { radius: 8 }
}
