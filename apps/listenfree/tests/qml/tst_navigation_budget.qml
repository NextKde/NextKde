import QtQuick
import QtTest
import "components"

TestCase {
    id: test
    name: "NavigationBudget"
    when: windowShown
    width: 500; height: 400
    Component {
        id: fakePage
        Item {
            id: page
            objectName: "testPage"
            property string key: parent.routeKey
            property int selection: 0
            function saveNavigationState() { return { selection: selection } }
            function restoreNavigationState(state) {
                selection = state.selection
                cover.status = Image.Loading
                settle.restart()
            }
            Item {
                id: cover
                objectName: "coverSourceImage"
                property bool cache: true
                property int status: Image.Ready
                property url source: Qt.resolvedUrl("assets/album_Cover_" + (page.key === "a" ? 1 : page.key === "b" ? 2 : 3) + ".png")
                property size sourceSize: Qt.size(128,128)
                implicitWidth: 128; implicitHeight: 128
            }
            Timer { id: settle; interval: 160; onTriggered: cover.status = Image.Ready }
        }
    }
    Component {
        id: cacheComponent
        NavigationCache {
            width: test.width; height: test.height
            route: "a"
            pages: [{route:"a",component:fakePage},{route:"b",component:fakePage},
                    {route:"c",component:fakePage},{route:"d",component:fakePage}]
        }
    }
    function pageFor(item,key) {
        if(item.objectName === "testPage" && item.key === key) return item
        for(const child of item.children) { const found=pageFor(child,key); if(found) return found }
        return null
    }
    function loaded(item) {
        let count=item.objectName === "testPage" ? 1 : 0
        for(const child of item.children) count+=loaded(child)
        return count
    }
    function test_evictionAndPreparedReturn() {
        const cache=createTemporaryObject(cacheComponent,test,{artworkBudgetBytes:128*128*10})
        tryCompare(cache,"displayedRoute","a")
        pageFor(cache,"a").selection=37
        cache.route="b";tryCompare(cache,"displayedRoute","b")
        cache.route="c";tryCompare(cache,"displayedRoute","c")
        compare(loaded(cache),2);verify(pageFor(cache,"a")===null)
        compare(cache.pageStates.a.selection,37)
        verify(cache.retainedArtworkBytes<=cache.artworkBudgetBytes)
        cache.route="d";tryCompare(cache,"displayedRoute","d")
        verify(cache.retainedArtworkCount<=1)
        cache.route="a"
        wait(40);compare(cache.displayedRoute,"d")
        tryCompare(cache,"displayedRoute","a")
        compare(pageFor(cache,"a").selection,37);compare(loaded(cache),2)
        cache.artworkBudgetBytes=0;compare(cache.retainedArtworkCount,0)
    }
    function test_uniqueBytesAndNewestFirst() {
        const cache=createTemporaryObject(cacheComponent,test,{artworkBudgetBytes:300})
        tryCompare(cache,"displayedRoute","a")
        cache.artworkOrder=["new","shared","old"]
        const one={source:Qt.resolvedUrl("assets/album_Cover_2.png"),width:5,height:5,bytes:250}
        const other={source:Qt.resolvedUrl("assets/album_Cover_3.png"),width:5,height:5,bytes:250}
        const states={new:[one],shared:[one],old:[other]}
        cache.retainArtwork(states)
        compare(cache.retainedArtworkBytes,250);compare(cache.retainedArtworkCount,1)
        verify(states.new!==undefined && states.shared!==undefined);verify(states.old===undefined)
        cache.retainArtwork({});compare(cache.retainedArtworkBytes,0);compare(cache.retainedArtworkCount,0)
    }
}
