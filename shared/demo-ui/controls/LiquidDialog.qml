import QtQuick
import QtQuick.Controls
import QtQuick.Window
import "../foundation" as Foundation

// One floating liquid background; its form fields and action buttons are solid.
Foundation.KosDialog {
    id: root
    property Item sourceItem: null
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.parent ? root.parent.Window.window : null)
    property alias contentBackdrop: sceneBackdrop
    property real cornerRadius: 32
    property real materialOpacity: LiquidStyle.panelMaterialOpacity
    readonly property real actionHeight: 30
    property bool reduceTransparency: Foundation.AppTheme.reduceTransparency
    readonly property bool sampling: dialogSurface.sampling
    popupType: Popup.Item
    modal: true
    closePolicy: Popup.CloseOnEscape
    padding: 24
    header: Label {
        text: root.title
        padding: 24
        topPadding: 20
        bottomPadding: 12
        color: Foundation.AppTheme.text
        font.pixelSize: Foundation.AppTheme.compactDesign ? 17 : 20
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.16 * root.revealProgress) }
    background: LiquidDialogSurface {
        id: dialogSurface
        cornerRadius: root.cornerRadius
        materialOpacity: root.materialOpacity
        reduceTransparency: root.reduceTransparency
        backdrop: root.sourceItem ? sceneBackdrop : root.backdrop
        LiquidBackdrop {
            id: sceneBackdrop
            sourceItem: root.sourceItem
            registerAsDefault: false
            active: root.visible && !root.reduceTransparency
            blur: 0.85
        }
    }
    footer: DialogButtonBox {
        padding: 24
        topPadding: 12
        spacing: 8
        alignment: Qt.AlignRight
        standardButtons: root.standardButtons
        delegate: LiquidDialogButton {
            primaryAction: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole
                || DialogButtonBox.buttonRole === DialogButtonBox.ApplyRole
            implicitHeight: root.actionHeight
        }
        background: Item {}
        // Dialog automatically forwards its DialogButtonBox lifecycle signals.
    }
}
