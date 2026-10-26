import QtQuick

// Light glass text sits over a soft continuous backdrop behind its text area.
// ShellText inherits Text's layout, elision and caller colours.
ShellText {
    id: root
    // Compatibility with hosts that disable the old readability outline.
    // The switch now controls the area backdrop; no glyph outline is painted.
    property bool outlineEnabled: true
    property bool shadowEnabled: outlineEnabled && AppearanceTokens.isDarkTheme
        && (color.r * 0.299 + color.g * 0.587 + color.b * 0.114 > 0.5)
    property real readabilityBackdropOpacity: 0.09
    color: AppearanceTokens.isDarkTheme ? "#ffffff" : "#000000"
    style: Text.Normal
    // Fit a rounded rectangular gradient to the text block, including padding.
    // Its opacity changes throughout the area, not just at a blurred border.
    Loader {
        id: backdrop
        z: -1
        active: root.shadowEnabled && root.text.length > 0
            && root.contentWidth > 0 && root.contentHeight > 0
        readonly property real availableWidth: Math.max(0,
            root.width - root.leftPadding - root.rightPadding)
        readonly property real availableHeight: Math.max(0,
            root.height - root.topPadding - root.bottomPadding)
        readonly property real textWidth: Math.min(availableWidth, root.contentWidth)
        readonly property real textHeight: root.contentHeight
        // Scale the inset with type size, with bounds to avoid oversized halos.
        readonly property real padX: Math.max(8, Math.min(14, root.font.pixelSize * 0.55))
        readonly property real padY: Math.max(7, Math.min(12, root.font.pixelSize * 0.45))
        x: root.leftPadding
            + (root.effectiveHorizontalAlignment === Text.AlignRight ? availableWidth - textWidth
            : root.effectiveHorizontalAlignment === Text.AlignHCenter
                ? (availableWidth - textWidth) / 2 : 0) - padX
        y: root.topPadding
            + (root.verticalAlignment === Text.AlignBottom ? availableHeight - textHeight
            : root.verticalAlignment === Text.AlignVCenter
                ? (availableHeight - textHeight) / 2 : 0) - padY
        width: textWidth + padX * 2
        height: textHeight + padY * 2
        sourceComponent: Canvas {
            readonly property real strength: Math.max(0,
                Math.min(1, root.readabilityBackdropOpacity))
            // Apply the faint strength once during scene composition. Baking
            // it into 64 tiny alpha increments can round every increment away.
            opacity: strength
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (width <= 0 || height <= 0)
                    return;

                const halfSide = Math.min(width, height) / 2;
                const outerRadius = Math.min(halfSide,
                    Math.max(12, backdrop.padY + 7));
                const steps = 64;
                let previousAlpha = 0;
                // Nested rounded contours approximate a continuous inward
                // gradient at full strength. Compensate source-over alpha;
                // the Canvas item's opacity controls the final faint backdrop.
                for (let i = 1; i < steps; ++i) {
                    const t = i / steps;
                    const inset = halfSide * t;
                    const x0 = inset;
                    const y0 = inset;
                    const x1 = width - inset;
                    const y1 = height - inset;
                    const r = Math.max(0, outerRadius - inset);
                    const alpha = t * t * (3 - 2 * t);
                    const layerAlpha = (alpha - previousAlpha)
                        / Math.max(1 - previousAlpha, 0.0001);
                    previousAlpha = alpha;
                    ctx.fillStyle = Qt.rgba(0.3, 0.3, 0.3, layerAlpha);
                    ctx.beginPath();
                    ctx.moveTo(x0 + r, y0);
                    ctx.lineTo(x1 - r, y0);
                    ctx.quadraticCurveTo(x1, y0, x1, y0 + r);
                    ctx.lineTo(x1, y1 - r);
                    ctx.quadraticCurveTo(x1, y1, x1 - r, y1);
                    ctx.lineTo(x0 + r, y1);
                    ctx.quadraticCurveTo(x0, y1, x0, y1 - r);
                    ctx.lineTo(x0, y0 + r);
                    ctx.quadraticCurveTo(x0, y0, x0 + r, y0);
                    ctx.closePath();
                    ctx.fill();
                }
            }
        }
    }
}
