import QtQuick

// IslandPointerTarget — a click target that deliberately does not accept
// hover.
//
// The island keeps exactly one hover source: the surface MouseArea in
// IslandWindow, which is the ancestor of everything inside the island. QML
// hover is exclusive — the topmost item that accepts hover receives it, and
// every ancestor stops being hovered — so a plain `MouseArea { hoverEnabled:
// true }` on a button was enough to make the whole island believe the
// pointer had left it and collapse.
//
// A MouseArea accepts hover only when `hoverEnabled` is true, so this type
// leaves it false and derives the highlight from the island's own pointer
// position instead. `pressed` still comes from the real press handling, which
// is what a button needs.
MouseArea {
    id: root

    // The item whose coordinate space IslandService.pointerX/Y is expressed
    // in. The island's content root passes itself; the position is then
    // mapped into this target's space.
    property Item pointerOrigin: null

    // Read-only: hovering is derived, never reported by Qt.
    readonly property bool hovered: _containsPointer()

    function _containsPointer() {
        if (!IslandService.hovered || !pointerOrigin)
            return false
        const p = mapFromItem(pointerOrigin, IslandService.pointerX, IslandService.pointerY)
        return p.x >= 0 && p.y >= 0 && p.x <= width && p.y <= height
    }
}
