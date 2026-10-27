import QtQuick
import qs.desktop.modules.common

// IslandAppTile — one pinned application on the island's quick-launch shelf.
//
// The reference looks like a book standing on a shelf: a rounded plate with a
// second, darker plate peeking out behind its lower-right edge and a contact
// shadow at its base. That is what makes it read as an object with an edge
// rather than a picture pasted onto the panel, and it is the part the earlier
// flat port was missing.
//
// The artwork sits in an inset well rather than bleeding to the plate's edge.
// An Image cannot be clipped to a rounded shape, and the only way to make the
// artwork itself rounded is a layer effect over it -- which renders *nothing*
// if the shader fails to compile. A blank tile is exactly the failure this
// port has been chasing, so the artwork keeps painting directly and the
// plate's own outline provides the frame.
//
// Every visual state is a plain property so the island's content layer can
// drive it from its single pointer source. Nothing here accepts hover or
// takes a press: the content layer owns both, which keeps the island's
// hover alive while the pointer is on a tile.
IslandCard {
    id: root

    required property string desktopId
    required property string appName

    // Resolved by IslandQuickLaunchModel (AppPresentationService.iconSource),
    // never the raw desktop-entry icon name: an unresolved name is a relative
    // URL to Qt, the load fails, and the tile is left showing nothing but its
    // own plate -- the "black box" the island used to draw.
    required property string iconSource

    property bool hovered: false
    property bool dragging: false

    // When this is a file shortcut, the tile grows a small grip that starts a
    // real platform drag, so the file can be dropped into another
    // application. The island's own pointer model only ever reorders things
    // inside the island -- it does not talk to the compositor's drag session
    // at all -- so this needs a genuine Drag, on a target of its own so it
    // cannot be confused with the tile's reorder.
    property string dragOutUri: ""
    property bool dragOutEnabled: false

    // Defaults for a standalone use; the island's delegate overrides both
    // with the scaled metrics, and everything inside is a fraction of the
    // plate so a tile looks the same at any panel size.
    width: 92
    height: 92
    cornerRadius: Math.round(width * 0.24)
    depth: 1.0
    // 0.07, not 0.05: on the near-black panel 0.05 was within 1.03:1 of
    // the plate, so neither the plate nor the well read as an edge.
    bodyColor: Qt.rgba(1, 1, 1, 0.07)
    bodyBorderColor: dragging ? Qt.rgba(0.29, 0.87, 0.5, 0.40)
        : (hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10))

    lift: dragging ? 1.0 : (hovered ? 0.5 : 0)

    // --- The well ---------------------------------------------------------
    // Darker than the plate and inset, with the light catching only its
    // bottom edge: a hole in the plate, not a second panel on it.
    Rectangle {
        id: well
        anchors.centerIn: parent
        width: Math.round(root.width * 0.89)
        height: width
        radius: Math.round(width * 0.26)
        color: Qt.rgba(0, 0, 0, 0.30)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.42)

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 1 }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        AppIcon {
            anchors.centerIn: parent
            width: Math.round(root.width * 0.76)
            height: width
            // Belt and braces: the model already resolves the icon and falls
            // back to the generic one, but a tile that somehow arrives without
            // a source must still show an icon rather than an empty plate.
            source: root.iconSource.length > 0
                ? root.iconSource
                : AppPresentationService.genericIconSource()
            smooth: true
        }
    }

    // --- The drag-out grip ------------------------------------------------
    // A file shortcut can be dragged out of the island and dropped into any
    // application. The grip is a separate target: pressing the tile still
    // picks it up for reordering, pressing the grip starts a platform drag.
    Item {
        id: grip
        anchors { right: parent.right; bottom: parent.bottom; margins: 2 }
        width: 16
        height: 16
        visible: root.dragOutEnabled && root.dragOutUri.length > 0
        z: 50

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.45)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }

        // Three dots: the grip reads as "there is something to grab here".
        Row {
            anchors.centerIn: parent
            spacing: 1.5

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 2
                    height: 2
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.6)
                    y: (index - 1) * 2.5
                }
            }
        }

        DragHandler {
            id: gripDrag
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromAnything
        }

        Drag {
            id: gripDragOut
            active: gripDrag.active
            dragType: Drag.Automatic
            keys: ["text/uri-list"]
            mimeData: ({ "text/uri-list": root.dragOutUri })
        }
    }
}
