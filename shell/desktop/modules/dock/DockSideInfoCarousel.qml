import QtQuick
import QtQuick.Effects
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.weather

// Readable one-line information carousel for a left/right Dock. Its parent
// Row is rotated by 90 degrees; the inner panel rotates back so the screen
// text remains horizontal while the card occupies two icon lengths vertically.
Item {
    id: carousel

    readonly property int musicPage: 0
    readonly property int weatherPage: 1
    readonly property int clockPage: 2
    readonly property int temperaturePage: 3

    property int iconSize: 44
    property int dockHeight: 60
    property real widthUnits: 2
    property bool showClock: false
    property bool showTemperature: true
    readonly property bool hasMusic: DockMprisService.hasPlayingPlayer
    readonly property bool hasWeather: WeatherService.available
    readonly property var player: DockMprisService.activePlayer
    readonly property url artworkSource: {
        const revision = DockMprisService.metadataRevision
        return player?.trackArtUrl ? player.trackArtUrl
            : Qt.resolvedUrl("../../assets/defaultCover.png")
    }
    readonly property bool monochrome: ConfigService.iconMode !== "color"
    readonly property int availablePageCount: Number(hasMusic)
        + Number(hasWeather) + Number(showClock) + Number(showTemperature)
    property int page: clockPage

    width: iconSize * widthUnits + iconSize * 0.2
    height: iconSize * 1.2
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function pageAvailable(candidate) {
        if (candidate === musicPage)
            return hasMusic
        if (candidate === weatherPage)
            return hasWeather
        if (candidate === clockPage)
            return showClock
        return candidate === temperaturePage && showTemperature
    }

    function availablePages() {
        const pages = []
        if (hasMusic) pages.push(musicPage)
        if (hasWeather) pages.push(weatherPage)
        if (showClock) pages.push(clockPage)
        if (showTemperature) pages.push(temperaturePage)
        return pages
    }

    function ensureValidPage() {
        if (pageAvailable(page))
            return
        const pages = availablePages()
        page = pages.length > 0 ? pages[0] : clockPage
    }

    function switchPage(direction) {
        const pages = availablePages()
        if (pages.length < 2)
            return
        let index = pages.indexOf(page)
        if (index < 0)
            index = 0
        const step = direction >= 0 ? 1 : -1
        page = pages[(index + step + pages.length) % pages.length]
    }

    function pageText() {
        if (page === musicPage)
            return "音乐"
        if (page === weatherPage)
            return WeatherService.temperature
        if (page === temperaturePage) {
            const value = MetricsService.currentMilliC >= 0
                ? Math.round(MetricsService.currentMilliC / 1000) + "°" : "--°"
            return value
        }
        return Qt.formatDateTime(clock.date, "HH:mm")
    }

    // Keep the side card on the exact same page-owned palette as the bottom
    // carousel. Only its compact icon/text layout is different.
    function artworkTint(color, alpha) {
        if (monochrome) {
            const luminance = color.r * 0.2126 + color.g * 0.7152
                + color.b * 0.0722
            return Qt.rgba(luminance, luminance, luminance, alpha)
        }
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function weatherStart(code, day) {
        if (code === 0) return day ? Qt.rgba(0.18, 0.54, 0.94, 0.58) : Qt.rgba(0.10, 0.15, 0.38, 0.66)
        if (code === 1 || code === 2) return Qt.rgba(0.36, 0.58, 0.76, 0.56)
        if (code === 3) return Qt.rgba(0.35, 0.43, 0.52, 0.62)
        if (code === 45 || code === 48) return Qt.rgba(0.38, 0.45, 0.49, 0.60)
        if (code >= 51 && code <= 67) return Qt.rgba(0.20, 0.35, 0.49, 0.64)
        if (code >= 71 && code <= 86) return Qt.rgba(0.54, 0.68, 0.78, 0.58)
        if (code >= 95) return Qt.rgba(0.24, 0.23, 0.40, 0.70)
        return Qt.rgba(0.32, 0.44, 0.58, 0.58)
    }

    function weatherEnd(code, day) {
        if (code === 0) return day ? Qt.rgba(1.0, 0.72, 0.30, 0.42) : Qt.rgba(0.36, 0.42, 0.70, 0.38)
        if (code === 1 || code === 2) return Qt.rgba(0.88, 0.90, 0.91, 0.46)
        if (code === 3) return Qt.rgba(0.92, 0.94, 0.95, 0.48)
        if (code === 45 || code === 48) return Qt.rgba(0.82, 0.85, 0.85, 0.44)
        if (code >= 51 && code <= 67) return Qt.rgba(0.58, 0.68, 0.73, 0.40)
        if (code >= 71 && code <= 86) return Qt.rgba(0.94, 0.98, 1.0, 0.50)
        if (code >= 95) return Qt.rgba(0.57, 0.54, 0.72, 0.46)
        return Qt.rgba(0.76, 0.82, 0.86, 0.42)
    }

    function ambientColor(source, alpha) {
        const neutral = ThemeService.isDark ? 0.035 : 0.90
        const colorWeight = ThemeService.isDark ? 0.54 : 0.20
        const color = WallpaperPaletteService.ready
            ? source : ThemeService.backgroundColor
        return ConfigService.styledDockColor(Qt.rgba(
            neutral + (color.r - neutral) * colorWeight,
            neutral + (color.g - neutral) * colorWeight,
            neutral + (color.b - neutral) * colorWeight, alpha))
    }

    function thermalColor(cool, warm, alpha) {
        const currentC = MetricsService.currentMilliC >= 0
            ? Math.round(MetricsService.currentMilliC / 1000) : -1
        const value = currentC >= 0 ? Math.max(0, Math.min(1,
            (currentC - 35) / 55)) : 0.25
        return ConfigService.styledDockColor(Qt.rgba(
            cool.r + (warm.r - cool.r) * value,
            cool.g + (warm.g - cool.g) * value,
            cool.b + (warm.b - cool.b) * value, alpha))
    }

    function backgroundStart() {
        if (page === musicPage)
            return artworkTint(artworkPalette.primary, 0.82)
        if (page === weatherPage)
            return ConfigService.styledDockColor(weatherStart(
                WeatherService.weatherCode, WeatherService.isDay))
        if (page === temperaturePage)
            return thermalColor(Qt.rgba(0.16, 0.38, 0.62, 1),
                Qt.rgba(0.68, 0.22, 0.18, 1), 0.68)
        return ambientColor(WallpaperPaletteService.primary, 0.74)
    }

    function backgroundMiddle() {
        if (page === musicPage)
            return artworkTint(artworkPalette.secondary, 0.64)
        if (page === clockPage)
            return ambientColor(Qt.rgba(
                (WallpaperPaletteService.primary.r + WallpaperPaletteService.secondary.r) / 2,
                (WallpaperPaletteService.primary.g + WallpaperPaletteService.secondary.g) / 2,
                (WallpaperPaletteService.primary.b + WallpaperPaletteService.secondary.b) / 2, 1), 0.66)
        return backgroundStart()
    }

    function backgroundEnd() {
        if (page === musicPage)
            return artworkTint(artworkPalette.primary, 0.38)
        if (page === weatherPage)
            return ConfigService.styledDockColor(weatherEnd(
                WeatherService.weatherCode, WeatherService.isDay))
        if (page === temperaturePage)
            return thermalColor(Qt.rgba(0.20, 0.56, 0.68, 1),
                Qt.rgba(0.96, 0.52, 0.18, 1), 0.54)
        return ambientColor(WallpaperPaletteService.secondary, 0.58)
    }

    Component.onCompleted: ensureValidPage()
    onHasMusicChanged: ensureValidPage()
    onHasWeatherChanged: ensureValidPage()
    onShowClockChanged: ensureValidPage()
    onShowTemperatureChanged: ensureValidPage()

    ArtworkPalette {
        id: artworkPalette
        source: carousel.artworkSource
    }

    Timer {
        interval: 30000
        running: carousel.availablePageCount > 1
        repeat: true
        onTriggered: {
            carousel.switchPage(1)
        }
    }

    Timer {
        id: wheelCooldown
        interval: 180
        repeat: false
    }

    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            const delta = wheel.angleDelta.y + wheel.pixelDelta.y
            if (delta === 0 || wheelCooldown.running)
                return
            carousel.switchPage(delta >= 0 ? -1 : 1)
            wheelCooldown.restart()
            wheel.accepted = true
        }
    }

    Item {
        id: readablePanel
        anchors.centerIn: parent
        width: carousel.height
        height: carousel.width
        rotation: -90

        Rectangle {
            anchors.fill: parent
            radius: Math.max(4, carousel.iconSize * 0.30)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: carousel.backgroundStart() }
                GradientStop { position: 0.52; color: carousel.backgroundMiddle() }
                GradientStop { position: 1.0; color: carousel.backgroundEnd() }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            // Keep the icon and its value as one compact visual group instead
            // of distributing them across the full two-unit card height.
            height: parent.height * 0.62
            spacing: 0

            Item {
                width: parent.width
                height: parent.height * 0.50

                Text {
                    anchors.centerIn: parent
                    visible: carousel.page === carousel.musicPage
                    text: "♫"
                    color: "white"
                    font.pixelSize: Math.max(10,
                        Math.round(carousel.iconSize * 0.54))
                }
                Text {
                    anchors.centerIn: parent
                    visible: carousel.page === carousel.weatherPage
                    text: WeatherService.conditionSymbol(WeatherService.weatherCode,
                                                         WeatherService.isDay)
                    color: "white"
                    font.pixelSize: Math.max(10,
                        Math.round(carousel.iconSize * 0.54))
                }
                DockMetricGlyph {
                    width: Math.max(10, Math.round(carousel.iconSize * 0.48))
                    height: width
                    anchors.centerIn: parent
                    visible: carousel.page === carousel.clockPage
                    kind: "clock"
                    glyphColor: "white"
                }
                DockMetricGlyph {
                    width: Math.max(10, Math.round(carousel.iconSize * 0.52))
                    height: width
                    anchors.centerIn: parent
                    visible: carousel.page === carousel.temperaturePage
                    kind: "temperature"
                    glyphColor: "white"
                }
            }

            Text {
                width: parent.width - carousel.iconSize * 0.12
                height: parent.height * 0.50
                anchors.horizontalCenter: parent.horizontalCenter
                text: carousel.pageText()
                color: "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 5
                font {
                    family: "SF Pro Display"
                    pixelSize: Math.max(8,
                        Math.round(carousel.iconSize * 0.42))
                    weight: Font.DemiBold
                }
            }
        }
    }
}
