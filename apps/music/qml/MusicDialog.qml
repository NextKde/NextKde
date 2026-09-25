import QtQuick
import QtQuick.Controls
import Kos.Ui

Dialog {
    id: root
    padding: 20
    modal: true
    background: Rectangle {
        radius: AppTheme.largeRadius
        color: AppTheme.windowRaised
        border.color: AppTheme.border
        antialiasing: true
    }
    header: Label {
        text: root.title
        visible: text.length > 0
        padding: 20
        bottomPadding: 4
        font.pixelSize: 19
        font.weight: Font.DemiBold
        color: AppTheme.text
        wrapMode: Text.WordWrap
    }
    footer: DialogButtonBox {
        visible: count > 0
        padding: 14
        spacing: 8
        background: Item {}
        standardButtons: root.standardButtons
        delegate: KosButton {}
        onAccepted: root.accept()
        onRejected: root.reject()
    }
}
