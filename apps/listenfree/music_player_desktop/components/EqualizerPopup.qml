pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Basic

Basic.Popup {
    id: popup
    objectName: "equalizerPopup"
    property var controller: null
    property int tab: 0
    readonly property var effects: controller ? controller.audioEffects : ({})
    readonly property string presetId: controller ? controller.equalizerPreset : "flat"
    readonly property var presetOptions: [{value:"custom",label:qsTr("自定义")}].concat(controller ? controller.equalizerPresets : [])
    readonly property int presetIndex: Math.max(0, presetOptions.findIndex(p => p.value === presetId))
    readonly property bool userPreset: presetId.indexOf("user-") === 0
    parent: Basic.Overlay.overlay
    popupType: Basic.Popup.Item
    anchors.centerIn: parent
    width: Math.min(700, parent ? parent.width - 40 : 700)
    height: Math.min(572, parent ? parent.height - 40 : 572)
    padding: 22
    modal: true
    focus: true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened: { AppTheme.presentPopup(popup); presetName.text = userPreset ? presetOptions[presetIndex].label : "" }
    onClosed: if (AppTheme.currentPopup === popup) AppTheme.currentPopup = null
    function setEffect(key, value) { if (controller) controller.setAudioEffect(key, value) }
    background: Rectangle { radius: 20; color: AppTheme.cardStrong; border.color: AppTheme.border }
    Basic.Overlay.modal: Rectangle { radius: AppTheme.windowCornerRadius; color: "#55000000" }
    component Caption: Text { color: AppTheme.textSecondary; font.pixelSize: 12; wrapMode: Text.Wrap }
    component SectionTitle: Text { color: AppTheme.textPrimary; font.pixelSize: 15; font.weight: Font.DemiBold }
    component Adjust: Item {
        id: adjust
        property string label
        property real value: 0
        property real minimum: 0
        property real maximum: 1
        property real step: .01
        property string suffix: "%"
        property real displayScale: 100
        signal moved(real value)
        implicitHeight: 36
        Text { y:9; width:85; text:adjust.label; color:AppTheme.textPrimary; font.pixelSize:12 }
        Basic.Slider {
            id: slider; x:86; width:parent.width-149; height:32
            from:adjust.minimum; to:adjust.maximum; stepSize:adjust.step; value:adjust.value
            onMoved:adjust.moved(value)
            background:Rectangle { x:slider.leftPadding; y:slider.topPadding+slider.availableHeight/2-2; width:slider.availableWidth; height:4; radius:2; color:AppTheme.border
                Rectangle { width:slider.visualPosition*parent.width; height:4; radius:2; color:AppTheme.textSecondary }
            }
            handle:Rectangle { x:slider.leftPadding+slider.visualPosition*(slider.availableWidth-width); y:slider.topPadding+slider.availableHeight/2-height/2; width:12; height:12; radius:6; color:AppTheme.textPrimary }
        }
        Text { anchors.right:parent.right; y:9; width:57; horizontalAlignment:Text.AlignRight; text:Number((adjust.value*adjust.displayScale).toFixed(adjust.displayScale===1?1:0))+adjust.suffix; color:AppTheme.textSecondary; font.pixelSize:11 }
    }
    contentItem: Item {
        MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onPressed:mouse=>mouse.accepted=true; onWheel:wheel=>wheel.accepted=true }
        SectionTitle { text:qsTr("音效"); font.pixelSize:22 }
        RoundIconButton { anchors.right:parent.right; diameter:30; kind:"close"; transparentSurface:true; onClicked:popup.close() }
        SegmentedTabBar { y:45; model:[qsTr("均衡器"),qsTr("空间与声道")]; cellWidth:118; cellHeight:30; currentIndex:popup.tab; controlled:true; onSelected:index=>popup.tab=index }
        Flickable {
            id:scroll; y:94; width:parent.width; height:parent.height-y; clip:true
            contentHeight:popup.tab===0?eqColumn.height:spatialColumn.height
            boundsBehavior:Flickable.StopAtBounds
            Connections { target:popup; function onTabChanged(){scroll.contentY=0} }
            Basic.ScrollBar.vertical:Basic.ScrollBar { policy:Basic.ScrollBar.AsNeeded }
            Column {
                id:eqColumn; width:scroll.width-4; spacing:10; visible:popup.tab===0
                Item {
                    width:parent.width; height:32
                    SettingsSelect {
                        objectName:"equalizerPresets"; width:238; height:30; darkMode:AppTheme.darkMode
                        options:popup.presetOptions; currentIndex:popup.presetIndex; maxVisibleItems:9
                        onValueSelected:(value,index)=>{if(value!=="custom" && popup.controller){popup.controller.selectEqualizerPreset(value);presetName.text=popup.userPreset?popup.presetOptions[popup.presetIndex].label:""}}
                    }
                    Text { anchors.right:toggle.left; anchors.rightMargin:9; y:7; text:"EQ"; color:AppTheme.textSecondary; font.pixelSize:12 }
                    SettingsSwitch { id:toggle; objectName:"equalizerToggle"; anchors.right:resetEq.left; anchors.rightMargin:18; y:2; controlled:true; darkMode:AppTheme.darkMode; checked:popup.controller?popup.controller.equalizerEnabled:false; onToggled:value=>{if(popup.controller)popup.controller.setEqualizerEnabled(value)} }
                    UiButton { id:resetEq; anchors.right:parent.right; width:66; height:30; label:qsTr("归零"); onClicked:if(popup.controller)popup.controller.resetEqualizer() }
                }
                Caption { width:parent.width; text:popup.presetOptions[popup.presetIndex].description || qsTr("手动调整，或保存为自己的预设") }
                Rectangle {
                    width:parent.width; height:196; radius:12; color:AppTheme.actionSurface
                    Row {
                        x:8; y:12; width:parent.width-16
                        Repeater {
                            model:["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                            delegate:Column {
                                id:band
                                required property string modelData
                                required property int index
                                width:(eqColumn.width-16)/10; spacing:5; opacity:toggle.checked?1:.45
                                Text { width:parent.width; horizontalAlignment:Text.AlignHCenter; text:eqSlider.value.toFixed(1); color:AppTheme.textSecondary; font.pixelSize:11 }
                                Basic.Slider {
                                    id:eqSlider; objectName:"eqBand"+band.index
                                    anchors.horizontalCenter:parent.horizontalCenter; orientation:Qt.Vertical; height:131; width:30
                                    from:-12; to:12; stepSize:.5; enabled:toggle.checked
                                    value:popup.controller?Number(popup.controller.equalizerGains[band.index]||0):0
                                    onMoved:if(popup.controller)popup.controller.setEqualizerBand(band.index,value)
                                    background:Rectangle { x:eqSlider.width/2-2; y:eqSlider.topPadding; width:4; height:eqSlider.availableHeight; radius:2; color:AppTheme.border
                                        Rectangle { x:-4; y:parent.height/2; width:12; height:1; color:AppTheme.textSecondary; opacity:.5 }
                                        Rectangle { width:4; height:Math.abs(eqSlider.visualPosition-.5)*parent.height; y:Math.min(eqSlider.visualPosition,.5)*parent.height; radius:2; color:AppTheme.textSecondary }
                                    }
                                    handle:Rectangle { x:eqSlider.width/2-width/2; y:eqSlider.topPadding+eqSlider.visualPosition*(eqSlider.availableHeight-height); width:18; height:10; radius:4; color:AppTheme.textPrimary }
                                }
                                Text { width:parent.width; horizontalAlignment:Text.AlignHCenter; text:band.modelData; color:AppTheme.textPrimary; font.pixelSize:11 }
                            }
                        }
                    }
                }
                Adjust { width:parent.width; label:qsTr("前级增益"); minimum:-12; maximum:12; step:.5; displayScale:1; suffix:" dB"; value:popup.controller?popup.controller.equalizerPreamp:0; enabled:toggle.checked; onMoved:value=>{if(popup.controller)popup.controller.setEqualizerPreamp(value)} }
                Item {
                    width:parent.width; height:28
                    SettingsSwitch { id:headroom; width:40; height:24; controlled:true; darkMode:AppTheme.darkMode; checked:popup.controller?popup.controller.equalizerAutoHeadroom:true; onToggled:value=>{if(popup.controller)popup.controller.setEqualizerAutoHeadroom(value)} }
                    Text { x:51; y:4; text:qsTr("自动预留余量"); color:AppTheme.textPrimary; font.pixelSize:12 }
                    Caption { anchors.right:parent.right; y:4; text:qsTr("实际前级 %1 dB").arg(popup.controller?popup.controller.equalizerEffectivePreamp.toFixed(1):"0.0") }
                }
                Caption { width:parent.width; text:qsTr("提升频段时适当降低前级，减少削波；原声曲线不会额外降低音量。") }
                Row {
                    width:parent.width; spacing:7
                    Basic.TextField {
                        id:presetName; objectName:"equalizerPresetName"; width:parent.width-238; height:32; maximumLength:40; selectByMouse:true
                        placeholderText:qsTr("为当前曲线命名"); color:AppTheme.textPrimary; font.pixelSize:12
                        background:Rectangle { radius:8; color:AppTheme.actionSurface; border.color:AppTheme.border }
                        onAccepted:if(popup.controller)popup.controller.saveEqualizerPreset(text)
                    }
                    UiButton { objectName:"equalizerSavePreset"; width:72; height:32; label:qsTr("另存"); onClicked:if(popup.controller)popup.controller.saveEqualizerPreset(presetName.text) }
                    UiButton { width:76; height:32; label:qsTr("覆盖同名"); onClicked:if(popup.controller)popup.controller.saveEqualizerPreset(presetName.text,true) }
                    UiButton { width:69; height:32; label:qsTr("删除"); enabled:popup.userPreset; opacity:enabled?1:.4; onClicked:if(popup.controller)popup.controller.deleteEqualizerPreset(popup.presetId) }
                }
                Caption { width:parent.width; text:popup.controller?popup.controller.audioEffectsMessage:""; visible:text.length>0 }
            }
            Column {
                id:spatialColumn; width:scroll.width-4; spacing:12; visible:popup.tab===1
                Caption { width:parent.width; visible:popup.controller && !popup.controller.audioEffectsAvailable; text:qsTr("空间音效组件未加载，请使用完整便携包。"); color:"#dc825c" }
                Row {
                  width:parent.width; spacing:24
                  Column {
                    width:(parent.width-parent.spacing)/2; spacing:12
                Item {
                    width:parent.width; height:30
                    SectionTitle { y:4; text:qsTr("混响") }
                    SettingsSwitch { objectName:"reverbToggle"; anchors.right:parent.right; controlled:true; darkMode:AppTheme.darkMode; checked:popup.effects.reverbEnabled||false; enabled:popup.controller && popup.controller.audioEffectsAvailable; onToggled:value=>popup.setEffect("reverbEnabled",value) }
                }
                Row { spacing:8
                    Repeater { model:[{id:"room",name:qsTr("房间")},{id:"hall",name:qsTr("音乐厅")},{id:"church",name:qsTr("教堂")}]
                        UiButton { required property var modelData; width:80; height:30; label:modelData.name; onClicked:if(popup.controller)popup.controller.setReverbPreset(modelData.id) }
                    }
                }
                Column { width:parent.width; enabled:popup.effects.reverbEnabled||false; opacity:enabled?1:.45
                    Adjust { width:parent.width; label:qsTr("混响量"); maximum:.6; value:popup.effects.wet||0; onMoved:value=>popup.setEffect("wet",value) }
                    Adjust { width:parent.width; label:qsTr("空间大小"); minimum:.1; maximum:.92; value:popup.effects.room||.5; onMoved:value=>popup.setEffect("room",value) }
                    Adjust { width:parent.width; label:qsTr("高频吸收"); value:popup.effects.damping||0; onMoved:value=>popup.setEffect("damping",value) }
                }
                  }
                  Column {
                    width:(parent.width-parent.spacing)/2; spacing:12
                Item { width:parent.width; height:30
                    SectionTitle { y:4; text:qsTr("3D 环绕") }
                    SettingsSwitch { objectName:"surroundToggle"; anchors.right:parent.right; controlled:true; darkMode:AppTheme.darkMode; checked:popup.effects.surroundEnabled||false; enabled:popup.controller && popup.controller.audioEffectsAvailable; onToggled:value=>popup.setEffect("surroundEnabled",value) }
                }
                Caption { width:parent.width; text:qsTr("声像随音乐循环移动，使用立体声耳机更明显。") }
                Column { width:parent.width; enabled:popup.effects.surroundEnabled||false; opacity:enabled?1:.45
                    Adjust { width:parent.width; label:qsTr("环绕强度"); value:popup.effects.depth||0; onMoved:value=>popup.setEffect("depth",value) }
                    Adjust { width:parent.width; label:qsTr("一圈时长"); minimum:4; maximum:40; step:1; displayScale:1; suffix:qsTr(" 秒"); value:popup.effects.period||12; onMoved:value=>popup.setEffect("period",value) }
                }
                  }
                }
                Item { width:parent.width; height:30
                    SectionTitle { y:4; text:qsTr("声道") }
                    UiButton { anchors.right:parent.right; width:90; height:28; label:qsTr("恢复默认"); onClicked:if(popup.controller)popup.controller.resetAudioEffects() }
                }
                Column { width:parent.width
                    Adjust { width:parent.width; label:qsTr("左右平衡"); minimum:-1; maximum:1; value:popup.effects.balance||0; onMoved:value=>popup.setEffect("balance",value) }
                    Adjust { width:parent.width; label:qsTr("立体声宽度"); maximum:2; value:popup.effects.width===undefined?1:popup.effects.width; enabled:!popup.effects.mono; onMoved:value=>popup.setEffect("width",value) }
                }
                Item { width:parent.width; height:28
                    Text { y:5; text:qsTr("合并为单声道"); color:AppTheme.textPrimary; font.pixelSize:12 }
                    SettingsSwitch { anchors.right:parent.right; controlled:true; darkMode:AppTheme.darkMode; checked:popup.effects.mono||false; onToggled:value=>popup.setEffect("mono",value) }
                }
                Caption { width:parent.width; text:qsTr("平衡向左为负值，向右为正值；宽度 100% 为原始声场。") }
            }
        }
    }
}
