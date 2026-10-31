import QtQuick
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

// Calendar data adapter; selection visuals and keyboard handling belong to Demo.
Item {
    id: control
    property alias model: picker.model
    property alias textRole: picker.textRole
    property alias colorRole: picker.colorRole
    property alias currentIndex: picker.currentIndex
    readonly property string displayText: picker.labelAt(picker.currentIndex)
    signal activated(int index)
    implicitWidth: picker.implicitWidth
    implicitHeight: 24
    activeFocusOnTab: true
    onActiveFocusChanged: if (activeFocus) picker.forceActiveFocus()
    Demo.LiquidSelect {
        id: picker
        anchors.fill: parent
        objectName: control.objectName + "Select"
        appearanceMode: AppTheme.dark ? "dark" : "light"
        indicatorStyle: "upDown"
        plainTrigger: true
        indicatorBackground: true
        popupMaterialForm: true
        neutralOptionHighlight: true
        compactPopup: true
        popupBorderWidth: 0
        popupShadowEnabled: true
        popupFontWeight: Font.Normal
        implicitHeight: 24
        onActivated: index => {
            currentIndex = index
            control.activated(index)
        }
    }
}
