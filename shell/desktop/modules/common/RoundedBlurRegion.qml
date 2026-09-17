import Quickshell
import QtQuick

// A reusable blur-region mask for a rounded rectangle. Wayland regions are
// rectangular primitives, so this combines two rectangles and four ellipses.
// Use it as: BackgroundEffect.blurRegion: RoundedBlurRegion { item: target }
Region {
    id: root

    required property Item item
    // Reads the item's x/y as surface coordinates. A panel nested inside a
    // positioned wrapper reports 0 here, so callers point `item` at that
    // wrapper (LiquidGlassPanel's blurAnchor) instead of at the panel itself.
    property real radius: Math.min(item.width, item.height) / 2

    readonly property point itemPosition: Qt.point(item.x, item.y)
    readonly property int roundedRadius: Math.max(0, Math.min(Math.round(radius), Math.floor(Math.min(item.width, item.height) / 2)))

    // Vertical center of the rounded rectangle.
    x: Math.round(itemPosition.x + roundedRadius)
    y: Math.round(itemPosition.y)
    width: Math.max(0, Math.round(item.width - roundedRadius * 2))
    height: Math.round(item.height)

    // Horizontal center.
    Region {
        x: Math.round(root.itemPosition.x)
        y: Math.round(root.itemPosition.y + root.roundedRadius)
        width: Math.round(root.item.width)
        height: Math.max(0, Math.round(root.item.height - root.roundedRadius * 2))
    }

    // The corners complete the rounded outline.
    Region {
        x: Math.round(root.itemPosition.x)
        y: Math.round(root.itemPosition.y)
        width: root.roundedRadius * 2
        height: root.roundedRadius * 2
        shape: RegionShape.Ellipse
    }
    Region {
        x: Math.round(root.itemPosition.x + root.item.width - root.roundedRadius * 2)
        y: Math.round(root.itemPosition.y)
        width: root.roundedRadius * 2
        height: root.roundedRadius * 2
        shape: RegionShape.Ellipse
    }
    Region {
        x: Math.round(root.itemPosition.x)
        y: Math.round(root.itemPosition.y + root.item.height - root.roundedRadius * 2)
        width: root.roundedRadius * 2
        height: root.roundedRadius * 2
        shape: RegionShape.Ellipse
    }
    Region {
        x: Math.round(root.itemPosition.x + root.item.width - root.roundedRadius * 2)
        y: Math.round(root.itemPosition.y + root.item.height - root.roundedRadius * 2)
        width: root.roundedRadius * 2
        height: root.roundedRadius * 2
        shape: RegionShape.Ellipse
    }
}
