// PanelPlacement.mjs — pure placement math for the persistent status panels.
//
// Both halves used to live inside QML expressions, which is how two
// regressions shipped without a test:
//  - a panel on a secondary output was pinned to that screen's far edge
//    (virtual-desktop centre passed into a screen-local clamp);
//  - a side-Dock panel sank below the bottom edge (missing upper clamp).
// The functions take plain numbers so test_panel_placement.mjs can drive
// them without a compositor.

// PanelPlacement for a status cell. `hostOrigin` is the screen-space origin of
// the surface that hosts the cell (Bar or Dock window). The returned `offset`
// and `center` are screen-local, because PersistentPanelWindow consumes them
// against the output origin and clamps them to the output size.
export function panelPlacement({
    edge = "top",
    screenX = 0,
    screenY = 0,
    screenWidth = 0,
    screenHeight = 0,
    hostOrigin = { x: 0, y: 0 },
    hasAnchor = false,
    anchorX = 0,
    anchorY = 0,
    anchorWidth = 0,
    anchorHeight = 0,
    dockRect = null,
    gap = 4,
}) {
    const gx = hostOrigin.x + anchorX;
    const gy = hostOrigin.y + anchorY;
    // A null anchor (hidden or unresolvable cell) must still open the panel
    // somewhere sane: center it on the dock artwork, or the screen when there
    // is no dock rect, instead of collapsing the center onto the output origin.
    const centerH = hasAnchor ? gx + anchorWidth / 2
        : (dockRect ? dockRect.x + dockRect.width / 2 : screenX + screenWidth / 2);
    const centerV = hasAnchor ? gy + anchorHeight / 2
        : (dockRect ? dockRect.y + dockRect.height / 2 : screenY + screenHeight / 2);
    if (edge === "top") {
        // The offset measures from the dock artwork itself, not from the
        // anchor cell: the cell sits well inside the glass, so a cell-based
        // offset sinks the panel into the dock.
        const near = dockRect ? dockRect.y + dockRect.height : gy + anchorHeight;
        return { edge, offset: near + gap - screenY, center: centerH - screenX };
    }
    if (edge === "bottom") {
        const near = dockRect ? dockRect.y : gy;
        return { edge, offset: screenY + screenHeight - near + gap, center: centerH - screenX };
    }
    if (edge === "left") {
        const near = dockRect ? dockRect.x + dockRect.width : gx + anchorWidth;
        return { edge, offset: near + gap - screenX, center: centerV - screenY };
    }
    const near = dockRect ? dockRect.x : gx;
    return { edge, offset: screenX + screenWidth - near + gap, center: centerV - screenY };
}

// The along-edge margin PersistentPanelWindow uses for a panel centred on the
// anchor cell: keep it inside [edgeMargin, screenSize - size - edgeMargin] on
// both ends. Both ends matter — the horizontal branch always clamped, the
// vertical one did not, and a side-Dock panel ran off the bottom of the
// screen ("sunken, truncated").
export function clampedCenterOffset({ center, size, screenSize, edgeMargin }) {
    const centered = Math.round(center - size / 2);
    return Math.max(edgeMargin, Math.min(centered, screenSize - size - edgeMargin));
}
