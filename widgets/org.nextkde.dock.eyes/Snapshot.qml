import QtQuick

Item {
    function getSnapshot(size) {
        return {
            status: "ready",
            skin: "cat",
            tempC: 48,
            cpuPercent: 24,
            cpuHistory: [0.22, 0.28, 0.25, 0.34, 0.27, 0.24],
            playing: false,
            trackTitle: "",
            weatherCode: 1,
            isDay: true,
            uptimeSeconds: 2400
        }
    }
}
