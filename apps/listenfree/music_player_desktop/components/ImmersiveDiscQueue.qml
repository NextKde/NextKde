pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: queue
    objectName: "immersiveDiscQueue"
    property bool open: false
    property bool reducedMotion: false
    property var sourceModel: null
    property var rows: []
    property int currentIndex: -1
    property bool playing: false
    readonly property int trackCount: sourceModel ? sourceModel.count : (rows ? rows.length : 0)
    property int selectedIndex: -1
    property int requestedIndex: -1
    property real wheelPosition: 0
    property real travel: 0
    property real expansion: 0
    property string phase: "closed"
    property real wheelDebt: 0
    readonly property bool presented: phase!=="closed"
    readonly property int loadedSectorCount: windowRows.count
    readonly property real radius: Math.max(height*.96,width*.64)
    readonly property real innerRadius: radius-Math.min(width*.20,height*.33)
    readonly property real discEdge: width*.37
    readonly property real angularStep: 11
    readonly property var selectedTrack: { const revision=queueRevision; return trackAt(selectedIndex) }
    property int queueRevision: 0
    property bool initialized: false
    signal playRequested(int index, var track)
    signal togglePlaybackRequested()
    signal closeRequested()
    signal closed()
    clip: true
    visible: presented
    focus: open

    function trackAt(index) {
        if(index<0 || index>=trackCount)return ({})
        return (sourceModel ? sourceModel.get(index) : rows[index]) || ({})
    }
    function bounded(index) { return trackCount ? Math.max(0,Math.min(trackCount-1,index)) : -1 }
    function syncWindow(refresh) {
        const middle=Math.round(wheelPosition),first=Math.max(0,middle-5),last=Math.min(trackCount-1,middle+5)
        while(windowRows.count && windowRows.get(0).queueRow<first)windowRows.remove(0)
        while(windowRows.count && windowRows.get(windowRows.count-1).queueRow>last)windowRows.remove(windowRows.count-1)
        if(windowRows.count && windowRows.get(0).queueRow>last)windowRows.clear()
        if(windowRows.count && windowRows.get(windowRows.count-1).queueRow<first)windowRows.clear()
        let before=windowRows.count ? windowRows.get(0).queueRow-1 : last
        for(let i=before;i>=first;i--)windowRows.insert(0,{queueRow:i,track:trackAt(i)})
        let after=windowRows.count ? windowRows.get(windowRows.count-1).queueRow+1 : first
        for(let i=after;i<=last;i++)windowRows.append({queueRow:i,track:trackAt(i)})
        if(refresh)for(let i=0;i<windowRows.count;i++)windowRows.setProperty(i,"track",trackAt(windowRows.get(i).queueRow))
    }
    function refreshQueue() {
        if(!initialized)return
        ++queueRevision
        requestedIndex=bounded(requestedIndex<0 ? currentIndex : requestedIndex)
        selectedIndex=bounded(selectedIndex)
        if(wheelPosition>trackCount-1)wheelPosition=Math.max(0,trackCount-1)
        syncWindow(true)
        if(presented)advance()
    }
    function animateSlide(value, stage) {
        if(slide.running && slide.to===value)return
        slide.stop(); phase=stage; slide.from=travel; slide.to=value
        slide.duration=Math.max(80,(value===1?500:380)*Math.abs(value-travel));slide.start()
    }
    function animateExpansion(value, stage) {
        if(radial.running && radial.to===value)return
        radial.stop();phase=stage;radial.from=expansion;radial.to=value
        radial.duration=Math.max(70,(value===1?260:180)*Math.abs(value-expansion));radial.start()
    }
    // All transitions retarget their current values. Rapid input only changes
    // the destination; it never queues a backlog of full animation sequences.
    function advance() {
        if(!initialized)return
        if(reducedMotion){
            slide.stop();radial.stop();spin.stop()
            travel=open?1:0;selectedIndex=bounded(requestedIndex);wheelPosition=Math.max(0,selectedIndex)
            expansion=open&&trackCount?1:0;phase=open?"idle":"closed";syncWindow(false)
            if(!open)closed()
            return
        }
        if(!open){
            spin.stop();slide.stop()
            if(expansion>.001){animateExpansion(0,"retract");return}
            if(travel>.001){animateSlide(0,"exit");return}
            phase="closed";windowRows.clear();closed();return
        }
        if(travel<.999){
            radial.stop();spin.stop()
            if(expansion>.001){animateExpansion(0,"retract");return}
            animateSlide(1,"enter");return
        }
        if(requestedIndex!==selectedIndex || Math.abs(wheelPosition-Math.max(0,requestedIndex))>.001){
            if(expansion>.001){spin.stop();animateExpansion(0,"retract");return}
            if(spin.running && spin.to===Math.max(0,requestedIndex))return
            spin.stop();phase="rotate"
            // A distant locate jump only traverses a small neighborhood.
            if(Math.abs(requestedIndex-wheelPosition)>6)wheelPosition=requestedIndex+(wheelPosition>requestedIndex?4:-4)
            spin.from=wheelPosition;spin.to=Math.max(0,requestedIndex)
            spin.duration=Math.min(500,280+Math.abs(spin.to-spin.from)*55);spin.start();return
        }
        if(expansion<.999 && trackCount){animateExpansion(1,"expand");return}
        phase="idle"
    }
    function selectIndex(index) {
        if(!open || !trackCount)return
        requestedIndex=bounded(index);advance()
    }
    function step(amount) { selectIndex((requestedIndex>=0?requestedIndex:0)+amount) }
    function turnWheel(angleDelta, pixelDelta) {
        wheelDebt-=pixelDelta!==0 ? pixelDelta/42 : angleDelta/120
        const steps=Math.trunc(wheelDebt)
        if(steps){wheelDebt-=steps;step(steps)}
    }
    function playSelection() {
        if(selectedIndex<0 || !open || (phase!=="idle" && phase!=="expand"))return
        if(selectedIndex===currentIndex)togglePlaybackRequested()
        else playRequested(selectedIndex,trackAt(selectedIndex))
    }
    onOpenChanged: {
        if(open && phase==="closed"){
            selectedIndex=bounded(currentIndex>=0?currentIndex:0);requestedIndex=selectedIndex
            wheelPosition=Math.max(0,selectedIndex);wheelDebt=0;syncWindow(true)
        }
        advance()
    }
    onReducedMotionChanged: if(presented)advance()
    onWheelPositionChanged: if(initialized)syncWindow(false)
    onRowsChanged: refreshQueue()
    onSourceModelChanged: refreshQueue()
    onTrackCountChanged: refreshQueue()
    onCurrentIndexChanged: if(open && currentIndex>=0)selectIndex(currentIndex)
    Component.onCompleted: {
        initialized=true
        selectedIndex=bounded(currentIndex>=0?currentIndex:0);requestedIndex=selectedIndex
        wheelPosition=Math.max(0,selectedIndex);syncWindow(true)
        if(open)advance()
    }
    Connections {
        target: queue.sourceModel; ignoreUnknownSignals: true
        function onModelReset() { queue.refreshQueue() }
        function onDataChanged() { queue.refreshQueue() }
    }
    ListModel { id: windowRows; dynamicRoles: true }
    NumberAnimation {
        id: slide;target:queue;property:"travel"
        easing.type:Easing.BezierSpline;easing.bezierCurve:[.32,.72,0,1,1,1]
        onFinished:queue.advance()
    }
    NumberAnimation {
        id: radial;target:queue;property:"expansion"
        easing.type:Easing.BezierSpline;easing.bezierCurve:[.23,1,.32,1,1,1]
        onFinished:queue.advance()
    }
    NumberAnimation {
        id: spin;target:queue;property:"wheelPosition"
        easing.type:Easing.BezierSpline;easing.bezierCurve:[.77,0,.175,1,1,1]
        onFinished:{queue.selectedIndex=queue.bounded(Math.round(queue.wheelPosition));queue.advance()}
    }

    Rectangle { anchors.fill:parent;color:"#080a10";opacity:queue.travel*.90 }
    MouseArea {
        anchors.fill:parent;acceptedButtons:Qt.AllButtons
        onClicked:queue.closeRequested()
        onWheel:wheel=>{queue.turnWheel(wheel.angleDelta.y,wheel.pixelDelta.y);wheel.accepted=true}
    }
    Item {
        id: disc;objectName:"queueDisc"
        x:queue.discEdge-queue.radius-(1-queue.travel)*(queue.discEdge+140)
        y:queue.height*.5-Math.sin(queue.travel*Math.PI)*24
        rotation:(1-queue.travel)*-7
        scale:.95+.05*queue.travel;opacity:queue.travel
        Rectangle {
            x:-queue.radius;y:x;width:queue.radius*2;height:width;radius:width/2
            color:"#ea151b21";border.width:1;border.color:"#28ffffff"
        }
        Repeater {
            model:7
            Rectangle {
                required property int index
                readonly property real ringRadius:queue.innerRadius-20-index*19
                x:-ringRadius;y:x;width:ringRadius*2;height:width;radius:width/2
                color:"transparent";border.width:1;border.color:index===0?"#24ffffff":"#09ffffff"
            }
        }
        Repeater {
            model:windowRows
            delegate:QueueDiscSector {
                id: wedge
                required property int queueRow
                required property var track
                objectName:"queueSector"+queueRow
                readonly property real difference:queueRow-queue.selectedIndex
                readonly property real spread:queue.expansion*1.35
                readonly property real leftEdge:(queueRow-queue.wheelPosition-.5)*queue.angularStep+(difference<=0?-spread:spread)
                readonly property real rightEdge:(queueRow-queue.wheelPosition+.5)*queue.angularStep+(difference<0?-spread:spread)
                selected:queueRow===queue.selectedIndex
                emphasis:selected?queue.expansion:0
                angle:(leftEdge+rightEdge)/2;halfAngle:(rightEdge-leftEdge)/2
                innerRadius:queue.innerRadius
                outerRadius:queue.radius+(selected?queue.expansion*Math.min(78,queue.width*.055):0)
                artwork:track ? (track.artwork||track.artworkUrl||"") : ""
                opacity:Math.max(.30,1-Math.abs(queueRow-queue.wheelPosition)*.13)
                z:selected?2:1
                onSelectedRequested:queue.selectIndex(queueRow)
            }
        }
    }
    Column {
        x:32;y:36;spacing:6;opacity:queue.travel
        Text { text:qsTr("播放列表");color:"#e9edf0";font.family:AppTheme.fontFamily;font.pixelSize:19;font.weight:Font.DemiBold }
        Text { text:queue.trackCount+qsTr(" 首歌曲");color:"#88ffffff";font.pixelSize:12 }
    }
    Column {
        id: information; objectName:"discQueueInformation"
        x:parent.width*.51+(1-queue.expansion)*18
        width:parent.width*.42
        y:Math.max(110,(parent.height-height)*.5)
        spacing:20;opacity:queue.trackCount?queue.expansion*queue.travel:queue.travel
        Text {
            text:queue.trackCount?(queue.selectedIndex===queue.currentIndex?(queue.playing?qsTr("正在播放"):qsTr("已暂停")):qsTr("队列选曲")):qsTr("播放列表为空")
            color:"#a7b3be";font.pixelSize:12;font.letterSpacing:2
        }
        Text {
            width:parent.width;text:queue.selectedTrack.title||""
            color:"#f5f6f8";font.family:AppTheme.fontFamily
            font.pixelSize:Math.max(28,Math.min(52,queue.width*.034));font.weight:Font.DemiBold
            wrapMode:Text.Wrap;maximumLineCount:3;elide:Text.ElideRight;textFormat:Text.PlainText
        }
        Column {
            width:parent.width;spacing:9
            Text { width:parent.width;text:queue.selectedTrack.artist||"";textFormat:Text.PlainText;color:"#d6dce3";font.pixelSize:19;elide:Text.ElideRight }
            Text { width:parent.width;text:queue.selectedTrack.album||"";textFormat:Text.PlainText;color:"#85929f";font.pixelSize:14;elide:Text.ElideRight }
        }
        Row {
            visible:queue.trackCount>0;spacing:18
            RoundIconButton {
                objectName:"discQueuePlay";diameter:60
                kind:queue.selectedIndex===queue.currentIndex && queue.playing?"pause":"play"
                glyphColor:"#ffffff";transparentSurface:true;darkMode:true
                tooltip:qsTr("播放／暂停");onClicked:queue.playSelection()
            }
            Column {
                anchors.verticalCenter:parent.verticalCenter;spacing:6
                Text { text:(queue.selectedIndex+1)+" / "+queue.trackCount;color:"#d1d7de";font.pixelSize:13 }
                Text {
                    readonly property int seconds:Math.max(0,Math.floor(Number(queue.selectedTrack.duration||0)/1000))
                    text:Math.floor(seconds/60)+":"+String(seconds%60).padStart(2,"0")
                    color:"#75838f";font.pixelSize:12
                }
            }
        }
        Text {
            visible:queue.currentIndex>=0 && queue.selectedIndex!==queue.currentIndex
            text:qsTr("回到正在播放");color:locateHover.hovered?"white":"#a2b2c2";font.pixelSize:13
            HoverHandler { id:locateHover;cursorShape:Qt.PointingHandCursor }
            TapHandler { onTapped:queue.selectIndex(queue.currentIndex) }
        }
    }
    Row {
        anchors.bottom:parent.bottom;anchors.bottomMargin:30
        x:parent.width*.51;spacing:12;opacity:queue.travel*.65
        IconGlyph { width:16;height:16;kind:"queue";glyphColor:"#c4d0db" }
        Text { text:qsTr("滚轮浏览 · 点击封面选曲");color:"#c4d0db";font.pixelSize:12 }
    }
    RoundIconButton {
        objectName:"discQueueClose";anchors.right:parent.right;anchors.rightMargin:28
        y:28;diameter:38;kind:"close";glyphColor:"#eef2f6";transparentSurface:true;darkMode:true
        opacity:queue.travel;tooltip:qsTr("返回沉浸");onClicked:queue.closeRequested()
    }
    Keys.onEscapePressed:event=>{queue.closeRequested();event.accepted=true}
    Keys.onDownPressed:event=>{queue.step(1);event.accepted=true}
    Keys.onUpPressed:event=>{queue.step(-1);event.accepted=true}
    Keys.onRightPressed:event=>{queue.step(1);event.accepted=true}
    Keys.onLeftPressed:event=>{queue.step(-1);event.accepted=true}
    Keys.onReturnPressed:event=>{queue.playSelection();event.accepted=true}
}
