import Quickshell
import QtQuick

// A reusable blur-region mask for a rounded rectangle. Wayland regions are
// rectangular primitives, so this combines two rectangles and four ellipses.
// Use it as: BackgroundEffect.blurRegion: RoundedBlurRegion { item: target }
Region {
    id: root

    required property Item item
    // Most callers use a direct child of their window, but control-center
    // cards can live several Row/Column levels down. Map those cards into the
    // window's coordinate space before publishing the compositor blur region.
    // Leaving this null preserves the original direct-child behavior.
    property Item coordinateSpace: null
    property real radius: Math.min(item.width, item.height) / 2

    readonly property point itemPosition: coordinateSpace ? item.mapToItem(coordinateSpace, 0, 0) : Qt.point(item.x, item.y)
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
