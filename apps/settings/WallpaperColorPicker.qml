import "../../shared/qml/controls" as SharedControls
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/foundation/WallpaperCatalog.js" as WallpaperCatalog

Dialog {
    id: picker
    property var colors: ({card:"#283545", primaryText:"white", secondaryText:"#aeb8c5", accent:"#70A0F5"})
    property color selectedColor: "#70A0F5"
    property int selectedTab: 0
    property string errorMessage: ""
    signal colorApplied(color value)
    signal eyedropperRequested()
    property bool eyedropperAvailable: false
    objectName: "customWallpaperColorDialog"
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(450, parent ? parent.width - 32 : 450)
    padding: 20
    standardButtons: Dialog.NoButton
    background: Rectangle { radius: 26; color: picker.colors.card }
    function setRgb(channel, value) {
        selectedColor = Qt.rgba(channel===0 ? value : selectedColor.r,
            channel===1 ? value : selectedColor.g, channel===2 ? value : selectedColor.b, 1)
    }
    function gridColor(index) {
        const row = Math.floor(index / 12), col = index % 12
        if (row===0) return Qt.rgba(1-col/11,1-col/11,1-col/11,1)
        const hues = [0.54,0.61,0.71,0.79,0.91,0.015,0.065,0.105,0.135,0.17,0.21,0.28]
        return Qt.hsva(hues[col], row>5 ? Math.max(0.12,1-(row-5)*0.22) : 0.93,
            row>5 ? 1 : 0.18+row*0.15, 1)
    }
    contentItem: ColumnLayout {
        spacing: 18
        RowLayout {
            Layout.fillWidth: true
            ToolButton {
                objectName: "wallpaperEyedropper"
                visible: picker.eyedropperAvailable
                text: "取色"
                Accessible.name: "从屏幕取色"
                onClicked: picker.eyedropperRequested()
            }
            Label { text:"颜色"; color:picker.colors.primaryText; font.pixelSize:18; font.weight:Font.DemiBold; Layout.fillWidth:true; horizontalAlignment:Text.AlignHCenter }
            ToolButton { contentItem: SharedControls.VectorIcon { name: "close"; size: 20; color: picker.colors.primaryText } Accessible.name:"关闭"; onClicked:picker.close() }
        }
        TabBar {
            Layout.fillWidth: true
            currentIndex: picker.selectedTab
            onCurrentIndexChanged: picker.selectedTab = currentIndex
            Repeater {
                model: ["网格", "光谱", "滑块"]
                TabButton { required property string modelData; text: modelData }
            }
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: picker.selectedTab===2 ? 250 : 290
            Grid {
                visible: picker.selectedTab===0
                anchors.fill: parent
                columns: 12; rows: 10
                Repeater {
                    model: 120
                    Rectangle {
                        required property int index
                        width: parent.width / 12; height: parent.height / 10
                        color: picker.gridColor(index)
                        border.width: picker.selectedColor.toString()===color.toString() ? 2 : 0
                        border.color: picker.colors.primaryText
                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:picker.selectedColor=parent.color }
                    }
                }
            }
            Canvas {
                id: spectrum
                visible: picker.selectedTab===1
                anchors.fill: parent
                onVisibleChanged: if (visible) requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx=getContext("2d")
                    for(let x=0;x<72;x++) for(let y=0;y<48;y++) {
                        ctx.fillStyle=Qt.hsla(x/71,1,1-y/47,1).toString()
                        ctx.fillRect(x*width/72,y*height/48,Math.ceil(width/72),Math.ceil(height/48))
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    function pick(mouse) { picker.selectedColor=Qt.hsla(Math.max(0,Math.min(1,mouse.x/width)),1,1-Math.max(0,Math.min(1,mouse.y/height)),1) }
                    onPressed: function(mouse) { pick(mouse) }
                    onPositionChanged: function(mouse) { if(pressed) pick(mouse) }
                }
                Rectangle {
                    width:14; height:14; radius:7; color:"transparent"; border.width:2; border.color:"white"
                    x: Math.max(0,picker.selectedColor.hslHue)*parent.width-width/2
                    y: (1-picker.selectedColor.hslLightness)*parent.height-height/2
                }
            }
            ColumnLayout {
                visible: picker.selectedTab===2
                anchors.fill: parent
                spacing: 18
                Repeater {
                    model: ["红", "绿", "蓝"]
                    delegate: ColumnLayout {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        RowLayout {
                            Label { text:modelData; color:picker.colors.secondaryText; Layout.fillWidth:true }
                            Label { text:Math.round([picker.selectedColor.r,picker.selectedColor.g,picker.selectedColor.b][index]*255); color:picker.colors.primaryText }
                        }
                        LiquidControls.ColorRampSlider {
                            Layout.fillWidth: true
                            value: [picker.selectedColor.r,picker.selectedColor.g,picker.selectedColor.b][index]
                            thumbColor: picker.selectedColor
                            rampColors: Array.from({length:7},(_,i)=>Qt.rgba(index===0?i/6:picker.selectedColor.r,index===1?i/6:picker.selectedColor.g,index===2?i/6:picker.selectedColor.b,1))
                            onPreviewChanged: function(value) { picker.setRgb(index,value) }
                            onCommitRequested: function(value) { picker.setRgb(index,value) }
                        }
                    }
                }
                TextField {
                    Layout.fillWidth: true
                    text: picker.selectedColor.toString().toUpperCase()
                    placeholderText: "#RRGGBB"
                    maximumLength: 7
                    onEditingFinished: {
                        if(/^#[0-9a-fA-F]{6}$/.test(text)) picker.selectedColor=text
                        else text=picker.selectedColor.toString().toUpperCase()
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(0.5,0.5,0.5,0.2) }
        RowLayout {
            Layout.fillWidth: true
            Rectangle { width:68; height:68; radius:18; color:picker.selectedColor }
            Grid {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                columns: 5
                columnSpacing: 14; rowSpacing: 12
                Repeater {
                    model: ["#000000","#006AFF","#35C759","#FFCC00","#FF453A","#FF9500","#3D238E","#FF8954","#AB7100","#FFDA47"]
                    Rectangle {
                        required property string modelData
                        width:30; height:30; radius:15; color:modelData
                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:picker.selectedColor=parent.color }
                    }
                }
            }
        }
        Label { Layout.fillWidth:true; text:picker.errorMessage; visible:text.length>0; wrapMode:Text.Wrap; color:"#e66f73" }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Button { text:"取消"; onClicked:picker.close() }
            Button { text:"使用此颜色"; onClicked:picker.colorApplied(picker.selectedColor) }
        }
    }
}
