import QtQuick
import QtTest
import "Components"

Item {
    width: 1066; height: 760
    QtObject {
        id: backend
        property var lyricCandidates: []
        property var lyricMatchSources: []
        property bool lyricMatchBusy: true
        property string lyricMatchError: ""
        property string lyricPreview: ""
        property var lyricPreviewLines: []
        property int searches: 0
        function searchLyricMatches(track,query) { ++searches }
        function cancelLyricMatch() { lyricMatchBusy=false }
        function releaseLyricMatch() { cancelLyricMatch();lyricCandidates=[];lyricMatchSources=[];lyricPreview="";lyricPreviewLines=[] }
        function previewLyricMatch(index) { lyricPreview=lyricCandidates[index].title;lyricPreviewLines=[{text:lyricPreview}] }
    }
    LyricsMatchPopup { id: popup;controller: backend }
    TestCase {
        name: "LyricSearchInteraction"
        when: windowShown
        function row(key,source,title) { return {key:key,lyricSource:source,title:title,artist:"Artist",score:90,sourceLabel:source,features:["逐字"]} }
        function init() {
            backend.lyricMatchBusy=true;backend.lyricPreview="";backend.lyricPreviewLines=[];backend.searches=0
            backend.lyricCandidates=[row("wy:1","wy","First")]
            popup.selectedKey="";popup.sourceFilter="all";popup.open();wait(40)
        }
        function cleanup() { popup.close();wait(20) }
        function test_previewDuringSearchAndStableSelectionAfterRanking() {
            mouseClick(findChild(popup.contentItem,"lyricCandidate-wy:1"))
            compare(backend.lyricPreview,"First")
            verify(findChild(popup,"lyricApplyButton").enabled)
            backend.lyricCandidates=[row("amll:2","amll","New higher match"),row("wy:1","wy","First")]
            compare(popup.selectedIndex,1);compare(popup.selected.title,"First");compare(backend.lyricPreview,"First")
            popup.sourceFilter="wy"
            compare(popup.visibleResults.length,1);compare(backend.searches,0)
        }
        function test_stopPreservesVerifiedPreview() {
            mouseClick(findChild(popup.contentItem,"lyricCandidate-wy:1"))
            mouseClick(findChild(popup,"lyricStopButton"))
            compare(backend.lyricMatchBusy,false);compare(backend.lyricPreview,"First")
            verify(findChild(popup,"lyricApplyButton").enabled)
        }
    }
}
