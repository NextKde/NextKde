import QtQuick
import qs.desktop.modules.common
import "../../../shared/qml/i18n"

// UI-only layout: candidate order and selection indices remain engine-owned.
Item {
    id: root
    property var candidates: []
    property int cursorIndex: -1
    property int engineLayout: 0
    property string layoutPreference: "engine"
    property int fontSize: 15
    property bool showAnnotations: true
    property bool highContrast: false
    property bool reduceMotion: false
    property bool dark: false
    property color foreground: "#202020"
    property color secondary: "#606060"
    property real maximumWidth: 800
    property real maximumHeight: 400
    property bool hasPrev: false
    property bool hasNext: false
    signal candidateSelected(int candidateIndex)
    signal previousPage()
    signal nextPage()

    // Measure the same delegates in either orientation; adaptive layout does
    // not need a second hidden set of text items and readability backdrops.
    property var candidateGeometry: ({positions: [], width: 0, height: 0, maxWidth: 0, maxHeight: 0})
    // Measure after text and delegate bindings settle. Publishing geometry from
    // inside their evaluation feeds layout changes back into the same binding.
    function updateCandidateGeometry() {
        const positions = []
        let width = 0, height = 0, maxWidth = 0, maxHeight = 0
        for (let i = 0; i < candidateItems.count; ++i) {
            const item = candidateItems.itemAt(i)
            positions.push({ x: width, y: height })
            if (item) {
                width += item.implicitWidth + 8
                height += item.implicitHeight + 4
                maxWidth = Math.max(maxWidth, item.implicitWidth)
                maxHeight = Math.max(maxHeight, item.implicitHeight)
            }
        }
        candidateGeometry = { positions: positions, width: Math.max(0, width - 8),
            height: Math.max(0, height - 4), maxWidth: maxWidth, maxHeight: maxHeight }
    }
    readonly property real horizontalWidth: candidateGeometry.width
    readonly property bool isVertical: layoutPreference === "vertical"
        || (layoutPreference === "engine" && engineLayout === 1)
        || (layoutPreference === "adaptive" && horizontalWidth
            > maximumWidth - (paging.visible ? paging.implicitWidth + 6 : 0))
    readonly property real naturalWidth: isVertical ? candidateGeometry.maxWidth : candidateGeometry.width
    readonly property real naturalHeight: isVertical ? candidateGeometry.height : candidateGeometry.maxHeight
    readonly property real pagerWidth: paging.visible && !isVertical ? paging.implicitWidth + 6 : 0
    readonly property real footerHeight: paging.visible && isVertical ? paging.height + 4 : 0
    implicitWidth: Math.min(Math.max(1, maximumWidth), Math.max(80, naturalWidth + pagerWidth, paging.implicitWidth))
    implicitHeight: Math.min(Math.max(1, maximumHeight), Math.max(naturalHeight + footerHeight, paging.visible ? paging.height : 0))

    property rect _selectionRect: Qt.rect(0, 0, 0, 0)
    property bool _selectionVisible: false
    property bool _selectionReady: false

    function scrollSelection(horizontal, position) {
        const animation = horizontal ? horizontalScroll : verticalScroll
        const current = horizontal ? viewport.contentX : viewport.contentY
        if (animation.running && Math.abs(animation.to - position) < 0.5) return
        animation.stop()
        if (Math.abs(current - position) < 0.5) return
        if (reduceMotion || !_selectionReady) {
            if (horizontal) viewport.contentX = position
            else viewport.contentY = position
        } else {
            animation.from = current
            animation.to = position
            animation.start()
        }
    }

    function revealSelection() {
        const item = candidateItems.itemAt(cursorIndex)
        if (!item) { _selectionVisible = false; viewport.returnToBounds(); return }
        _selectionRect = Qt.rect(item.x, item.y, item.width, item.height)
        _selectionVisible = true
        if (isVertical) {
            if (item.y < viewport.contentY) scrollSelection(false, item.y)
            else if (item.y + item.height > viewport.contentY + viewport.height)
                scrollSelection(false, item.y + item.height - viewport.height)
            else scrollSelection(false, viewport.contentY)
        } else {
            if (item.x < viewport.contentX) scrollSelection(true, item.x)
            else if (item.x + item.width > viewport.contentX + viewport.width)
                scrollSelection(true, item.x + item.width - viewport.width)
            else scrollSelection(true, viewport.contentX)
        }
        _selectionReady = true
    }
    onCursorIndexChanged: Qt.callLater(revealSelection)
    onCandidatesChanged: Qt.callLater(revealSelection)
    onCandidateGeometryChanged: Qt.callLater(revealSelection)
    onNaturalWidthChanged: Qt.callLater(revealSelection)
    onNaturalHeightChanged: Qt.callLater(revealSelection)
    onIsVerticalChanged: {
        horizontalScroll.stop()
        verticalScroll.stop()
        _selectionReady = false
        viewport.contentX = 0
        viewport.contentY = 0
        Qt.callLater(revealSelection)
    }

    NumberAnimation {
        id: horizontalScroll
        target: viewport
        property: "contentX"
        duration: 160
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: verticalScroll
        target: viewport
        property: "contentY"
        duration: 160
        easing.type: Easing.OutCubic
    }

    Flickable {
        id: viewport
        objectName: "candidateViewport"
        width: Math.max(1, root.width - root.pagerWidth)
        height: Math.max(1, root.height - root.footerHeight)
        contentWidth: root.naturalWidth
        contentHeight: root.naturalHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: root.isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        onWidthChanged: Qt.callLater(root.revealSelection)
        onHeightChanged: Qt.callLater(root.revealSelection)
        onDraggingChanged: if (dragging) { horizontalScroll.stop(); verticalScroll.stop() }
        onFlickStarted: { horizontalScroll.stop(); verticalScroll.stop() }

        // One plate follows selection across stable text instead of fading a
        // separate background into every delegate. Candidate activation is immediate.
        Rectangle {
            objectName: "candidateSelection"
            x: root._selectionRect.x
            y: root._selectionRect.y
            width: root._selectionRect.width
            height: root._selectionRect.height
            radius: 7
            color: root.highContrast ? (root.dark ? "#ffffff" : "#202020")
                : (root.dark ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.09))
            opacity: root._selectionVisible ? 1 : 0
            Behavior on x { enabled: !root.reduceMotion && root._selectionReady; SmoothedAnimation { duration: 150; velocity: -1 } }
            Behavior on y { enabled: !root.reduceMotion && root._selectionReady; SmoothedAnimation { duration: 150; velocity: -1 } }
            Behavior on width { enabled: !root.reduceMotion && root._selectionReady; SmoothedAnimation { duration: 150; velocity: -1 } }
            Behavior on height { enabled: !root.reduceMotion && root._selectionReady; SmoothedAnimation { duration: 150; velocity: -1 } }
            Behavior on opacity { enabled: !root.reduceMotion; NumberAnimation { duration: 90 } }
        }
        Repeater {
            id: candidateItems
            // A numeric model preserves existing items while their text changes.
            model: root.candidates.length
            delegate: candidateDelegate
            onItemAdded: Qt.callLater(root.updateCandidateGeometry)
            onItemRemoved: Qt.callLater(root.updateCandidateGeometry)
        }
    }

    Component {
        id: candidateDelegate
        Item {
            id: entry
            required property int index
            readonly property var modelData: root.candidates[index] || ({})
            readonly property var position: root.candidateGeometry.positions[index]
            x: root.isVertical ? 0 : (position?.x || 0)
            y: root.isVertical ? (position?.y || 0) : 0
            onImplicitWidthChanged: Qt.callLater(root.updateCandidateGeometry)
            onImplicitHeightChanged: Qt.callLater(root.updateCandidateGeometry)
            readonly property bool selected: index === root.cursorIndex
            readonly property string annotation: root.showAnnotations ? String(modelData.comment || "") : ""
            readonly property real labelWidth: label.implicitWidth
            readonly property real annotationWidth: annotation ? Math.min(comment.implicitWidth, root.maximumWidth * 0.3) : 0
            implicitWidth: Math.min(root.maximumWidth, labelWidth + word.implicitWidth + annotationWidth + (annotation ? 28 : 22))
            implicitHeight: Math.max(label.implicitHeight, word.implicitHeight, comment.implicitHeight) + 8
            width: implicitWidth
            height: implicitHeight
            objectName: (root.isVertical ? "verticalCandidate-" : "horizontalCandidate-") + index
            Accessible.role: Accessible.Button
            Accessible.name: String(modelData.text || "") + (annotation ? " " + annotation : "")
            Accessible.onPressAction: root.candidateSelected(index)
            Rectangle {
                anchors.fill: parent
                radius: 7
                color: mouse.containsMouse && !entry.selected
                    ? (root.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.05)) : "transparent"
                Behavior on color { enabled: !root.reduceMotion; ColorAnimation { duration: 100 } }
            }
            readonly property color ink: root.highContrast && selected
                ? (root.dark ? "#000000" : "#ffffff") : root.foreground
            Row {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                GlassText {
                    id: label
                    text: String(entry.modelData.label || (entry.index + 1) + ".")
                    textFormat: Text.PlainText
                    font.pixelSize: root.fontSize - 2
                    color: root.highContrast ? entry.ink : root.secondary
                    anchors.verticalCenter: parent.verticalCenter
                }
                GlassText {
                    id: word
                    objectName: "candidateWord"
                    width: Math.max(1, entry.width - entry.labelWidth - entry.annotationWidth - (entry.annotation ? 28 : 22))
                    text: String(entry.modelData.text || "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: root.fontSize
                    // Keep glyph widths stable while the selection plate moves.
                    font.weight: Font.Medium
                    color: entry.ink
                    anchors.verticalCenter: parent.verticalCenter
                }
                GlassText {
                    id: comment
                    objectName: "candidateAnnotation"
                    visible: entry.annotation.length > 0
                    width: entry.annotationWidth
                    text: entry.annotation
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: root.fontSize - 3
                    color: root.highContrast ? entry.ink : root.secondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.candidateSelected(entry.index)
            }
        }
    }

    Row {
        id: paging
        visible: root.hasPrev || root.hasNext
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 6
        Repeater {
            model: ["‹", "›"]
            delegate: Item {
                required property int index
                required property string modelData
                width: 28
                height: Math.max(24, root.fontSize + 8)
                enabled: index === 0 ? root.hasPrev : root.hasNext
                opacity: enabled ? 1 : 0.35
                Accessible.role: Accessible.Button
                Accessible.name: index === 0 ? I18n.tr("Previous page") : I18n.tr("Next page")
                Accessible.onPressAction: if (index === 0) root.previousPage(); else root.nextPage()
                GlassText { anchors.centerIn: parent; text: modelData; font.pixelSize: root.fontSize; color: root.foreground }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (parent.index === 0) root.previousPage(); else root.nextPage()
                }
            }
        }
    }
}
