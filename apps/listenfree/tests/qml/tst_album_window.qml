import QtQuick
import QtTest
import "pages"

TestCase {
    id: test
    name: "AlbumWindow"
    when: windowShown
    visible: true
    width: 1066; height: 709

    Component { id: pageComponent; LibraryPage { width: test.width; height: test.height; reduceMotion: true } }
    SignalSpy { id: opened; signalName: "openCollection" }
    function countItems(item, prefix) {
        let count = String(item.objectName).indexOf(prefix) === 0 ? 1 : 0
        for (const child of item.children) count += countItems(child, prefix)
        return count
    }
    function catalog(count) {
        const albums = []
        for (let i = 0; i < count; ++i)
            albums.push({ title: "Album " + i, artist: "Artist " + i,
                          artwork: Qt.resolvedUrl("assets/album_Cover_2.png") })
        return { albums: albums, songs: [], artists: [] }
    }
    function makePage(count) { return createTemporaryObject(pageComponent, test, { catalog: catalog(count) }) }
    function select(page, index) {
        page.selectedAlbumIndex = index
        tryVerify(() => findChild(page, "albumCard" + index) !== null)
        tryVerify(() => page.loadedAlbumCount <= 9)
    }
    function test_largeLibraryAndIdentity() {
        const page = makePage(5000)
        verify(page !== null)
        select(page, 2500)
        const middle = findChild(page, "albumCard2500")
        compare(middle.album.title, "Album 2500")
        compare(page.loadedAlbumCount, 9)
        compare(countItems(page, "albumCard"), 9)
        compare(countItems(page, "albumReflection"), 9)
        select(page, 2501)
        verify(middle === findChild(page, "albumCard2500"), "Wheel navigation must retain existing animated cards")
        compare(middle.relativeIndex, -1)
        const reflected = findChild(page, "albumReflection2501")
        const image = findChild(findChild(page, "albumCard2501"), "coverSourceImage")
        compare(reflected.source, image.source)
        compare(reflected.sourceSize, image.sourceSize)
        compare(reflected.fillMode, image.fillMode)
        for (const index of [0, 4999, 3, 4996, 100, 101, 99]) {
            select(page, index)
            compare(findChild(page, "albumCard" + index).album.title, "Album " + index)
        }
    }
    function test_clickUsesAbsoluteAlbumIdentity() {
        const page = makePage(600)
        select(page, 350)
        opened.target = page
        opened.clear()
        const card = findChild(page, "albumCard350")
        mouseClick(card, card.width / 2, card.height / 2)
        tryCompare(opened, "count", 1)
        compare(opened.signalArguments[0][0], "Album")
        compare(opened.signalArguments[0][1], "Album 350")
        opened.target = null
    }
    function test_filterLayoutAndRestore() {
        const page = makePage(600)
        select(page, 580)
        const state = page.saveNavigationState()
        select(page, 4)
        page.restoreNavigationState(state)
        select(page, 580)
        compare(page.selectedAlbumIndex, state.albumIndex)
        page.filterText = "no matching album"
        tryCompare(page, "loadedAlbumCount", 0)
        page.filterText = "Album 599"
        tryCompare(page, "loadedAlbumCount", 1)
        compare(findChild(page, "albumCard0").album.title, "Album 599")
        page.albumGridLayout = true
        tryCompare(page, "loadedAlbumCount", 0)
        page.albumGridLayout = false
        tryCompare(page, "loadedAlbumCount", 1)
        page.catalog = catalog(0)
        tryCompare(page, "loadedAlbumCount", 0)
        page.filterText = ""
        page.catalog = catalog(2)
        tryCompare(page, "loadedAlbumCount", 2)
        page.section = "songs"
        tryCompare(page, "loadedAlbumCount", 0)
    }
}
