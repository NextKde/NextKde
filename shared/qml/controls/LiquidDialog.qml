import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Foundation.KosDialog {
    id: root
    padding: 20
    header: Label {
        text: root.title
        padding: 20
        color: Foundation.AppTheme.text
        font.pixelSize: 20
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
