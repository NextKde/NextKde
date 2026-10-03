pragma Singleton
import QtQuick
import Quickshell.Services.UPower
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import qs.desktop.modules.weather
import "../../../Kos/Ui"
import "../../../Kos/Ui/foundation/WallpaperCatalog.js" as Catalog
import "ThemeWallpaperPolicy.mjs" as Policy

QtObject {
    id: root
    readonly property bool preview: WallpaperPreviewService.active && WallpaperPreviewService.mode === "theme"
    readonly property bool active: preview || (!WallpaperPreviewService.active
        && WallpaperService.takeoverEnabled && WallpaperService.mode === "theme")
    readonly property string themeId: preview ? WallpaperPreviewService.image.replace(/^theme:/, "") : WallpaperService.themeId
    readonly property bool economical: UPower.onBattery
    property var dockRects: ({})
    function setDockRect(screenName, rect) {
        if (!screenName || JSON.stringify(dockRects[screenName] ?? null) === JSON.stringify(rect)) return
        const next=Object.assign({},dockRects); next[screenName]=rect; dockRects=next
    }
    property var componentRects: ({})
    function setWidgetRects(screenName, rectangles) {
        if (!screenName || JSON.stringify(componentRects[screenName] || []) === JSON.stringify(rectangles)) return
        const next = Object.assign({}, componentRects)
        next[screenName] = rectangles
        componentRects = next
    }
    property var interactionByScreen: ({})
    function pointerMoved(screenName, x, y, inside) {
        if (!running || !screenName) return
        const old=interactionByScreen[screenName] || {clickX:-1,clickY:-1,clickTime:-100}
        const next=Object.assign({},interactionByScreen)
        next[screenName]=Object.assign({},old,{x:x,y:y,inside:inside})
        interactionByScreen=next
    }
    function pointerPressed(screenName, x, y) {
        if (!running || !screenName) return
        const old=interactionByScreen[screenName] || {}
        const next=Object.assign({},interactionByScreen)
        next[screenName]=Object.assign({},old,{x:x,y:y,inside:true,clickX:x,clickY:y,clickTime:phase})
        interactionByScreen=next
    }
    property bool locked: false
    property bool lockPollPending: false
    property real phase: 0
    property real lastTick: 0
    readonly property bool anyVisible: ScreenLifecycle.outputAvailable
        && ScreenLifecycle.usableScreens.some(screen => !covered(screen))
    readonly property bool hasVisibleWindows: {
        const revision=WindowService.revision+WindowService.placementRevision
        return Policy.hasVisibleWindows(WindowService.records,WindowService.currentDesktopId)
    }
    readonly property bool idleEligible: active && !preview && !locked
        && !AppTheme.reduceMotion && ScreenLifecycle.outputAvailable && !hasVisibleWindows
    property bool idleReady: false
    function rearmIdle() {
        if (!idleDelay) return
        idleReady=false
        idleDelay.stop()
        if (idleEligible) idleDelay.start()
    }
    property Timer idleDelay: Timer {
        interval: 10000
        repeat: false
        onTriggered: if (root.idleEligible) root.idleReady=true
    }
    property Connections desktopChanges: Connections {
        target: WindowService
        function onCurrentDesktopIdChanged() { root.rearmIdle() }
    }
    // Preview always animates, including when Settings covers the desktop.
    readonly property int cadence: preview
        ? (locked || !ScreenLifecycle.outputAvailable ? 0 : economical ? 125 : 67)
        : Policy.cadence(economical, UPower.onBattery, AppTheme.reduceMotion,locked,anyVisible)
    readonly property bool running: active && cadence>0 && (preview || idleReady && idleEligible)
    readonly property int weatherCode: themeId === "weather" ? WeatherService.weatherCode : 0
    readonly property real windStrength: WeatherService.available ? Math.min(1,Math.max(0.08,Number(WeatherService.current.windSpeed || 0)*(WeatherService.units === "imperial" ? 1.609344 : 1)/60)) : 0.15
    readonly property real windDirection: WeatherService.available ? Number(WeatherService.current.windDirection || 0) : 0
    readonly property bool weatherAvailable: themeId === "weather" && WeatherService.available
    readonly property bool isDay: !weatherAvailable || WeatherService.isDay
    readonly property string temperature: weatherAvailable ? WeatherService.temperature : "--°"
    readonly property string city: weatherAvailable ? WeatherService.cityName : "天气光景"

    function covered(screen) {
        // Explicit dependencies: KWin updates records in place for geometry changes.
        const revision = WindowService.placementRevision + WindowService.revision
        return Policy.covered(screen, WindowService.records, WindowService.currentDesktopId)
    }
    function refreshColors() {
        const theme = Catalog.theme(themeId)
        WallpaperColorSource.proceduralPrimary = active
            ? (theme ? theme.accent : ThemePackService.accent(themeId)) : ""
    }
    function pollLock() {
        if (lockPollPending || !PlatformClient.supports("session.visibility")) return
        lockPollPending = true
        PlatformClient.request("session.visibility", {}, response => {
            lockPollPending = false
            if (response?.ok) locked = !!response.result.locked
        })
    }
    property Timer clock: Timer {
        interval: Math.max(33, root.cadence)
        repeat: true
        running: root.running
        onTriggered: {
            const now = Date.now()
            if (root.lastTick) root.phase += Math.min(0.15, (now - root.lastTick) / 1000) * 0.5
            root.lastTick = now
        }
    }
    property Timer lockState: Timer {
        interval: 5000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.pollLock()
    }
    onIdleEligibleChanged: rearmIdle()
    onRunningChanged: {
        lastTick=0
        if (!running) interactionByScreen=({})
    }
    onActiveChanged: refreshColors()
    onThemeIdChanged: { refreshColors(); rearmIdle() }
    Component.onCompleted: { refreshColors(); rearmIdle() }
}
