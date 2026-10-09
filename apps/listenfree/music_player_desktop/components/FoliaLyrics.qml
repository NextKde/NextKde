pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import ListenFree.Native 1.0
import "FoliaComposition.js" as Program

Item {
    id: pv
    property var lyrics: []
    property string style: "classic"
    property real positionMs: 0
    property bool playing: false
    property bool active: true
    property bool reducedMotion: false
    property string title: ""
    property string artist: ""
    property url artwork: ""
    property real renderPosition: positionMs
    property bool showTranslation: true
    property bool wordTimingEnabled: true
    property real energy: 0
    readonly property int lineIndex: nativeScene.lineIndex
    signal seekRequested(real timeMs, int index)
    onPositionMsChanged: renderPosition=positionMs
    onPlayingChanged: renderPosition=positionMs
    onActiveChanged: renderPosition=positionMs
    // Use Qt's existing image loading/cache, and sample once per ready cover.
    // Kept outside the viewport so the source itself never covers the PV.
    Image {
        id: accentSample; objectName: "foliaAccentSample"
        x: -128; width: 64; height: 64
        source: (pv.style==="claddagh" || pv.style==="diorama") ? pv.artwork : ""
        sourceSize: Qt.size(64,64); fillMode: Image.PreserveAspectFit
        asynchronous: true
        onSourceChanged: {
            accentTimer.stop(); nativeScene.resetArtworkAccent()
            if(status===Image.Ready)accentTimer.restart()
        }
        onStatusChanged: {
            if(status===Image.Ready)accentTimer.restart()
            else if(status===Image.Error || status===Image.Null)nativeScene.resetArtworkAccent()
        }
        Component.onCompleted: if(status===Image.Ready)accentTimer.restart()
    }
    Timer { id: accentTimer; interval: 16; onTriggered: if(accentSample.status===Image.Ready)nativeScene.sampleArtwork(accentSample) }
    FrameAnimation {
        running: pv.active && pv.playing && pv.style!=="still"
        onTriggered: pv.renderPosition=Math.min(pv.positionMs+250,pv.renderPosition+frameTime*1000)
    }
    Loader {
        id:compositionLoader
        anchors.fill:parent;active:pv.style==="tempera"
        sourceComponent:FoliaComposition {
            seed:pv.title+" / "+pv.artist;lineIndex:nativeScene.lineIndex
            positionMs:pv.renderPosition;reducedMotion:pv.reducedMotion
            startMs:lineIndex>=0?Number(pv.lyrics[lineIndex].timeMs||0):0
            endMs:lineIndex+1<pv.lyrics.length?Number(pv.lyrics[lineIndex+1].timeMs):startMs+5000
        }
    }
    FoliaDecor { anchors.fill:parent;scene:nativeScene;clip:true }
    FoliaScene {
        id: nativeScene; objectName: "foliaNativeScene"
        anchors.fill: parent
        lyrics: pv.lyrics; style: pv.style; seed: pv.title+" / "+pv.artist
        position: pv.renderPosition; fontFamily: AppTheme.fontFamily
        wordTiming: pv.wordTimingEnabled; reducedMotion: pv.reducedMotion;energy: pv.energy
        composition:compositionLoader.item?compositionLoader.item.profile:({})
        placements:pv.style==="sonnet"?Program.sonnetLayout(layoutUnits,shotName,pv.title,width,height):[]
        Repeater {
            model: nativeScene.model
            delegate: FoliaNodeItem {
                id: letter
                required node
                scene: nativeScene
                width: node.width; height: node.height
                Loader {
                    active: pv.style==="claddagh" && letter.node.kind===0 && !pv.reducedMotion && letter.opacity>.005
                    sourceComponent: Text {
                        text: letter.node.text||""; textFormat: Text.PlainText
                        font.family: AppTheme.fontFamily; font.pixelSize: letter.node.fontSize; font.weight: Font.DemiBold
                        color: letter.ink
                        opacity: Math.max(Math.min(1,letter.defocus/2),letter.highlight*.35)
                        // Only this soft copy is rasterized. The sharp body
                        // below remains a scalable Qt curve at every zoom/DPR.
                        layer.enabled: true; layer.smooth: true
                        layer.effect: MultiEffect {
                            blurEnabled: true; blurMax: 12
                            blur: Math.max(.28,Math.min(1,letter.defocus/12))
                            shadowEnabled: true; shadowColor: letter.ink
                            shadowOpacity: letter.highlight*.5
                            shadowHorizontalOffset: 0; shadowVerticalOffset: 0; shadowBlur: .8
                        }
                    }
                }
                Text {
                    id: glyphBody
                    objectName: "foliaGlyphBody"
                    visible: letter.node.kind===0
                    text: letter.node.text||""; textFormat: Text.PlainText
                    font.family: AppTheme.fontFamily
                    font.pixelSize: letter.node.fontSize
                    font.weight: pv.style==="tilt"?Font.Normal:Font.DemiBold
                    font.italic: letter.node.italic||false
                    color: letter.ink
                    opacity: pv.style==="claddagh" && !pv.reducedMotion ? 1-Math.min(1,letter.defocus/2) : 1
                    renderType: (pv.style==="claddagh" || pv.style==="diorama") ? Text.CurveRendering : Text.QtRendering
                    // Focused orbit/diorama glyphs remain native curves at any
                    // zoom/DPR; only defocused planes need raster layers.
                    layer.enabled: visible && !pv.reducedMotion && letter.opacity>0.005 &&
                                   !(pv.style==="diorama" && letter.defocus===0) &&
                                   (pv.style==="classic"||pv.style==="cadenza"||pv.style==="diorama"||pv.style==="monet")
                    layer.textureSize: Qt.size(Math.ceil(width),Math.ceil(height))
                    // These two scenes have no glow and keep the focused row
                    // exactly sharp. Qt retains a MultiEffect's blur pyramid
                    // after blurEnabled=false, so retire that effect instance
                    // once focus has settled. Keep the source layer, padding
                    // and sampling unchanged; any nonzero blur restores the
                    // full effect immediately. The delay avoids focus churn.
                    readonly property bool canSettleFocus: (pv.style === "monet" || pv.style === "diorama") && letter.defocus === 0
                    property bool focusSettled: false
                    onCanSettleFocusChanged: {
                        focusSettled = false
                        if (canSettleFocus) focusSettle.restart()
                        else focusSettle.stop()
                    }
                    Component.onCompleted: if (canSettleFocus) focusSettle.restart()
                    Timer {
                        id: focusSettle
                        interval: 200
                        onTriggered: glyphBody.focusSettled = glyphBody.canSettleFocus
                    }
                    layer.effect: focusSettled ? focusedEffect : depthEffect
                    Component {
                        id: focusedEffect
                        MultiEffect {
                            autoPaddingEnabled: false
                            paddingRect: Qt.rect(12, 12, 12, 12)
                        }
                    }
                    Component {
                        id: depthEffect
                        MultiEffect {
                            blurEnabled:true;blurMax:12;blur:Math.min(1,letter.defocus/12)
                            shadowEnabled:pv.style==="classic"||pv.style==="cadenza"||pv.style==="claddagh"
                            shadowColor:letter.ink;shadowOpacity:letter.highlight*.65
                            shadowHorizontalOffset:0;shadowVerticalOffset:0;shadowBlur:.8
                        }
                    }
                }
                Loader {
                    active: letter.node.kind===0 && (pv.style==="diorama"||pv.style==="cadenza"||pv.style==="tempera")
                    sourceComponent: Text {
                        text: letter.node.text||"";textFormat:Text.PlainText
                        font.family: AppTheme.fontFamily;font.pixelSize: letter.node.fontSize;font.weight:Font.DemiBold
                        color:letter.ink;opacity:letter.ghostOpacity;y:letter.ghostLift;scale:letter.ghostScale
                    }
                }
                Loader {
                    active: letter.node.kind===1 || letter.node.kind===2
                    anchors.fill:parent
                    sourceComponent: Rectangle {
                        radius: letter.node.kind===1?16:letter.node.kind===3?width/2:0
                        color:letter.ink
                        border.width:letter.node.kind===1?1:0;border.color:"#20ffffff"
                    }
                }
                Loader {
                    active:letter.node.kind===3;anchors.fill:parent
                    sourceComponent:CoverArt { source:pv.artwork;cornerRadius:width/2 }
                }
                TapHandler {
                    enabled:letter.node.kind===0 && letter.opacity>.2
                    onTapped:pv.seekRequested(Number(pv.lyrics[letter.node.line].timeMs||0),letter.node.line)
                }
            }
        }
    }
    Text {
        x:parent.width*.12;width:parent.width*.76;y:parent.height*.82
        visible:pv.showTranslation && nativeScene.translation.length>0
        text:nativeScene.translation;textFormat:Text.PlainText;wrapMode:Text.Wrap
        color:"#bff0ece5";font.family:AppTheme.fontFamily;font.pixelSize:Math.max(14,Math.min(22,parent.height*.026))
        horizontalAlignment:Text.AlignHCenter
    }
    Column {
        anchors.centerIn:parent;width:parent.width*.8;spacing:16;visible:nativeScene.lineIndex<0
        Text { width:parent.width;text:pv.title;textFormat:Text.PlainText;color:"#f5f2ed";font.family:AppTheme.fontFamily;font.pixelSize:Math.min(64,pv.width*.053);font.weight:Font.DemiBold;wrapMode:Text.Wrap;horizontalAlignment:Text.AlignHCenter }
        Text { width:parent.width;text:pv.artist;textFormat:Text.PlainText;color:"#bfffffff";font.pixelSize:18;horizontalAlignment:Text.AlignHCenter }
    }
}
