import QtQuick
import Quickshell
import Quickshell.Io

// Selects two distinct colours from Quickshell's asynchronous image
// quantizer. It works for both MPRIS artwork and local wallpaper files.
Item {
    id: root

    property url source: ""
    readonly property color fallbackPrimary: Qt.rgba(0.16, 0.20, 0.28, 1)
    readonly property color fallbackSecondary: Qt.rgba(0.30, 0.16, 0.30, 1)
    property color primary: fallbackPrimary
    property color secondary: fallbackSecondary
    property bool ready: false
    property url quantizerSource: ""
    property var _downloadProcess: null
    readonly property string cacheDirectory: Quickshell.stateDir + "/artwork-palette"
    // Consumers that already animate their own material can set this to 0 so
    // there is one deliberate colour transition rather than two retargeting
    // animations chasing one another.
    property int transitionDuration: 760

    Behavior on primary {
        enabled: root.transitionDuration > 0
        ColorAnimation { duration: root.transitionDuration; easing.type: Easing.InOutCubic }
    }
    Behavior on secondary {
        enabled: root.transitionDuration > 0
        ColorAnimation { duration: root.transitionDuration; easing.type: Easing.InOutCubic }
    }

    function _distance(left, right) {
        return Math.abs(left.r - right.r)
            + Math.abs(left.g - right.g)
            + Math.abs(left.b - right.b)
    }

    function _apply(colors) {
        const usable = colors.filter(color => {
            const brightest = Math.max(color.r, color.g, color.b)
            const darkest = Math.min(color.r, color.g, color.b)
            return brightest > 0.16 && darkest < 0.90 && brightest - darkest > 0.10
        })
        if (usable.length === 0) {
            primary = fallbackPrimary
            secondary = fallbackSecondary
            ready = false
            return
        }

        primary = usable[0]
        secondary = usable.find(color => _distance(color, primary) > 0.28)
            || Qt.rgba(
                Math.min(1, primary.r * 0.70 + 0.12),
                Math.min(1, primary.g * 0.70 + 0.07),
                Math.min(1, primary.b * 0.78 + 0.18),
                1
            )
        ready = true
    }

    function _cacheName(url) {
        const text = url.toString()
        let hash = 2166136261
        for (let index = 0; index < text.length; ++index) {
            hash ^= text.charCodeAt(index)
            hash = Math.imul(hash, 16777619)
        }
        return (hash >>> 0).toString(16) + ".img"
    }

    function _refreshQuantizerSource() {
        ready = false
        const sourceText = source.toString()
        const remote = sourceText.match(/^https?:\/\//i)
        if (!sourceText) {
            quantizerSource = ""
            primary = fallbackPrimary
            secondary = fallbackSecondary
            return
        }
        if (!remote) {
            // ColorQuantizer accepts URL sources. Plasma stores local
            // wallpapers as bare absolute paths, so normalize only paths that
            // do not already carry a URL scheme (file:, image:, qrc:, ...).
            const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(sourceText)
            quantizerSource = hasScheme ? source : "file://" + sourceText
            return
        }
        const requestedSource = source.toString()
        const cachePath = cacheDirectory + "/" + _cacheName(requestedSource)
        quantizerSource = ""
        const process = processFactory.createObject(root, {
            command: ["sh", "-c",
                "mkdir -p \"$1\" && if [ ! -s \"$2\" ]; then curl --fail --location --silent --show-error --max-time 15 --output \"$2.$$.tmp\" \"$3\" && mv \"$2.$$.tmp\" \"$2\"; fi",
                "artwork-palette-cache", cacheDirectory, cachePath, requestedSource]
        })
        _downloadProcess = process
        process.exited.connect(function(exitCode) {
            if (root._downloadProcess === process)
                root._downloadProcess = null
            if (exitCode === 0 && root.source.toString() === requestedSource)
                root.quantizerSource = "file://" + cachePath
            process.destroy()
        })
        process.running = true
    }

    onSourceChanged: _refreshQuantizerSource()
    Component.onCompleted: _refreshQuantizerSource()

    ColorQuantizer {
        id: quantizer
        source: root.quantizerSource
        depth: 8
        rescaleSize: 48
        onColorsChanged: root._apply(colors)
    }
    property Component processFactory: Component { Process { stderr: StdioCollector {} } }
}
