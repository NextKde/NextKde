import QtQuick
import Quickshell.Io
import qs.desktop.modules.bar
import qs.desktop.modules.dock

// Live transfer-rate companion for NetworkStatus. NetworkService decides
// which interface is active; this component only samples that interface's
// kernel byte counters and never performs network-management actions.
Item {
    id: root

    // BarWindow routes this request to the shared NetworkPanel. Keeping the
    // event at component level lets the same traffic readout be reused in a
    // future control centre without owning any popup or anchor geometry.
    signal panelToggleRequested()

    property var _sampleProcess: null
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
    }

    function sample() {
        const device = NetworkService.deviceName
        if (!visible || !device) {
            reset("")
            return
        }
        if (sampledDevice !== device)
            reset(device)
        if (_sampleProcess)
            return

        // Interface names are passed positionally. The shell never expands a
        // NetworkManager-provided device name into code or a file path.
        const proc = processFactory.createObject(root, {
            command: ["sh", "-c",
                "cat \"/sys/class/net/$1/statistics/rx_bytes\" "
                + "\"/sys/class/net/$1/statistics/tx_bytes\" 2>/dev/null",
                "network-traffic-sample", device]
        })
        _sampleProcess = proc
        proc.exited.connect(function(code) {
            if (root._sampleProcess === proc)
                root._sampleProcess = null
            const fields = (proc.stdout?.text ?? "").trim().split(/\s+/)
            const rx = Number(fields[0])
            const tx = Number(fields[1])
            const now = Date.now()
            if (code === 0 && root.sampledDevice === device
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
            proc.destroy()
        })
        proc.running = true
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

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
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
