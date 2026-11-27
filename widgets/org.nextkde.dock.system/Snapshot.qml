import QtQml

QtObject {
    function getSnapshot(size) {
        return {
            status: "ready",
            cpuUsage: 0.34,
            memoryUsedBytes: 9800000000,
            memoryTotalBytes: 16000000000,
            diskUsedBytes: 410000000000,
            diskTotalBytes: 1000000000000,
            temperatureMilliC: 52000,
            temperatureMaxMilliC: 61000
        }
    }
}
