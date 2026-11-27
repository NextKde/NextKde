import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import "DockInfoCardOrder.mjs" as DockInfoCardOrder

// Readable one-line information carousel for a left/right Dock. Its parent
// Row is rotated by 90 degrees; the inner panel rotates back so the screen
// text remains horizontal while the card occupies two icon lengths vertically.
// Cards are installed widget packages (see DockInfoCarousel); a package adapts
// to this form through `host.orientation === "vertical"`.
Item {
    id: carousel
    signal editRequested()

    // Slide with the magnified row (see DockContainer's hover spread).
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
    property var hiddenCards: ({})

    function cardIdOf(pkg) { return DockInfoCardOrder.cardIdOf(pkg) }

    function packageForId(id) {
        return (dockPackages || []).find(p => carousel.cardIdOf(p) === id) ?? null
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

    property int iconSize: 44
    property int dockHeight: 60
    property real edgePadding: Math.round(iconSize * 0.18)
    property real surfaceOriginX: 0
    property real surfaceOriginY: 0
    property string dockEdge: "left"
    required property real cornerRadius
    property real widthUnits: 2
    property bool expanded: false
    property bool autoRotate: true
    readonly property int availablePageCount: availableIds().length
    readonly property real cardSpacing: Math.max(4, Math.round(iconSize * 0.14))
    readonly property real collapsedWidth: iconSize * widthUnits + iconSize * 0.2
    readonly property real outerInset: Math.max(0, (dockHeight - height) / 2)
    readonly property real concentricInset: (outerInset + edgePadding) / 2
    readonly property real cardRadius: cornerRadius > 0
        ? Math.max(Math.round(iconSize * 0.16), Math.min(height / 2, Math.round(cornerRadius - concentricInset)))
        : Math.max(6, Math.round(iconSize * 0.18))
    readonly property real contentSideMargin: 3
    readonly property real contentEndMargin: {
        const r = cardRadius
        const s = contentSideMargin
        if (r <= s) return Math.max(6, s)
        return Math.max(6, Math.ceil(r - Math.sqrt(Math.max(0, r * r - (r - s) * (r - s)))))
    }
    property string activeCardId: ""

    width: expanded
        ? availablePageCount * collapsedWidth
            + Math.max(0, availablePageCount - 1) * cardSpacing
        : collapsedWidth
    height: iconSize * 1.2
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    function cardVisibleId(id) {
        return (orderedCardIds || []).indexOf(id) >= 0 && !hiddenCards[id]
    }

    function availableIds() {
        const ids = []
        for (const id of (orderedCardIds || [])) {
            if (cardVisibleId(id)) ids.push(id)
        }
        return ids
    }

    function ensureValidPage() {
        if (cardVisibleId(activeCardId))
            return
        const ids = availableIds()
        activeCardId = ids.length > 0 ? ids[0] : ""
    }

    function switchPage(direction) {
        const ids = availableIds()
        if (ids.length < 2)
            return
        let index = ids.indexOf(activeCardId)
        if (index < 0)
            index = 0
        const step = Math.trunc(direction)
        activeCardId = ids[((index + step) % ids.length + ids.length) % ids.length]
    }

    Component.onCompleted: ensureValidPage()
    onCardOrderChanged: ensureValidPage()
    onDockPackagesChanged: ensureValidPage()
    onOrderedCardIdsChanged: ensureValidPage()
    onAvailablePageCountChanged: ensureValidPage()
    onHiddenCardsChanged: ensureValidPage()

    Timer {
        interval: 30000
        running: carousel.visible && carousel.autoRotate && !carousel.expanded
            && carousel.availablePageCount > 1
        repeat: true
        onTriggered: carousel.switchPage(1)
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
            carousel.switchPage(steps > 0 ? 1 : -1)
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 10
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

    property bool slotHovered: false
    property Item hoveredAnchorItem: null
    property var hoveredPackage: null

    function midGradientColor(spec) {
        if (!spec) return "transparent"
        const mid = spec.midColor
        if (mid !== undefined && mid !== null && String(mid).length > 0)
            return mid
        const s = Qt.color(String(spec.startColor ?? "transparent"))
        const e = Qt.color(String(spec.endColor ?? "transparent"))
        return Qt.rgba((s.r + e.r) * 0.5, (s.g + e.g) * 0.5, (s.b + e.b) * 0.5, (s.a + e.a) * 0.5)
    }

    function handlePackageHover(hovered, anchorItem, pkg) {
        if (hovered) {
            carousel.slotHovered = true
            if (pkg && pkg.hasPopup && String(pkg.popupEntry || "").length > 0) {
                sidePopupCloseDelay.stop()
                carousel.hoveredAnchorItem = anchorItem
                carousel.hoveredPackage = pkg
                if (sideWidgetPopup.visible)
                    DockModelService.openDockPopup(sideWidgetPopup)
                else if (!sidePopupOpenDelay.running)
                    sidePopupOpenDelay.start()
            } else {
                sidePopupOpenDelay.stop()
                if (sideWidgetPopup.visible)
                    sideWidgetPopup.requestClose()
            }
        } else if (carousel.hoveredAnchorItem === anchorItem || !anchorItem) {
            carousel.slotHovered = false
            if (!sideWidgetPopup.pointerInside) {
                sidePopupOpenDelay.stop()
                sidePopupCloseDelay.restart()
            }
        }
    }

    Timer {
        id: sidePopupOpenDelay
        interval: DockAnimation.infoPopupOpenDelay
        repeat: false
        onTriggered: {
            if (carousel.slotHovered && carousel.hoveredPackage && carousel.hoveredAnchorItem)
                DockModelService.openDockPopup(sideWidgetPopup)
        }
    }

    Timer {
        id: sidePopupCloseDelay
        interval: 260
        repeat: false
        onTriggered: {
            if (!carousel.slotHovered && !sideWidgetPopup.pointerInside && sideWidgetPopup.visible)
                sideWidgetPopup.requestClose()
        }
    }

    DockWidgetPopup {
        id: sideWidgetPopup
        anchorItem: carousel.hoveredAnchorItem
        dockEdge: carousel.dockEdge
        packageEntry: carousel.hoveredPackage
        onPointerInsideChanged: {
            if (pointerInside) {
                sidePopupCloseDelay.stop()
                if (!sideWidgetPopup.requestedOpen && sideWidgetPopup.packageEntry)
                    DockModelService.openDockPopup(sideWidgetPopup)
            } else if (!carousel.slotHovered) {
                sidePopupCloseDelay.restart()
            }
        }
        onVisibleChanged: if (!visible) DockModelService.releaseDockPopup(sideWidgetPopup)
    }

    Row {
        anchors.fill: parent
        spacing: carousel.expanded ? carousel.cardSpacing : 0

        Repeater {
            model: carousel.orderedCardIds

            delegate: Item {
                id: sideSlot
                required property string modelData
                readonly property var packageEntry: carousel.packageForId(modelData)
                width: carousel.collapsedWidth
                height: carousel.height
                // Every ordered card stays instantiated so its `dockVisible`
                // keeps the carousel's visibility current; only the shown ones
                // take part in the Row layout.
                visible: carousel.cardVisibleId(modelData)
                    && (carousel.expanded || carousel.activeCardId === modelData)
                Item {
                    id: readablePanel
                    anchors.centerIn: parent
                    width: sideSlot.height
                    height: sideSlot.width
                    rotation: -90

                    Rectangle {
                        anchors.fill: parent
                        visible: sideSlot.packageEntry !== null
                        radius: carousel.cardRadius
                        clip: true
                        readonly property var spec: sidePkgHost.backgroundSpec
                        readonly property bool paintGradient: !AppearanceTokens.isMaterial
                            && !!spec && !WidgetHostService.widgetAppearance.transparent
                        color: paintGradient ? "transparent"
                            : (AppearanceTokens.isMaterial
                                ? Qt.rgba(AppearanceTokens.colors.layer2.r,
                                    AppearanceTokens.colors.layer2.g,
                                    AppearanceTokens.colors.layer2.b, 0.72)
                                : Qt.rgba(1, 1, 1, AppearanceTokens.isDarkTheme ? 0.08 : 0.16))
                        gradient: paintGradient ? sidePkgGradient : null
                        Gradient {
                            id: sidePkgGradient
                            orientation: sidePkgHost.backgroundSpec?.orientation === "horizontal"
                                ? Gradient.Horizontal : Gradient.Vertical
                            GradientStop { position: 0; color: sidePkgHost.backgroundSpec?.startColor ?? "transparent" }
                            GradientStop {
                                position: Math.max(0.01, Math.min(0.99,
                                    sidePkgHost.backgroundSpec?.midPosition !== undefined
                                        ? Number(sidePkgHost.backgroundSpec.midPosition) : 0.5))
                                color: carousel.midGradientColor(sidePkgHost.backgroundSpec)
                            }
                            GradientStop { position: 1; color: sidePkgHost.backgroundSpec?.endColor ?? "transparent" }
                        }

                        HoverHandler {
                            enabled: sideSlot.packageEntry !== null
                            onHoveredChanged: carousel.handlePackageHover(
                                hovered, readablePanel, sideSlot.packageEntry)
                        }

                        WidgetPackageHost {
                            id: sidePkgHost
                            anchors.fill: parent
                            anchors.leftMargin: carousel.contentSideMargin
                            anchors.rightMargin: carousel.contentSideMargin
                            anchors.topMargin: carousel.contentEndMargin
                            anchors.bottomMargin: carousel.contentEndMargin
                            packageId: String(sideSlot.packageEntry?.id ?? "")
                            instanceId: "dock:" + String(sideSlot.packageEntry?.id ?? "")
                            widgetEntry: String(sideSlot.packageEntry?.widgetEntry ?? "")
                            settingsEntry: String(sideSlot.packageEntry?.settingsEntry ?? "")
                            packageRevision: String(sideSlot.packageEntry?.revision ?? "")
                            hasSettings: Boolean(sideSlot.packageEntry?.hasSettings)
                            containerType: "dock"
                            containerOrientation: "vertical"
                            hostActive: carousel.visible && (carousel.expanded || carousel.activeCardId === sideSlot.modelData)
                            surfaceOriginX: carousel.surfaceOriginX
                            surfaceOriginY: carousel.surfaceOriginY
                            widgetSize: [1, 2]
                            appearance: WidgetHostService.widgetAppearance
                        }
                    }
                }

                readonly property bool packageVisible: sidePkgHost.widgetItem
                    && sidePkgHost.widgetItem.dockVisible !== undefined
                    ? Boolean(sidePkgHost.widgetItem.dockVisible) : true
                onPackageVisibleChanged: carousel.setCardHidden(modelData, !packageVisible)
                Component.onCompleted: carousel.setCardHidden(modelData, !packageVisible)
            }
        }
    }
}
