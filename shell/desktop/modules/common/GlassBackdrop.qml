pragma Singleton
import QtQuick

// Host-declared in-scene backdrop for the QML glass fallback. The item is
// usually a hidden copy of the scene backdrop: LiquidGlassSurface captures
// it with hideSource, so it never paints but still feeds every surface.
// Null keeps every existing surface on its previous path.
QtObject {
    property Item sourceItem: null
}
