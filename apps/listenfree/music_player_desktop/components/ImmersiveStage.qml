pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtMultimedia
import ListenFree.Native 1.0

Item {
    id: stage
    objectName: "immersiveStage"
    property alias settingsPanel: settingsPopup
    property alias sourcesPanel: sourcesPopup
    required property var service
    required property var playerPage
    property var controller: null
    property var track: ({})
    readonly property string songIdentity: String(track.entryId || track.localPath || [track.source,track.rid,track.title,track.artist].join("|"))
    property var settingsStore: null
    property url artwork: ""
    property var lyrics: []
    property real positionMs: 0
    property bool playing: false
    property bool exposed: true
    property bool reducedMotion: false
    property string title: ""
    property string artist: ""
    property bool showTranslation: true
    property bool wordTimingEnabled: true
    property string backgroundMode: preference("background", "aura")
    property string pvStyle: preference("lyricStyle", "fume")
    property string visualization: preference("visualization", "none")
    property real visualHeight: Math.max(40, Math.min(240, Number(preference("visualHeight", 112))))
    property real hideDelay: Math.max(1, Math.min(10, Number(preference("hideDelay", 3))))
    property bool controlsOpen: true
    readonly property bool controlsShown: controlsOpen || progress.pressed || settingsPopup.visible || sourcesPopup.visible
    readonly property bool videoVisible: backgroundMode === "mv" && service && service.videoReady
    readonly property real energy: {
        if (!service || !playing) return 0
        let sum=0; const bins=service.spectrum
        for(let i=0;i<bins.length;i++)sum+=Number(bins[i]||0)
        return Math.min(1, sum/Math.max(1,bins.length)*2.5)
    }
    readonly property vector3d frequencyEnergy: {
        if(!service || !playing)return Qt.vector3d(0,0,0)
        const bins=service.spectrum;let low=0,mid=0,high=0
        for(let i=0;i<bins.length;i++){const value=Number(bins[i]||0);if(i<10)low+=value;else if(i<22)mid+=value;else high+=value}
        return Qt.vector3d(Math.min(1,low*.22),Math.min(1,mid*.2),Math.min(1,high*.28))
    }
    signal seekRequested(real timeMs, int index)
    signal fullScreenRequested()
    function preference(key, fallback) { return settingsStore ? settingsStore.value("immersive."+key, fallback) : fallback }
    function save(key, value) { if(settingsStore)settingsStore.setValue("immersive."+key, value) }
    function cancelAutoMatch() { matchTimer.stop() }
    function matchVideo() { if(backgroundMode === "mv" && service && title.length) service.autoMatchMv(title, artist, playerPage.durationMs) }
    onBackgroundModeChanged: { save("background",backgroundMode); if(backgroundMode!=="mv" && service)service.clearVideo();else matchTimer.restart() }
    onPvStyleChanged: save("lyricStyle",pvStyle)
    onVisualizationChanged: { save("visualization",visualization); syncActive() }
    onVisualHeightChanged: save("visualHeight",visualHeight)
    onHideDelayChanged: save("hideDelay",hideDelay)
    onSongIdentityChanged: if(backgroundMode === "mv")matchTimer.restart()
    function syncActive() { if(service){service.suspended=!exposed;service.spectrumEnabled=visualization!=="none";service.active=true} }
    onExposedChanged: syncActive()
    Component.onCompleted: { syncActive();hideTimer.restart();if(backgroundMode==="mv")matchTimer.restart() }
    Component.onDestruction: if(service){service.active=false;service.attachVideoSink(null)}
    Timer { id: matchTimer; interval:150; onTriggered:stage.matchVideo() }
    Timer { id: hideTimer; interval: stage.hideDelay*1000; onTriggered: if(!progress.pressed)stage.controlsOpen=false }

    ArtworkBackground {
        objectName: "immersiveBackground"
        anchors.fill: parent; artwork: stage.artwork
        mode: stage.backgroundMode === "aura" ? "DynamicFlow" : "BlurredArtwork"
        playing: stage.playing && stage.exposed && !stage.videoVisible
        reducedMotion: stage.reducedMotion
        blurAmount: 80; neutralImage: true
        visible: !stage.videoVisible
    }
    Loader {
        anchors.fill:parent; active:stage.backgroundMode === "mv" && stage.exposed
        sourceComponent: VideoOutput {
            objectName:"immersiveVideo";fillMode:VideoOutput.PreserveAspectCrop;visible:stage.videoVisible
            Component.onCompleted:if(stage.service)stage.service.attachVideoSink(videoSink)
            Component.onDestruction:if(stage.service)stage.service.attachVideoSink(null)
        }
    }
    Rectangle { anchors.fill:parent;color:stage.videoVisible ? "#60000000" : stage.backgroundMode === "blur" ? "#85000000" : "#50000000" }
    MouseArea { anchors.fill:parent;acceptedButtons:Qt.AllButtons;onPressed:mouse=>{mouse.accepted=true;AppTheme.closePopup()};onWheel:wheel=>wheel.accepted=true }
    Loader {
        id: pvLoader; objectName:"immersivePvLoader";anchors.fill:parent
        active:stage.exposed;sourceComponent:stage.pvStyle==="fume"?fume:otherPv
    }
    Component {
        id: fume
        FumeLyrics {
            objectName:"immersivePv";lyrics:stage.lyrics;seed:stage.title+" / "+stage.artist
            title:stage.title;artist:stage.artist;positionMs:stage.positionMs;playing:stage.playing;reducedMotion:stage.reducedMotion;wordTimingEnabled:stage.wordTimingEnabled
        }
    }
    Component {
        id: otherPv
        FoliaLyrics {
            objectName:"immersivePv";lyrics:stage.lyrics;style:stage.pvStyle
            title:stage.title;artist:stage.artist;positionMs:stage.positionMs;playing:stage.playing;reducedMotion:stage.reducedMotion
            showTranslation:stage.showTranslation;wordTimingEnabled:stage.wordTimingEnabled
            energy:stage.energy
            artwork:stage.artwork
            onSeekRequested:(timeMs,index)=>stage.seekRequested(timeMs,index)
        }
    }
    ImmersiveSpectrum {
        objectName:"immersiveSpectrum";anchors.bottom:parent.bottom;width:parent.width;height:stage.visualHeight
        visible:stage.visualization==="spectrum"
        bands:visible&&stage.service?stage.service.spectrum:[]
    }
    ShaderEffect {
        objectName:"immersiveAmbient";anchors.fill:parent
        visible:stage.visualization==="ambient" && GraphicsInfo.api!==GraphicsInfo.Software
        property real phase:0
        property vector2d viewport:Qt.vector2d(width,height)
        property real energy:stage.energy
        property real kind:0
        property vector3d bands:stage.frequencyEnergy
        fragmentShader:"qrc:/shaders/immersive-atmosphere.frag.qsb"
    }
    Item {
        height:38;width:parent.width;opacity:stage.controlsShown?1:0
        Behavior on opacity { NumberAnimation { duration:stage.reducedMotion?0:180 } }
        MouseArea { anchors.fill:parent;anchors.rightMargin:130;onPressed:if(stage.playerPage.hostWindow)stage.playerPage.hostWindow.startSystemMove() }
        Row {
            id: immersiveTrafficCluster
            anchors.right:parent.right;anchors.rightMargin:9;y:7;spacing:10
            WindowTrafficButton {
                action:"minimize";fillColor:"#2fc866"
                revealGlyph:immersiveTrafficHover.hovered
                reducedMotion:stage.reducedMotion
                onClicked:if(stage.playerPage.hostWindow)stage.playerPage.hostWindow.showMinimized()
            }
            WindowTrafficButton {
                action:"maximize";fillColor:"#ffbf18"
                revealGlyph:immersiveTrafficHover.hovered
                reducedMotion:stage.reducedMotion
                onClicked:if(stage.playerPage.hostWindow) {
                    if(stage.playerPage.hostWindow.visibility===Window.Maximized)stage.playerPage.hostWindow.showNormal()
                    else stage.playerPage.hostWindow.showMaximized()
                }
            }
            WindowTrafficButton {
                action:"close";fillColor:"#ff5f57"
                revealGlyph:immersiveTrafficHover.hovered
                reducedMotion:stage.reducedMotion
                onClicked:if(stage.playerPage.hostWindow)stage.playerPage.hostWindow.close()
            }
            HoverHandler { id: immersiveTrafficHover }
        }
    }
    Item {
        id: hotzone;objectName:"immersiveBottomHotzone";anchors.bottom:parent.bottom;width:parent.width;height:stage.controlsShown?125:26
        HoverHandler { onHoveredChanged:{if(hovered){stage.controlsOpen=true;hideTimer.restart()}} onPointChanged:if(hovered){stage.controlsOpen=true;hideTimer.restart()} }
    }
    Item {
        id: footer;objectName:"immersiveFooter";anchors.bottom:parent.bottom;width:parent.width;height:100
        opacity:stage.controlsShown?1:0;visible:opacity>0;enabled:stage.controlsShown
        Behavior on opacity { NumberAnimation { duration:stage.reducedMotion?0:220 } }
        Row {
            objectName:"immersiveLeftControls";x:28;anchors.verticalCenter:parent.verticalCenter;spacing:14
            RoundIconButton { diameter:34;kind:"queue";transparentSurface:true;glyphColor:"white";tooltip:qsTr("播放列表");onClicked:stage.playerPage.queueRequested() }
            RoundIconButton { objectName:"immersiveExit";diameter:34;kind:"chevronRight";rotation:180;transparentSurface:true;glyphColor:"white";tooltip:qsTr("退出沉浸式");onClicked:stage.playerPage.immersiveActive=false }
            RoundIconButton { diameter:34;kind:"equalizer";transparentSurface:true;glyphColor:"white";tooltip:qsTr("音效");onClicked:stage.playerPage.equalizerRequested() }
        }
        Row {
            anchors.centerIn:parent;spacing:28
            RoundIconButton { anchors.verticalCenter:parent.verticalCenter;diameter:32;kind:"previous";transparentSurface:true;glyphColor:"white";onClicked:stage.playerPage.previousRequested() }
            RoundIconButton { diameter:52;glyphSize:38;kind:stage.playing?"pause":"play";transparentSurface:true;glyphColor:"white";onClicked:stage.playerPage.playPauseRequested() }
            RoundIconButton { anchors.verticalCenter:parent.verticalCenter;diameter:32;kind:"next";transparentSurface:true;glyphColor:"white";onClicked:stage.playerPage.nextRequested() }
        }
        Row {
            objectName:"immersiveRightControls";anchors.right:parent.right;anchors.rightMargin:28;anchors.verticalCenter:parent.verticalCenter;spacing:12
            RoundIconButton { objectName:"immersiveSourceButton";diameter:34;kind:"sourceSwap";transparentSurface:true;glyphColor:"white";tooltip:qsTr("MV 与歌词换源");onClicked:sourcesPopup.open() }
            RoundIconButton { objectName:"immersiveSettingsButton";diameter:34;kind:"adjustments";transparentSurface:true;glyphColor:"white";tooltip:qsTr("沉浸设置");onClicked:settingsPopup.open() }
            Item {
                width:Math.min(Math.max(songInfoTitle.implicitWidth,songInfoArtist.implicitWidth),Math.max(80,Math.min(180,stage.width*.18)));height:40
                Column {
                    width:parent.width;spacing:3
                    Text { id:songInfoTitle;width:parent.width;text:stage.title;textFormat:Text.PlainText;elide:Text.ElideRight;color:"white";font.pixelSize:15;font.weight:Font.DemiBold;horizontalAlignment:Text.AlignRight }
                    Text { id:songInfoArtist;width:parent.width;text:stage.artist;textFormat:Text.PlainText;elide:Text.ElideRight;color:"#bfffffff";font.pixelSize:11;horizontalAlignment:Text.AlignRight }
                }
                TapHandler { onTapped:stage.playerPage.informationRequested() }
            }
            CoverArt { width:42;height:42;source:stage.artwork;cornerRadius:7;TapHandler{onTapped:stage.playerPage.informationRequested()} }
        }
    }
    ProgressBar {
        id: progress;objectName:"immersiveProgress";anchors.bottom:parent.bottom;width:parent.width;height:stage.controlsShown?16:2
        darkMode:true;alignToBottom:true;trackThickness:stage.controlsShown?5:2;showHandle:false
        interactive:stage.controlsShown && !stage.playerPage.live;value:stage.playerPage.progressValue;commitOnRelease:true
        onValueChangedByUser:value=>stage.playerPage.progressChangedByUser(value)
        onInteractionEnded:hideTimer.restart()
    }
    ImmersiveSettingsPopup { id:settingsPopup;stage:stage }
    ImmersiveSourcesPopup { id:sourcesPopup;stage:stage;controller:stage.controller;track:stage.track }
}
