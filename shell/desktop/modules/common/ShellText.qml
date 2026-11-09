import QtQuick

// Match the platform's small-text rasterization once motion settles. Keep
// distance fields during scale/rotation, including motion on a parent item.
Text {
    id: root

    // Hosts using a Scale/Rotation in their transform list can opt in too.
    property bool scalableRendering: false
    readonly property bool transformed: {
        let item = root;
        while (item) {
            if (item.scale !== 1 || item.rotation !== 0)
                return true;
            item = item.parent;
        }
        return false;
    }

    renderType: scalableRendering || transformed
        ? Text.QtRendering : Text.NativeRendering
}
