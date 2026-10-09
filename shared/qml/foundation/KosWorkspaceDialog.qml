import QtQuick
import QtQuick.Controls

KosDialog {
    id: root
    padding: 20
    background: KosSurface { radius: AppTheme.largeRadius; fillColor: AppTheme.windowRaised; elevation: 0.5 }
    header: Label {
        text: root.title; color: AppTheme.text
        font.pixelSize: 20; font.weight: Font.DemiBold
        padding: 22; bottomPadding: 12
        elide: Text.ElideRight
    }
    footer: DialogButtonBox {
        standardButtons: root.standardButtons
        padding: 16; spacing: 8
        alignment: Qt.AlignRight
        delegate: KosButton {
            highlighted: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole
                || DialogButtonBox.buttonRole === DialogButtonBox.ApplyRole
        }
        background: Item {}
    }
    Overlay.modal: Rectangle {
        radius: root.ApplicationWindow.window ? root.ApplicationWindow.window.windowCornerRadius || 0 : 0
        color: AppTheme.withAlpha(AppTheme.blackSeed, AppTheme.dark ? 0.42 : 0.2)
    }
}
