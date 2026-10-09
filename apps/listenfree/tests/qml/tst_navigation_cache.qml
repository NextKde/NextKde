import QtQuick
import QtTest
import "../../music_player_desktop/components"

TestCase {
    id: test
    name: "NavigationCacheLifecycle"
    when: windowShown
    width: 400; height: 300

    Component {
        id: pageComponent
        Item {
            objectName: "page:" + parent.routeKey
            property int selectedIndex: 0
            property real viewportY: 0
            property alias artwork: cover.source
            Image {
                id: cover
                objectName: "coverSourceImage"
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectCrop
            }
            function saveNavigationState() { return { selection: selectedIndex, y: viewportY } }
            function restoreNavigationState(state) { selectedIndex = state.selection; viewportY = state.y }
        }
    }
    Component {
        id: cacheComponent
        NavigationCache {
            width: 400; height: 300
            route: "a"
            pages: [
                { route: "a", component: pageComponent },
                { route: "b", component: pageComponent },
                { route: "c", component: pageComponent },
                { route: "d", component: pageComponent }
            ]
        }
    }
    function makeCache() { return createTemporaryObject(cacheComponent, test) }
    function page(cache, route) { return findChild(cache, "page:" + route) }
    function go(cache, route) { cache.route = route; tryVerify(function() { return page(cache, route) !== null }) }

    function test_pageBudget() {
        const cache = makeCache()
        go(cache, "b"); go(cache, "c"); go(cache, "d")
        tryVerify(function() { return page(cache, "a") === null && page(cache, "b") === null },
                  1000, "Old visual pages must be evicted after two more routes")
        verify(page(cache, "c") !== null, "Keep the most recent page for immediate back navigation")
    }
    function test_stateSurvivesEviction() {
        const cache = makeCache()
        page(cache, "a").selectedIndex = 17
        page(cache, "a").viewportY = 723.5
        go(cache, "b"); go(cache, "c")
        tryVerify(function() { return page(cache, "a") === null })
        go(cache, "a")
        compare(page(cache, "a").selectedIndex, 17)
        compare(page(cache, "a").viewportY, 723.5)
    }
    function test_transitionSourceOutlivesEviction() {
        const cache = makeCache()
        cache.transitionSourceItem = page(cache, "a")
        go(cache, "b"); go(cache, "c"); go(cache, "d")
        verify(page(cache, "a") !== null, "A sampled transition source must remain alive")
        page(cache, "a").selectedIndex = 34
        cache.transitionSourceItem = null
        tryVerify(function() { return page(cache, "a") === null })
        go(cache, "a")
        compare(page(cache, "a").selectedIndex, 34)
    }
    Component {
        id: settingsComponent
        QtObject {
            property int revision: 0
            property bool remember: true
            function value(key, fallback) { return remember }
        }
    }
    function test_disablingMemoryDropsStateAndOldPages() {
        const settings = createTemporaryObject(settingsComponent, test)
        const cache = createTemporaryObject(cacheComponent, test, { settingsStore: settings })
        page(cache, "a").selectedIndex = 22
        go(cache, "b"); go(cache, "c")
        settings.remember = false; ++settings.revision
        tryVerify(function() { return page(cache, "b") === null })
        go(cache, "a")
        compare(page(cache, "a").selectedIndex, 0)
        tryVerify(function() { return page(cache, "c") === null })
    }
    function test_artworkReferenceSurvivesFurtherNavigationAndIsReleased() {
        const settings = createTemporaryObject(settingsComponent, test)
        const cache = createTemporaryObject(cacheComponent, test, { settingsStore: settings })
        page(cache, "a").artwork = Qt.resolvedUrl("../../music_player_desktop/assets/album_Cover_2.png")
        tryCompare(findChild(page(cache, "a"), "coverSourceImage"), "status", Image.Ready)
        go(cache, "b"); go(cache, "c")
        const retained = findChild(cache, "navigationRetainedArtwork")
        verify(retained !== null)
        compare(retained.status, Image.Ready)
        go(cache, "d")
        verify(retained === findChild(cache, "navigationRetainedArtwork"),
               "Further navigation must keep the existing image reference alive")
        settings.remember = false; ++settings.revision
        tryVerify(function() { return findChild(cache, "navigationRetainedArtwork") === null })
    }
}
