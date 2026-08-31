import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.dock
import qs.desktop.modules.platform

// Live transfer-rate companion for NetworkStatus. NetworkService decides
// which interface is active; this component only samples that interface's
// kernel byte counters and never performs network-management actions.
Item {
    id: root

    // BarWindow routes this request to the shared NetworkPanel. Keeping the
    // event at component level lets the same traffic readout be reused in a
    // future control centre without owning any popup or anchor geometry.
    signal panelToggleRequested()

    property bool _samplePending: false
    property int _sampleGeneration: 0
    property string sampledDevice: ""
    property real _previousRx: -1
    property real _previousTx: -1
    property double _previousTimestamp: 0
    property real downloadBytesPerSecond: 0
    property real uploadBytesPerSecond: 0

    implicitWidth: trafficContent.implicitWidth
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight
    visible: NetworkService.available && NetworkService.deviceState === "connected"

    function formatRate(bytesPerSecond) {
        const value = Math.max(0, Number(bytesPerSecond) || 0)
        if (value < 1024)
            return value.toFixed(2) + " B/s"
        if (value < 1024 * 1024)
            return (value / 1024).toFixed(2) + " KB/s"
        if (value < 1024 * 1024 * 1024)
            return (value / (1024 * 1024)).toFixed(2) + " MB/s"
        return (value / (1024 * 1024 * 1024)).toFixed(2) + " GB/s"
    }

    function reset(device) {
        sampledDevice = device || ""
        _previousRx = -1
        _previousTx = -1
        _previousTimestamp = 0
        downloadBytesPerSecond = 0
        uploadBytesPerSecond = 0
        _samplePending = false
        _sampleGeneration++
    }

    function sample() {
        const device = NetworkService.deviceName
        if (!visible || !device) {
            reset("")
            return
        }
        if (sampledDevice !== device)
            reset(device)
        if (_samplePending)
            return
        _samplePending = true
        const generation = _sampleGeneration
        PlatformClient.request("network.traffic", { device: device }, function(response) {
            if (generation !== root._sampleGeneration
                    || root.sampledDevice !== device) {
                return
            }
            root._samplePending = false
            const result = response?.ok ? response.result || ({}) : ({})
            const rx = Number(result.rxBytes)
            const tx = Number(result.txBytes)
            const now = Date.now()
            if (response?.ok
                    && Number.isFinite(rx) && Number.isFinite(tx)) {
                if (root._previousTimestamp > 0 && rx >= root._previousRx
                        && tx >= root._previousTx) {
                    const seconds = Math.max(0.25,
                        (now - root._previousTimestamp) / 1000)
                    root.downloadBytesPerSecond = (rx - root._previousRx) / seconds
                    root.uploadBytesPerSecond = (tx - root._previousTx) / seconds
                }
                root._previousRx = rx
                root._previousTx = tx
                root._previousTimestamp = now
            }
        })
    }

    Row {
        id: trafficContent
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        // Draw arrows ourselves so their white foreground is as dependable as
        // NetworkStatus on transparent glass, independent of icon themes.
        Canvas {
            id: directionGlyph
            width: 13
            height: 18
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "white"
                ctx.lineWidth = 1.35
                ctx.lineCap = "round"
                ctx.beginPath()
                // Keep the opposing arrows offset: together they read as one
                // compact traffic glyph, rather than two independent controls.
                // The adjacent labels explicitly identify the two data rows.
                // Download arrow.
                ctx.moveTo(3.5, 2.5); ctx.lineTo(3.5, 7.5)
                ctx.moveTo(1.4, 5.5); ctx.lineTo(3.5, 7.7); ctx.lineTo(5.6, 5.5)
                // Upload arrow.
                ctx.moveTo(9.5, 15.5); ctx.lineTo(9.5, 10.5)
                ctx.moveTo(7.4, 12.5); ctx.lineTo(9.5, 10.3); ctx.lineTo(11.6, 12.5)
                ctx.stroke()
            }
        }

        Column {
            spacing: -1
            Text {
                text: "下行 " + root.formatRate(root.downloadBytesPerSecond)
                color: ThemeService.foregroundColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.38)
                font { family: "SF Pro Display"; pixelSize: 9; weight: Font.DemiBold }
            }
            Text {
                text: "上行 " + root.formatRate(root.uploadBytesPerSecond)
                color: ThemeService.foregroundColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.38)
                font { family: "SF Pro Display"; pixelSize: 9; weight: Font.DemiBold }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }

    Connections {
        target: NetworkService
        function onDeviceNameChanged() { root.reset(NetworkService.deviceName) }
        function onDeviceStateChanged() {
            if (NetworkService.deviceState !== "connected")
                root.reset("")
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
