import QtQuick
import QtQuick.Effects
import Quickshell
import Qt5Compat.GraphicalEffects
import qs.desktop.modules.common
import qs.desktop.modules.weather

// Two-row clock page for the Dock information carousel. macOS uses layered
// highlights directly on the seconds glyphs; there is no inner pill/card.
Item {
    id: widget

    property int iconSize: 44
    property int dockHeight: 60
    property int widthUnits: 4
    readonly property real backgroundGap: iconSize * 0.1
    readonly property real contentWidth: iconSize * widthUnits
    readonly property bool compact: iconSize < 32

    width: contentWidth + backgroundGap * 2
    height: iconSize

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    function shortWeekday(date) {
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][date.getDay()]
    }

    // Clock has no content-owned palette like weather or album artwork, so it
    // borrows the wallpaper palette and compresses it toward a quiet neutral.
    // Dark/light modes use different neutral anchors to preserve text contrast.
    function ambientColor(source, alpha) {
        const neutral = ThemeService.isDark ? 0.035 : 0.90
        const colorWeight = ThemeService.isDark ? 0.54 : 0.20
        const color = WallpaperPaletteService.ready
            ? source : ThemeService.backgroundColor
        return IconAppearanceService.styledColor(Qt.rgba(
            neutral + (color.r - neutral) * colorWeight,
            neutral + (color.g - neutral) * colorWeight,
            neutral + (color.b - neutral) * colorWeight,
            alpha))
    }

    function ambientMidpoint(first, second, alpha) {
        return ambientColor(Qt.rgba(
            (first.r + second.r) / 2,
            (first.g + second.g) / 2,
            (first.b + second.b) / 2, 1), alpha)
    }

    component SolarEventRow: Item {
        property string label: ""
        property string value: "--:--"

        Row {
            anchors.centerIn: parent
            spacing: Math.max(1, Math.round(widget.iconSize * 0.04))

            Text {
                text: label
                color: ThemeService.foregroundColor
                opacity: 0.72
                font {
                    family: "Noto Sans CJK SC"
                    pixelSize: Math.max(8, Math.round(widget.iconSize * 0.18))
                    weight: Font.Medium
                }
            }
            Text {
                text: value
                color: ThemeService.foregroundColor
                opacity: value === "--:--" ? 0.48 : 0.92
                font {
                    family: "SF Pro Display"
                    pixelSize: Math.max(8, Math.round(widget.iconSize * 0.19))
                    weight: Font.DemiBold
                }
            }
        }
    }

    // Match the music/weather card contract exactly: the visible background
    // extends by backgroundGap on every side and shares their 0.35 radius.
    Rectangle {
        id: clockBackground
        anchors.horizontalCenter: parent.horizontalCenter
        y: -widget.backgroundGap
        width: widget.width
        height: widget.iconSize + widget.backgroundGap * 2
        radius: widget.iconSize * 0.35
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: widget.ambientColor(WallpaperPaletteService.primary, 0.74)
            }
            GradientStop {
                position: 0.55
                color: widget.ambientMidpoint(WallpaperPaletteService.primary,
                    WallpaperPaletteService.secondary, 0.66)
            }
            GradientStop {
                position: 1.0
                color: widget.ambientColor(WallpaperPaletteService.secondary, 0.58)
            }
        }
        border.width: 0
        z: -1
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        visible: !widget.compact
        width: Math.min(parent.width - widget.backgroundGap * 2,
                        widget.iconSize * 3.86)
        height: Math.round(widget.iconSize * 0.88)
        spacing: 0

        Column {
            width: contentRow.width * 0.60
            height: parent.height
            spacing: Math.max(1, Math.round(widget.iconSize * 0.03))

            Item {
                id: clockLine
                width: parent.width
                height: Math.round(widget.iconSize * 0.58)

                // The glyph itself is the mask: a shifted, blurred sample of
                // the ambient card is visible only inside the numbers.
                ShaderEffectSource {
                    id: ambientTexture
                    anchors.fill: parent
                    visible: false
                    sourceItem: clockBackground
                    sourceRect: Qt.rect(0, 0,
                        clockBackground.width, clockBackground.height)
                    live: true
                    hideSource: false
                    smooth: true
                }
                FastBlur {
                    id: refractedTexture
                    anchors.fill: parent
                    visible: false
                    source: ambientTexture
                    radius: Math.max(2, Math.round(widget.iconSize * 0.16))
                    transparentBorder: true
                    cached: true
                }
                Text {
                    id: glyphMask
                    anchors.fill: parent
                    text: timeText.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: timeText.font
                    visible: false
                    layer.enabled: true
                }

                OpacityMask {
                    anchors.fill: parent
                    visible: AppearanceTokens.isMacos
                    source: refractedTexture
                    maskSource: glyphMask
                    opacity: 0.92
                }

                // White-to-transparent specular fill gives every glyph the
                // curved highlight and darker lower body of iOS glass.
                Rectangle {
                    id: glyphSheen
                    anchors.fill: parent
                    visible: false
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.88) }
                        GradientStop { position: 0.32; color: Qt.rgba(0.78, 0.94, 1, 0.54) }
                        GradientStop { position: 0.62; color: Qt.rgba(1, 1, 1, 0.18) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.08, 0.12, 0.20, 0.48) }
                    }
                }
                OpacityMask {
                    anchors.fill: parent
                    visible: AppearanceTokens.isMacos
                    source: glyphSheen
                    maskSource: glyphMask
                    opacity: 0.72 * AppearanceTokens.glass.liquidStrength
                }

                Text {
                    id: timeText
                    anchors.centerIn: parent
                    width: parent.width
                    text: Qt.formatDateTime(clock.date, "HH:mm:ss")
                    color: AppearanceTokens.isMacos
                        ? Qt.rgba(1, 1, 1,
                            0.18 + 0.18 * AppearanceTokens.glass.liquidStrength)
                        : ThemeService.foregroundColor
                    style: Text.Outline
                    styleColor: AppearanceTokens.isMacos
                        ? Qt.rgba(0.84, 0.97, 1.0,
                            0.72 * AppearanceTokens.glass.liquidStrength)
                        : Qt.rgba(0, 0, 0, 0.34)
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 13
                    font {
                        family: "SF Pro Display"
                        pixelSize: Math.max(16, Math.round(widget.iconSize * 0.43))
                        weight: Font.DemiBold
                        letterSpacing: 0.6
                    }
                }
            }

            Text {
                width: parent.width
                height: Math.round(widget.iconSize * 0.27)
                text: Qt.formatDateTime(clock.date, "yyyy年M月d日")
                    + " " + widget.shortWeekday(clock.date)
                color: ThemeService.foregroundColor
                opacity: 0.82
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 7
                font {
                    family: "Noto Sans CJK SC"
                    pixelSize: Math.max(9, Math.round(widget.iconSize * 0.21))
                    weight: Font.Medium
                }
            }
        }

        Column {
            id: solarEvents
            width: contentRow.width * 0.40
            height: parent.height
            spacing: 0

            SolarEventRow {
                width: parent.width
                height: parent.height / 2
                label: "日落"
                value: WeatherService.sunsetTime
            }
            SolarEventRow {
                width: parent.width
                height: parent.height / 2
                label: "日出"
                value: WeatherService.sunriseTime
            }
        }
    }

    Row {
        anchors.centerIn: parent
        visible: widget.compact
        height: parent.height
        spacing: Math.max(2, Math.round(widget.iconSize * 0.08))

        DockMetricGlyph {
            width: Math.max(8, Math.round(widget.iconSize * 0.42))
            height: width
            anchors.verticalCenter: parent.verticalCenter
            kind: "clock"
            glyphColor: "white"
        }
        Text {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
            font {
                family: "SF Pro Display"
                pixelSize: Math.max(9, Math.round(widget.iconSize * 0.52))
                weight: Font.DemiBold
            }
        }
        Text {
            text: "· 日落 " + WeatherService.sunsetTime
            color: "white"
            opacity: 0.68
            anchors.verticalCenter: parent.verticalCenter
            font {
                family: "Noto Sans CJK SC"
                pixelSize: Math.max(6, Math.round(widget.iconSize * 0.28))
                weight: Font.Medium
            }
        }
    }
}
