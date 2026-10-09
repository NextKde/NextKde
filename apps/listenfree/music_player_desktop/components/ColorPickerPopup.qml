pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Controls.Basic as Basic

Basic.Popup {
    id: popup
    objectName: "backgroundColorPicker"
    property color selectedColor: "#c8bad9"
    property int currentTab: 0
    signal colorEdited(color value)
    function choose(value) { selectedColor=value; colorEdited(value) }
    function channel(index, value) {
        const rgb=[selectedColor.r,selectedColor.g,selectedColor.b]
        rgb[index]=Math.max(0,Math.min(255,value))/255
        choose(Qt.rgba(rgb[0],rgb[1],rgb[2],selectedColor.a))
    }
    function swatch(index) {
        const row=Math.floor(index/12), col=index%12
        if(row===0)return Qt.rgba(1-col/11,1-col/11,1-col/11,1)
        return Qt.hsla(((205+col*30)%360)/360, row<6 ? .82 : .86-(row-6)*.13,
                       row<6 ? .12+row*.072 : .60+(row-6)*.085, 1)
    }
    function hex() {
        return "#"+[selectedColor.r,selectedColor.g,selectedColor.b].map(v=>Math.round(v*255).toString(16).padStart(2,"0")).join("").toUpperCase()
    }
    parent: Basic.Overlay.overlay
    popupType: Basic.Popup.Item
    anchors.centerIn: parent
    width: 376; height: 506; padding: 22
    modal: true; focus: true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened: AppTheme.presentPopup(popup)
    onClosed: if(AppTheme.currentPopup===popup)AppTheme.currentPopup=null
    background: Rectangle { radius: 28; color: AppTheme.darkMode ? "#252b34" : "#fcfcfe"; border.color: AppTheme.border }
    Basic.Overlay.modal: Rectangle { color: "#33000000"; radius: AppTheme.windowCornerRadius }
    contentItem: Item {
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: mouse=>mouse.accepted=true; onWheel: wheel=>wheel.accepted=true }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 2; text: qsTr("颜色"); color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 17; font.weight: Font.DemiBold }
        RoundIconButton { anchors.right: parent.right; y: -3; diameter: 28; kind: "close"; transparentSurface: true; onClicked: popup.close() }
        Rectangle {
            id: tabs
            y: 42; width: parent.width; height: 32; radius: 16
            color: AppTheme.darkMode ? "#363c45" : "#ededf0"
            Row {
                anchors.fill: parent; anchors.margins: 2
                Repeater {
                    model: [qsTr("色板"), qsTr("数值")]
                    Basic.Button {
                        required property int index
                        required property string modelData
                        objectName: "colorPickerTab"+index
                        width: (tabs.width-4)/2; height: 28
                        contentItem: Text { text: parent.modelData; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium }
                        background: Rectangle { radius: 14; color: popup.currentTab===parent.index ? (AppTheme.darkMode ? "#535c69" : "white") : "transparent" }
                        onClicked: popup.currentTab=index
                    }
                }
            }
        }
        Grid {
            id: palette
            objectName: "colorPickerPalette"
            y: 90; width: parent.width; height: 240
            visible: popup.currentTab===0
            columns: 12
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: Rectangle { parent: popup.contentItem; width: palette.width; height: palette.height; radius: 10; visible: false; layer.enabled: true }
            }
            Repeater {
                model: 120
                Basic.Button {
                    id: cell
                    required property int index
                    readonly property color value: popup.swatch(index)
                    width: palette.width/12; height: 24
                    padding: 0
                    Accessible.name: String(value)
                    background: Rectangle { color: cell.value }
                    contentItem: Rectangle {
                        color: "transparent"
                        border.color: "white"; border.width: 2
                        visible: cell.activeFocus || Math.abs(cell.value.r-popup.selectedColor.r)+Math.abs(cell.value.g-popup.selectedColor.g)+Math.abs(cell.value.b-popup.selectedColor.b)<.015
                    }
                    onClicked: popup.choose(Qt.rgba(value.r,value.g,value.b,popup.selectedColor.a))
                }
            }
        }
        Column {
            y: 92; width: parent.width; spacing: 16
            visible: popup.currentTab===1
            Row {
                spacing: 12
                Text { width: 46; height: 34; text: "HEX"; verticalAlignment: Text.AlignVCenter; color: AppTheme.textSecondary; font.pixelSize: 11 }
                Basic.TextField {
                    id: hexField
                    objectName: "colorPickerHex"
                    width: 152; height: 34; text: popup.hex(); selectByMouse: true
                    color: AppTheme.textPrimary; font.family: "Consolas"; font.pixelSize: 14
                    maximumLength: 7; leftPadding: 12
                    validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                    background: Rectangle { radius: 9; color: AppTheme.field; border.color: hexField.activeFocus ? AppTheme.accent : AppTheme.divider }
                    onEditingFinished: if(acceptableInput)popup.choose(Qt.rgba(parseInt(text.slice(1,3),16)/255,parseInt(text.slice(3,5),16)/255,parseInt(text.slice(5,7),16)/255,popup.selectedColor.a))
                }
            }
            Repeater {
                model: [qsTr("红"), qsTr("绿"), qsTr("蓝")]
                Row {
                    id: channelRow
                    required property int index
                    required property string modelData
                    readonly property int value: Math.round([popup.selectedColor.r,popup.selectedColor.g,popup.selectedColor.b][index]*255)
                    spacing: 12; width: parent.width
                    Text { width: 24; height: 38; text: channelRow.modelData; verticalAlignment: Text.AlignVCenter; color: AppTheme.textSecondary; font.pixelSize: 12 }
                    Basic.Slider {
                        id: rgbSlider
                        objectName: "colorPickerChannel"+channelRow.index
                        width: 208; height: 38; from: 0; to: 255; stepSize: 1; value: channelRow.value
                        onMoved: popup.channel(channelRow.index,value)
                        background: Rectangle {
                            x: rgbSlider.leftPadding; y: (rgbSlider.height-height)/2; width: rgbSlider.availableWidth; height: 6; radius: 3
                            gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#303844" } GradientStop { position: 1; color: ["#ff6767","#50c879","#4a97ef"][channelRow.index] } }
                        }
                        handle: Rectangle { x: rgbSlider.leftPadding+rgbSlider.visualPosition*(rgbSlider.availableWidth-width); y: (rgbSlider.height-height)/2; width: 20; height: 20; radius: 10; color: "white"; border.color: "#22000000" }
                    }
                    Basic.TextField {
                        id: numberField
                        objectName: "colorPickerNumber"+channelRow.index
                        width: 64; height: 36; text: channelRow.value; horizontalAlignment: Text.AlignHCenter
                        color: AppTheme.textPrimary; font.pixelSize: 13; selectByMouse: true
                        validator: IntValidator { bottom: 0; top: 255 }
                        background: Rectangle { radius: 9; color: AppTheme.field; border.color: numberField.activeFocus ? AppTheme.accent : AppTheme.divider }
                        onEditingFinished: if(acceptableInput)popup.channel(channelRow.index,Number(text))
                    }
                }
            }
        }
        Text { y: 347; text: qsTr("不透明度"); color: AppTheme.textSecondary; font.pixelSize: 11; font.weight: Font.Medium }
        Basic.Slider {
            id: alphaSlider
            objectName: "colorPickerOpacity"
            y: 365; width: parent.width-58; height: 30
            from: 0; to: 100; stepSize: 1; value: Math.round(popup.selectedColor.a*100)
            onMoved: popup.choose(Qt.rgba(popup.selectedColor.r,popup.selectedColor.g,popup.selectedColor.b,value/100))
            background: Item {
                x: alphaSlider.leftPadding; y: (alphaSlider.height-height)/2; width: alphaSlider.availableWidth; height: 16; clip: true
                Grid { columns: 36; Repeater { model: 72; Rectangle { required property int index; width: 8; height: 8; color: (index+Math.floor(index/36))%2 ? "#999" : "white" } } }
                Rectangle { anchors.fill: parent; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Qt.rgba(popup.selectedColor.r,popup.selectedColor.g,popup.selectedColor.b,0) } GradientStop { position: 1; color: Qt.rgba(popup.selectedColor.r,popup.selectedColor.g,popup.selectedColor.b,1) } } }
            }
            handle: Rectangle { x: alphaSlider.leftPadding+alphaSlider.visualPosition*(alphaSlider.availableWidth-width); y: (alphaSlider.height-height)/2; width: 26; height: 26; radius: 13; color: popup.selectedColor; border.color: "white"; border.width: 3 }
        }
        Text { anchors.right: parent.right; y: 370; text: Math.round(popup.selectedColor.a*100)+"%"; color: AppTheme.textPrimary; font.pixelSize: 13 }
        Rectangle { y: 407; width: parent.width; height: 1; color: AppTheme.divider }
        Rectangle { y: 425; width: 38; height: 38; radius: 10; color: popup.selectedColor; border.color: AppTheme.divider }
        Row {
            x: 56; y: 430; spacing: 12
            Repeater {
                model: ["#c8bad9","#33c759","#ffcc00","#ff8a25","#ff4050",AppTheme.accent,"#7555ed"]
                Basic.Button {
                    id: favorite
                    required property string modelData
                    readonly property color value: modelData
                    width: 28; height: 28
                    Accessible.name: modelData
                    background: Rectangle { radius: 14; color: favorite.modelData; border.width: favorite.activeFocus ? 2 : 0; border.color: AppTheme.textPrimary }
                    onClicked: popup.choose(Qt.rgba(value.r,value.g,value.b,popup.selectedColor.a))
                }
            }
        }
    }
}
