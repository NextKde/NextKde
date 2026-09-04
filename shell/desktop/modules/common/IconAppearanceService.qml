pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell-wide icon appearance. Application icons, launcher results, Bar icons
// and future desktop widgets share this contract; it is not Dock state.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/appearance"
    readonly property string configPath: configDir + "/icon-appearance.json"
    readonly property string legacyConfigPath: Quickshell.stateDir + "/dock/config.json"
    property string mode: "color" // "color" | "grayscale" | "tint"
    property real opacity: 0.5
    property color tintColor: "#a855f7"
    readonly property real saturation: mode === "color" ? 1.0 : 0.0
    readonly property real tintEnabled: mode === "tint" ? 1.0 : 0.0
    readonly property bool monochrome: mode !== "color"
    property bool ready: false

    function isValidMode(value) { return value === "color" || value === "grayscale" || value === "tint" }
    function isValidColor(value) { return /^#[0-9a-f]{6}$/.test(String(value).toLowerCase()) }
    function normalizedOpacity(value) {
        const number = Number(value)
        return Number.isFinite(number) ? Math.max(0.1, Math.min(1.0, number)) : NaN
    }
    function updateMode(value) {
        const next = String(value)
        if (!isValidMode(next) || mode === next) return false
        mode = next; saveTimer.restart(); return true
    }
    function updateOpacity(value) {
        const next = normalizedOpacity(value)
        if (!Number.isFinite(next) || Math.abs(opacity - next) <= 0.001) return false
        opacity = next; saveTimer.restart(); return true
    }
    function updateTintColor(value) {
        const next = String(value).toLowerCase()
        if (!isValidColor(next) || tintColor.toString().toLowerCase() === next) return false
        tintColor = next; saveTimer.restart(); return true
    }
    function styledColor(source) {
        if (mode === "color") return source
        const luminance = source.r * 0.299 + source.g * 0.587 + source.b * 0.114
        if (mode === "grayscale") return Qt.rgba(luminance, luminance, luminance, source.a)
        return Qt.rgba((tintColor.r + (1 - tintColor.r) * luminance) * luminance,
            (tintColor.g + (1 - tintColor.g) * luminance) * luminance,
            (tintColor.b + (1 - tintColor.b) * luminance) * luminance, source.a)
    }
    function styledSymbolicColor() {
        return mode === "tint" ? styledColor(Qt.rgba(0.72, 0.72, 0.72, 1)) : Qt.rgba(1, 1, 1, 1)
    }
    // Desktop widget content stays monochrome in both grayscale and tint
    // modes. Tint is reserved for the WidgetGlassMaterial background; Canvas,
    // images, and QML text do not all enter an ancestor shader consistently.
    function glassContentColor(alpha) {
        const opacity = alpha === undefined ? 1.0 : alpha
        return Qt.rgba(1, 1, 1, opacity)
    }

    property Timer saveTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: service.save()
    }
    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }
    function save() {
        const payload = JSON.stringify({ version: 1, mode, opacity, tintColor: tintColor.toString() }, null, 2)
        const process = processFactory.createObject(service, { command: ["sh", "-c",
            "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/icon-appearance.json.tmp\" && mv \"$1/icon-appearance.json.tmp\" \"$1/icon-appearance.json\"",
            "icon-appearance-save", configDir, payload] })
        process.running = true
        process.exited.connect(function(code) { if (code !== 0) console.warn("[IconAppearance] save failed: " + code); process.destroy() })
    }
    function load() {
        const process = processFactory.createObject(service, { command: ["sh", "-c",
            "if [ -f \"$1\" ]; then cat \"$1\"; elif [ -f \"$2\" ]; then cat \"$2\"; fi",
            "icon-appearance-load", configPath, legacyConfigPath] })
        process.exited.connect(function(code) {
            if (code === 0 && process.stdout?.text) {
                try {
                    const object = JSON.parse(process.stdout.text)
                    const legacyMode = object.iconMode === "duotone" ? "tint" : object.iconMode
                    const loadedMode = object.mode ?? legacyMode
                    if (isValidMode(loadedMode)) mode = loadedMode
                    const loadedOpacity = normalizedOpacity(object.opacity ?? object.iconOpacity)
                    if (Number.isFinite(loadedOpacity)) opacity = loadedOpacity
                    const loadedTint = String(object.tintColor ?? object.iconTintColor ?? "").toLowerCase()
                    if (isValidColor(loadedTint)) tintColor = loadedTint
                } catch (error) { console.warn("[IconAppearance] parse error: " + error) }
            }
            ready = true; process.destroy()
        })
        process.running = true
    }
    Component.onCompleted: load()
}
