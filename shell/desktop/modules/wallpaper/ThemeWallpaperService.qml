pragma Singleton
import QtQuick
import Quickshell.Services.UPower
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock
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
    readonly property bool locked: motion.locked
    property real phase: 0
    property real lastTick: 0
    readonly property bool anyVisible: ScreenLifecycle.outputAvailable
        && ScreenLifecycle.usableScreens.some(screen => !covered(screen))
    readonly property bool hasVisibleWindows: motion.hasVisibleWindows
    readonly property bool idleEligible: motion.idleEligible
    readonly property bool idleReady: motion.idleReady
    readonly property Timer idleDelay: motion.idleDelay
    function rearmIdle() { if (motion) motion.rearmIdle() }
    property WallpaperMotionGate motion: WallpaperMotionGate {
        enabled: root.active
        preview: root.preview
    }
    // Preview always animates, including when Settings covers the desktop.
    readonly property int cadence: preview
        ? (locked || !ScreenLifecycle.outputAvailable ? 0 : economical ? 125 : 67)
        : Policy.cadence(economical, UPower.onBattery, AppTheme.reduceMotion,locked,anyVisible)
    readonly property bool running: motion.running && cadence > 0
    readonly property int weatherCode: themeId === "weather" ? WeatherService.weatherCode : 0
    readonly property real windStrength: WeatherService.available ? Math.min(1,Math.max(0.08,Number(WeatherService.current.windSpeed || 0)*(WeatherService.units === "imperial" ? 1.609344 : 1)/60)) : 0.15
    readonly property real windDirection: WeatherService.available ? Number(WeatherService.current.windDirection || 0) : 0
    readonly property bool weatherAvailable: themeId === "weather" && WeatherService.available
    readonly property bool isDay: !weatherAvailable || WeatherService.isDay
    readonly property string temperature: weatherAvailable ? WeatherService.temperature : "--°"
    readonly property string city: weatherAvailable ? WeatherService.cityName : I18n.tr("Weather scene")

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
    onRunningChanged: {
        lastTick=0
        if (!running) interactionByScreen=({})
    }
    onActiveChanged: refreshColors()
    onThemeIdChanged: { refreshColors(); rearmIdle() }
    Component.onCompleted: { refreshColors(); rearmIdle() }
}
