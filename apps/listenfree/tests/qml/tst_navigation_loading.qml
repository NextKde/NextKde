import QtQuick
import QtTest
import "../../music_player_desktop/components"

TestCase {
    id: test
    name: "NavigationLoading"
    visible: true
    when: windowShown
    width: 500; height: 400
    Component {
        id: fakePage
        Rectangle {
            objectName: "page:" + parent.routeKey
            property bool started: false
            property int clicks: 0
            Component.onCompleted: started = true
            color: "red"
            MouseArea { anchors.fill: parent; onClicked: ++parent.clicks }
        }
    }
    Component {
        id: factory
        NavigationCache {
            width: test.width; height: test.height
            property bool slowBusy: true
            property string requestError: ""
            route: "slow"
            contentBusy: route === "slow" && slowBusy
            pages: [{route:"slow",component:fakePage},{route:"ready",component:fakePage},
                    {route:"other",component:fakePage}]
        }
    }
    function page(cache, route) { return findChild(cache, "page:" + route) }
    function waitForPage(cache, route) { tryVerify(() => page(cache, route) !== null) }

    function test_initialRequestStartsWhileHidden() {
        const cache = createTemporaryObject(factory, test)
        verify(cache.loading)
        waitForPage(cache, "slow")
        verify(page(cache, "slow").started, "Hidden pages must still start their data requests")
        verify(!page(cache, "slow").visible)
        verify(!page(cache, "slow").enabled)
        cache.slowBusy = false
        tryCompare(cache, "loading", false)
        verify(page(cache, "slow").visible)
        mouseClick(page(cache, "slow"), 20, 20)
        compare(page(cache, "slow").clicks, 1)
    }
    function test_refreshAndFailureRestoreContent() {
        const cache = createTemporaryObject(factory, test, { slowBusy: false })
        tryCompare(cache, "loading", false)
        cache.slowBusy = true
        verify(cache.loading)
        verify(!page(cache, "slow").visible)
        mouseClick(cache, 20, 20)
        compare(page(cache, "slow").clicks, 0)
        cache.requestError = "Connection failed"
        cache.slowBusy = false
        tryCompare(cache, "loading", false)
        verify(page(cache, "slow").visible, "An empty or failed result must exit the loading state")
    }
    function test_fastSwitchAndLateReply() {
        const cache = createTemporaryObject(factory, test)
        waitForPage(cache, "slow")
        cache.route = "ready"
        verify(!page(cache, "slow").visible)
        tryCompare(cache, "loading", false)
        verify(page(cache, "ready").visible)
        cache.route = "slow"
        verify(cache.loading)
        verify(!page(cache, "ready").visible)
        cache.route = "ready"
        tryCompare(cache, "loading", false)
        cache.slowBusy = false
        wait(80)
        compare(cache.displayedRoute, "ready")
        verify(page(cache, "ready").visible)
        verify(!page(cache, "slow").visible)
    }
    function test_cachedAndUnknownRoutes() {
        const cache = createTemporaryObject(factory, test, { slowBusy: false })
        tryCompare(cache, "loading", false)
        const first = page(cache, "slow")
        cache.route = "ready"; tryCompare(cache, "loading", false)
        cache.route = "slow"; tryCompare(cache, "loading", false)
        verify(first === page(cache, "slow"))
        cache.route = "missing"
        verify(!cache.loading, "An unknown route must not spin forever")
        verify(!first.visible)
        cache.route = "slow"; tryCompare(cache, "loading", false)
        verify(page(cache, "slow").visible)
    }
}
