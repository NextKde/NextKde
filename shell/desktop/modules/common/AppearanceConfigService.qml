pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.platform

// Global appearance settings shared by shell surfaces. Keep these values out
// of DockConfigService: glass material is a shell-wide concern, while pinned
// items, Dock geometry and visibility remain Dock-owned state.
QtObject {
    id: service

    readonly property string configDir: Quickshell.stateDir + "/appearance"
    readonly property string configPath: configDir + "/config.json"

    // KWin owns one glass pipeline, so every shell surface shares the active
    // material's values. The values themselves still belong to a preset.
    property real globalBlurStrength: 0.0
    property real globalLiquidStrength: 1.0
    // Material Design has no liquid preset. Its blur is independent so moving
    // the Material slider never overwrites the selected glass style.
    property real materialPresetBlurStrength: 0.10

    // Every style is a preset over the same compositor material. Keeping the
    // values flattened makes user-tuned presets easy to persist and migrate.
    property string glassStyle: "liquid" // "liquid" | "soft" | "frosted"
    // Liquid glass deliberately favors refraction over frosting.
    property real liquidPresetBlurStrength: 0.0
    property real liquidPresetLiquidStrength: 1.0
    property real softPresetBlurStrength: 0.10
    property real softPresetLiquidStrength: 0.5
    property real frostedPresetBlurStrength: 1.0
    property real frostedPresetLiquidStrength: 0.5
    // The liquid preset is the set tuned on screen on 2026-09-16. Switching the
    // material style away and back restores exactly these values, and so does
    // resetGlassPreset("liquid").
    //
    // RefractionEdgeSize reaches the shader as device pixels: it is compared
    // straight against the shape's SDF distance there. Main multiplied this same
    // kwinrc key by ten before use, so the 1.8 that used to be written here is a
    // sub-pixel hairline -- the edge lens and everything gated by it (the bevel,
    // the glints) vanish. The tuned value sits at the top of the KCM/debug range.
    property real liquidPresetRefraction: 1.0
    property real liquidPresetEdgeSize: 50.0
    property real liquidPresetNormalPow: 5.0
    property real liquidPresetRGBFringing: 0.0
    property real liquidPresetOffsetStrength: 0.0
    property real liquidPresetSoftness: 0.0
    property real liquidPresetReflection: 0.0
    // Soft glass avoids the embossed look of a broad, directional reflection:
    // keep only a restrained lens and let high softness carry the material.
    property real softPresetRefraction: 0.28
    property real softPresetEdgeSize: 18.0
    property real softPresetNormalPow: 4.0
    property real softPresetRGBFringing: 0.0
    // Soft glass does not shift the backdrop body. That 40 px body lens is the
    // raised/embossed band; softness comes only from the inward edge glow.
    property real softPresetOffsetStrength: 0.0
    property real softPresetSoftness: 0.65
    property real softPresetReflection: 0.0
    // 磨砂玻璃: a diffuse sheet with no lens. Refraction at zero is what makes it
    // that, and it is not a token value: the shader skips its refraction sample
    // entirely when refractionStrength is zero, so the backdrop reaches the
    // surface pixel-identical and nothing is bent or split. Offset strength,
    // bevel and fringing sit at zero too, so raising 折射强度 later (the debug
    // page's own row) still cannot bend the body or add a bevel ring on its own.
    // That leaves the diffuse sheen as the whole material: 柔和度 is pushed to
    // its maximum for the milky wash, 宽反射强度 keeps a broad, soft edge glow,
    // and 折射边缘范围 is the width of that glow -- with no lens left to size, it
    // sizes the sheen instead. Hard glints are off: they are the liquid lens's
    // specular, and their strength is gated on refraction anyway, so 窄高光强度
    // and 高光宽度 do nothing here until 折射强度 is raised.
    //
    // How frosted the result looks is mostly this preset's blur strength.
    property real frostedPresetRefraction: 0.0
    property real frostedPresetEdgeSize: 24.0
    property real frostedPresetNormalPow: 4.0
    property real frostedPresetRGBFringing: 0.0
    property real frostedPresetOffsetStrength: 0.0
    property real frostedPresetSoftness: 1.0
    property real frostedPresetReflection: 0.3

    // One resolution point for "the preset in force". Spelled out per field
    // rather than looked up by name: these are read from a binding by the effect
    // sync and the settings snapshot, and a dynamic lookup would leave the QML
    // compiler unable to see what the binding depends on.
    readonly property real activePresetRefraction: glassStyle === "frosted"
        ? frostedPresetRefraction : glassStyle === "soft" ? softPresetRefraction
        : liquidPresetRefraction
    readonly property real activePresetSoftness: glassStyle === "frosted"
        ? frostedPresetSoftness : glassStyle === "soft" ? softPresetSoftness
        : liquidPresetSoftness
    readonly property real activePresetEdgeSize: glassStyle === "frosted"
        ? frostedPresetEdgeSize : glassStyle === "soft" ? softPresetEdgeSize
        : liquidPresetEdgeSize
    readonly property real activePresetNormalPow: glassStyle === "frosted"
        ? frostedPresetNormalPow : glassStyle === "soft" ? softPresetNormalPow
        : liquidPresetNormalPow
    readonly property real activePresetRGBFringing: glassStyle === "frosted"
        ? frostedPresetRGBFringing : glassStyle === "soft" ? softPresetRGBFringing
        : liquidPresetRGBFringing
    readonly property real activePresetOffsetStrength: glassStyle === "frosted"
        ? frostedPresetOffsetStrength : glassStyle === "soft" ? softPresetOffsetStrength
        : liquidPresetOffsetStrength
    readonly property real activePresetReflection: glassStyle === "frosted"
        ? frostedPresetReflection : glassStyle === "soft" ? softPresetReflection
        : liquidPresetReflection
    readonly property real activePresetBlurStrength: glassStyle === "frosted"
        ? frostedPresetBlurStrength : glassStyle === "soft" ? softPresetBlurStrength
        : liquidPresetBlurStrength
    readonly property real activePresetLiquidStrength: glassStyle === "frosted"
        ? frostedPresetLiquidStrength : glassStyle === "soft" ? softPresetLiquidStrength
        : liquidPresetLiquidStrength

    // Which set updateGlassPresetParameter() and resetGlassPreset() write.
    readonly property string presetPrefix: glassStyle === "frosted" ? "frostedPreset"
        : glassStyle === "soft" ? "softPreset" : "liquidPreset"

    property real blurStrength: globalBlurStrength
    property real liquidStrength: globalLiquidStrength

    // Material Design reuses KWin's backdrop-blur pass but deliberately never
    // enables its liquid/refraction pass.
    readonly property real effectiveDockBlur: globalBlurStrength
    readonly property real effectiveDockLiquid: shellStyle === "material"
        ? 0.0 : globalLiquidStrength
    readonly property real effectiveBarBlur: globalBlurStrength
    readonly property real effectiveBarLiquid: shellStyle === "material"
        ? 0.0 : globalLiquidStrength
    readonly property real effectiveLauncherBlur: globalBlurStrength
    readonly property real effectiveLauncherLiquid: shellStyle === "material"
        ? 0.0 : globalLiquidStrength

    // "macos" matches the shell geometry that predates selectable styles,
    // so upgrading an existing installation does not unexpectedly reshape it.
    property string shellStyle: "macos"
    // Global colour-scheme preference shared by every shell style. The Dock
    // settings page historically persisted this value in DockConfigService;
    // that service mirrors the legacy value here during migration.
    property string themeMode: "system" // "system" | "light" | "dark"
    // AppearanceTokens' wallpaper bridge persists this once the shared
    // WallpaperColorSource reports a sampled seed; AppearanceTokens falls back
    // to the KDE accent until then.
    property color wallpaperSeedColor: "transparent"
    // Whether the liquid glass's appearance (its adaptive contrast scrim and
    // depth) follows the resolved light/dark palette. Persisted here; the
    // rendering behaviour that consumes it is wired up independently.
    property bool glassFollowsAppearanceMode: false
    property bool barIntegratedWithDock: false
    property string barVisibilityMode: "always" // "always" | "smart" | "persistent"
    property string barLayoutMode: "transparent" // "full" | "floating" | "transparent"
    property string dockWindowAnimationStyle: "scale"
    property bool ready: false

    function isValidShellStyle(value) {
        return value === "windows12" || value === "macos"
            || value === "material"
    }

    function isValidThemeMode(value) {
        return value === "system" || value === "light" || value === "dark"
    }

    function isValidBarVisibilityMode(value) {
        return value === "always" || value === "smart"
            || value === "persistent"
    }

    function isValidBarLayoutMode(value) {
        return value === "full" || value === "floating" || value === "transparent"
    }

    function isValidDockWindowAnimationStyle(value) {
        return value === "scale" || value === "genie"
    }

    function isValidGlassStyle(value) {
        return value === "liquid" || value === "soft" || value === "frosted"
    }

    function _normalized(value) {
        const number = Number(value)
        return Number.isFinite(number)
            ? Math.max(0.0, Math.min(1.0, number)) : NaN
    }

    // Blur radius is perceived much more strongly in the lower half of the
    // compositor's 15-step range.  A perceptual response keeps the middle of
    // the settings slider clear and refractive, while preserving both end
    // points for users who explicitly want no blur or maximum frosting.
    // Public: per-component blur overrides (LiquidGlassPanel.blurStrength) map
    // through this same curve so a panel that follows the global value renders
    // identically whether it is overridden or not.
    function compositorBlurLevel(strength) {
        const value = _normalized(strength)
        return Number.isFinite(value)
            ? Math.round(1 + Math.pow(value, 1.5) * 14) : 1
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
        if (shellStyle === "material")
            materialPresetBlurStrength = value
        else
            service[service.presetPrefix + "BlurStrength"] = value
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
        service[service.presetPrefix + "LiquidStrength"] = value
        saveTimer.restart()
        effectSyncTimer.restart()
        return true
    }

    function updateGlassStyle(rawStyle) {
        const style = String(rawStyle)
        if (!isValidGlassStyle(style) || glassStyle === style)
            return false
        glassStyle = style
        // Style selection is deliberately a preset application, not a recall
        // of the last slider position. Every switch starts from the material's
        // authored blur/liquid and optical values.
        resetGlassPreset(style)
        return true
    }

    // The writable preset parameters, valued in preset units, bracketed by the
    // range the compositor clamps them into when it writes kwinrc (theme.sync-glass
    // in platform/src/daemon/PlatformServer.cpp). Two unit systems meet here:
    // Refraction is 0..1 and reaches kwinrc as RefractionStrength 0..20 through
    // `round(globalLiquidStrength * Refraction * 20)`; every other entry maps one
    // to one onto the kwinrc key of the same name.
    //
    // Parenthesised so QML reads this as an object literal and not a block.
    readonly property var presetParameterRanges: ({
        "Refraction": [0.0, 1.0],
        "EdgeSize": [0.0, 50.0],
        "NormalPow": [0.1, 10.0],
        "RGBFringing": [0.0, 20.0],
        "OffsetStrength": [0.0, 20.0],
        "Softness": [0.0, 1.0],
        "Reflection": [0.0, 1.0]
    })

    function updateGlassPresetParameter(rawName, rawValue) {
        const name = String(rawName)
        // Not `_normalized`: that helper clamps to 0..1, which is right for the
        // four unit-range fields and wrong for every optical one -- it would turn
        // a requested edge size of 50 into 1. The table below owns the range.
        const value = Number(rawValue)
        if (!Number.isFinite(value))
            return false
        const key = name.charAt(0).toUpperCase() + name.slice(1)
        const range = service.presetParameterRanges[key]
        if (!range)
            return false
        const clamped = Math.min(Math.max(value, range[0]), range[1])
        const propertyName = service.presetPrefix + key
        if (Math.abs(Number(service[propertyName]) - clamped) <= 0.001)
            return false
        service[propertyName] = clamped
        saveTimer.restart()
        effectSyncTimer.restart()
        return true
    }

    function resetGlassPreset(rawStyle) {
        const style = String(rawStyle)
        if (!isValidGlassStyle(style))
            return false
        if (style === "soft") {
            softPresetBlurStrength = 0.10
            softPresetLiquidStrength = 0.5
            softPresetRefraction = 0.28
            softPresetEdgeSize = 18.0
            softPresetNormalPow = 4.0
            softPresetRGBFringing = 0.0
            softPresetOffsetStrength = 0.0
            softPresetSoftness = 0.65
            softPresetReflection = 0.0
        } else if (style === "frosted") {
            // Must stay identical to the frostedPreset* defaults above.
            frostedPresetBlurStrength = 1.0
            frostedPresetLiquidStrength = 0.5
            frostedPresetRefraction = 0.0
            frostedPresetEdgeSize = 24.0
            frostedPresetNormalPow = 4.0
            frostedPresetRGBFringing = 0.0
            frostedPresetOffsetStrength = 0.0
            frostedPresetSoftness = 1.0
            frostedPresetReflection = 0.3
        } else {
            // Must stay identical to the liquidPreset* defaults above: both are
            // "the liquid preset", one for a fresh install and one for a reset.
            liquidPresetBlurStrength = 0.0
            liquidPresetLiquidStrength = 1.0
            liquidPresetRefraction = 1.0
            liquidPresetEdgeSize = 50.0
            liquidPresetNormalPow = 5.0
            liquidPresetRGBFringing = 0.0
            liquidPresetOffsetStrength = 0.0
            liquidPresetSoftness = 0.0
            liquidPresetReflection = 0.0
        }
        if (glassStyle === style) {
            globalBlurStrength = activePresetBlurStrength
            blurStrength = activePresetBlurStrength
            globalLiquidStrength = activePresetLiquidStrength
            liquidStrength = activePresetLiquidStrength
        }
        saveTimer.restart()
        if (glassStyle === style)
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
        if (shellStyle === "material") {
            // Material always enters at its authored 10% blur preset; a
            // previous Material slider adjustment is not carried across a
            // theme switch.
            materialPresetBlurStrength = 0.10
            globalBlurStrength = 0.10
            blurStrength = 0.10
        } else {
            // Returning to a glass shell applies (rather than restores) the
            // current material's complete fixed preset, including blur and
            // liquid strength.
            resetGlassPreset(glassStyle)
        }
        saveTimer.restart()
        effectSyncTimer.restart()
        return true
    }

    function updateThemeMode(rawMode) {
        const mode = String(rawMode)
        if (!isValidThemeMode(mode) || themeMode === mode)
            return false
        themeMode = mode
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

    function updateGlassFollowsAppearanceMode(rawValue) {
        const value = _toBool(rawValue)
        if (glassFollowsAppearanceMode === value)
            return false
        glassFollowsAppearanceMode = value
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

    // theme.sync-* are absolute-state writes, so they are not queued while
    // the daemon is down — re-push the desired effect configuration on every
    // reconnect or a change made mid-outage would silently never apply.
    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                service.effectSyncTimer.restart()
                service.dockAnimationEffectSyncTimer.restart()
            }
        }
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
            version: 26,
            globalBlurStrength: service.globalBlurStrength,
            globalLiquidStrength: service.globalLiquidStrength,
            materialPresetBlurStrength: service.materialPresetBlurStrength,
            glassStyle: service.glassStyle,
            liquidPresetBlurStrength: service.liquidPresetBlurStrength,
            liquidPresetLiquidStrength: service.liquidPresetLiquidStrength,
            softPresetBlurStrength: service.softPresetBlurStrength,
            softPresetLiquidStrength: service.softPresetLiquidStrength,
            frostedPresetBlurStrength: service.frostedPresetBlurStrength,
            frostedPresetLiquidStrength: service.frostedPresetLiquidStrength,
            liquidPresetRefraction: service.liquidPresetRefraction,
            liquidPresetEdgeSize: service.liquidPresetEdgeSize,
            liquidPresetNormalPow: service.liquidPresetNormalPow,
            liquidPresetRGBFringing: service.liquidPresetRGBFringing,
            liquidPresetOffsetStrength: service.liquidPresetOffsetStrength,
            liquidPresetSoftness: service.liquidPresetSoftness,
            liquidPresetReflection: service.liquidPresetReflection,
            softPresetRefraction: service.softPresetRefraction,
            softPresetEdgeSize: service.softPresetEdgeSize,
            softPresetNormalPow: service.softPresetNormalPow,
            softPresetRGBFringing: service.softPresetRGBFringing,
            softPresetOffsetStrength: service.softPresetOffsetStrength,
            softPresetSoftness: service.softPresetSoftness,
            softPresetReflection: service.softPresetReflection,
            frostedPresetRefraction: service.frostedPresetRefraction,
            frostedPresetEdgeSize: service.frostedPresetEdgeSize,
            frostedPresetNormalPow: service.frostedPresetNormalPow,
            frostedPresetRGBFringing: service.frostedPresetRGBFringing,
            frostedPresetOffsetStrength: service.frostedPresetOffsetStrength,
            frostedPresetSoftness: service.frostedPresetSoftness,
            frostedPresetReflection: service.frostedPresetReflection,
            blurStrength: service.globalBlurStrength,
            liquidStrength: service.globalLiquidStrength,
            shellStyle: service.shellStyle,
            themeMode: service.themeMode,
            glassFollowsAppearanceMode: service.glassFollowsAppearanceMode,
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
        const contentBlurLevel = service.compositorBlurLevel(
            service.globalBlurStrength)
        const materialBlurOnly = service.shellStyle === "material"
        const refractionLevel = materialBlurOnly ? 0
            : Math.round(service.globalLiquidStrength
                * service.activePresetRefraction * 20)
        PlatformClient.request("theme.sync-glass", {
            contentBlurLevel: contentBlurLevel,
            refractionLevel: refractionLevel,
            // Material Design uses this effect strictly as a backdrop-blur
            // provider. Reset every optical/glint channel as well as
            // refraction, otherwise values left by a liquid/soft preset still
            // give the blurred region a glass rim or reflected sheen.
            refractionEdgeSize: materialBlurOnly ? 0 : service.activePresetEdgeSize,
            refractionNormalPow: materialBlurOnly ? 0.1 : service.activePresetNormalPow,
            refractionRGBFringing: materialBlurOnly ? 0 : service.activePresetRGBFringing,
            refractionOffsetStrength: materialBlurOnly ? 0 : service.activePresetOffsetStrength,
            materialSoftness: materialBlurOnly ? 0 : service.activePresetSoftness,
            materialReflectionStrength: materialBlurOnly ? 0 : service.activePresetReflection,
            cornerExponent: AppearanceTokens.shape.cornerExponent,
        }, function(response) {
            if (!response?.ok)
                console.warn("[AppearanceConfig] Glass effect sync failed: "
                    + (response?.error?.message || "platform unavailable"))
            else {
                console.log("[AppearanceConfig] Glass effect blur=" + contentBlurLevel
                    + " liquid=" + refractionLevel
                    + " style=" + service.glassStyle
                    + " softness=" + service.activePresetSoftness
                    + " reflection=" + service.activePresetReflection
                    + " cornerExponent=" + AppearanceTokens.shape.cornerExponent)
            }
        })
    }

    function _syncDockWindowAnimationEffect() {
        PlatformClient.request("theme.sync-dock-animation", {
            style: service.dockWindowAnimationStyle,
        }, function(response) {
            if (!response?.ok)
                console.warn("[AppearanceConfig] Dock animation sync failed: "
                    + (response?.error?.message || "platform unavailable"))
            else {
                console.log("[AppearanceConfig] Dock window animation="
                    + service.dockWindowAnimationStyle)
            }
        })
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
                    const themeMode = String(object.themeMode ?? "")
                    const hasBarIntegration = typeof object.barIntegratedWithDock === "boolean"
                    const barVisibility = String(object.barVisibilityMode ?? "")
                    const barLayout = String(object.barLayoutMode ?? "")
                    const animationStyle = String(object.dockWindowAnimationStyle ?? "")
                    const glassStyle = String(object.glassStyle ?? "liquid")
                    const followsAppearance = object.glassFollowsAppearanceMode
                    const followsAppearanceLegacy = object.glassFollowsColorMode
                    const hasGlassFollows = typeof followsAppearance === "boolean"
                        || typeof followsAppearanceLegacy === "boolean"

                    if (Number.isFinite(globalBlur)) {
                        service.globalBlurStrength = globalBlur
                        service.blurStrength = globalBlur
                    }
                    if (Number.isFinite(globalLiquid)) {
                        service.globalLiquidStrength = globalLiquid
                        service.liquidStrength = globalLiquid
                    }
                    const materialBlur = service._normalized(
                        object.materialPresetBlurStrength)
                    if (Number.isFinite(materialBlur))
                        service.materialPresetBlurStrength = materialBlur
                    if (service.isValidShellStyle(style))
                        service.shellStyle = style
                    if (service.isValidThemeMode(themeMode))
                        service.themeMode = themeMode
                    if (hasBarIntegration)
                        service.barIntegratedWithDock = object.barIntegratedWithDock
                    if (hasGlassFollows)
                        service.glassFollowsAppearanceMode =
                            typeof followsAppearance === "boolean"
                                ? followsAppearance
                                : followsAppearanceLegacy
                    if (service.isValidBarVisibilityMode(barVisibility))
                        service.barVisibilityMode = barVisibility
                    if (service.isValidBarLayoutMode(barLayout))
                        service.barLayoutMode = barLayout
                    if (service.isValidDockWindowAnimationStyle(animationStyle))
                        service.dockWindowAnimationStyle = animationStyle
                    if (service.isValidGlassStyle(glassStyle))
                        service.glassStyle = glassStyle

                    // One loop over every style's preset, driven by the same
                    // range table that updateGlassPresetParameter() clamps
                    // against. A missing style in the file leaves its defaults
                    // in place; a value outside its range is clamped rather
                    // than dropped, so a hand-edited config cannot put a
                    // parameter somewhere the UI can never reach.
                    for (const presetStyle of ["liquid", "soft", "frosted"]) {
                        for (const strength of ["BlurStrength", "LiquidStrength"]) {
                            const value = service._normalized(object[presetStyle
                                + "Preset" + strength])
                            if (Number.isFinite(value))
                                service[presetStyle + "Preset" + strength] = value
                        }
                        for (const parameter in service.presetParameterRanges) {
                            const value = Number(object[presetStyle + "Preset"
                                + parameter])
                            if (!Number.isFinite(value))
                                continue
                            const range = service.presetParameterRanges[parameter]
                            service[presetStyle + "Preset" + parameter] =
                                Math.max(range[0], Math.min(range[1], value))
                        }
                    }
                    // Older files had one global pair. Keep it as the selected
                    // non-liquid style's initial value; the liquid default is
                    // intentionally 100% liquid and 0% blur.
                    if (Number(object.version) < 16 && glassStyle !== "liquid") {
                        service[service.presetPrefix + "BlurStrength"] =
                            service.globalBlurStrength
                        service[service.presetPrefix + "LiquidStrength"] =
                            service.globalLiquidStrength
                    }
                    // v17 makes the material balance intentional: soft glass
                    // is half liquid, while frosted glass is fully blurred and
                    // half liquid. This migration replaces the former shared
                    // defaults, which were never user-tuned per preset.
                    if (Number(object.version) < 17) {
                        service.softPresetLiquidStrength = 0.5
                        service.frostedPresetBlurStrength = 1.0
                        service.frostedPresetLiquidStrength = 0.5
                    }
                    // v18 introduces a dedicated Material blur preset. Its
                    // initial 10% value must not be inferred from a prior
                    // glass style's global strength.
                    if (Number(object.version) < 18)
                        service.materialPresetBlurStrength = 0.10
                    if (Number(object.version) < 19)
                        service.softPresetBlurStrength = 0.10
                    if (Number(object.version) < 20) {
                        service.softPresetRefraction = 0.15
                        service.softPresetEdgeSize = 12.0
                        service.softPresetNormalPow = 4.0
                        service.softPresetRGBFringing = 0.0
                        service.softPresetOffsetStrength = 2.0
                        service.softPresetSoftness = 0.90
                        service.softPresetReflection = 0.18
                    }
                    if (Number(object.version) < 21)
                        service.softPresetBlurStrength = 0.10
                    if (Number(object.version) < 22) {
                        service.softPresetRefraction = 0.28
                        service.softPresetEdgeSize = 18.0
                        service.softPresetNormalPow = 4.0
                        service.softPresetRGBFringing = 0.0
                        service.softPresetOffsetStrength = 5.0
                        service.softPresetSoftness = 0.65
                        service.softPresetReflection = 0.0
                    }
                    if (Number(object.version) < 23)
                        service.softPresetOffsetStrength = 0.0
                    // v24 clears values left by the old debug experiment so
                    // the redesigned soft-glow path starts from one known,
                    // internally consistent preset.
                    if (Number(object.version) < 24) {
                        service.softPresetBlurStrength = 0.10
                        service.softPresetLiquidStrength = 0.50
                        service.softPresetRefraction = 0.28
                        service.softPresetEdgeSize = 18.0
                        service.softPresetNormalPow = 4.0
                        service.softPresetRGBFringing = 0.0
                        service.softPresetOffsetStrength = 0.0
                        service.softPresetSoftness = 0.65
                        service.softPresetReflection = 0.0
                    }
                    // v26 calms the liquid preset's body lens. Migrate only the
                    // former authored default so an explicitly tuned value is
                    // preserved.
                    if (Number(object.version) < 26
                            && Math.abs(service.liquidPresetOffsetStrength - 8.0) < 0.001)
                        service.liquidPresetOffsetStrength = 0.0
                    service.globalBlurStrength = service.shellStyle === "material"
                        ? service.materialPresetBlurStrength
                        : service.activePresetBlurStrength
                    service.blurStrength = service.globalBlurStrength
                    service.globalLiquidStrength = service.activePresetLiquidStrength
                    service.liquidStrength = service.activePresetLiquidStrength

                    if (Number(object.version) !== 26
                            || !service.isValidShellStyle(style)
                            || !service.isValidThemeMode(themeMode)
                            || !hasBarIntegration
                            || !hasGlassFollows
                            || !service.isValidBarVisibilityMode(barVisibility)
                            || !service.isValidBarLayoutMode(barLayout)
                            || !service.isValidGlassStyle(glassStyle)
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
