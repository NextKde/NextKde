import QtQuick
import QtQuick.Controls
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.notifications
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"
import "../../../Kos/Ui"

// A deck of independent cards, not a glass panel containing ordinary rows.
// One stable model preserves the first three delegates while the viewport
// unfolds. Older rows append on expansion and retire after the closing fade.
Item {
    id: pane
    objectName: "notification-history-pane"
    property Item captureAnchor: null
    property Item outerViewport: null
    property bool compositorGlass: AppearanceTokens.surface.usesKwinBlur
    // Standalone history can show an empty state; embedded controls hide it.
    property bool showEmptyState: true
    property real backdropScale: 1
    property real glassOpacity: 1
    property real maximumHeight: 560
    property bool expanded: false
    property bool active: visible
    property bool folding: false
    property real revealProgress: expanded ? 1 : 0
    property real clockNow: Date.now()
    readonly property color ink: AppearanceTokens.content.glassInk()
    readonly property int displayedMessageCount: expanded ? NotificationHistoryService.count : Math.min(3, NotificationHistoryService.count)
    readonly property real previewRowsHeight: {
        const children = historyList.contentItem.children
        let result = 0
        for (let i = 0; i < Math.min(3, NotificationHistoryService.count); ++i) {
            const cell = children.find(child => child.notificationCell && child.index === i && !child.exiting)
            result += cell ? cell.height : 120
        }
        return result
    }
    readonly property real previewHeight: Math.min(maximumHeight,
        NotificationHistoryService.count ? 36 + previewRowsHeight + (NotificationHistoryService.count > 3 ? 52 : 8) : 104)
    readonly property real expandedHeight: Math.min(maximumHeight, Math.max(previewHeight,
        36 + NotificationHistoryService.count * 120 + 40))
    property real removalHeight: 0
    readonly property real desiredHeight: !historyEmptyReady && NotificationHistoryService.count === 0
        ? removalHeight : expanded ? expandedHeight : previewHeight
    readonly property var paintedCards: historyList.contentItem.children
        .filter(child => child.notificationCell && child.cardItem && child.cardItem.backdropVisible)
        .map(child => child.cardItem)
    readonly property alias blurRegion: glassRegions
    property int historyExitCount: 0
    property bool historyEmptyReady: true
    // Once the last delegate retires, fade a fixed-size empty card while the
    // deck contracts. Waiting for both animations leaves a conspicuous gap.
    readonly property bool emptyStateReady: showEmptyState && NotificationHistoryService.count === 0
        && historyEmptyReady && historyExitCount === 0
    property var historyClearDelays: ({})
    property SceneBounds listBounds: SceneBounds { item: historyList }
    property SceneBounds outerBounds: SceneBounds { item: pane.outerViewport }
    readonly property rect visibleListRect: {
        const rect = listBounds.rect
        if (!outerViewport) return rect
        const outer = outerBounds.rect
        const x = Math.max(rect.x, outer.x), y = Math.max(rect.y, outer.y)
        return Qt.rect(x, y, Math.max(0, Math.min(rect.x + rect.width, outer.x + outer.width) - x),
            Math.max(0, Math.min(rect.y + rect.height, outer.y + outer.height) - y))
    }
    property var detailStates: ({})
    function setDetails(key, value) {
        const next = Object.assign({}, detailStates)
        if (value) next[key] = true
        else delete next[key]
        detailStates = next
    }
    property bool modelReady: false
    ListModel { id: displayedRows }
    function reconcileRows() {
        if (!modelReady) return
        const keepOlder = expanded || revealProgress > 0.001
        const source = NotificationHistoryService.history
        const allKeys = new Set()
        for (let i = 0; i < source.count; ++i) allKeys.add(String(source.get(i).historyKey))
        const nextDetails = ({})
        let pruned = false
        for (const key of Object.keys(detailStates)) {
            if (allKeys.has(key)) nextDetails[key] = true
            else pruned = true
        }
        if (pruned) detailStates = nextDetails
        const count = keepOlder ? source.count : Math.min(3, source.count)
        const desired = []
        for (let i = 0; i < count; ++i) {
            const row = source.get(i)
            desired.push({historyKey:row.historyKey, appName:row.appName, appIcon:row.appIcon,
                desktopEntry:row.desktopEntry, summary:row.summary, body:row.body, timestamp:row.timestamp})
        }
        const keys = new Set(desired.map(row => row.historyKey))
        for (let i = displayedRows.count - 1; i >= 0; --i)
            if (!keys.has(displayedRows.get(i).historyKey)) displayedRows.remove(i)
        for (let i = 0; i < desired.length; ++i) {
            let found = -1
            for (let j = i; j < displayedRows.count; ++j)
                if (displayedRows.get(j).historyKey === desired[i].historyKey) { found = j; break }
            if (found < 0) displayedRows.insert(i, desired[i])
            else {
                if (found !== i) displayedRows.move(found, i, 1)
                displayedRows.set(i, desired[i])
            }
        }
    }
    Component.onCompleted: { modelReady = true; reconcileRows() }
    Connections {
        target: NotificationHistoryService
        function onHistoryUpdated() {
            if (NotificationHistoryService.count === 0 && (pane.expanded || pane.folding)) {
                pane.reset()
            }
            pane.reconcileRows()
        }
    }
    onExpandedChanged: reconcileRows()
    onRevealProgressChanged: if (!expanded && revealProgress <= 0.001) reconcileRows()

    function reset() {
        scrollHome.stop(); folding = false; expanded = false
        historyList.cancelFlick(); historyList.positionViewAtBeginning()
    }
    function requestExpanded(value) {
        historyList.cancelFlick()
        if (value) { scrollHome.stop(); folding = false; expanded = true; return }
        if (historyList.contentY > historyList.originY + 1) {
            folding = true
            scrollHome.to = historyList.originY
            scrollHome.restart()
        } else expanded = false
    }
    function beginHistoryExit() { historyExitCount++ }
    function endHistoryExit() {
        historyExitCount = Math.max(0, historyExitCount - 1)
        if (historyExitCount === 0 && !emptySettlement.running) historyEmptyReady = true
    }
    function historyGroupVisible(item) {
        return active && item.y + item.height > historyList.contentY
            && item.y < historyList.contentY + historyList.height
    }
    function historyExitDelay(source) { return historyClearDelays[source] || 0 }
    function prepareHistoryRemoval() {
        removalHeight = height; historyEmptyReady = false; emptySettlement.restart()
    }
    function clearHistory() {
        const delays = ({})
        let index = 0
        for (const item of historyList.contentItem.children)
            if (item.notificationCell && historyGroupVisible(item)) delays[item.historyKey] = Math.min(96, index++ * 18)
        historyClearDelays = delays
        prepareHistoryRemoval()
        NotificationHistoryService.removeKeys(NotificationHistoryService.allKeys())
        AppNotificationService.clearAll()
        reset()
    }
    // Defer until ListView has registered removals. Visible delegates release
    // the layout themselves; an offscreen removal has no exit to wait for.
    Timer { id: emptySettlement; interval: 0; onTriggered: if (pane.historyExitCount === 0) pane.historyEmptyReady = true }
    Timer { interval: 60000; repeat: true; running: pane.active; onTriggered: pane.clockNow = Date.now() }
    Behavior on height {
        enabled: pane.active && pane.glassOpacity > 0.999 && !AppTheme.reduceMotion
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }
    Behavior on revealProgress {
        NumberAnimation { duration: AppTheme.reduceMotion ? 0 : 300; easing.type: Easing.OutCubic }
    }
    NumberAnimation {
        id: scrollHome
        target: historyList; property: "contentY"
        duration: AppTheme.reduceMotion ? 0 : 220
        easing.type: Easing.OutCubic
        onFinished: { historyList.positionViewAtBeginning(); pane.folding = false; pane.expanded = false }
    }
    onActiveChanged: if (!active) { historyList.cancelFlick(); scrollHome.stop(); folding = false }
    Region {
        id: glassRegions
        regions: pane.paintedCards.map(card => card.blurRegion).filter(region => region !== null)
            .concat(footerButton.visible && footerButton.backdropVisible && footerButton.blurRegion ? [footerButton.blurRegion] : [])
            .concat(emptyGlass.visible && emptyGlass.blurRegion ? [emptyGlass.blurRegion] : [])
    }
    component DeckButton: AbstractButton {
        id: button
        property bool glassButton: false
        property SceneBounds sceneBounds: SceneBounds { item: button }
        readonly property rect clipped: {
            const b = sceneBounds.rect
            if (!pane.outerViewport || b.width <= 0 || b.height <= 0) return Qt.rect(0, 0, width, height)
            const v = pane.outerBounds.rect
            const left = Math.max(b.x, v.x), top = Math.max(b.y, v.y)
            return Qt.rect((left - b.x) * width / b.width, (top - b.y) * height / b.height,
                Math.max(0, Math.min(b.x + b.width, v.x + v.width) - left) * width / b.width,
                Math.max(0, Math.min(b.y + b.height, v.y + v.height) - top) * height / b.height)
        }
        readonly property bool backdropVisible: clipped.width > 0 && clipped.height > 0
        readonly property alias blurRegion: buttonGlass.blurRegion
        implicitWidth: label.implicitWidth + 28
        implicitHeight: 32
        activeFocusOnTab: backdropVisible
        Accessible.name: text
        Item { id: buttonPlate; x: button.clipped.x; y: button.clipped.y; width: button.clipped.width; height: button.clipped.height }
        background: Item {
            ControlCenterGlass {
                id: buttonGlass
                anchors.fill: parent
                visible: button.glassButton && button.backdropVisible
                radius: 16
                useKwinEffect: pane.compositorGlass
                captureAnchor: pane.captureAnchor
                blurAnchor: buttonPlate
                backdropScale: pane.backdropScale
                backdropRadius: Math.min(radius, buttonPlate.height / 2, buttonPlate.width / 2)
                scrimOpacity: pane.glassOpacity
                materialOpacity: pane.glassOpacity
            }
            Rectangle {
                anchors.fill: parent; radius: height / 2
                color: pane.ink
                opacity: button.down ? 0.14 : button.hovered || button.activeFocus ? 0.09 : button.glassButton ? 0 : 0.06
                border.width: button.activeFocus ? 1 : 0
                border.color: pane.ink
            }
        }
        contentItem: GlassText {
            id: label
            text: button.text; color: pane.ink
            opacity: button.enabled ? 1 : 0.35
            font { pixelSize: 11; weight: Font.Medium }
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
    GlassText {
        x: 2; y: 7
        text: I18n.tr("Notifications")
        color: pane.ink
        font { pixelSize: 16; weight: Font.DemiBold }
    }
    GlassText {
        x: 44; y: 10
        text: NotificationHistoryService.count || ""
        color: pane.ink; opacity: 0.85
        font.pixelSize: 11
    }
    DeckButton {
        anchors { right: parent.right; top: parent.top; topMargin: 1 }
        text: "×"
        implicitWidth: 30; implicitHeight: 30
        enabled: NotificationHistoryService.count > 0
        Accessible.name: I18n.tr("Clear all notifications")
        onClicked: pane.clearHistory()
        ToolTip.visible: hovered
        ToolTip.text: I18n.tr("Clear all")
    }
    ListView {
        id: historyList
        objectName: "notification-history-list"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top
            topMargin: 36; bottomMargin: pane.expanded || NotificationHistoryService.count <= 3 ? 0 : 12 * (1 - pane.revealProgress) }
        clip: true
        spacing: 0
        cacheBuffer: pane.expanded ? 112 : 600
        activeFocusOnTab: pane.visibleListRect.height > 0
        Accessible.name: I18n.tr("Notification list")
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 2200
        model: displayedRows
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 3 }
        displaced: Transition { NumberAnimation { property: "y"; duration: 240; easing.type: Easing.OutCubic } }
        add: Transition {
            // The popup supplies its entrance fade. Only later arrivals need one.
            enabled: pane.active && pane.glassOpacity > 0.999 && !AppTheme.reduceMotion
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
        }
        delegate: Item {
            id: cell
            required property int index
            required property int historyKey
            required property string appName
            required property string appIcon
            required property string desktopEntry
            required property string summary
            required property string body
            required property real timestamp
            readonly property bool notificationCell: true
            readonly property bool revealed: true
            readonly property var cardItem: cardLoader.item
            property bool exiting: false
            property bool registeredExit: false
            property real frozenHeight: 0
            property var painted: ({key:historyKey, appName:appName, appIcon:appIcon, desktopEntry:desktopEntry,
                summary:summary, body:body, timestamp:timestamp})
            width: historyList.width
            height: exiting ? frozenHeight : (cardItem ? cardItem.height : 112) + 8
            enabled: !exiting && revealed
            ListView.onRemove: {
                painted = {key:historyKey, appName:appName, appIcon:appIcon, desktopEntry:desktopEntry,
                    summary:summary, body:body, timestamp:timestamp}
                frozenHeight = height
                exiting = true
                if (pane.historyGroupVisible(cell) && frozenHeight > 0) {
                    registeredExit = true; pane.beginHistoryExit()
                    ListView.delayRemove = true; exitMotion.start()
                }
            }
            function releaseExit() { if (registeredExit) pane.endHistoryExit(); registeredExit = false }
            Component.onDestruction: releaseExit()
            SequentialAnimation {
                id: exitMotion
                PauseAnimation { duration: pane.historyClearDelays[cell.painted.key] || 0 }
                ParallelAnimation {
                    NumberAnimation { target: cell; property: "x"; to: 18; duration: 180; easing.type: Easing.InCubic }
                    NumberAnimation { target: cell; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
                }
                onFinished: { cell.releaseExit(); cell.ListView.delayRemove = false }
            }
            Loader {
                id: cardLoader
                width: parent.width
                active: cell.revealed || cell.exiting
                sourceComponent: NotificationHistoryCard {
                    width: cardLoader.width
                    historyKey: cell.painted.key
                    appName: cell.painted.appName; appIcon: cell.painted.appIcon; desktopEntry: cell.painted.desktopEntry
                    summary: cell.painted.summary; body: cell.painted.body; timestamp: cell.painted.timestamp
                    detailsExpanded: pane.detailStates[cell.painted.key] === true
                    onDetailsRequested: value => pane.setDetails(cell.painted.key, value)
                    clockNow: pane.clockNow
                    showPreview: NotificationPolicyService.showPreview
                    interactive: !cell.exiting && (cell.index < 3 || pane.expanded)
                    compositorGlass: pane.compositorGlass
                    captureAnchor: pane.captureAnchor || historyList
                    clipSceneRect: pane.visibleListRect
                    backdropScale: pane.backdropScale
                    opacity: cell.index < 3 || cell.exiting ? 1 : pane.revealProgress
                    glassOpacity: pane.glassOpacity * cell.opacity * opacity
                    onRemoveRequested: key => {
                        pane.prepareHistoryRemoval(); NotificationHistoryService.remove(key)
                    }
                }
            }
        }
        KosKineticScroll { flickable: historyList; enabled: pane.active && !pane.folding }
    }
    // Rear cards expose only their rounded bottom edges. Their full outlines
    // sit above this clipped strip, so no border crosses a translucent front.
    Item {
        x: 0; y: historyList.y + historyList.height - 8
        width: pane.width; height: 14
        clip: true
        visible: NotificationHistoryService.count > 3 && pane.revealProgress < 0.999
            && historyList.contentY + historyList.height >= historyList.originY + historyList.contentHeight - 1
        opacity: 1 - pane.revealProgress
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                z: -index
                x: 8 + index * 6
                y: -112 + (index + 1) * 6
                width: pane.width - x * 2
                height: 112
                radius: 24
                color: ThemeService.isDark ? Qt.rgba(0.82, 0.88, 0.96, index === 0 ? 0.14 : 0.09)
                    : Qt.rgba(1, 1, 1, index === 0 ? 0.38 : 0.26)
            }
        }
    }
    property SceneBounds emptyBounds: SceneBounds { item: emptyGlass }
    readonly property rect emptyRect: {
        const r = emptyBounds.rect
        if (!outerViewport || r.width <= 0 || r.height <= 0) return Qt.rect(0, 36, emptyGlass.width, emptyGlass.height)
        const v = outerBounds.rect
        const x = Math.max(r.x, v.x), y = Math.max(r.y, v.y)
        return Qt.rect((x - r.x) * width / r.width, 36 + (y - r.y) * emptyGlass.height / r.height,
            Math.max(0, Math.min(r.x + r.width, v.x + v.width) - x) * width / r.width,
            Math.max(0, Math.min(r.y + r.height, v.y + v.height) - y) * emptyGlass.height / r.height)
    }
    Item { id: emptyOutline; x: pane.emptyRect.x; y: pane.emptyRect.y; width: pane.emptyRect.width; height: pane.emptyRect.height }
    ControlCenterGlass {
        id: emptyGlass
        objectName: "notification-history-empty"
        x: 0; y: 36; width: pane.width; height: Math.max(0, pane.previewHeight - 36)
        opacity: pane.emptyStateReady ? 1 : 0
        visible: pane.emptyStateReady && opacity > 0
            && emptyOutline.width > 0 && emptyOutline.height > 0
        Behavior on opacity {
            enabled: pane.active && !AppTheme.reduceMotion
            NumberAnimation { duration: 360; easing.type: Easing.InOutSine }
        }
        radius: 24
        blurAnchor: emptyOutline
        backdropRadius: Math.min(radius, emptyOutline.width / 2, emptyOutline.height / 2)
        useKwinEffect: pane.compositorGlass
        captureAnchor: pane.captureAnchor
        backdropScale: pane.backdropScale
        scrimOpacity: pane.glassOpacity * opacity; materialOpacity: pane.glassOpacity * opacity
        GlassText { anchors.centerIn: parent; text: I18n.tr("No notifications yet"); color: pane.ink; opacity: 0.85; font.pixelSize: 12 }
    }
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: NotificationHistoryService.count > 0 && (NotificationHistoryService.count > 3 || pane.expanded) ? 40 : 8
        DeckButton {
            id: footerButton
            objectName: "notification-history-expand"
            anchors.centerIn: parent
            visible: NotificationHistoryService.count > 0 && (NotificationHistoryService.count > 3 || pane.expanded)
            glassButton: true
            text: pane.expanded ? I18n.tr("Collapse notifications  ⌃") : I18n.tr("More notifications  ·  %1  ⌄").arg(Math.max(0, NotificationHistoryService.count - 3))
            onClicked: pane.requestExpanded(pane.folding || !pane.expanded)
        }
    }
}
