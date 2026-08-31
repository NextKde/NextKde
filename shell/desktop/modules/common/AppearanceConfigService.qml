pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Global appearance settings shared by shell surfaces. Keep these values out
// of DockConfigService: glass material is a shell-wide concern, while pinned
// items, Dock geometry and visibility remain Dock-owned state.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/appearance"
    readonly property string configPath: configDir + "/config.json"

    // KWin owns one glass pipeline. Surface-specific overrides cannot map
    // reliably to its compositor parameters, so every shell surface shares
    // this one global configuration.
    property real globalBlurStrength: 0.42
    property real globalLiquidStrength: 1.0

    property real blurStrength: globalBlurStrength
    property real liquidStrength: globalLiquidStrength

    // Retain descriptive names at call sites; they intentionally resolve to
    // the one global KWin glass configuration.
    readonly property real effectiveDockBlur: globalBlurStrength
    readonly property real effectiveDockLiquid: globalLiquidStrength
    readonly property real effectiveBarBlur: globalBlurStrength
    readonly property real effectiveBarLiquid: globalLiquidStrength
    readonly property real effectiveLauncherBlur: globalBlurStrength
    readonly property real effectiveLauncherLiquid: globalLiquidStrength

    // "macos" matches the shell geometry that predates selectable styles,
    // so upgrading an existing installation does not unexpectedly reshape it.
    property string shellStyle: "macos"
    property bool barIntegratedWithDock: false
    property string barVisibilityMode: "always" // "always" | "smart" | "persistent"
    property string barLayoutMode: "full" // "full" | "floating"
    property string dockWindowAnimationStyle: "scale"
    property bool ready: false

    function isValidShellStyle(value) {
        return value === "windows12" || value === "macos"
            || value === "material"
    }

    function isValidBarVisibilityMode(value) {
        return value === "always" || value === "smart"
            || value === "persistent"
    }

    function isValidBarLayoutMode(value) {
        return value === "full" || value === "floating"
    }

    function isValidDockWindowAnimationStyle(value) {
        return value === "scale" || value === "genie"
    }

    function _normalized(value) {
        const number = Number(value)
        return Number.isFinite(number)
            ? Math.max(0.0, Math.min(1.0, number)) : NaN
    }

    function _toBool(value) {
        return value === true || value === 1
            || String(value).toLowerCase() === "true"
    }

    function updateGlobalBlurStrength(rawValue) {
        const value = _normalized(rawValue)
        if (!Number.isFinite(value)
                || Math.abs(globalBlurStrength - value) <= 0.001)
            return false
        globalBlurStrength = value
        blurStrength = value
        saveTimer.restart()
        effectSyncTimer.restart()
        return true
    }

    function updateGlobalLiquidStrength(rawValue) {
        const value = _normalized(rawValue)
        if (!Number.isFinite(value)
                || Math.abs(globalLiquidStrength - value) <= 0.001)
            return false
        globalLiquidStrength = value
        liquidStrength = value
        saveTimer.restart()
        effectSyncTimer.restart()
        return true
    }

    // Backward compatibility aliases
    function updateBlurStrength(rawValue) {
        return updateGlobalBlurStrength(rawValue)
    }

    function updateLiquidStrength(rawValue) {
        return updateGlobalLiquidStrength(rawValue)
    }

    function updateShellStyle(rawStyle) {
        const style = String(rawStyle)
        if (!isValidShellStyle(style) || shellStyle === style)
            return false
        shellStyle = style
        saveTimer.restart()
        return true
    }

    function updateBarIntegratedWithDock(rawValue) {
        const value = _toBool(rawValue)
        if (barIntegratedWithDock === value)
            return false
        barIntegratedWithDock = value
        saveTimer.restart()
        return true
    }

    function updateBarVisibilityMode(rawMode) {
        const mode = String(rawMode)
        if (!isValidBarVisibilityMode(mode) || barVisibilityMode === mode)
            return false
        barVisibilityMode = mode
        saveTimer.restart()
        return true
    }

    function updateBarLayoutMode(rawMode) {
        const mode = String(rawMode)
        if (!isValidBarLayoutMode(mode) || barLayoutMode === mode)
            return false
        barLayoutMode = mode
        saveTimer.restart()
        return true
    }

    function updateDockWindowAnimationStyle(rawStyle) {
        const style = String(rawStyle)
        if (!isValidDockWindowAnimationStyle(style)
                || dockWindowAnimationStyle === style)
            return false
        dockWindowAnimationStyle = style
        saveTimer.restart()
        dockAnimationEffectSyncTimer.restart()
        return true
    }

    function resetStrengths() {
        const globalBlurChanged = Math.abs(globalBlurStrength - 0.42) > 0.001
        const globalLiquidChanged = Math.abs(globalLiquidStrength - 1.0) > 0.001

        globalBlurStrength = 0.42
        globalLiquidStrength = 1.0
        blurStrength = 0.42
        liquidStrength = 1.0

        const changed = globalBlurChanged || globalLiquidChanged

        if (changed) {
            saveTimer.restart()
            effectSyncTimer.restart()
        }
        return changed
    }

    property Timer saveTimer: Timer {
        interval: 350
        repeat: false
        onTriggered: service._save()
    }

    // The compositor plugin owns the real backdrop blur/refraction for Dock
    // and other BackgroundEffect regions. Quickshell can publish the region,
    // but Wayland exposes no per-surface strength field, so synchronize the
    // two user-facing values with the custom Glass effect's own settings.
    // This deliberately does not touch KDE's stock [Effect-blur] group.
    property Timer effectSyncTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: service._syncGlassEffect()
    }

    property Timer dockAnimationEffectSyncTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: service._syncDockWindowAnimationEffect()
    }

    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
    }

    function _makeProcess(command) {
        try {
            return processFactory.createObject(service, { command })
        } catch (error) {
            console.warn("[AppearanceConfig] cannot create process: " + error)
        }
        return null
    }

    function _save() {
        const payload = JSON.stringify({
            version: 8,
            globalBlurStrength: service.globalBlurStrength,
            globalLiquidStrength: service.globalLiquidStrength,
            blurStrength: service.globalBlurStrength,
            liquidStrength: service.globalLiquidStrength,
            shellStyle: service.shellStyle,
            barIntegratedWithDock: service.barIntegratedWithDock,
            barVisibilityMode: service.barVisibilityMode,
            barLayoutMode: service.barLayoutMode,
            dockWindowAnimationStyle: service.dockWindowAnimationStyle,
        }, null, 2)
        const process = _makeProcess([
            "sh", "-c",
            "mkdir -p \"$1\" && printf %s \"$2\" > \"$1/config.json.tmp\" && mv \"$1/config.json.tmp\" \"$1/config.json\"",
            "appearance-config-save",
            service.configDir,
            payload,
        ])
        if (!process)
            return
        process.exited.connect(function(code) {
            if (code !== 0) {
                console.warn("[AppearanceConfig] save failed code=" + code
                    + " stderr=" + (process.stderr?.text ?? ""))
            }
        })
        process.running = true
    }

    function _syncGlassEffect() {
        const dockBlurLevel = Math.round(1 + service.globalBlurStrength * 14)
        const contentBlurLevel = Math.round(1 + service.globalBlurStrength * 14)
        const refractionLevel = Math.round(service.globalLiquidStrength * 20)
        const process = _makeProcess([
            "sh", "-c",
            "kwriteconfig6 --file kwinrc --group Effect-blurplus --key BlurStrength \"$1\" && "
                + "kwriteconfig6 --file kwinrc --group Effect-blurplus --key DockBlurStrength \"$2\" && "
                + "kwriteconfig6 --file kwinrc --group Effect-blurplus --key RefractionStrength \"$3\" && "
                + "kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength \"$1\" && "
                + "if [ \"$(qdbus6 org.kde.KWin /Effects org.kde.KWin.Effects.isEffectLoaded glass 2>/dev/null)\" != \"true\" ]; then "
                + "  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect blur 2>/dev/null; "
                + "  qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass 2>/dev/null; "
                + "fi; "
                + "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect glass 2>/dev/null || "
                + "qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect blur 2>/dev/null",
            "appearance-glass-sync",
            String(contentBlurLevel),
            String(dockBlurLevel),
            String(refractionLevel),
        ])
        if (!process)
            return
        process.exited.connect(function(code) {
            if (code !== 0) {
                console.warn("[AppearanceConfig] Glass effect sync failed code="
                    + code + " stderr=" + (process.stderr?.text ?? ""))
            } else {
                console.log("[AppearanceConfig] Glass effect dockBlur=" + dockBlurLevel
                    + " contentBlur=" + contentBlurLevel + " liquid=" + refractionLevel)
            }
            process.destroy()
        })
        process.running = true
    }

    function _syncDockWindowAnimationEffect() {
        const process = _makeProcess([
            "sh", "-c",
            "kwriteconfig6 --file kwinrc --group Effect-kos_dock_window_animation "
                + "--key AnimationStyle \"$1\" && "
                + "qdbus6 org.kde.KWin /Effects "
                + "org.kde.kwin.Effects.reconfigureEffect kos_dock_window_animation",
            "appearance-dock-animation-sync",
            service.dockWindowAnimationStyle,
        ])
        if (!process)
            return
        process.exited.connect(function(code) {
            if (code !== 0) {
                console.warn("[AppearanceConfig] Dock animation sync failed code="
                    + code + " stderr=" + (process.stderr?.text ?? ""))
            } else {
                console.log("[AppearanceConfig] Dock window animation="
                    + service.dockWindowAnimationStyle)
            }
            process.destroy()
        })
        process.running = true
    }

    function _load() {
        const process = _makeProcess([
            "sh", "-c", "cat \"$1\"", "appearance-config-load",
            service.configPath,
        ])
        if (!process) {
            ready = true
            return
        }
        process.exited.connect(function(code) {
            if (code === 0 && process.stdout?.text) {
                try {
                    const object = JSON.parse(process.stdout.text)
                    // Old v7 files may have a Dock value but never a global
                    // one. Read it once as the global migration source, then
                    // save the flattened v8 shape below.
                    const globalBlur = service._normalized(object.globalBlurStrength
                        ?? object.blurStrength ?? object.dockBlurStrength)
                    const globalLiquid = service._normalized(object.globalLiquidStrength
                        ?? object.liquidStrength ?? object.dockLiquidStrength)
                    const style = String(object.shellStyle ?? "")
                    const hasBarIntegration = typeof object.barIntegratedWithDock === "boolean"
                    const barVisibility = String(object.barVisibilityMode ?? "")
                    const barLayout = String(object.barLayoutMode ?? "")
                    const animationStyle = String(object.dockWindowAnimationStyle ?? "")

                    if (Number.isFinite(globalBlur)) {
                        service.globalBlurStrength = globalBlur
                        service.blurStrength = globalBlur
                    }
                    if (Number.isFinite(globalLiquid)) {
                        service.globalLiquidStrength = globalLiquid
                        service.liquidStrength = globalLiquid
                    }
                    if (service.isValidShellStyle(style))
                        service.shellStyle = style
                    if (hasBarIntegration)
                        service.barIntegratedWithDock = object.barIntegratedWithDock
                    if (service.isValidBarVisibilityMode(barVisibility))
                        service.barVisibilityMode = barVisibility
                    if (service.isValidBarLayoutMode(barLayout))
                        service.barLayoutMode = barLayout
                    if (service.isValidDockWindowAnimationStyle(animationStyle))
                        service.dockWindowAnimationStyle = animationStyle

                    if (Number(object.version) !== 8
                            || !service.isValidShellStyle(style)
                            || !hasBarIntegration
                            || !service.isValidBarVisibilityMode(barVisibility)
                            || !service.isValidBarLayoutMode(barLayout)
                            || !service.isValidDockWindowAnimationStyle(animationStyle))
                        service.saveTimer.restart()
                } catch (error) {
                    console.warn("[AppearanceConfig] parse error: " + error)
                }
            }
            service.ready = true
            service.effectSyncTimer.restart()
            service.dockAnimationEffectSyncTimer.restart()
            process.destroy()
        })
        process.running = true
    }

    Component.onCompleted: _load()
}
