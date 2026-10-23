import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Foundation.KosDialog {
    id: root
    padding: 24
    header: Label {
        text: root.title
        padding: 0
        bottomPadding: 8
        color: Foundation.AppTheme.text
        font.pixelSize: 17
        font.weight: Font.DemiBold
    }
    background: LiquidSurface { radius: 24; readability: 0.60 }
    footer: DialogButtonBox {
        standardButtons: root.standardButtons
        delegate: LiquidActionButton {}
        background: Item {}
        onAccepted: root.accept()
        onRejected: root.reject()
    }
}
