import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            hasPlayer: true,
            playing: true,
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            artworkUrl: "",
            artworkColors: { ready: true, primary: "#5b6bd6", secondary: "#c850a0" },
            positionSeconds: 96,
            lengthSeconds: 243,
            lyric: "Waiting in a car, waiting for a ride in the dark"
        }
    }
}
