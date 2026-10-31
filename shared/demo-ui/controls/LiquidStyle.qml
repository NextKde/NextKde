pragma Singleton
import QtQuick

QtObject {
    // Glass-layer opacity over a blurred underlay; tint coverage is independent.
    readonly property real panelMaterialOpacity: 0.95
    // Material intensity only: never changes layout, typography or fill alpha.
    property string intensityLevel: "medium"
    // Independent from liquid intensity: 1=dark/tight, 3=light/broad.
    property int shadowLevel: 1
    property real controlShadowOutset: 1
    readonly property var shadowProfiles: ({
        "1": { opacity: .24, softness: 2, spread: 8, offsetY: 1 },
        "2": { opacity: .16, softness: 5, spread: 16, offsetY: 2 },
        "3": { opacity: .10, softness: 10, spread: 32, offsetY: 3 }
    })
    function shadowProfile(level) {
        return shadowProfiles[String(level)] || shadowProfiles["1"]
    }
    property color controlFillCenter: "#e2e2e6"
    property color controlFillCenterDark: "#20252f"
    property color controlFillEdgeDark: "#77777d"
    property real controlFillEdgeSpanDark: 4
    property real controlFillOpacity: .35
    property color controlFillEdge: "#ffffff"
    property real controlFillCenterExtent: .70
    property real controlFillWhiteRimX: 0
    property real controlFillWhiteRimY: 2
    property real controlFillWhiteRimYDark: 1
    property real controlWhiteEdgeDepth: 3
    property real controlWhiteEdgeAlpha: .10
    readonly property var intensityProfiles: ({
        "light": { refraction: 1.5, hoverRefraction: 2.25,
            magnification: 1.012, hoverMagnification: 1.022,
            reflection: .28, hoverReflection: .42, blur: 0, edgeShade: .04 },
        "medium": { refraction: 3, hoverRefraction: 4.5,
            magnification: 1.025, hoverMagnification: 1.045,
            reflection: .50, hoverReflection: .72, blur: 0, edgeShade: .10 },
        "strong": { refraction: 6, hoverRefraction: 8,
            magnification: 1.05, hoverMagnification: 1.07,
            reflection: .80, hoverReflection: 1.10, blur: .15, edgeShade: .10 }
    })
    function intensityProfile(level) {
        return intensityProfiles[level] || intensityProfiles.medium
    }

    property var _backdrops: []

    function registerBackdrop(backdrop) {
        _backdrops = _backdrops.concat([backdrop])
    }

    function unregisterBackdrop(backdrop) {
        _backdrops = _backdrops.filter(item => item !== backdrop)
    }

    // Start at the parent: a material container must never select its own
    // content provider when it resolves the source for its background.
    function backdropForItem(item, window) {
        for (let host = item ? item.parent : null; host; host = host.parent) {
            if (!("contentBackdrop" in host)) continue
            const candidate = host.contentBackdrop
            if (candidate && typeof candidate.canSample === "function" && candidate.canSample(item))
                return candidate
        }
        return backdropFor(window)
    }

    function backdropFor(window) {
        if (!window) return null
        for (let index = _backdrops.length - 1; index >= 0; --index) {
            const backdrop = _backdrops[index]
            if (backdrop && backdrop.registerAsDefault && backdrop.available
                    && backdrop.hostWindow === window)
                return backdrop
        }
        return null
    }
}
