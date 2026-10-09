pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Dialogs

Basic.Popup {
    id: popup
    objectName:"immersiveSourcesPopup"
    required property var stage
    property var controller:null
    property var track:({})
    property int tab:0
    property string provider:"wy"
    property int selectedLyric:-1
    function plays(value){const n=Number(value||0);return (n>=10000?(n/10000).toFixed(1)+qsTr("万"):String(n))+qsTr("次播放")}
    readonly property string songIdentity:stage.songIdentity
    onSongIdentityChanged:{
        selectedLyric=-1
        if(visible){if(controller)controller.cancelLyricMatch();Qt.callLater(refreshForTrack)}
    }
    function refreshForTrack(){
        query.text=[stage.title,stage.artist].filter(Boolean).join(" ")
        if(visible && tab===1)search()
    }
    readonly property var lyricResults:controller?controller.lyricCandidates:[]
    function search(){
        if(tab===0 && stage.service)stage.service.searchMv(query.text,provider)
        else if(controller){selectedLyric=-1;controller.searchLyricMatches(track,query.text)}
    }
    function autoMatch(){
        if(tab===0 && stage.service){stage.backgroundMode="mv";stage.cancelAutoMatch();stage.service.autoMatchMv(stage.title,stage.artist,stage.playerPage.durationMs)}
        else search()
    }
    parent:Basic.Overlay.overlay;anchors.centerIn:parent
    width:Math.min(980,parent?parent.width-48:980);height:Math.min(680,parent?parent.height-48:680)
    padding:24;modal:true;focus:true
    closePolicy:Basic.Popup.CloseOnEscape|Basic.Popup.CloseOnPressOutside
    onOpened:{AppTheme.presentPopup(popup);query.text=[stage.title,stage.artist].filter(Boolean).join(" ")}
    onClosed:{if(controller)controller.cancelLyricMatch();if(AppTheme.currentPopup===popup)AppTheme.currentPopup=null}
    onTabChanged:if(tab===1 && !lyricResults.length)search()
    background:Rectangle{radius:24;color:"#f2141923";border.color:"#40ffffff"}
    Basic.Overlay.modal:Rectangle{color:"#70000000"}
    contentItem:Item {
        Text{text:qsTr("换源");color:"white";font.pixelSize:23;font.weight:Font.DemiBold}
        Text{y:34;text:qsTr("选择 MV 与歌词来源");color:"#a9b1bd";font.pixelSize:13}
        RoundIconButton{anchors.right:parent.right;diameter:32;kind:"close";transparentSurface:true;glyphColor:"white";onClicked:popup.close()}
        Column{
            objectName:"immersiveSourceTabs";y:85;width:100;spacing:8
            Repeater{
                model:["MV",qsTr("歌词")]
                Rectangle{
                    required property string modelData
                    required property int index
                    width:100;height:50;radius:12;color:popup.tab===index?"#3a4558":"#222a36"
                    Text{anchors.centerIn:parent;text:parent.modelData;color:"white";font.pixelSize:15}
                    TapHandler{onTapped:popup.tab=parent.index}
                }
            }
        }
        Item{
            x:122;y:82;width:parent.width-x;height:parent.height-y
            Row{
                id:sourceButtons;width:parent.width;spacing:8
                Action{label:qsTr("网易云");selected:popup.provider==="wy";visible:popup.tab===0;onClicked:{popup.provider="wy";popup.search()}}
                Action{label:qsTr("B 站");selected:popup.provider==="bili";visible:popup.tab===0;onClicked:{popup.provider="bili";popup.search()}}
                Action{objectName:"immersiveAutoMatch";label:qsTr("自动匹配");onClicked:popup.autoMatch()}
                Action{label:qsTr("本地视频");visible:popup.tab===0;onClicked:localMv.open()}
            }
            Row{
                y:52;width:parent.width;spacing:8
                Basic.TextField{
                    id:query;objectName:"immersiveSourceQuery";width:parent.width-88;height:38;selectByMouse:true
                    color:"white";placeholderText:qsTr("歌曲名 / 艺术家");leftPadding:12;rightPadding:12
                    background:Rectangle{color:"#22ffffff";radius:10}
                    onAccepted:popup.search()
                }
                Action{width:80;height:38;label:qsTr("搜索");onClicked:popup.search()}
            }
            Text{
                y:102;width:parent.width;height:38;wrapMode:Text.Wrap;color:"#a9b7c8";font.pixelSize:12
                text:popup.tab===0?(popup.stage.service && popup.stage.service.busy?qsTr("正在匹配 / 加载 MV…"):popup.stage.service && popup.stage.service.error.length?popup.stage.service.error:popup.stage.service && popup.stage.service.videoReady?qsTr("MV 已加载")+" · "+popup.stage.service.videoResolution+" · "+popup.stage.service.videoTitle:qsTr("自动模式优先网易云，再尝试 B 站；下方可手动选择候选"))
                    :(popup.controller && popup.controller.lyricMatchBusy?qsTr("正在获取歌词…"):popup.controller && popup.controller.lyricMatchError.length?popup.controller.lyricMatchError:qsTr("按歌曲、艺术家、专辑与时长匹配，预览后应用"))
            }
            ListView{
                id:mvCandidates;objectName:"immersiveMvCandidates";y:145;width:parent.width;height:parent.height-y-58
                visible:popup.tab===0;clip:true;spacing:8;boundsBehavior:Flickable.StopAtBounds
                model:popup.stage.service?popup.stage.service.candidates:[]
                delegate:Rectangle{
                    id:mvRow
                    required property var modelData
                    required property int index
                    width:mvCandidates.width;height:78;radius:12;color:hover.hovered?"#354155":"#252e3b"
                    Image{
                        x:10;y:10;width:92;height:58
                        source:popup.visible && popup.tab===0?(mvRow.modelData.cover||""):""
                        // Keep three source pixels per physical display pixel;
                        // video posters need not decode as full-size photographs.
                        sourceSize:Qt.size(Math.ceil(width*Screen.devicePixelRatio*3),Math.ceil(height*Screen.devicePixelRatio*3))
                        // Closed source pickers must not retain decoded covers.
                        cache:false;fillMode:Image.PreserveAspectCrop;asynchronous:true
                    }
                    Column{
                        x:116;y:16;width:parent.width-x-12;spacing:7
                        Text{width:parent.width;text:mvRow.modelData.title||"";textFormat:Text.PlainText;elide:Text.ElideRight;color:"#f2f5fa";font.pixelSize:14;font.weight:Font.DemiBold}
                        Text{width:parent.width;text:[popup.plays(mvRow.modelData.playCount),mvRow.modelData.provider==="bili"?qsTr("B 站"):qsTr("网易云"),mvRow.modelData.artist].join(" · ");textFormat:Text.PlainText;elide:Text.ElideRight;color:"#a4b0c0";font.pixelSize:12}
                    }
                    HoverHandler{id:hover}
                    TapHandler{onTapped:{popup.stage.backgroundMode="mv";popup.stage.cancelAutoMatch();popup.stage.service.selectMv(mvRow.index)}}
                }
                Basic.ScrollBar.vertical:Basic.ScrollBar{}
            }
            ListView{
                id:lyricCandidates;objectName:"immersiveLyricCandidates";y:145;width:parent.width*.44;height:parent.height-y-58
                visible:popup.tab===1;clip:true;spacing:8;model:popup.lyricResults
                delegate:Rectangle{
                    id:lyricRow
                    required property var modelData
                    required property int index
                    width:lyricCandidates.width;height:86;radius:12;color:popup.selectedLyric===index?"#3d4b61":"#252e3b"
                    Column{
                        x:12;y:12;width:parent.width-24;spacing:6
                        Text{width:parent.width;text:lyricRow.modelData.title||"";textFormat:Text.PlainText;elide:Text.ElideRight;color:"white";font.pixelSize:14}
                        Text{width:parent.width;text:lyricRow.modelData.artist||"";textFormat:Text.PlainText;elide:Text.ElideRight;color:"#a4b0c0";font.pixelSize:12}
                        Text{width:parent.width;text:(lyricRow.modelData.score||0)+"% · "+(lyricRow.modelData.sourceLabel||"");elide:Text.ElideRight;color:"#aac7ef";font.pixelSize:11}
                    }
                    TapHandler{onTapped:{popup.selectedLyric=lyricRow.index;popup.controller.previewLyricMatch(lyricRow.index)}}
                }
                Basic.ScrollBar.vertical:Basic.ScrollBar{}
            }
            Rectangle{
                x:parent.width*.46;y:145;width:parent.width-x;height:parent.height-y-58;radius:12;color:"#202733";visible:popup.tab===1
                ListView{
                    anchors.fill:parent;anchors.margins:16;clip:true;spacing:12
                    model:popup.controller?popup.controller.lyricPreviewLines:[]
                    delegate:Text{
                        required property var modelData
                        width:ListView.view.width;text:[modelData.text,modelData.translation,modelData.romanization].filter(Boolean).join("\n")
                        textFormat:Text.PlainText;wrapMode:Text.Wrap;color:"#dbe3f1";font.pixelSize:13
                    }
                    Basic.ScrollBar.vertical:Basic.ScrollBar{}
                }
            }
            Row{
                anchors.bottom:parent.bottom;spacing:8;visible:popup.tab===0
                Action{label:qsTr("画面 −0.5s");onClicked:if(popup.stage.service)popup.stage.service.offsetMs-=500}
                Text{height:38;verticalAlignment:Text.AlignVCenter;width:50;text:popup.stage.service?(popup.stage.service.offsetMs/1000).toFixed(1)+" s":"0 s";color:"white"}
                Action{label:qsTr("画面 +0.5s");onClicked:if(popup.stage.service)popup.stage.service.offsetMs+=500}
            }
            Action{
                anchors.right:parent.right;anchors.bottom:parent.bottom;label:qsTr("应用歌词");visible:popup.tab===1
                enabled:popup.selectedLyric>=0 && popup.controller && !popup.controller.lyricMatchBusy && popup.controller.lyricPreview.length>0
                onClicked:if(popup.controller.applyLyricMatch(popup.track,popup.controller.lyricPreview))popup.close()
            }
        }
    }
    component Action: UiButton { foregroundColor:"#edf3ff";color:selected?"#4a5f7a":"#303c4e";border.color:"#53617a" }
    FileDialog{
        id:localMv;title:qsTr("选择本地 MV");nameFilters:[qsTr("视频文件 (*.mp4 *.mkv *.webm *.mov *.avi *.m4v)")]
        onAccepted:{popup.stage.backgroundMode="mv";popup.stage.cancelAutoMatch();popup.stage.service.openLocalVideo(selectedFile)}
    }
}
