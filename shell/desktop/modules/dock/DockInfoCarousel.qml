import QtQuick
import qs.desktop.modules.weather

// One Dock slot shared by music, weather, clock and metrics.
//
// Two layouts over the same four cards:
//   carousel — the historical fixed-size slot; the enabled pages rotate
//     through it and the width never follows the content.
//   expanded — every enabled card takes its own place in the row, sized by
//     what it actually draws (clock 3 icon units, the rest 4), and nothing
//     rotates any more.
//
Item {
    id: carousel
    signal editRequested()

    readonly property int musicPage: 0
    readonly property int weatherPage: 1
    readonly property int clockPage: 2
    readonly property int temperaturePage: 3
    property var cardOrder: ["music", "weather", "clock", "metrics"]
    readonly property var pageOrder: {
        const pages = []
        for (const id of cardOrder) {
            const candidate = pageForId(id)
            if (candidate >= 0 && pages.indexOf(candidate) < 0)
                pages.push(candidate)
        }
        return pages
    }

    property int iconSize: 44
    property int dockHeight: 60
    property int widthUnits: 4
    property bool showClock: false
    property bool showTemperature: true

    property bool expanded: false
    property bool autoRotate: true

    readonly property bool hasMusic: DockMprisService.hasPlayer
    readonly property bool hasWeather: WeatherService.available
    readonly property real cardGap: iconSize * 0.2
    // Visible seam between neighbouring expanded cards. Each card's painted
    // background already extends cardGap/2 past its content, so without this
    // extra step two adjacent cards touch edge to edge.
    readonly property real cardSpacing: Math.max(4, Math.round(iconSize * 0.14))

    // Prefer the clock when Bar has just moved into Dock. This preserves the
    // information users previously saw at the leading edge of the Dock.
    property int page: clockPage
    property int previousPage: -1
    property int transitionDirection: 1
    property int hoveredPage: -1

    width: expanded ? expandedWidth : iconSize * widthUnits + iconSize * 0.2
    height: iconSize * 1.2
    clip: !expanded
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    function pageForId(id) {
        if (id === "music")
            return musicPage
        if (id === "weather")
            return weatherPage
        if (id === "clock")
            return clockPage
        if (id === "metrics" || id === "temperature")
            return temperaturePage
        return -1
    }

    function cardVisible(candidate) {
        if (candidate === musicPage)
            return hasMusic
        if (candidate === weatherPage)
            return hasWeather
        if (candidate === clockPage)
            return showClock
        return showTemperature
    }

    function unitsFor(candidate) {
        // The clock draws two rows of text and needs three icon units; every
        // other card keeps the four it always reserved.
        return candidate === clockPage ? 3 : 4
    }

    function cardWidth(candidate) {
        return iconSize * (expanded ? unitsFor(candidate) : widthUnits)
            + cardGap * 2
    }

    readonly property int availablePageCount: {
        let count = 0
        for (const candidate of (pageOrder || [])) {
            if (cardVisible(candidate))
                count++
        }
        return count
    }

    readonly property real expandedWidth: {
        let total = 0
        for (const candidate of (pageOrder || [])) {
            if (!cardVisible(candidate))
                continue
            total += iconSize * unitsFor(candidate) + cardGap + cardSpacing
        }
        return total
    }

    function pageAvailable(candidate) {
        return cardVisible(candidate)
    }

    function availablePages() {
        const pages = []
        for (const candidate of (pageOrder || [])) {
            if (cardVisible(candidate))
                pages.push(candidate)
        }
        return pages
    }

    function ensureValidPage(preferClock) {
        if (preferClock && showClock && pageOrder.indexOf(clockPage) >= 0) {
            previousPage = page
            page = clockPage
            return
        }
        if (pageAvailable(page))
            return
        const pages = availablePages()
        previousPage = page
        page = pages.length > 0 ? pages[0] : clockPage
    }

    function switchPage(resetTimer, requestedDirection) {
        const pages = availablePages()
        if (pages.length < 2)
            return
        const direction = requestedDirection === undefined
            ? 1 : (requestedDirection >= 0 ? 1 : -1)
        let currentIndex = pages.indexOf(page)
        if (currentIndex < 0)
            currentIndex = 0
        previousPage = page
        transitionDirection = direction
        page = pages[(currentIndex + direction + pages.length) % pages.length]
        if (resetTimer && autoRotate)
            carouselTimer.restart()
    }

    function pageX(pageIndex, pageWidth) {
        if (page === pageIndex)
            return 0
        if (previousPage === pageIndex)
            return -transitionDirection * pageWidth
        return transitionDirection * pageWidth
    }

    // Expanded mode stacks the cards left to right in page order, skipping
    // the ones that are off; carousel mode keeps the sliding viewport.
    function layoutX(candidate) {
        if (!expanded)
            return pageX(candidate, cardWidth(candidate))
        let offset = 0
        for (const other of (pageOrder || [])) {
            if (other === candidate)
                return offset
            if (cardVisible(other))
                offset += iconSize * unitsFor(other) + cardGap + cardSpacing
        }
        return offset
    }

    function isShown(candidate) {
        return expanded || page === candidate
    }

    function hoveredPageAt(x) {
        if (!expanded)
            return page
        let start = 0
        for (const candidate of (pageOrder || [])) {
            if (!cardVisible(candidate))
                continue
            const span = iconSize * unitsFor(candidate) + cardGap + cardSpacing
            if (x >= start && x < start + span)
                return candidate
            start += span
        }
        return page
    }

    Component.onCompleted: ensureValidPage(showClock)
    onHasMusicChanged: ensureValidPage(false)
    onHasWeatherChanged: ensureValidPage(false)
    onShowClockChanged: ensureValidPage(showClock)
    onShowTemperatureChanged: ensureValidPage(false)
    onCardOrderChanged: ensureValidPage(showClock)
    onExpandedChanged: ensureValidPage(false)

    Timer {
        id: carouselTimer
        interval: 30000
        // Nothing rotates once every card has its own place.
        running: carousel.autoRotate && !carousel.expanded
            && carousel.availablePageCount > 1
        repeat: true
        onTriggered: carousel.switchPage(false, 1)
    }

    Timer {
        id: wheelCooldown
        interval: 180
        repeat: false
    }

    MouseArea {
        anchors.fill: parent
        z: 20
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            if (carousel.expanded)
                return
            const delta = wheel.angleDelta.y + wheel.pixelDelta.y
            if (delta === 0 || wheelCooldown.running)
                return
            carousel.switchPage(true, delta >= 0 ? -1 : 1)
            wheelCooldown.restart()
            wheel.accepted = true
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: carousel.editRequested()
    }

    Item {
        id: infoAnchor
        visible: false
        y: 0
        height: carousel.height
        x: carousel.hoveredPage >= 0 ? carousel.layoutX(carousel.hoveredPage) : 0
        width: carousel.hoveredPage >= 0
            ? carousel.cardWidth(carousel.hoveredPage) : carousel.width
    }

    readonly property int pointerPage: infoHover.hovered
        ? carousel.hoveredPageAt(infoHover.point.position.x) : -1

    onPointerPageChanged: {
        if (pointerPage < 0)
            return
        if (pointerPage === carousel.musicPage) {
            if (infoPopup.visible)
                infoPopup.requestClose()
            return
        }
        carousel.hoveredPage = pointerPage
        if (infoPopup.visible)
            infoPopupOpenDelay.stop()
    }

    HoverHandler {
        id: infoHover
        onHoveredChanged: {
            if (hovered) {
                infoPopupCloseDelay.stop()
                infoPopupOpenDelay.restart()
            } else if (!infoPopup.pointerInside) {
                infoPopupOpenDelay.stop()
                infoPopupCloseDelay.restart()
            }
        }
    }

    Timer {
        id: infoPopupOpenDelay
        interval: 420
        repeat: false
        onTriggered: {
            if (infoHover.hovered && carousel.pointerPage >= 0
                    && carousel.pointerPage !== carousel.musicPage)
                DockModelService.openDockPopup(infoPopup)
        }
    }

    Timer {
        id: infoPopupCloseDelay
        interval: 260
        repeat: false
        onTriggered: {
            if (!infoHover.hovered && !infoPopup.pointerInside)
                infoPopup.requestClose()
        }
    }

    DockInfoPopup {
        id: infoPopup
        anchorItem: infoAnchor
        page: carousel.hoveredPage
        onVisibleChanged: if (!visible) DockModelService.releaseDockPopup(infoPopup)
    }

    DockMusicPlayer {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: carousel.iconSize
        dockHeight: carousel.dockHeight
        widthUnits: carousel.expanded
            ? carousel.unitsFor(carousel.musicPage) : carousel.widthUnits
        visible: carousel.cardVisible(carousel.musicPage)
        enabled: carousel.isShown(carousel.musicPage)
        pageActive: carousel.isShown(carousel.musicPage)
        x: carousel.layoutX(carousel.musicPage)
        opacity: carousel.isShown(carousel.musicPage) ? 1 : 0
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    DockWeatherWidget {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: carousel.iconSize
        dockHeight: carousel.dockHeight
        widthUnits: carousel.expanded
            ? carousel.unitsFor(carousel.weatherPage) : carousel.widthUnits
        visible: carousel.cardVisible(carousel.weatherPage)
        enabled: carousel.isShown(carousel.weatherPage)
        pageActive: carousel.isShown(carousel.weatherPage)
        x: carousel.layoutX(carousel.weatherPage)
        opacity: carousel.isShown(carousel.weatherPage) ? 1 : 0
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    DockClockWidget {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: carousel.iconSize
        dockHeight: carousel.dockHeight
        widthUnits: carousel.expanded
            ? carousel.unitsFor(carousel.clockPage) : carousel.widthUnits
        visible: carousel.cardVisible(carousel.clockPage)
        enabled: carousel.isShown(carousel.clockPage)
        pageActive: carousel.isShown(carousel.clockPage)
        x: carousel.layoutX(carousel.clockPage)
        opacity: carousel.isShown(carousel.clockPage) ? 1 : 0
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }

    DockTemperatureWidget {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: carousel.iconSize
        dockHeight: carousel.dockHeight
        widthUnits: carousel.expanded
            ? carousel.unitsFor(carousel.temperaturePage) : carousel.widthUnits
        visible: carousel.cardVisible(carousel.temperaturePage)
        enabled: carousel.isShown(carousel.temperaturePage)
        pageActive: carousel.isShown(carousel.temperaturePage)
        x: carousel.layoutX(carousel.temperaturePage)
        opacity: carousel.isShown(carousel.temperaturePage) ? 1 : 0
        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    }
}
