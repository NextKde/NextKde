import QtQuick
import qs.desktop.modules.common
import "../../../Kos/Ui/wallpapers" as ThemeVisuals

Item {
    id: root
    property var targetScreen: null
    property bool foreground: false
    property bool rendererEnabled: true
    readonly property bool active: ThemeWallpaperService.active
    readonly property var sceneItem: sceneLoader.item
    // Offscreen desktops retain their last frame, instead of receiving phase updates.
    property real framePhase: 0
    function updateFrame() {
        if (active && !ThemeWallpaperService.locked
            && (ThemeWallpaperService.preview || !ThemeWallpaperService.covered(targetScreen)))
            framePhase = ThemeWallpaperService.phase
    }
    function reportReady() {
        if (!active || foreground || !targetScreen) return
        const id = ThemeWallpaperService.themeId
        if (ThemeWallpaperService.preview)
            WallpaperPreviewService.imageReady("theme:" + id, targetScreen.name)
        else WallpaperService.reportThemeReady(targetScreen.name, id)
    }
    Loader {
        id: sceneLoader
        anchors.fill: parent
        active: root.active && root.rendererEnabled
        sourceComponent: ThemeVisuals.ThemeWallpaperScene {
            // Pack themes (marketplace) resolve through ThemePackService; the
            // shared module itself stays free of deskcenter imports.
            packResolver: ThemePackService.entryUrl
            readonly property var interaction: ThemeWallpaperService.interactionByScreen[root.targetScreen?.name] || {}
            pointer: Qt.vector4d((interaction.x ?? -10000)/Math.max(1,width),
                (interaction.y ?? -10000)/Math.max(1,height),interaction.inside ? 1 : 0,0)
            clickPulse: Qt.vector4d((interaction.clickX ?? -10000)/Math.max(1,width),
                (interaction.clickY ?? -10000)/Math.max(1,height),interaction.clickTime ?? -100,0)
            themeId: ThemeWallpaperService.themeId
            phase: root.framePhase
            widgetRects: {
                const dock=ThemeWallpaperService.dockRects[root.targetScreen?.name]
                const cards=ThemeWallpaperService.componentRects[root.targetScreen?.name] || []
                return dock ? [dock].concat(cards).slice(0,8) : cards
            }
            foreground: root.foreground
            economical: ThemeWallpaperService.economical
            particleCount: 80
            windStrength: ThemeWallpaperService.windStrength
            windDirection: ThemeWallpaperService.windDirection
            weatherCode: ThemeWallpaperService.weatherCode
            weatherAvailable: ThemeWallpaperService.weatherAvailable
            isDay: ThemeWallpaperService.isDay
            temperature: ThemeWallpaperService.temperature
            city: ThemeWallpaperService.city
            onFrameReady: Qt.callLater(root.reportReady)
        }
        onLoaded: root.updateFrame()
    }
    Connections {
        target: ThemeWallpaperService
        function onPhaseChanged() { root.updateFrame() }
    }
}
