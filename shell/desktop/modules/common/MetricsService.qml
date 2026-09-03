pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// The Bar thermal indicator, Dock temperature page and DeskCenter system card
// all consume the kos-data-service metrics snapshot through this singleton,
// so no QML surface polls /proc or /sys and their values cannot drift apart.
// The Go service owns sampling, history and sensor enumeration; this file only
// reads the atomic snapshot and reformats it for the three views.
QtObject {
    id: service

    property bool ready: false
    property real currentMilliC: -1
    property real maximum5MinuteMilliC: -1
    // Compatibility aliases for out-of-tree/older consumers. New UI should
    // use the explicit package-current and five-minute-maximum names.
    readonly property real averageMilliC: currentMilliC
    readonly property real maximumMilliC: maximum5MinuteMilliC
    property real cpuUsage: 0
    property real cpuFrequencyMhz: 0
    property real memoryUsedBytes: 0
    property real memoryTotalBytes: 0
    property real diskUsedBytes: 0
    property real diskTotalBytes: 0
    property var sensors: []
    property var memoryHistory: []
    property var cpuHistory: []
    property var frequencyHistory: []
    readonly property var memoryHistoryValues: historyValues(memoryHistory)
    readonly property var cpuHistoryValues: historyValues(cpuHistory)
    readonly property var frequencyHistoryValues: historyValues(frequencyHistory)

    function historyValues(samples) {
        return samples.map(sample => sample.value)
    }

    // Keep the same ten-second cadence as the service sampler with a little
    // slack so the reloads never synchronize with its writes.
    property Timer refreshTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: service.reload()
    }

    function reload() {
        DataClient.request("metrics.snapshot", {}, function(response) {
            if (response.ok) {
                const metrics = response.result?.metrics ?? response.result ?? {}
                currentMilliC = Number(metrics.currentMilliC
                    ?? metrics.averageMilliC ?? -1)
                maximum5MinuteMilliC = Number(metrics.maximum5MinuteMilliC
                    ?? metrics.maximumMilliC ?? -1)
                cpuUsage = Number(metrics.cpu ?? 0)
                cpuFrequencyMhz = Number(metrics.frequencyMhz ?? 0)
                memoryUsedBytes = Number(metrics.memoryUsedBytes ?? 0)
                memoryTotalBytes = Number(metrics.memoryTotalBytes ?? 0)
                diskUsedBytes = Number(metrics.diskUsedBytes ?? 0)
                diskTotalBytes = Number(metrics.diskTotalBytes ?? 0)
                sensors = Array.isArray(metrics.sensors) ? metrics.sensors : []
                memoryHistory = normalized(metrics.history, sample => sample.memory)
                cpuHistory = normalized(metrics.history, sample => sample.cpu)
                frequencyHistory = normalized(metrics.history, sample => sample.frequencyMhz,
                                              0, Number.POSITIVE_INFINITY)
                ready = true
            } else {
                // The service has not been installed or written its first
                // snapshot yet. Keep the previous values and the callers'
                // availability fallbacks.
            }
        })
    }

    // History samples older than one hour or outside the requested range are
    // dropped; ratio charts use the default 0..1 range and frequency passes
    // its native MHz range explicitly.
    function normalized(history, pick, minimum, maximum) {
        const cutoff = Date.now() - 60 * 60 * 1000
        const result = []
        const samples = Array.isArray(history) ? history : []
        const lowerBound = minimum ?? 0
        const upperBound = maximum ?? 1
        for (let i = 0; i < samples.length; i++) {
            const sample = samples[i]
            const at = Number(sample?.at ?? 0)
            const value = Number(sample ? pick(sample) : 0)
            if (at >= cutoff && Number.isFinite(value)
                    && value >= lowerBound && value <= upperBound)
                result.push({ time: at, value: value })
        }
        return result
    }

    property Connections dataTransport: Connections {
        target: DataClient
        function onTransportChanged(connected) {
            if (connected)
                service.reload()
        }
    }

    Component.onCompleted: reload()
}
