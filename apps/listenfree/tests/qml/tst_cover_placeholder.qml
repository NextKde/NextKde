import QtQuick
import QtTest
import "Components"

Item {
    width: 240; height: 200
    Rectangle { anchors.fill: parent; color: "#667366" }
    CoverArt { id: cover; x: 20; y: 20; width: 132; height: 132; source: "" }
    QtObject {
        id: artworkLookup
        property var currentTrack: ({})
        signal trackArtworkResolved(string source, string rid, string artwork)
        function isCurrentTrack(track) { return false }
        function requestTrackArtwork(track) {}
    }
    SongRow { id: song; visible: false; width: 700; playerController: artworkLookup; favorites: null }
    TestCase {
        name: "CoverPlaceholder"
        when: windowShown
        function init() { cover.source = ""; cover.fallbackSource = "" }
        function test_async_artwork_reaches_playlist_row() {
            const first = Qt.resolvedUrl("opaque.png")
            const second = Qt.resolvedUrl("transparent.png")
            song.track = { source: "kw", rid: "123", title: "First" }
            compare(String(song.artworkSource), "")
            artworkLookup.trackArtworkResolved("wy", "123", String(first))
            compare(String(song.artworkSource), "", "Providers may reuse the same numeric song ID")
            artworkLookup.trackArtworkResolved("kw", "123", String(first))
            compare(song.artworkSource, first, "A playlist row must receive a completed cover lookup")
            song.track = { source: "kw", rid: "456", title: "Next" }
            compare(String(song.artworkSource), "", "A reused row must discard the previous cover")
            artworkLookup.trackArtworkResolved("kw", "123", String(first))
            compare(String(song.artworkSource), "", "A late reply must not overwrite another song")
            artworkLookup.trackArtworkResolved("kw", "456", String(first))
            compare(song.artworkSource, first)
            song.track = { source: "kw", rid: "456", artwork: second }
            artworkLookup.trackArtworkResolved("kw", "456", String(first))
            compare(song.artworkSource, second, "Metadata artwork takes precedence over a lookup")
        }
        function test_empty_source_uses_fallback_then_primary() {
            cover.fallbackSource = Qt.resolvedUrl("opaque.png")
            tryCompare(cover, "missingArtwork", false)
            verify(cover.usingFallback)
            cover.source = Qt.resolvedUrl("opaque.png")
            tryCompare(cover, "missingArtwork", false)
            verify(!cover.usingFallback, "The real track cover must replace its fallback")
            cover.source = ""
            tryCompare(cover, "missingArtwork", false)
            verify(cover.usingFallback)
        }
        function test_missing_data() {
            return [
                { tag: "empty", source: "" },
                { tag: "failed", source: Qt.resolvedUrl("nonexistent.png") },
                { tag: "transparent-sentinel", source: Qt.resolvedUrl("transparent.png") }
            ]
        }
        function test_missing(data) {
            cover.source = data.source
            wait(200)
            if (data.tag !== "transparent-sentinel")
                verify(cover.missingArtwork, "A missing image must show the placeholder")
            const frame = grabImage(cover)
            // The old five-pixel inset shadow left a different band at the top.
            compare(frame.pixel(66, 2), frame.pixel(66, 9), "Placeholder must fill the outline evenly")
            compare(frame.pixel(66, 9), frame.pixel(66, 120))
        }
        function test_loaded() {
            cover.source = Qt.resolvedUrl("opaque.png")
            tryCompare(cover, "missingArtwork", false)
            // Offscreen rendering validates the backing; actual GPU cover
            // pixels are checked by --cover-grid-only in the application.
        }
    }
}
