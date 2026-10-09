import QtQuick
import "Components"

Item {
    id: scene
    width: 960; height: 760
    Rectangle { anchors.fill: parent; color: "#283343" }
    LyricsPanel {
        id: panel
        objectName: "probeLyrics"
        x: 100; y: 30; width: 760; height: 700
        artworkBackground: true
        fontSize: 36
    }
    function fixture(count) {
        const lines = []
        const text = "让每一个音符随时间轻轻流动 停留"
        for (let i = 0; i < count; ++i) {
            const words = []
            for (let j = 0; j < text.length - 2; ++j)
                words.push({text: text[j], startMs: i*4000+j*110, endMs: i*4000+(j+1)*110})
            words.push({text: "停留", startMs: i*4000+1800, endMs: i*4000+3800})
            lines.push({text: text, timeMs: i*4000, translation: "Let every note flow gently with time", words: words})
        }
        return lines
    }
    function effects(item) {
        const name = String(item.objectName)
        let result = { items: 1,
            rowLayers: name.indexOf("lyricRow") === 0 && item.layer.enabled ? 1 : 0,
            wordLayers: name.indexOf("lyricWord") === 0 && item.layer.enabled ? 1 : 0,
            accents: name.indexOf("lyricAccentTexture") === 0 ? 1 : 0,
            glyphs: name.indexOf("lyricGrapheme") === 0 ? 1 : 0 }
        const children = item.children || []
        for (let i = 0; i < children.length; ++i) {
            const child = effects(children[i])
            for (const key in result) result[key] += child[key]
        }
        return result
    }
    function effectCounts() { return JSON.stringify(effects(panel)) }
    // Only the offline capture calls this. Keep frame diagnostics out of the
    // production component and ordinary benchmark's measured frame loop.
    function captureState() {
        const rows=[], words=[], glyphs=[]
        function visit(item, row) {
            const name=String(item.objectName)
            if (name.indexOf("lyricRow")===0) {
                row=item
                if (item.nearViewport) rows.push({index:item.index,y:item.renderedY,
                    targetY:item.targetY,focus:item.focusAmount,blur:item.blurAmount,
                    blurLayer:item.layer.enabled,targetBatch:item.targetBatch})
            }
            if (row && row.nearViewport && name.indexOf("lyricWord")===0
                    && item.parent.progress!==undefined && item.parent.hasInk) {
                const bounds=item.mapToItem(scene,0,0,item.implicitWidth,item.implicitHeight)
                const word=item.parent
                words.push({id:name,row:row.index,rect:[bounds.x,bounds.y,bounds.width,bounds.height],
                    progress:word.progress,focus:row.focusAmount,nativeVisible:item.visible,
                    effect:row.focusAmount>0 && (word.accentActive || word.emphasisActive),
                    longTone:word.emphasized,liftEm:word.lift/panel.fontSize})
            }
            if (row && row.nearViewport && name.indexOf("lyricGrapheme")===0) {
                const center=item.mapToItem(scene,item.width/2,item.height/2)
                glyphs.push({id:name,row:row.index,center:[center.x,center.y],scale:item.scale,
                    glow:item.glowAlpha,progress:item.progress,envelope:item.envelope})
            }
            const children=item.children || []
            for (let i=0;i<children.length;++i) visit(children[i],row)
        }
        visit(panel,null)
        return JSON.stringify({positionMs:panel.renderPositionMs,rows:rows,words:words,glyphs:glyphs,fontSize:panel.fontSize,
            layoutReason:panel.layoutReason,layoutBatch:panel.layoutBatch,
            firstVisibleLine:panel.firstVisibleLine,seeking:panel.seeking})
    }
    function prepareMotionCapture() {
        const lines=fixture(40)
        const passages=[
            ["让每个音符 慢慢发亮",["让","每","个","音","符"," ","慢","慢","发亮"],[200,220,200,240,240,80,300,320,2000],"Give each note room to glow"],
            ["Let the quiet moments glow",["Let ","the ","quiet ","moments ","glow"],[450,350,650,750,1800],"让安静的片刻慢慢发亮"],
            ["光经过窗边 轻轻停留",["光","经","过","窗","边"," ","轻","轻","停留"],[200,220,200,240,240,80,300,320,2000],"Light rests softly by the window"]
        ]
        for (let i=0;i<lines.length;++i) {
            const passage=passages[((i-20)%3+3)%3]
            let time=i*4000
            const words=[]
            for (let j=0;j<passage[1].length;++j) {
                words.push({text:passage[1][j],startMs:time,endMs:time+passage[2][j]})
                time+=passage[2][j]
            }
            lines[i]={text:passage[0],timeMs:i*4000,translation:passage[3],words:words}
        }
        panel.lyrics=lines
        panel.currentLineIndex=20
        panel.positionMs=80000
        panel.playing=true
        panel.notifySeek()
    }
    // The original video has no TTML. These two observed long-word intervals
    // are explicit test inputs, not a claim about Apple's hidden timestamps.
    function prepareWordReferenceCapture() {
        const lines=[]
        for (let i=0;i<40;++i) {
            const word=i%2===0?"bad":"better"
            const duration=i%2===0?1200:1467
            lines.push({text:"Still "+word,timeMs:i*4000,words:[
                {text:"Still ",startMs:i*4000-300,endMs:i*4000},
                {text:word,startMs:i*4000+1000,endMs:i*4000+1000+duration}]})
        }
        panel.fontSize=64
        panel.showTranslation=false
        panel.lyrics=lines
        panel.currentLineIndex=20
        panel.positionMs=80000
        panel.playing=true
        panel.notifySeek()
    }
    Component.onCompleted: {
        panel.lyrics = fixture(300)
        panel.currentLineIndex = 20
        panel.positionMs = 82000
        panel.notifySeek()
    }
}
