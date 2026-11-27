import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import "DockInfoCardOrder.mjs" as DockInfoCardOrder

// The Dock's information slot. Every card is an installed widget package that
// declares `"dock"` in `metadata.json`'s `containers` -- the official music,
// weather, clock and system cards use exactly the same contract as third-party
// ones. The host owns the slot shell, the rotation/expansion behaviour and the
// hover popup shell (DockWidgetPopup); a package only paints the card content
// and, optionally, the popup content.
Item {
    id: carousel
    signal editRequested()

    // Slide with the magnified row so the information slot keeps its place
    // between the spreading icons (see DockContainer's hover spread).
    transform: Translate {
        x: {
            let p = carousel.parent
            while (p && typeof p.spreadFor !== "function")
                p = p.parent
            return p ? p.spreadFor(carousel) : 0
        }
    }

    property var cardOrder: []
    property var dockPackages: []
    // Card ids a package asked to hide through `dockVisible: false` (for
    // instance a music card while no player is running).
    property var hiddenCards: ({})

    function cardIdOf(pkg) { return DockInfoCardOrder.cardIdOf(pkg) }

    function packageForId(id) {
        return (dockPackages || []).find(p => carousel.cardIdOf(p) === id) ?? null
    }

    function hasPackagePopup(id) {
        const pkg = packageForId(id)
        return Boolean(pkg && pkg.hasPopup && String(pkg.popupEntry || "").length > 0)
    }

    function setCardHidden(id, hidden) {
        if (Boolean(hiddenCards[id]) === hidden)
            return
        const next = Object.assign({}, hiddenCards)
        if (hidden) next[id] = true
        else delete next[id]
        hiddenCards = next
    }

    readonly property var orderedCardIds: {
        const ids = []
        for (const rawId of (cardOrder || [])) {
            const id = String(rawId)
            if (ids.indexOf(id) >= 0) continue
            if (carousel.packageForId(id) !== null)
                ids.push(id)
        }
        return ids
    }
    readonly property var activeDockPackages: {
        const out = []
        for (const id of orderedCardIds)
            out.push(carousel.packageForId(id))
        return out
    }

    property int iconSize: 44
    property int dockHeight: 60
    property real edgePadding: Math.round(iconSize * 0.18)
    property real surfaceOriginX: 0
    property real surfaceOriginY: 0
    required property real cornerRadius
    property int widthUnits: 4

    property bool expanded: false
    property bool autoRotate: true

    readonly property real cardGap: iconSize * 0.2
    readonly property real cardSpacing: Math.max(4, Math.round(iconSize * 0.14))
    readonly property real outerInset: Math.max(0, (dockHeight - height) / 2)
    readonly property real concentricInset: (outerInset + edgePadding) / 2
    readonly property real cardRadius: cornerRadius > 0
        ? Math.max(Math.round(iconSize * 0.16), Math.min(height / 2, Math.round(cornerRadius - concentricInset)))
        : Math.max(6, Math.round(iconSize * 0.18))
    readonly property real contentVerticalMargin: 4
    readonly property real contentHorizontalMargin: {
        const r = cardRadius
        const v = contentVerticalMargin
        if (r <= v) return Math.max(6, v)
        return Math.max(6, Math.ceil(r - Math.sqrt(Math.max(0, r * r - (r - v) * (r - v)))))
    }

    property string activeCardId: ""
    property string previousCardId: ""
    property int transitionDirection: 1
    property string hoveredCardId: ""

    width: expanded ? expandedWidth : iconSize * widthUnits + iconSize * 0.2
    height: iconSize * 1.2
    clip: !expanded
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    function cardVisibleId(id) {
        return (orderedCardIds || []).indexOf(id) >= 0 && !hiddenCards[id]
    }

    function unitsForId(id) {
        const pkg = packageForId(id)
        return Math.max(2, Math.min(4, Number(pkg?.dockUnits) || 4))
    }

    function midGradientColor(spec) {
        if (!spec) return "transparent"
        const mid = spec.midColor
        if (mid !== undefined && mid !== null && String(mid).length > 0)
            return mid
        const s = Qt.color(String(spec.startColor ?? "transparent"))
        const e = Qt.color(String(spec.endColor ?? "transparent"))
        return Qt.rgba((s.r + e.r) * 0.5, (s.g + e.g) * 0.5, (s.b + e.b) * 0.5, (s.a + e.a) * 0.5)
    }

    function cardWidthForId(id) {
        return iconSize * (expanded ? unitsForId(id) : widthUnits) + cardGap
    }

    readonly property int availablePageCount: {
        let count = 0
        for (const id of (orderedCardIds || [])) {
            if (cardVisibleId(id)) count++
        }
        return count
    }

    readonly property real expandedWidth: {
        let total = 0
        let count = 0
        for (const id of (orderedCardIds || [])) {
            if (!cardVisibleId(id)) continue
            if (count > 0) total += cardSpacing
            total += iconSize * unitsForId(id) + cardGap
            count++
        }
        return total
    }

    function availableCardIds() {
        const ids = []
        for (const id of (orderedCardIds || [])) {
            if (cardVisibleId(id)) ids.push(id)
        }
        return ids
    }

    function ensureValidPage() {
        if (cardVisibleId(activeCardId))
            return
        const ids = availableCardIds()
        previousCardId = activeCardId
        activeCardId = ids.length > 0 ? ids[0] : ""
    }

    function switchPage(resetTimer, requestedDirection) {
        const ids = availableCardIds()
        if (ids.length < 2)
            return
        const direction = requestedDirection === undefined
            ? 1 : Math.trunc(requestedDirection)
        let currentIndex = ids.indexOf(activeCardId)
        if (currentIndex < 0)
            currentIndex = 0
        previousCardId = activeCardId
        transitionDirection = direction >= 0 ? 1 : -1
        activeCardId = ids[((currentIndex + direction) % ids.length + ids.length) % ids.length]
        if (resetTimer && autoRotate)
            carouselTimer.restart()
    }

    function pageXForId(id, pageWidth) {
        if (activeCardId === id) return 0
        if (previousCardId === id) return -transitionDirection * pageWidth
        return transitionDirection * pageWidth
    }

    function layoutXForId(id) {
        if (!expanded)
            return pageXForId(id, cardWidthForId(id))
        let offset = 0
        for (const other of (orderedCardIds || [])) {
            if (other === id) return offset
            if (cardVisibleId(other))
                offset += iconSize * unitsForId(other) + cardGap + cardSpacing
        }
        return offset
    }

    function isShownId(id) {
        return expanded || activeCardId === id
    }

    function hoveredCardIdAt(x) {
        if (!expanded)
            return activeCardId
        let start = 0
        for (const id of (orderedCardIds || [])) {
            if (!cardVisibleId(id)) continue
            const span = iconSize * unitsForId(id) + cardGap + cardSpacing
            if (x >= start && x < start + span)
                return id
            start += span
        }
        return activeCardId
    }

    Component.onCompleted: ensureValidPage()
    onCardOrderChanged: ensureValidPage()
    onDockPackagesChanged: ensureValidPage()
    onOrderedCardIdsChanged: ensureValidPage()
    onAvailablePageCountChanged: ensureValidPage()
    onHiddenCardsChanged: ensureValidPage()
    onExpandedChanged: ensureValidPage()

    Timer {
        id: carouselTimer
        interval: 30000
        running: carousel.visible && carousel.autoRotate && !carousel.expanded
            && carousel.availablePageCount > 1
        repeat: true
        onTriggered: carousel.switchPage(false, 1)
    }

    property real wheelRemainder: 0
    property bool wheelUsesPixels: false
    property int wheelSteps: 0
    property double lastWheelSwitchMs: 0
    FrameAnimation {
        running: carousel.wheelSteps !== 0
        onTriggered: {
            const steps = carousel.wheelSteps
            carousel.wheelSteps = 0
            carousel.wheelRemainder = 0
            if (steps === 0 || carousel.expanded)
                return
            const now = Date.now()
            if (now - carousel.lastWheelSwitchMs < 140)
                return
            carousel.lastWheelSwitchMs = now
            carousel.switchPage(true, steps > 0 ? 1 : -1)
        }
    }

    MouseArea {
        id: wheelOverlay
        anchors.fill: parent
        z: 20
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            if (carousel.expanded)
                return
            const pixels = wheel.angleDelta.y === 0
            const delta = pixels ? wheel.pixelDelta.y : wheel.angleDelta.y
            if (delta === 0) return
            if (carousel.wheelSteps * delta < 0) carousel.wheelSteps = 0
            if (pixels !== carousel.wheelUsesPixels || carousel.wheelRemainder * delta < 0)
                carousel.wheelRemainder = 0
            carousel.wheelUsesPixels = pixels
            carousel.wheelRemainder += delta / (pixels ? 40 : 120)
            const steps = carousel.wheelRemainder >= 0
                ? Math.floor(carousel.wheelRemainder) : Math.ceil(carousel.wheelRemainder)
            carousel.wheelRemainder -= steps
            carousel.wheelSteps += steps
            wheel.accepted = true
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        grabPermissions: PointerHandler.CanTakeOverFromItems
            | PointerHandler.CanTakeOverFromHandlersOfSameType
            | PointerHandler.CanTakeOverFromHandlersOfDifferentType
        onTapped: carousel.editRequested()
    }

    // Zero-width probe that tracks the card under the pointer; the popup is
    // anchored to it so the panel reads as belonging to that card.
    Item {
        id: infoAnchor
        visible: false
        y: 0
        height: carousel.height
        x: carousel.hoveredCardId.length > 0 ? carousel.layoutXForId(carousel.hoveredCardId) : 0
        width: carousel.hoveredCardId.length > 0
            ? carousel.cardWidthForId(carousel.hoveredCardId) : carousel.width
    }

    readonly property bool pointerOverCarousel: infoHover.hovered || wheelOverlay.containsMouse
    readonly property real pointerLocalX: infoHover.hovered
        ? infoHover.point.position.x : wheelOverlay.mouseX
    readonly property string pointerCardId: carousel.pointerOverCarousel
        ? carousel.hoveredCardIdAt(carousel.pointerLocalX) : ""
    readonly property var hoveredPackage: carousel.packageForId(carousel.hoveredCardId)
    readonly property bool canShowPopup: pointerCardId.length > 0
        && carousel.hasPackagePopup(pointerCardId)

    onPointerOverCarouselChanged: {
        if (pointerOverCarousel) {
            popupCloseDelay.stop()
            const cid = carousel.pointerCardId || carousel.activeCardId
            if (cid.length > 0 && carousel.hasPackagePopup(cid)) {
                carousel.hoveredCardId = cid
                if (widgetPopup.requestedOpen && widgetPopup.visible)
                    DockModelService.openDockPopup(widgetPopup)
                else if (!popupOpenDelay.running)
                    popupOpenDelay.start()
            }
        } else if (!widgetPopup.pointerInside) {
            popupOpenDelay.stop()
            popupCloseDelay.restart()
        }
    }

    onPointerCardIdChanged: {
        if (!canShowPopup) {
            popupOpenDelay.stop()
            if (carousel.pointerOverCarousel && widgetPopup.visible)
                widgetPopup.requestClose()
            return
        }
        carousel.hoveredCardId = pointerCardId
        if (widgetPopup.requestedOpen && widgetPopup.visible)
            DockModelService.openDockPopup(widgetPopup)
        else if (carousel.pointerOverCarousel && !popupOpenDelay.running)
            popupOpenDelay.start()
    }

    HoverHandler {
        id: infoHover
    }

    Timer {
        id: popupOpenDelay
        interval: DockAnimation.infoPopupOpenDelay
        repeat: false
        onTriggered: {
            const cid = carousel.pointerCardId || carousel.activeCardId
            if (carousel.pointerOverCarousel && cid.length > 0 && carousel.hasPackagePopup(cid)) {
                carousel.hoveredCardId = cid
                DockModelService.openDockPopup(widgetPopup)
            }
        }
    }

    Timer {
        id: popupCloseDelay
        interval: 260
        repeat: false
        onTriggered: {
            if (!carousel.pointerOverCarousel && !widgetPopup.pointerInside && widgetPopup.visible)
                widgetPopup.requestClose()
        }
    }

    DockWidgetPopup {
        id: widgetPopup
        anchorItem: infoAnchor
        dockEdge: "bottom"
        packageEntry: {
            const id = carousel.hoveredCardId || carousel.activeCardId
            return carousel.hasPackagePopup(id) ? carousel.packageForId(id) : null
        }
        onPointerInsideChanged: {
            if (pointerInside) {
                popupCloseDelay.stop()
                if (!widgetPopup.requestedOpen && widgetPopup.packageEntry)
                    DockModelService.openDockPopup(widgetPopup)
            } else if (!carousel.pointerOverCarousel) {
                popupCloseDelay.restart()
            }
        }
        onVisibleChanged: if (!visible) DockModelService.releaseDockPopup(widgetPopup)
    }

    Repeater {
        model: carousel.activeDockPackages
        delegate: Item {
            id: pkgCard
            required property var modelData
            readonly property string cardId: carousel.cardIdOf(modelData)
            readonly property int cardUnits: carousel.expanded
                ? carousel.unitsForId(cardId) : carousel.widthUnits
            readonly property bool shown: carousel.isShownId(cardId)
            readonly property bool packageVisible: pkgHost.widgetItem
                && pkgHost.widgetItem.dockVisible !== undefined
                ? Boolean(pkgHost.widgetItem.dockVisible) : true
            onPackageVisibleChanged: carousel.setCardHidden(cardId, !packageVisible)
            Component.onCompleted: carousel.setCardHidden(cardId, !packageVisible)

            anchors.verticalCenter: parent.verticalCenter
            width: carousel.iconSize * cardUnits + carousel.cardGap
            height: carousel.height
            visible: carousel.cardVisibleId(cardId)
            enabled: shown
            x: carousel.layoutXForId(cardId)
            opacity: shown ? 1 : 0
            Behavior on x { NumberAnimation { duration: AppearanceTokens.motion.base.duration; easing.type: AppearanceTokens.motion.enterCurve } }
            Behavior on opacity { NumberAnimation { duration: AppearanceTokens.motion.fast.duration; easing.type: AppearanceTokens.motion.enterCurve } }

            // Host-owned slot shell. macOS cards may publish a `backgroundSpec`
            // gradient; Material slots always use the theme tonal plate.
            Rectangle {
                anchors.fill: parent
                radius: carousel.cardRadius
                clip: true
                readonly property var spec: pkgHost.backgroundSpec
                readonly property bool paintGradient: !AppearanceTokens.isMaterial
                    && !!spec && !WidgetHostService.widgetAppearance.transparent
                color: paintGradient ? "transparent"
                    : (AppearanceTokens.isMaterial
                        ? Qt.rgba(AppearanceTokens.colors.layer2.r,
                            AppearanceTokens.colors.layer2.g,
                            AppearanceTokens.colors.layer2.b, 0.72)
                        : Qt.rgba(1, 1, 1, AppearanceTokens.isDarkTheme ? 0.08 : 0.16))
                gradient: paintGradient ? dockPkgGradient : null
                Gradient {
                    id: dockPkgGradient
                    orientation: pkgHost.backgroundSpec?.orientation === "horizontal"
                        ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0; color: pkgHost.backgroundSpec?.startColor ?? "transparent" }
                    GradientStop {
                        position: Math.max(0.01, Math.min(0.99,
                            pkgHost.backgroundSpec?.midPosition !== undefined
                                ? Number(pkgHost.backgroundSpec.midPosition) : 0.5))
                        color: carousel.midGradientColor(pkgHost.backgroundSpec)
                    }
                    GradientStop { position: 1; color: pkgHost.backgroundSpec?.endColor ?? "transparent" }
                }

                WidgetPackageHost {
                    id: pkgHost
                    anchors.fill: parent
                    anchors.topMargin: carousel.contentVerticalMargin
                    anchors.bottomMargin: carousel.contentVerticalMargin
                    anchors.leftMargin: carousel.contentHorizontalMargin
                    anchors.rightMargin: carousel.contentHorizontalMargin
                    packageId: String(pkgCard.modelData.id ?? "")
                    instanceId: "dock:" + String(pkgCard.modelData.id ?? "")
                    widgetEntry: String(pkgCard.modelData.widgetEntry ?? "")
                    settingsEntry: String(pkgCard.modelData.settingsEntry ?? "")
                    packageRevision: String(pkgCard.modelData.revision ?? "")
                    hasSettings: Boolean(pkgCard.modelData.hasSettings)
                    containerType: "dock"
                    containerOrientation: "horizontal"
                    hostActive: carousel.visible && pkgCard.shown
                    surfaceOriginX: carousel.surfaceOriginX
                    surfaceOriginY: carousel.surfaceOriginY
                    widgetSize: [pkgCard.cardUnits, 1]
                    appearance: WidgetHostService.widgetAppearance
                }
            }
        }
    }
}
