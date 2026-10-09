pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Popup {
    id: popup
    objectName: "immersiveSettingsPopup"
    required property var stage
    property int tab: 0
    parent: Basic.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(810,parent ? parent.width-32 : 810)
    height: Math.min(572,parent ? parent.height-32 : 572)
    padding: 24;modal:true;focus:true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened:AppTheme.presentPopup(popup)
    onClosed:if(AppTheme.currentPopup===popup)AppTheme.currentPopup=null
    background:Rectangle { radius:20;color:"#f51b2029";border.color:"#26ffffff" }
    Basic.Overlay.modal:Rectangle { color:"#65000000" }
    contentItem:Item {
        Text { text:qsTr("沉浸设置");color:"#eceef4";font.pixelSize:20;font.weight:Font.DemiBold }
        Text { y:30;text:qsTr("让文字、光与音乐一起流动");color:"#969eac";font.pixelSize:12 }
        RoundIconButton { anchors.right:parent.right;diameter:28;kind:"close";transparentSurface:true;glyphColor:"#b8c0cc";onClicked:popup.close() }
        Row {
            objectName:"immersiveSettingsTabs";y:66;width:parent.width;spacing:4
            Repeater {
                model:[qsTr("歌词样式"),qsTr("可视化"),qsTr("背景")]
                delegate:Rectangle {
                    required property string modelData
                    required property int index
                    width:(parent.width-8)/3;height:34;radius:8
                    color:popup.tab===index?"#343d4b":hover.hovered?"#292f3a":"transparent"
                    Text { anchors.centerIn:parent;text:parent.modelData;color:popup.tab===parent.index?"#f2f4f8":"#939cac";font.pixelSize:13;font.weight:popup.tab===parent.index?Font.DemiBold:Font.Normal }
                    HoverHandler{id:hover} TapHandler{onTapped:popup.tab=parent.index}
                }
            }
        }
        Basic.ScrollView {
            y:118;width:parent.width;height:parent.height-y-65;clip:true
            contentWidth:availableWidth
            Basic.ScrollBar.horizontal.policy:Basic.ScrollBar.AlwaysOff
            Column {
                width:parent.width;spacing:16
                Grid {
                    width:parent.width;columns:popup.width<660?2:3;spacing:8;visible:popup.tab===0
                    Repeater {
                        model:[
                            {key:"classic",name:qsTr("流光"),detail:qsTr("逐字扫光 · 轻盈浮动"),symbol:"Aa"},
                            {key:"cadenza",name:qsTr("心象"),detail:qsTr("字距呼吸 · 层叠余辉"),symbol:"心"},
                            {key:"partita",name:qsTr("云阶"),detail:qsTr("错落分组 · 阶梯排版"),symbol:"阶"},
                            {key:"fume",name:qsTr("浮名"),detail:qsTr("纸面游走 · 逐字印记"),symbol:"名"},
                            {key:"cappella",name:qsTr("群唱"),detail:qsTr("对话气泡 · 交替吟唱"),symbol:"···"},
                            {key:"tilt",name:qsTr("倾诉"),detail:qsTr("斜向长句 · 字符交错"),symbol:"斜"},
                            {key:"claddagh",name:qsTr("回环"),detail:qsTr("椭圆轨道 · 逐字聚焦"),symbol:"∞"},
                            {key:"diorama",name:qsTr("镜台"),detail:qsTr("空间镜头 · 字形残影"),symbol:"◇"},
                            {key:"monet",name:qsTr("莫奈"),detail:qsTr("柔色画布 · 纵向诗行"),symbol:"墨"},
                            {key:"pendolo",name:qsTr("时计"),detail:qsTr("轮轴弧线 · 擒纵节奏"),symbol:"◷"},
                            {key:"sonnet",name:qsTr("商籁"),detail:qsTr("海报构图 · 片段蒙太奇"),symbol:"S"},
                            {key:"tempera",name:qsTr("凝彩"),detail:qsTr("色块构成 · 字符入场"),symbol:"▧"},
                            {key:"still",name:qsTr("静止"),detail:qsTr("安静阅读 · 前后诗句"),symbol:"静"}]
                        delegate:Choice {
                            required property var modelData
                            width:(parent.width-(parent.columns-1)*8)/parent.columns;height:60
                            label:modelData.name;detail:modelData.detail;symbol:modelData.symbol
                            selected:popup.stage.pvStyle===modelData.key
                            onClicked:popup.stage.pvStyle=modelData.key
                        }
                    }
                }
                Column {
                    width:parent.width;spacing:10;visible:popup.tab===1
                    Repeater {
                        model:[{key:"none",name:qsTr("关闭"),detail:qsTr("只保留歌词与背景"),symbol:"—"},{key:"spectrum",name:qsTr("柱状频谱"),detail:qsTr("贴着底边，随各频段实时起伏"),symbol:"▥"},{key:"ambient",name:qsTr("氛围灯"),detail:qsTr("12 px 贴边光晕，跟随低、中、高频呼吸"),symbol:"◌"}]
                        delegate:Choice {
                            required property var modelData
                            width:parent.width;height:64
                            label:modelData.name;detail:modelData.detail;symbol:modelData.symbol;selected:popup.stage.visualization===modelData.key
                            onClicked:popup.stage.visualization=modelData.key
                        }
                    }
                    Row {
                        spacing:18;visible:popup.stage.visualization==="spectrum"
                        Text { height:32;verticalAlignment:Text.AlignVCenter;text:qsTr("频谱高度")+"  "+Math.round(popup.stage.visualHeight)+" px";color:"#b6bfcd";font.pixelSize:12 }
                        SlimSlider { width:Math.min(350,popup.width*.42);height:32;from:40;to:240;stepSize:1;value:popup.stage.visualHeight;onMoved:popup.stage.visualHeight=value }
                    }
                }
                Column {
                    width:parent.width;spacing:10;visible:popup.tab===2
                    Repeater {
                        model:[{key:"aura",name:qsTr("动态流转"),detail:qsTr("封面色彩交融，缓慢流动的光场"),symbol:"≈"},{key:"blur",name:qsTr("模糊专辑"),detail:qsTr("柔和纹理铺满屏幕"),symbol:"▦"},{key:"mv",name:qsTr("MV 画面"),detail:qsTr("自动匹配视频，暂无画面时显示封面"),symbol:"▷"}]
                        delegate:Choice {
                            required property var modelData
                            width:parent.width;height:72
                            label:modelData.name;detail:modelData.detail;symbol:modelData.symbol;selected:popup.stage.backgroundMode===modelData.key
                            onClicked:popup.stage.backgroundMode=modelData.key
                        }
                    }
                }
            }
        }
        Item {
            anchors.bottom:parent.bottom;width:parent.width;height:43
            Rectangle { width:parent.width;height:1;color:"#16ffffff" }
            Text { y:20;text:qsTr("控件自动隐藏");font.pixelSize:12;color:"#aeb8c8" }
            SlimSlider { x:Math.min(190,parent.width*.3);width:parent.width-x-55;anchors.bottom:parent.bottom;height:28;from:1;to:10;stepSize:1;value:popup.stage.hideDelay;onMoved:popup.stage.hideDelay=value }
            Text { anchors.right:parent.right;y:20;text:Math.round(popup.stage.hideDelay)+" s";font.pixelSize:12;color:"#c7d0dc" }
        }
    }
    component SlimSlider:Basic.Slider {
        id:slider
        leftPadding:6;rightPadding:6
        background:Rectangle {
            x:slider.leftPadding;y:slider.topPadding+(slider.availableHeight-height)/2
            width:slider.availableWidth;height:3;radius:1.5;color:"#48505c"
            Rectangle { width:slider.visualPosition*parent.width;height:parent.height;radius:parent.radius;color:"#9aafca" }
        }
        handle:Rectangle {
            x:slider.leftPadding+slider.visualPosition*(slider.availableWidth-width)
            y:slider.topPadding+(slider.availableHeight-height)/2
            width:12;height:12;radius:6;color:slider.pressed?"#f0f5fc":"#c9d4e3"
            border.color:slider.activeFocus?"#7da6dc":"#586576"
        }
    }
    component Choice:Rectangle {
        id: choice
        property string label:""
        property string detail:""
        property string symbol:""
        property bool selected:false
        signal clicked()
        radius:10;color:selected?"#343f50":hover.hovered?"#303641":"#252b35"
        border.width:1;border.color:selected?"#8ba7ca":"#18ffffff"
        Rectangle {
            x:10;anchors.verticalCenter:parent.verticalCenter;width:36;height:36;radius:8
            color:choice.selected?"#3047617e":"#18acbcd3"
            Text { anchors.centerIn:parent;text:choice.symbol;color:choice.selected?"#d7e7fc":"#95a7c0";font.pixelSize:19;font.family:AppTheme.fontFamily }
        }
        Column {
            x:57;anchors.verticalCenter:parent.verticalCenter;width:parent.width-x-12;spacing:5
            Text { width:parent.width;text:choice.label;color:"#e6eaf1";font.pixelSize:13;font.weight:Font.DemiBold }
            Text { width:parent.width;text:choice.detail;color:"#929daf";font.pixelSize:10;elide:Text.ElideRight }
        }
        HoverHandler{id:hover}TapHandler{onTapped:choice.clicked()}
    }
}
