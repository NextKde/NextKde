// Input geometry uses the Dock's full-reveal rectangle in surface coordinates,
// never its animated position. Hidden docks only claim their projection onto
// a 2px screen-edge strip. Once revealing, the same target bridges the floating
// gap and overlaps the Dock by 2px so pointer travel cannot release the hold.
export function revealHitRect({ position, windowWidth, windowHeight,
                                dockX, dockY, dockWidth, dockHeight,
                                active, expanded }) {
    const empty = { x: 0, y: 0, width: 0, height: 0 }
    if (!active || !["bottom", "left", "right"].includes(position)
            || ![windowWidth, windowHeight, dockX, dockY, dockWidth, dockHeight]
                .every(Number.isFinite)
            || windowWidth <= 0 || windowHeight <= 0
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
