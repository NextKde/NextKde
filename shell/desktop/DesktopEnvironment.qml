import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.bar
import qs.desktop.modules.dock
import qs.desktop.modules.quicksearch
import qs.desktop.modules.notifications
import qs.desktop.modules.applauncher
import qs.desktop.modules.deskcenter
import qs.desktop.modules.overview
import qs.desktop.modules.common
import qs.desktop.modules.platform
import qs.desktop.modules.shortcuts
import qs.desktop.modules.weather

Item {
    id: shell

    readonly property bool barIntegratedWithDock:
        AppearanceConfigService.barIntegratedWithDock

    Component {
        id: integratedBarStatus
        BarStatusArea {
            dockHosted: true
            dockEdge: ConfigService.position
        }
    }

    // Theme watching is non-visual and only loads a tiny FileView. The
    // AppLauncher and its icon grid remain lazy.
    //
    // ShortcutsService is a QML singleton, so it only instantiates on first
    // access — and nothing else touches it during startup. Touch it here so
    // the global shortcuts are registered on every Shell start (self-heal);
    // the request queues until the platform daemon connects.
    Component.onCompleted: {
        IconThemeReloadService.initialize()
        ShortcutsService.applyToPlatform()
        // Touch the lock screen feed so it exists on every shell start, not
        // only when a widget happens to reference WeatherService: the lock
        // screen cannot read anything the shell does not write out for it.
        LockScreenFeedService.initialize()
        if (shell.barIntegratedWithDock)
            WorkspaceLayoutService.clearBar(ScreenLifecycle.activeScreen)
    }

    onBarIntegratedWithDockChanged: {
        if (shell.barIntegratedWithDock)
            WorkspaceLayoutService.clearBar(ScreenLifecycle.activeScreen)
    }

    // The standalone Settings app is intentionally not allowed to import a
    // desktop module. This narrow IPC endpoint is its only Dock write path.
    IpcHandler {
        target: "dock-settings"

        function snapshot(): string {
            const theme = ConfigService.isValidTheme(ConfigService.theme)
                ? ConfigService.theme : "dark"
            const position = ConfigService.isValidPosition(ConfigService.position)
                ? ConfigService.position : "bottom"
            const iconMode = ConfigService.isValidIconMode(ConfigService.iconMode)
                ? ConfigService.iconMode : "color"
            const visibilityMode = ConfigService.isValidVisibilityMode(ConfigService.visibilityMode)
                ? ConfigService.visibilityMode : "always"
            const windowGrouping = ConfigService.isValidWindowGrouping(ConfigService.windowGrouping)
                ? ConfigService.windowGrouping : "grouped"
            const dockStyle = ConfigService.isValidDockStyle(ConfigService.dockStyle)
                ? ConfigService.dockStyle : "floating"
            const contentStyle = ConfigService.isValidContentStyle(ConfigService.contentStyle)
                ? ConfigService.contentStyle : "compact"
            const infoCardMode = ConfigService.isValidInfoCardMode(ConfigService.infoCardMode)
                ? ConfigService.infoCardMode : "carousel"
            return JSON.stringify({
                baseHeight: ConfigService.baseHeight,
                theme: theme,
                position: position,
                dockStyle: dockStyle,
                contentStyle: contentStyle,
                infoCardMode: infoCardMode,
                infoCardAutoRotate: ConfigService.infoCardAutoRotate,
                infoCardOrder: JSON.stringify(ConfigService.infoCardOrder),
                iconMode: iconMode,
                iconOpacity: ConfigService.iconOpacity,
                iconTintColor: ConfigService.iconTintColor,
                visibilityMode,
                windowGrouping,
                showLauncher: ConfigService.showLauncher,
                showTrash: ConfigService.showTrash,
            })
        }

        function updateLayout(height: real): string {
            ConfigService.updateLayout(height)
            return snapshot()
        }

        function updateBuiltinVisibility(id: string, visible: bool): string {
            ConfigService.updateBuiltinVisibility(id, visible)
            return snapshot()
        }

        function updatePosition(newPosition: string): string {
            ConfigService.updatePosition(newPosition)
            return snapshot()
        }

        function updateContentStyle(newStyle: string): string {
            ConfigService.updateContentStyle(newStyle)
            return snapshot()
        }

        function updateDockStyle(newStyle: string): string {
            ConfigService.updateDockStyle(newStyle)
            return snapshot()
        }

        function updateInfoCardMode(mode: string): string {
            ConfigService.updateInfoCardMode(mode)
            return snapshot()
        }

        function updateInfoCardAutoRotate(enabled: bool): string {
            ConfigService.updateInfoCardAutoRotate(enabled)
            return snapshot()
        }

        function updateInfoCardOrder(orderJson: string): string {
            try {
                ConfigService.updateInfoCardOrder(JSON.parse(orderJson))
            } catch (error) {
                console.warn("[DockSettings] invalid info card order: " + error)
            }
            return snapshot()
        }

        function updateTheme(theme: string): string {
            ConfigService.updateTheme(theme)
            return snapshot()
        }

        function updateIconMode(mode: string): string {
            ConfigService.updateIconMode(mode)
            return snapshot()
        }

        function updateIconOpacity(opacity: real): string {
            ConfigService.updateIconOpacity(opacity)
            return snapshot()
        }

        function updateIconTintColor(color: string): string {
            ConfigService.updateIconTintColor(color)
            return snapshot()
        }

        function updateVisibilityMode(mode: string): string {
            ConfigService.updateVisibilityMode(mode)
            return snapshot()
        }

        function updateWindowGrouping(mode: string): string {
            ConfigService.updateWindowGrouping(mode)
            return snapshot()
        }

    }

    // Shell-wide appearance controls used by the standalone Settings app.
    // Blur/liquid values are synchronized only with the custom Glass effect,
    // never KDE's stock blur effect. shellStyle selects semantic shape tokens.
    IpcHandler {
        target: "appearance-settings"

        function snapshot(): string {
            return JSON.stringify({
                globalBlurStrength: AppearanceConfigService.globalBlurStrength,
                globalLiquidStrength: AppearanceConfigService.globalLiquidStrength,
                glassStyle: AppearanceConfigService.glassStyle,
                // Every field of the active style's preset, because the Settings
                // debug page is the editor for them: a raw kwinrc write there is
                // reverted by the next effect sync. Preset units; Refraction is
                // 0..1 and becomes RefractionStrength 0..20 on the way to kwinrc.
                activePresetRefraction: AppearanceConfigService.activePresetRefraction,
                activePresetEdgeSize: AppearanceConfigService.activePresetEdgeSize,
                activePresetNormalPow: AppearanceConfigService.activePresetNormalPow,
                activePresetRGBFringing: AppearanceConfigService.activePresetRGBFringing,
                activePresetOffsetStrength: AppearanceConfigService.activePresetOffsetStrength,
                activePresetSoftness: AppearanceConfigService.activePresetSoftness,
                activePresetReflection: AppearanceConfigService.activePresetReflection,
                effectiveDockBlur: AppearanceConfigService.effectiveDockBlur,
                effectiveDockLiquid: AppearanceConfigService.effectiveDockLiquid,
                effectiveBarBlur: AppearanceConfigService.effectiveBarBlur,
                effectiveBarLiquid: AppearanceConfigService.effectiveBarLiquid,
                effectiveLauncherBlur:
                    AppearanceConfigService.effectiveLauncherBlur,
                effectiveLauncherLiquid:
                    AppearanceConfigService.effectiveLauncherLiquid,
                blurStrength: AppearanceConfigService.globalBlurStrength,
                liquidStrength: AppearanceConfigService.globalLiquidStrength,
                iconMode: IconAppearanceService.mode,
                iconOpacity: IconAppearanceService.opacity,
                // JSON has no QColor primitive. Send the canonical #rrggbb
                // form so the standalone Settings C++ bridge does not parse
                // the value as an object and fall back to its previous tint.
                iconTintColor: IconAppearanceService.tintColor.toString(),
                shellStyle: AppearanceConfigService.shellStyle,
                materialColorScheme:
                    AppearanceConfigService.materialColorScheme,
                materialAccentName: AppearanceTokens.materialAccentName,
                // Serialised here, not passed as a nested structure: the
                // settings bridge is a C++ QVariantMap with a hand-written
                // whitelist, and a plain string crosses it with no conversion
                // left to get wrong.
                materialColorSwatches:
                    JSON.stringify(AppearanceTokens.colorSchemeSwatches),
                glassFollowsAppearanceMode:
                    AppearanceConfigService.glassFollowsAppearanceMode,
                barIntegratedWithDock:
                    AppearanceConfigService.barIntegratedWithDock,
                barVisibilityMode: AppearanceConfigService.barVisibilityMode,
                barLayoutMode: AppearanceConfigService.barLayoutMode,
                dockWindowAnimationStyle:
                    AppearanceConfigService.dockWindowAnimationStyle,
                // Same reason as materialColorSwatches above: these are arrays,
                // and a plain JSON string crosses the hand-written C++ whitelist
                // with no conversion left to get wrong. They carry the *hidden*
                // ids, so an id absent from the list means "visible".
                hiddenDeskCenterWidgets: JSON.stringify(
                    AppearanceConfigService.hiddenDeskCenterWidgets),
                hiddenStatusCells: JSON.stringify(
                    AppearanceConfigService.hiddenStatusCells),
                // The known id sets, so the Settings page builds its switches
                // from the Shell's own list instead of a second hardcoded copy
                // that can drift from the surfaces the shell actually creates.
                deskCenterWidgetIds: JSON.stringify(
                    AppearanceConfigService.deskCenterWidgetIds),
                statusCellIds: JSON.stringify(
                    AppearanceConfigService.statusCellIds),
                tokenVersion: AppearanceTokens.version,
            })
        }

        function updateGlobalBlurStrength(value: real): string {
            AppearanceConfigService.updateGlobalBlurStrength(value)
            return snapshot()
        }

        function updateGlobalLiquidStrength(value: real): string {
            AppearanceConfigService.updateGlobalLiquidStrength(value)
            return snapshot()
        }

        function updateGlassStyle(style: string): string {
            AppearanceConfigService.updateGlassStyle(style)
            return snapshot()
        }

        function updateGlassPresetParameter(name: string, value: real): string {
            AppearanceConfigService.updateGlassPresetParameter(name, value)
            return snapshot()
        }

        function resetGlassPreset(style: string): string {
            AppearanceConfigService.resetGlassPreset(style)
            return snapshot()
        }

        function updateGlobalIconMode(mode: string): string {
            IconAppearanceService.updateMode(mode)
            return snapshot()
        }

        function updateGlobalIconOpacity(opacity: real): string {
            IconAppearanceService.updateOpacity(opacity)
            return snapshot()
        }

        function updateGlobalIconTintColor(color: string): string {
            IconAppearanceService.updateTintColor(color)
            return snapshot()
        }

        function updateBlurStrength(value: real): string {
            AppearanceConfigService.updateGlobalBlurStrength(value)
            return snapshot()
        }

        function updateLiquidStrength(value: real): string {
            AppearanceConfigService.updateGlobalLiquidStrength(value)
            return snapshot()
        }

        function updateShellStyle(style: string): string {
            AppearanceConfigService.updateShellStyle(style)
            return snapshot()
        }

        function updateMaterialColorScheme(scheme: string): string {
            AppearanceConfigService.updateMaterialColorScheme(scheme)
            return snapshot()
        }

        function updateBarIntegratedWithDock(enabled: bool): string {
            AppearanceConfigService.updateBarIntegratedWithDock(enabled)
            return snapshot()
        }

        function updateGlassFollowsAppearanceMode(enabled: bool): string {
            AppearanceConfigService.updateGlassFollowsAppearanceMode(enabled)
            return snapshot()
        }

        function updateBarVisibilityMode(mode: string): string {
            AppearanceConfigService.updateBarVisibilityMode(mode)
            return snapshot()
        }

        function updateBarLayoutMode(mode: string): string {
            AppearanceConfigService.updateBarLayoutMode(mode)
            return snapshot()
        }

        function updateDockWindowAnimationStyle(style: string): string {
            AppearanceConfigService.updateDockWindowAnimationStyle(style)
            return snapshot()
        }

        // Per-surface visibility. `visible` is the wanted state, so the switch
        // in the Settings page holds the same value it displays.
        function updateDeskCenterWidgetVisibility(id: string, visible: bool): string {
            AppearanceConfigService.setDeskCenterWidgetVisible(id, visible)
            return snapshot()
        }

        function updateStatusCellVisibility(id: string, visible: bool): string {
            AppearanceConfigService.setStatusCellVisible(id, visible)
            return snapshot()
        }

        // The standalone Settings app talks to this narrow Shell endpoint;
        // only the resident platform daemon performs KDE theme operations.
        function applySystemAppearance(dark: bool): string {
            PlatformClient.request("theme.apply-system", { dark: dark },
                function(response) {
                    if (!response?.ok)
                        console.warn("[Appearance] system theme failed: "
                            + (response?.error?.message || "platform unavailable"))
                })
            return JSON.stringify({ accepted: true })
        }

        function resetStrengths(): string {
            AppearanceConfigService.resetStrengths()
            return snapshot()
        }
    }

    // AppLauncher settings endpoint for standalone Settings app and IPC clients.
    IpcHandler {
        target: "applauncher-settings"

        function snapshot(): string {
            return JSON.stringify({
                displayMode: AppLauncherConfigService.displayMode,
                layoutProfiles: AppLauncherConfigService.layoutProfiles,
            })
        }

        function updateDisplayMode(mode: string): string {
            AppLauncherConfigService.updateDisplayMode(mode)
            return snapshot()
        }

        function updateProfileIconSize(mode: string, size: string): string {
            AppLauncherConfigService.updateProfileIconSize(mode, size)
            return snapshot()
        }

        function updateProfileDensity(mode: string, density: string): string {
            AppLauncherConfigService.updateProfileDensity(mode, density)
            return snapshot()
        }

        function updateProfileFontWeight(mode: string, weight: string): string {
            AppLauncherConfigService.updateProfileFontWeight(mode, weight)
            return snapshot()
        }

        function resetProfile(mode: string): string {
            AppLauncherConfigService.resetProfile(mode)
            return snapshot()
        }
    }

    // Global-shortcut endpoint for the standalone Settings app. ShortcutsService
    // owns defaults, overrides, and the kglobalaccel handoff; this handler is
    // the only write path the Settings app gets, matching the other targets.
    IpcHandler {
        target: "shortcuts-settings"

        function snapshot(): string {
            return JSON.stringify(ShortcutsService.snapshot())
        }

        function updateShortcut(id: string, combo: string): string {
            return JSON.stringify(ShortcutsService.updateShortcut(id, combo))
        }

        function resetShortcut(id: string): string {
            return JSON.stringify(ShortcutsService.resetShortcut(id))
        }
    }

    // Read-only health snapshot for the standalone Settings app. Keep these
    // values sourced from the live Shell connections so the UI reports what
    // is actually connected, not merely which units were installed.
    IpcHandler {
        target: "integration-status"

        function snapshot(): string {
            return JSON.stringify({
                shellReady: true,
                platformConnected: PlatformClient.connected,
                dataConnected: DataClient.connected,
                outputAvailable: ScreenLifecycle.outputAvailable,
                desktopWidgetsVisible: ScreenLifecycle.outputAvailable
                    && ScreenLifecycle.activeScreen !== null,
                desktopFilesReady: DesktopFilesService.ready,
            })
        }
    }

    // The KWin effect observes pointer presses at compositor scope and routes
    // them through WindowService's existing local bridge. Keep the policy here
    // so individual desktop, Dock, and tray surfaces need no outside-click
    // listeners.
    Connections {
        target: WindowService
        function onGlobalPointerPressed(x, y, button, timestamp) {
            ContextMenuCoordinator.dismissForGlobalPointerPress(x, y, timestamp)
        }
    }

    QuickSearch {
        id: quickSearch
    }
    AppLauncher {}
    Overview {}
    IpcHandler {
        target: "desktop"
        function toggle(): void { WindowService.toggleShowDesktop() }
        function show(): void { WindowService.toggleShowDesktop() }
    }
    NotificationCenter {
        id: notificationCenter
    }

    DeskCenter {}
    DesktopLyrics {}
    // Do not briefly map the standalone Bar with the default setting and then
    // hide it while its tray delegates are still being constructed. Qt 6.11
    // can crash while cleaning that incomplete QQuickWindow scene. Wait for
    // the persisted integration choice before making the Bar visible.
    Bar {
        enabled: AppearanceConfigService.ready
            && !shell.barIntegratedWithDock
    }
    Dock {
        clockInInfoCarousel: shell.barIntegratedWithDock
            && ConfigService.position === "bottom"
        trailingAccessory: shell.barIntegratedWithDock
            ? integratedBarStatus : null
    }
}
