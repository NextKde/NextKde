// Opt-in Demo material, imported from nextkdeAppDemo (2026-10-26).
// Existing LiquidSurface consumers retain their current rendering.
import QtQuick
import QtQuick.Window
import "../foundation" as Foundation

Item {
    id: root
    property real radius: 22
    // Real sampled pixels plus luminance-dependent readability; no fixed glass fill.
    property bool adaptiveGlass: false
    readonly property color _adaptiveTint: darkAppearance ? Foundation.AppTheme.blackSeed : Foundation.AppTheme.whiteSeed
    readonly property real _reflection: adaptiveGlass && !sampling ? 0 : reflectionStrength
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    property bool darkAppearance: Foundation.AppTheme.dark
    property color tintColor: darkAppearance ? "#141c30" : "#ffffff"
    property real tintStrength: 0.08
    property bool gradientFill: false
    property color fillEdgeColor: tintColor
    property real fillCenterExtent: 0
    property real fillWhiteRim: 0
    property real fillWhiteRimX: fillWhiteRim
    property real fillWhiteRimY: fillWhiteRim
    // Optional total vertical fill-edge width, including its transition; not the optical rim.
    property real fillEdgeSpanY: -1
    property real whiteEdgeDepth: 0
    property real whiteEdgeAlpha: 0
    // Pigmented diffuse finish for unsampled surfaces; never claims external blur.
    property real diffuseStrength: 0
    property real blurStrength: 0.45
    property real readability: 0.47
    property bool convexLens: false
    property real refractionStrength: 3
    property real magnification: 1.025
    property real edgeWidth: 12
    property real highlightTintStrength: 0
    property real edgeShadeStrength: 0
    property real reflectionStrength: 1
    property bool fullHighlight: false
    property color rimColor: Qt.rgba(1, 1, 1, 0.30)
    readonly property bool sampling: canSampleBackdrop && _mappingValid
        && optics.item !== null && optics.item.status !== ShaderEffect.Error
    readonly property bool canSampleBackdrop: !(adaptiveGlass && Foundation.AppTheme.reduceTransparency)
        && backdrop !== null && backdrop.canSample(root)
        && width > 0 && height > 0 && GraphicsInfo.api !== GraphicsInfo.Software
    property bool _mappingValid: false
    property vector2d _sampleOrigin: Qt.vector2d(0, 0)
    property vector2d _sampleAxisX: Qt.vector2d(1, 0)
    property vector2d _sampleAxisY: Qt.vector2d(0, 1)

    function updateMapping() {
        if (!canSampleBackdrop) { _mappingValid = false; return }
        const source = backdrop.sourceItem
        const origin = mapToItem(source, 0, 0)
        const endX = mapToItem(source, width, 0)
        const endY = mapToItem(source, 0, height)
        _sampleOrigin = Qt.vector2d(origin.x / source.width, origin.y / source.height)
        _sampleAxisX = Qt.vector2d((endX.x - origin.x) / source.width, (endX.y - origin.y) / source.height)
        _sampleAxisY = Qt.vector2d((endY.x - origin.x) / source.width, (endY.y - origin.y) / source.height)
        _mappingValid = true
    }

    Component.onCompleted: Qt.callLater(updateMapping)
    onBackdropChanged: { _mappingValid = false; Qt.callLater(updateMapping) }
    onCanSampleBackdropChanged: Qt.callLater(updateMapping)
    onXChanged: updateMapping()
    onYChanged: updateMapping()
    onWidthChanged: updateMapping()
    onHeightChanged: updateMapping()
    Connections {
        target: root.Window.window
        enabled: root.visible && root.canSampleBackdrop
        // Also follows ancestor scrolling, rotation and animated scale.
        function onAfterAnimating() { root.updateMapping() }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.gradientFill && !root.sampling && (root.adaptiveGlass || root.diffuseStrength <= 0 || GraphicsInfo.api === GraphicsInfo.Software)
        radius: root.radius
        color: root.adaptiveGlass ? (Foundation.AppTheme.dark ? "#3A3A3C" : "#EDEDF0") : root.tintColor
        opacity: root.adaptiveGlass ? 1 : Math.max(0, Math.min(1, root.tintStrength))
    }
    ShaderEffect {
        anchors.fill: parent
        visible: !root.adaptiveGlass && !root.gradientFill && !root.sampling && root.diffuseStrength > 0 && GraphicsInfo.api !== GraphicsInfo.Software
        vertexShader: Qt.resolvedUrl("shaders/liquid_diffuse.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/liquid_diffuse.frag.qsb")
        property vector2d surfaceSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
        property real radius: root.radius
        property color tintColor: root.tintColor
        property real tintStrength: root.tintStrength
        property real diffuseStrength: root.diffuseStrength
    }
    // A hidden ShaderEffect still owns sampler bindings. Destroy the sampled
    // pass when its provider goes away instead of feeding a live node null.
    Loader {
        id: optics
        anchors.fill: parent
        active: root.canSampleBackdrop && root._mappingValid
        sourceComponent: ShaderEffect {
            anchors.fill: parent
            vertexShader: Qt.resolvedUrl(root.convexLens ? "shaders/liquid_convex.vert.qsb" : "shaders/liquid_compact_surface.vert.qsb")
            fragmentShader: Qt.resolvedUrl(root.convexLens ? "shaders/liquid_convex.frag.qsb" : "shaders/liquid_compact_surface.frag.qsb")
            property var source: root.canSampleBackdrop ? (root.backdrop.texture) : null
            property vector2d surfaceSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
            property vector2d sampleOrigin: root._sampleOrigin
            property vector2d sampleAxisX: root._sampleAxisX
            property vector2d sampleAxisY: root._sampleAxisY
            property real radius: root.radius
            property color tintColor: root.adaptiveGlass ? root._adaptiveTint : root.tintColor
            property real tintStrength: root.adaptiveGlass ? .08 : root.gradientFill ? 0 : root.tintStrength
            property real blurRadius: Math.max(0, root.blurStrength) * 8
            property real readability: root.adaptiveGlass ? .65 : root.readability
            property real lightAppearance: root.darkAppearance ? 0 : 1
            property real refractionStrength: root.refractionStrength
            property real magnification: root.magnification
            property real edgeWidth: root.edgeWidth
            property real diffuseStrength: root.diffuseStrength
        }
    }
    // One fill over the refracted scene, not a second flat tint underneath it.
    // QML paint keeps this change hot-reloadable without rebaking optical shaders.
    Canvas {
        id: controlFill
        anchors.fill: parent
        visible: root.gradientFill || root.whiteEdgeDepth > 0
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onRadiusChanged() { controlFill.requestPaint() }
            function onTintColorChanged() { controlFill.requestPaint() }
            function onTintStrengthChanged() { controlFill.requestPaint() }
            function onFillEdgeColorChanged() { controlFill.requestPaint() }
            function onFillCenterExtentChanged() { controlFill.requestPaint() }
            function onFillWhiteRimChanged() { controlFill.requestPaint() }
            function onFillWhiteRimXChanged() { controlFill.requestPaint() }
            function onFillWhiteRimYChanged() { controlFill.requestPaint() }
            function onFillEdgeSpanYChanged() { controlFill.requestPaint() }
            function onGradientFillChanged() { controlFill.requestPaint() }
            function onWhiteEdgeDepthChanged() { controlFill.requestPaint() }
            function onWhiteEdgeAlphaChanged() { controlFill.requestPaint() }
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0) return
            const r = Math.max(0, Math.min(root.radius, width / 2, height / 2))
            ctx.beginPath()
            ctx.moveTo(r, 0)
            ctx.arcTo(width, 0, width, height, r)
            ctx.arcTo(width, height, 0, height, r)
            ctx.arcTo(0, height, 0, 0, r)
            ctx.arcTo(0, 0, width, 0, r)
            ctx.closePath()
            ctx.clip()
            if (root.gradientFill) {
                ctx.save()
                if (root.fillWhiteRimX === 0) {
                    const span = root.fillEdgeSpanY >= 0 ? Math.min(root.fillEdgeSpanY, height / 2) : -1
                    const rim = Math.min(Math.max(0, root.fillWhiteRimY), span >= 0 ? span / 2 : height / 2)
                    const fade = span >= 0 ? span - rim : Math.max(.01, (height / 2 - rim)
                        * (1 - Math.max(0, Math.min(.99, root.fillCenterExtent))))
                    const outer = rim / height
                    const inner = Math.min(.5, (rim + fade) / height)
                    const fill = ctx.createLinearGradient(0, 0, 0, height)
                    fill.addColorStop(0, root.fillEdgeColor)
                    fill.addColorStop(outer, root.fillEdgeColor)
                    fill.addColorStop(inner, root.tintColor)
                    fill.addColorStop(1 - inner, root.tintColor)
                    fill.addColorStop(1 - outer, root.fillEdgeColor)
                    fill.addColorStop(1, root.fillEdgeColor)
                    ctx.fillStyle = fill
                    ctx.globalAlpha = Math.max(0, Math.min(1, root.tintStrength))
                    ctx.fillRect(0, 0, width, height)
                } else {
                // Offset the actual rounded contour, rather than an ellipse.
                // Paint opaque bands first, then apply fill alpha once so
                // overlapping bands cannot accumulate opacity in the centre.
                function insetShape(insetX, insetY, color) {
                    const right = width - insetX
                    const bottom = height - insetY
                    const rx = Math.max(0, Math.min(r - insetX, (right - insetX) / 2))
                    const ry = Math.max(0, Math.min(r - insetY, (bottom - insetY) / 2))
                    const k = .5522847498
                    ctx.beginPath()
                    ctx.moveTo(insetX + rx, insetY)
                    ctx.lineTo(right - rx, insetY)
                    ctx.bezierCurveTo(right - rx + k * rx, insetY, right, insetY + ry - k * ry, right, insetY + ry)
                    ctx.lineTo(right, bottom - ry)
                    ctx.bezierCurveTo(right, bottom - ry + k * ry, right - rx + k * rx, bottom, right - rx, bottom)
                    ctx.lineTo(insetX + rx, bottom)
                    ctx.bezierCurveTo(insetX + rx - k * rx, bottom, insetX, bottom - ry + k * ry, insetX, bottom - ry)
                    ctx.lineTo(insetX, insetY + ry)
                    ctx.bezierCurveTo(insetX, insetY + ry - k * ry, insetX + rx - k * rx, insetY, insetX + rx, insetY)
                    ctx.closePath()
                    ctx.fillStyle = color
                    ctx.fill()
                }
                const rimX = Math.min(Math.max(0, root.fillWhiteRimX), Math.max(0, width / 2 - .01))
                const rimY = Math.min(Math.max(0, root.fillWhiteRimY), Math.max(0, height / 2 - .01))
                const available = Math.min(width / 2 - rimX, height / 2 - rimY)
                const fade = Math.max(.01, available
                    * (1 - Math.max(0, Math.min(.99, root.fillCenterExtent))))
                insetShape(0, 0, root.fillEdgeColor)
                const steps = Math.max(16, Math.ceil(fade * 8))
                for (let i = 0; i <= steps; ++i) {
                    const t = i / steps
                    const edge = root.fillEdgeColor
                    const center = root.tintColor
                    insetShape(rimX + fade * t, rimY + fade * t, Qt.rgba(
                        edge.r + (center.r - edge.r) * t,
                        edge.g + (center.g - edge.g) * t,
                        edge.b + (center.b - edge.b) * t, 1))
                }
                ctx.globalCompositeOperation = "destination-in"
                ctx.fillStyle = Qt.rgba(0, 0, 0, Math.max(0, Math.min(1, root.tintStrength)))
                ctx.fillRect(0, 0, width, height)
                }
                ctx.restore()
            }
            const depth = Math.min(root.whiteEdgeDepth, height / 2)
            if (depth > 0 && root.whiteEdgeAlpha > 0) {
                const white = Qt.rgba(1, 1, 1, root.whiteEdgeAlpha)
                const clear = Qt.rgba(1, 1, 1, 0)
                const top = ctx.createLinearGradient(0, 0, 0, depth)
                top.addColorStop(0, white); top.addColorStop(1, clear)
                ctx.fillStyle = top; ctx.fillRect(0, 0, width, depth)
                const bottom = ctx.createLinearGradient(0, height - depth, 0, height)
                bottom.addColorStop(0, clear); bottom.addColorStop(1, white)
                ctx.fillStyle = bottom; ctx.fillRect(0, height - depth, width, depth)
            }
        }
    }
    // Sample the same excluded underlay as the lens; never capture the glint
    // itself. Destroy the sampler with its provider to avoid null textures.
    Loader {
        anchors.fill: parent
        active: root.sampling
        sourceComponent: ShaderEffect {
            anchors.fill: parent
            vertexShader: Qt.resolvedUrl("shaders/liquid_highlight_tint.vert.qsb")
            fragmentShader: Qt.resolvedUrl(root.fullHighlight ? "shaders/liquid_highlight_full_extended.frag.qsb" : "shaders/liquid_highlight_topbottom_wider.frag.qsb")
            property var source: root.backdrop ? (root.backdrop.texture) : null
            property vector2d surfaceSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
            property real radius: root.radius
            property real reflectionStrength: root._reflection
            property color rimColor: root.rimColor
            property real edgeWidth: root.edgeWidth
            property vector2d sampleOrigin: root._sampleOrigin
            property vector2d sampleAxisX: root._sampleAxisX
            property vector2d sampleAxisY: root._sampleAxisY
            property color tintColor: root.adaptiveGlass ? root._adaptiveTint : root.tintColor
            property real tintStrength: root.adaptiveGlass ? .08 : root.tintStrength
            property color fallbackColor: root.darkAppearance ? "#1c1c1e" : "#ffffff"
        property real edgeShadeStrength: root.edgeShadeStrength
        property real highlightTintStrength: root.highlightTintStrength
        }
    }
    ShaderEffect {
        anchors.fill: parent
        visible: !root.adaptiveGlass && !root.sampling && GraphicsInfo.api !== GraphicsInfo.Software
        vertexShader: Qt.resolvedUrl("shaders/liquid_highlight_tint.vert.qsb")
        fragmentShader: Qt.resolvedUrl(root.fullHighlight ? "shaders/liquid_highlight_full_extended_fallback.frag.qsb" : "shaders/liquid_highlight_topbottom_wider_fallback.frag.qsb")
        property vector2d surfaceSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
        property real radius: root.radius
        property real reflectionStrength: root._reflection
        property color rimColor: root.rimColor
        property real edgeWidth: root.edgeWidth
        property vector2d sampleOrigin: Qt.vector2d(0, 0)
        property vector2d sampleAxisX: Qt.vector2d(1, 0)
        property vector2d sampleAxisY: Qt.vector2d(0, 1)
        property color tintColor: root.tintColor
        property real tintStrength: root.tintStrength
        property color fallbackColor: root.darkAppearance ? "#1c1c1e" : "#ffffff"
        property real edgeShadeStrength: root.edgeShadeStrength
        property real highlightTintStrength: root.highlightTintStrength
    }
    // Software rendering cannot run ShaderEffect. Keep a restrained, open
    // directional arc instead of restoring the former all-around outline.
    Canvas {
        id: softReflection
        anchors.fill: parent
        visible: !root.adaptiveGlass && GraphicsInfo.api === GraphicsInfo.Software
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onRadiusChanged() { softReflection.requestPaint() }
            function onReflectionStrengthChanged() { softReflection.requestPaint() }
            function onSamplingChanged() { softReflection.requestPaint() }
            function onAdaptiveGlassChanged() { softReflection.requestPaint() }
            function onRimColorChanged() { softReflection.requestPaint() }
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width < 2 || height < 2) return
            const r = Math.min(root.radius, width / 2, height / 2)
            const strength = Math.max(0, Math.min(2, root._reflection))
            const fade = ctx.createLinearGradient(0, 0, width * .72, height)
            fade.addColorStop(0, Qt.rgba(1, 1, 1, .065 * strength))
            fade.addColorStop(.45, Qt.rgba(1, 1, 1, .022 * strength))
            fade.addColorStop(.75, "transparent")
            fade.addColorStop(1, "transparent")
            ctx.beginPath()
            ctx.moveTo(r, 2)
            ctx.lineTo(width - r, 2)
            ctx.arcTo(width - 2, 2, width - 2, r, r)
            ctx.lineTo(width - 2, height - r)
            ctx.arcTo(width - 2, height - 2, width - r, height - 2, r)
            ctx.lineTo(r, height - 2)
            ctx.arcTo(2, height - 2, 2, height - r, r)
            ctx.lineTo(2, r)
            ctx.arcTo(2, 2, r, 2, r)
            ctx.strokeStyle = fade
            ctx.lineWidth = 3
            ctx.stroke()
        }
    }
}
