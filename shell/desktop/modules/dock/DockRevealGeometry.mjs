// The default keeps the historical 14px full-edge target. The optional dockSpan
// mode uses the Dock's full-reveal rectangle in surface coordinates, never its
// animated position: a hidden Dock claims only its projected 2px edge strip.
// Once revealing, that target bridges the floating gap with a 2px Dock overlap.
export function revealHitRect({ position, windowWidth, windowHeight,
                                dockX, dockY, dockWidth, dockHeight,
                                active, expanded, triggerMode = "fullEdge" }) {
    const empty = { x: 0, y: 0, width: 0, height: 0 }
    if (!active || !["bottom", "left", "right"].includes(position)
            || ![windowWidth, windowHeight].every(Number.isFinite)
            || windowWidth <= 0 || windowHeight <= 0)
        return empty

    // Missing or unrecognised settings preserve the existing behaviour, even
    // before the Dock's own layout has a usable size.
    if (triggerMode !== "dockSpan") {
        const depth = Math.min(14, position === "bottom" ? windowHeight : windowWidth)
        return position === "bottom"
            ? { x: 0, y: windowHeight - depth, width: windowWidth, height: depth }
            : { x: position === "left" ? 0 : windowWidth - depth, y: 0,
                width: depth, height: windowHeight }
    }

    if (![dockX, dockY, dockWidth, dockHeight].every(Number.isFinite)
            || dockWidth <= 0 || dockHeight <= 0)
        return empty

    const left = Math.max(0, dockX)
    const top = Math.max(0, dockY)
    const right = Math.min(windowWidth, dockX + dockWidth)
    const bottom = Math.min(windowHeight, dockY + dockHeight)
    if (right <= left || bottom <= top)
        return empty

    const edgeThickness = 2
    if (position === "bottom") {
        const depth = Math.min(windowHeight, Math.max(edgeThickness,
            expanded ? windowHeight - bottom + edgeThickness : edgeThickness))
        return { x: left, y: windowHeight - depth,
                 width: right - left, height: depth }
    }

    const gap = position === "left" ? left : windowWidth - right
    const depth = Math.min(windowWidth, Math.max(edgeThickness,
        expanded ? gap + edgeThickness : edgeThickness))
    return { x: position === "left" ? 0 : windowWidth - depth, y: top,
             width: depth, height: bottom - top }
}
