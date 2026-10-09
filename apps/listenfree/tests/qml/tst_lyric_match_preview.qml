import QtQuick
import QtQuick.Controls.Basic as Basic
import QtTest
import "components"

Item {
    id: fixture
    width: 1066; height: 709
    property string acceptedText: ""
    property bool acceptedIntoEditor: false
    QtObject {
        id: mockController
        property var lyricCandidates: []
        property var lyricMatchSources: []
        property var lyricPreviewLines: []
        property string lyricPreview: ""
        property bool lyricMatchBusy: false
        property string lyricMatchError: ""
        property int releases: 0
        property int stops: 0
        function populate(count) {
            let rows=[]
            for(let i=0;i<count;i++) rows.push({timeMs:i*2000,text:"Line "+i+(i%4===0?" — 长文本换行测试，保持完整内容。".repeat(5):""),translation:i%3===0?"译文 "+i:"",romanization:i%5===0?"romanization "+i:""})
            lyricCandidates=[{key:"test:0",title:"测试歌曲",artist:"测试艺术家",score:100,lyricSource:"test",sourceLabel:"测试"}]
            lyricPreview="[00:01.00]完整原文"
            lyricPreviewLines=rows
        }
        function cancelLyricMatch() { ++stops;lyricMatchBusy=false }
        function releaseLyricMatch() { ++releases;cancelLyricMatch();lyricCandidates=[];lyricMatchSources=[];lyricPreviewLines=[];lyricPreview="" }
        function lyricMatchSeed(song) { return song }
        function searchLyricMatches(song,query) { populate(240) }
        function previewLyricMatch(index) { populate(7) }
    }
    LyricsMatchPopup {
        id: popup
        controller: mockController
        enter: Transition { NumberAnimation { property:"opacity";from:0;to:1;duration:80 } }
        exit: Transition { NumberAnimation { property:"opacity";from:1;to:0;duration:80 } }
        onAcceptedLyrics: (text,intoEditor)=>{fixture.acceptedText=text;fixture.acceptedIntoEditor=intoEditor}
    }
    TestCase {
        name: "LyricMatchPreview"
        when: windowShown
        function preview() { return findChild(popup,"lyricMatchPreview") }
        function liveRows() { return preview().contentItem.children.filter(child=>child.objectName==="lyricMatchPreviewLine") }
        function open(count) {
            mockController.populate(count);popup.selectedKey="test:0";popup.open()
            tryCompare(popup,"opened",true)
            tryCompare(preview(),"count",count)
            wait(30)
        }
        function init() {
            popup.close();tryCompare(popup,"visible",false)
            mockController.releaseLyricMatch();mockController.releases=0;mockController.stops=0
            fixture.acceptedText="";popup.intoEditor=false;AppTheme.currentPopup=null
        }
        function cleanup() { popup.close();tryCompare(popup,"visible",false) }
        function test_longPreviewVirtualizesAndReachesLastRow() {
            open(1200)
            verify(liveRows().length>0);verify(liveRows().length<80)
            preview().positionViewAtIndex(1199,ListView.End)
            tryVerify(()=>liveRows().some(row=>row.index===1199))
            verify(liveRows().length<80)
            const last=preview().itemAtIndex(1199)
            verify(last.y+last.height<=preview().contentY+preview().height+1)
            preview().positionViewAtBeginning()
            tryVerify(()=>preview().itemAtIndex(0)!==null)
            const first=preview().itemAtIndex(0)
            verify(first.height>preview().itemAtIndex(1).height)
            verify(Math.abs(preview().itemAtIndex(1).y-first.y-first.height-18)<1)
        }
        function test_stopPreservesPreviewAndApplyTransfersTextBeforeClose() {
            open(240);mockController.lyricMatchBusy=true;popup.intoEditor=true
            const stop=findChild(popup,"lyricStopButton")
            waitForPolish(stop.parent)
            tryCompare(stop,"x",stop.parent.width-stop.width)
            mouseClick(stop)
            compare(mockController.stops,1);compare(mockController.releases,0);compare(preview().count,240)
            const original=mockController.lyricPreview
            mouseClick(findChild(popup,"lyricApplyButton"))
            tryCompare(popup,"visible",false)
            compare(fixture.acceptedText,original);verify(fixture.acceptedIntoEditor)
            compare(mockController.releases,1);compare(mockController.lyricPreviewLines.length,0)
        }
        function test_candidateReplacementResetsScrollAndPreservesWidth() {
            open(240)
            preview().positionViewAtIndex(100,ListView.Beginning)
            wait(30);verify(preview().contentY!==preview().originY)
            mockController.populate(7)
            tryCompare(preview(),"count",7)
            tryVerify(()=>Math.abs(preview().contentY-preview().originY)<1)
            compare(findChild(popup,"lyricMatchPreviewLines").width,preview().width)
            compare(findChild(popup,"lyricMatchPreviewScrollbar").width,0)
        }
        function test_releaseWaitsForExitAndQuickReopenKeepsContent() {
            open(240)
            popup.close();verify(popup.visible);compare(mockController.releases,0)
            popup.open();tryCompare(popup,"opened",true)
            compare(mockController.releases,0);compare(preview().count,240)
            popup.close();tryCompare(popup,"visible",false)
            compare(mockController.releases,1);tryCompare(preview(),"count",0)
            compare(liveRows().length,0);compare(popup.selectedKey,"");compare(popup.sourceFilter,"all")
        }
        function test_escapeAndRepeatedOpenReleaseRows() {
            for(let i=0;i<8;i++) {
                open(i%2===0?240:3)
                popup.forceActiveFocus();keyClick(Qt.Key_Escape)
                tryCompare(popup,"visible",false)
                tryCompare(preview(),"count",0);compare(liveRows().length,0)
            }
            compare(mockController.releases,8)
        }
        function test_searchAndEmptyPreview() {
            popup.match({title:"新歌曲",artist:"新艺术家"},true)
            tryCompare(popup,"opened",true);tryCompare(preview(),"count",240)
            compare(findChild(popup,"lyricMatchQuery").text,"新歌曲 新艺术家")
            mockController.populate(0);tryCompare(preview(),"count",0);compare(liveRows().length,0)
        }
    }
}
