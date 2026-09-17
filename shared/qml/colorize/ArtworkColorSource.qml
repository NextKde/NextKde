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
        if (!sourceText) {
            quantizerSource = ""
            primary = fallbackPrimary
            secondary = fallbackSecondary
            return
        }
        // Bundled artwork is an inline data URI (the default cover lives in
        // BundledIcons). ColorQuantizer opens its source through QFile, so a
        // data URI never loads: it logs "Failed to load image" and reports zero
        // colours. Decode it into the same cache the remote path uses, then
        // quantize that file.
        if (sourceText.startsWith("data:")) {
            const comma = sourceText.indexOf(",")
            const base64 = comma > 0
                && sourceText.slice(0, comma).includes(";base64")
            if (!base64) {
                // A percent-encoded inline SVG carries no usable palette.
                quantizerSource = ""
                primary = fallbackPrimary
                secondary = fallbackSecondary
                return
            }
            _cacheAndQuantize(sourceText, sourceText.slice(comma + 1),
                "printf '%s' \"$3\" | base64 -d > \"$2.$$.tmp\"")
            return
        }
        if (!/^https?:\/\//i.test(sourceText)) {
            // ColorQuantizer accepts URL sources. Plasma stores local
            // wallpapers as bare absolute paths, so normalize only paths that
            // do not already carry a URL scheme (file:, image:, qrc:, ...).
            const hasScheme = /^[a-z][a-z0-9+.-]*:/i.test(sourceText)
            quantizerSource = hasScheme ? source : "file://" + sourceText
            return
        }
        _cacheAndQuantize(sourceText, sourceText,
            "curl --fail --location --silent --show-error --max-time 15 --output \"$2.$$.tmp\" \"$3\"")
    }

    // Materializes artwork that is not a local file (remote URL, inline data
    // URI) into the palette cache once, then points the quantizer at that file.
    // `payload` is what the fetch command reads as $3; `expectedSource` guards
    // against a slow fetch landing after the artwork already changed.
    function _cacheAndQuantize(expectedSource, payload, fetchCommand) {
        const cachePath = cacheDirectory + "/" + _cacheName(expectedSource)
        quantizerSource = ""
        const process = processFactory.createObject(root, {
            command: ["sh", "-c",
                "mkdir -p \"$1\" && if [ ! -s \"$2\" ]; then " + fetchCommand
                    + " && mv \"$2.$$.tmp\" \"$2\"; fi",
                "artwork-palette-cache", cacheDirectory, cachePath, payload]
        })
        _downloadProcess = process
        process.exited.connect(function(exitCode) {
            if (root._downloadProcess === process)
                root._downloadProcess = null
            if (exitCode === 0 && root.source.toString() === expectedSource)
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
