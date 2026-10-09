import QtQuick
import QtTest
import "Components"

TestCase {
    id: test
    name: "SongRowFavorites"
    when: windowShown
    width: 800; height: 300
    QtObject {
        id: favoriteService
        property var playlists: []
        property int likedTracksRevision: 0
        // Plain JS storage keeps instrumentation from becoming a binding input.
        property var storage: ({calls: 0})
        function isTrackLiked(track) {
            storage.calls++
            return !!storage[track.trackId]
        }
        function setLiked(id, value) {
            storage[id] = value
            likedTracksRevision++
            playlists = [{id: "liked-tracks"}]
        }
    }
    Component {
        id: rowComponent
        SongRow {
            width: 780
            playerController: null
            favorites: favoriteService
        }
    }
    function makeRow(id) {
        return createTemporaryObject(rowComponent, test, {track: {trackId:id,title:id,artist:"Fixture"}})
    }
    function init() {
        favoriteService.storage = {calls:0}
        favoriteService.playlists = []
        favoriteService.likedTracksRevision = 0
    }
    function test_unrelated_playlist_does_not_refresh_likes() {
        for (let i=0; i<16; ++i) verify(makeRow("song-"+i))
        wait(1)
        const calls = favoriteService.storage.calls
        verify(calls>=16)
        favoriteService.playlists = [{id:"unrelated",title:"Renamed playlist"}]
        wait(1)
        console.log("Unrelated playlist: additional lookups", favoriteService.storage.calls-calls)
        compare(favoriteService.storage.calls,calls,"Changing an unrelated playlist must not re-query every visible song")
    }
    function test_membership_refreshes_existing_rows() {
        const a=makeRow("a"), b=makeRow("b")
        verify(a && b); compare(a.liked,false); compare(b.liked,false)
        favoriteService.setLiked("a",true)
        tryCompare(a,"liked",true); compare(b.liked,false)
        favoriteService.setLiked("a",false)
        tryCompare(a,"liked",false)
    }
    function test_reused_row_rechecks_track_and_metadata() {
        favoriteService.setLiked("a",true)
        const row=makeRow("a")
        verify(row); compare(row.liked,true)
        row.track={trackId:"b",title:"Reused delegate"}
        tryCompare(row,"liked",false)
        row.track={trackId:"a",title:"Updated title"}
        tryCompare(row,"liked",true)
    }
}
