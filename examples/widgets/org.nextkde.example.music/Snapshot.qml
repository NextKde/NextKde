import QtQuick

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            hasPlayer: true,
            playing: true,
            loading: false,
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            artworkUrl: "",
            artworkColors: {
                ready: true,
                primary: "#6c3cc8",
                secondary: "#1f78c1"
            },
            positionSeconds: 84,
            lengthSeconds: 243,
            canPrevious: true,
            canTogglePlayPause: true,
            canNext: true,
            canRaise: true,
            lyric: "Waiting in a car"
        }
    }
}
