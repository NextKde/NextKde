import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Foundation.KosDialog {
    id: root
    property alias contentBackdrop: dialogBackdrop
    padding: 20
    header: Label {
        text: root.title
        padding: 20
        color: Foundation.AppTheme.text
        font.pixelSize: 20
        font.weight: Font.DemiBold
    }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.25) }
    background: Item {
        LiquidOuterShadow {
            anchors.fill: parent; radius: 24
            shadowColor: Foundation.AppTheme.dark ? "#606064" : "#000000"
            shadowOpacity: .32; softness: 20; spread: 52
            outwardOffset: 0; offset: Qt.vector2d(0, 0)
        }
        Rectangle {
            id: dialogFill
            anchors.fill: parent; radius: 24
            color: Foundation.AppTheme.dark ? "#29292d" : "#ffffff"
        }
        LiquidBackdrop { id: dialogBackdrop; sourceItem: dialogFill; registerAsDefault: false }
    }
    footer: DialogButtonBox {
        alignment: Qt.AlignHCenter
        standardButtons: root.standardButtons
        delegate: LiquidActionButton {
            materialForm: true
            surfaceColor: Foundation.AppTheme.dark ? "#454549" : "#d2d2d7"
            textColor: Foundation.AppTheme.text
        }
        background: Item {}
        onAccepted: root.accept()
        onRejected: root.reject()
    }
}
