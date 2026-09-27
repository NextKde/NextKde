import QtQuick
import QtQml.Models

QtObject {
    id: root

    required property Item item
    property rect rect: Qt.rect(0, 0, 0, 0)
    property var sources: []

    function update() {
        rect = item ? item.mapToItem(null, Qt.rect(0, 0, item.width, item.height))
            : Qt.rect(0, 0, 0, 0)
    }

    function rebuild() {
        const nextSources = []
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            nextSources.push(ancestor)
            for (let index = 0; index < ancestor.transform.length; ++index)
                nextSources.push(ancestor.transform[index])
        }
        sources = nextSources
        update()
    }

    onItemChanged: rebuild()
    Component.onCompleted: rebuild()

    property Instantiator watchers: Instantiator {
        model: root.sources
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            function onXChanged() { root.update() }
            function onYChanged() { root.update() }
            function onWidthChanged() { root.update() }
            function onHeightChanged() { root.update() }
            function onScaleChanged() { root.update() }
            function onRotationChanged() { root.update() }
            function onTransformOriginChanged() { root.update() }
            function onOriginChanged() { root.update() }
            function onXScaleChanged() { root.update() }
            function onYScaleChanged() { root.update() }
            function onAngleChanged() { root.update() }
            function onParentChanged() { Qt.callLater(root.rebuild) }
        }
    }
}
