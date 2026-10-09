pragma ComponentBehavior: Bound
import QtQuick
import ListenFree.Native 1.0

Item {
    id: scene
    objectName: "fumeLyrics"
    property var lyrics: []
    property string seed: ""
    property string title: ""
    property string artist: ""
    property real positionMs: 0
    property bool playing: false
    property bool active: true
    property bool reducedMotion: false
    property bool wordTimingEnabled: true
    property real renderPosition: positionMs
    property real cameraX: 750
    property real cameraY: 400
    property real cameraScale: 1
    property real vx: 0
    property real vy: 0
    property real vs: 0
    property real holdRatio: .35
    readonly property int lineIndex: {
        let lo=0,hi=layout.blocks.length
        while(lo<hi){const mid=(lo+hi)>>1;if(Number(layout.blocks[mid].start||0)<=renderPosition)lo=mid+1;else hi=mid}
        return lo-1
    }
    readonly property var focusBlock: {
        const blocks=layout.blocks
        for(let i=Math.min(lineIndex,blocks.length-1);i>=0;i--)if(Number(blocks[i].width)>0)return blocks[i]
        return ({})
    }
    readonly property real targetX: Number(focusBlock.x||0)+Number(focusBlock.width||700)*.5
    readonly property real targetY: Number(focusBlock.y||0)+Number(focusBlock.height||200)*.5
    // Keep the article's type hierarchy visible. Scaling by inverse font size
    // used to make both body text and hero titles look almost equally large.
    readonly property real targetScale: Math.max(.08,Math.min(2.2,
        Math.min(width/1066,height/720)*1.2,
        width*.84/Math.max(1,Number(focusBlock.width||700)),
        height*.72/Math.max(1,Number(focusBlock.height||200))))
    property real flightX: 0
    property real flightY: 0
    property real flightScale: 1
    property real flightStart: 0
    property bool longFlight: false
    readonly property real worldLeft: cameraX-width/(2*cameraScale)
    readonly property real worldTop: cameraY-height/(2*cameraScale)
    function snap(){cameraX=targetX;cameraY=targetY;cameraScale=targetScale;vx=0;vy=0;vs=0;longFlight=false}
    onWidthChanged: if(!playing||reducedMotion)Qt.callLater(snap)
    onHeightChanged: if(!playing||reducedMotion)Qt.callLater(snap)
    onPositionMsChanged: { const jump=Math.abs(positionMs-renderPosition)>1200;renderPosition=positionMs;if(jump||!playing)Qt.callLater(snap) }
    onPlayingChanged: renderPosition=positionMs
    onLineIndexChanged: {
        flightX=cameraX;flightY=cameraY;flightScale=cameraScale;flightStart=renderPosition
        longFlight=Math.hypot(targetX-cameraX,targetY-cameraY)*Math.max(cameraScale,targetScale)>Math.min(width,height)*2.75
        if(!playing||reducedMotion)Qt.callLater(snap)
    }
    onReducedMotionChanged: if(reducedMotion)snap()
    FumeLayout { id: layout; lyrics: scene.lyrics; seed: scene.seed; fontFamily: AppTheme.fontFamily; onLayoutChanged: Qt.callLater(scene.snap) }
    FrameAnimation {
        running: scene.active && scene.playing && !scene.reducedMotion
        onTriggered: {
            scene.renderPosition=Math.min(scene.positionMs+250,scene.renderPosition+frameTime*1000)
            let tx=scene.targetX,ty=scene.targetY,ts=scene.targetScale
            const phase=Math.min(1,Math.max(0,(scene.renderPosition-scene.flightStart)/700))
            if(scene.longFlight&&phase<1){
                const t=1-Math.pow(1-phase,3)
                tx=scene.flightX+(tx-scene.flightX)*t;ty=scene.flightY+(ty-scene.flightY)*t
                ts=(1-t)*scene.flightScale+t*ts-Math.sin(t*Math.PI)*Math.min(scene.flightScale,ts)*.6
            }
            // Folia's damped camera (208/24, zoom 54/13.5), substepped for low FPS.
            const dt=Math.min(frameTime,.05),steps=Math.max(1,Math.ceil(dt*120)),h=dt/steps
            for(let i=0;i<steps;i++){
                scene.vx+=((tx-scene.cameraX)*208-scene.vx*24)*h
                scene.vy+=((ty-scene.cameraY)*208-scene.vy*24)*h
                scene.vs+=((ts-scene.cameraScale)*54-scene.vs*13.5)*h
                scene.cameraX+=scene.vx*h;scene.cameraY+=scene.vy*h;scene.cameraScale=Math.max(.06,Math.min(2.24,scene.cameraScale+scene.vs*h))
            }
        }
    }
    clip: true
    Item {
        id: paper
        x: scene.width*.5-scene.cameraX*scene.cameraScale
        y: scene.height*.5-scene.cameraY*scene.cameraScale
        scale: scene.cameraScale;transformOrigin: Item.TopLeft
        Repeater {
            model: layout.blocks
            delegate: Loader {
                id: blockLoader
                required property var modelData
                objectName: "fumeBlock-"+Number(modelData.index)
                x: Number(modelData.x||0);y: Number(modelData.y||0)
                width: Number(modelData.width||0);height: Number(modelData.height||0)
                active: width>0 && x+width>scene.worldLeft-100 && x<scene.worldLeft+scene.width/scene.cameraScale+100
                    && y+height>scene.worldTop-100 && y<scene.worldTop+scene.height/scene.cameraScale+100
                sourceComponent: Item {
                    id: blockContent
                    readonly property var block: blockLoader.modelData
                    readonly property real age: Math.max(0,scene.renderPosition-Number(block.end))
                    readonly property real passedOpacity: .58-(.58-.075)*Math.pow(Math.min(1,age/Math.max(2400,scene.holdRatio*60000)),3)
                    // Unprinted letters keep a faint trace; old lines remain in the article.
                    Item {
                        width: blockContent.block.contentWidth;height: blockContent.block.contentHeight
                        x: blockContent.block.rotation===90 ? height : 0
                        rotation: blockContent.block.rotation;transformOrigin: Item.TopLeft
                        Repeater {
                            model: blockContent.block.runs
                            delegate: Text {
                                required property var modelData
                                x: modelData.x;y: modelData.y;width: modelData.width;height: modelData.height
                                text: modelData.text;textFormat: Text.PlainText;wrapMode: Text.NoWrap
                                lineHeightMode: Text.FixedHeight;lineHeight: blockContent.block.lineAdvance
                                horizontalAlignment: modelData.centered ? Text.AlignHCenter : Text.AlignLeft
                                font.family: AppTheme.fontFamily;font.pixelSize: blockContent.block.fontSize;font.weight: blockContent.block.fontWeight
                                color: "#edf0ef";opacity: scene.renderPosition<Number(blockContent.block.start) ? .14 : scene.renderPosition>=Number(blockContent.block.end) ? blockContent.passedOpacity : .22
                            }
                        }
                        Repeater {
                        model: scene.lineIndex===Number(blockContent.block.index) || (scene.renderPosition>=Number(blockContent.block.end) && scene.renderPosition<Number(blockContent.block.end)+800)?blockContent.block.glyphs:[]
                        delegate: Item {
                            id: glyph
                            required property var modelData
                            readonly property real progress: modelData.timed && scene.wordTimingEnabled?Math.max(0,Math.min(1,(scene.renderPosition-modelData.start)/Math.max(80,modelData.end-modelData.start))):1
                            x: modelData.x;y: modelData.y;width: modelData.width;height: modelData.height
                            visible: progress>0
                            opacity:scene.lineIndex===Number(blockLoader.modelData.index)?1:Math.max(0,1-(scene.renderPosition-Number(blockLoader.modelData.end))/800)
                            Rectangle { anchors.fill: parent;anchors.margins:-2;color:"#dce5dd";opacity: glyph.modelData.timed?Math.sin(glyph.progress*Math.PI)*.3:0 }
                            Text {
                                text:glyph.modelData.text;textFormat:Text.PlainText;color:"#fcfcf5"
                                font.family:AppTheme.fontFamily;font.pixelSize:blockLoader.modelData.fontSize;font.weight:blockLoader.modelData.fontWeight
                                opacity: glyph.progress>.02?1:glyph.progress/.02
                            }
                        }
                        }
                    }
                }
            }
        }
    }
    // Subtle paper geometry and drifting fog; no full article texture or Canvas.
    ShaderEffect {
        anchors.fill: parent;visible: !scene.reducedMotion && GraphicsInfo.api!==GraphicsInfo.Software
        property real phase: scene.renderPosition*.00006
        property vector2d viewport: Qt.vector2d(width,height)
        property real energy: 0
        property real kind: 1
        property vector3d bands: Qt.vector3d(0,0,0)
        fragmentShader: "qrc:/shaders/immersive-atmosphere.frag.qsb"
    }
    Column {
        anchors.centerIn: parent;width: parent.width*.7;spacing:18;visible: !scene.focusBlock.text
        Text {width:parent.width;text:scene.title;textFormat:Text.PlainText;color:"white";font.pixelSize:Math.min(64,scene.width*.06);font.weight:Font.Bold;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap}
        Text {width:parent.width;text:scene.artist;textFormat:Text.PlainText;color:"#bfffffff";font.pixelSize:20;horizontalAlignment:Text.AlignHCenter}
    }
}
