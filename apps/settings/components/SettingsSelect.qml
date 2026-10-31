import QtQuick
import QtQuick.Layouts
import Kos.Demo as Demo

// Settings geometry and legacy signal adapter; all visuals and menus come from Demo.
Demo.LiquidSelect {
    id: root
    required property var colors
    property bool disabled: false
    enabled: !disabled
    indicatorStyle: "upDown"
    plainTrigger: true
    indicatorBackground: true
    popupMaterialForm: true
    neutralOptionHighlight: true
    compactPopup: true
    popupBorderWidth: 0
    popupShadowEnabled: true
    popupFontWeight: Font.Normal
    appearanceMode: colors.dark ? "dark" : "light"
    implicitHeight: 24
    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    Layout.minimumWidth: 0
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: 24
    signal selectionChanged(int index)
    onActivated: index => selectionChanged(index)
}
