import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.dock
import "desktop/modules/dock/DockMagnification.mjs" as Magnification

// Real mapped, thin surface with no input region: synthetic sweeps never
// move the user's cursor or intercept input. Shipping icons and shared label
// render in one layer surface, with no xdg_popup protocol path.
PanelWindow {
    id: surface
    property string edge: "bottom"
    property bool side: edge !== "bottom"
    readonly property real iconSize: 44
    readonly property real thickness: 60
    readonly property real visualBudget: Magnification.visualHeadroom(iconSize, 4, 2, 0.2,
        thickness, DockAnimation.launchBounceHeightRatio)
    readonly property real labelBudget: DockAnimation.nameLabelGap + (side
        ? DockAnimation.nameLabelMaximumWidth : DockAnimation.nameLabelMaximumHeight)
    implicitWidth: side ? thickness + visualBudget + labelBudget + 12 : 0
    implicitHeight: side ? 0 : thickness + visualBudget + labelBudget + 12
    anchors.top: side
    anchors.bottom: true
    anchors.left: edge !== "right"
    anchors.right: edge !== "left"
    color: "transparent"
    WlrLayershell.namespace: "dock-label-sweep-probe"
    exclusionMode: ExclusionMode.Ignore
    mask: Region { width: 0; height: 0 }
    Component { id: shippingWindow; DockWindow { position: surface.edge } }
    function findContainer(item) {
        if (item.nameLabelsEnabled !== undefined) return item
        for (const child of item.children ?? []) {
            const found = findContainer(child)
            if (found) return found
        }
        return null
    }
    property var shippingProbe: null
    Component.onCompleted: {
        if (shippingWindow.status !== Component.Ready) {
            console.log("SWEEP_FAIL shipping DockWindow unavailable")
            Qt.quit()
        } else {
            shippingProbe = shippingWindow.createObject(null, {visible: false, screen: surface.screen})
            if (!shippingProbe) { console.log("SWEEP_FAIL shipping construction"); Qt.quit() }
        }
    }
    property bool finished: false
    property int frames: 0
    property real elapsed: 0
    property real largestFrame: 0
    property var intervals: []
    property int selected: 0
    property int selectionChecks: 0
    QtObject { id: popupStub; property bool visible: false; property bool pointerInside: false }
    QtObject { id: rigidStub }
    Item {
        id: host
        anchors.fill: parent
        property point magnificationPointer: Qt.point(0, 0)
        readonly property alias nameLabel: name
        property var frame: ({ entries: [], byItem: new Map() })
        function hoverFor(item) { return false } // labels must not rely on exact hover hits
        function magnificationFor(item) { return frame.byItem.get(item)?.progress ?? 0 }
        function spreadFor(item) { return frame.byItem.get(item)?.dx ?? 0 }
        function updateNameLabel() { name.updateGeometry() }
        Row {
            id: row
            x: surface.side ? (surface.edge === "left" ? 6 + 52 : surface.width - 6) : 200
            y: surface.side ? 220 : surface.height - 6 - surface.thickness
            rotation: surface.side ? 90 : 0
            spacing: 8
            Repeater {
                id: icons
                model: 6
                DockIcon {
                    iconSize: 44
                    appId: "label-sweep-probe-" + index + ".desktop"
                    displayName: "Application " + index
                    isRunning: index % 2 === 1
                    magnificationRoot: host
                    magnificationPointer: host.magnificationPointer
                    vertical: surface.side
                    dockEdge: surface.edge
                }
            }
        }
        DockNameLabel {
            id: name
            targetIcon: null
            pointerRoot: host
            pointerPosition: host.magnificationPointer
        }
    }
    function iconStates() {
        const states = []
        for (let i = 0; i < icons.count; ++i) {
            const icon = icons.itemAt(i)
            if (icon) states.push({ item: icon, cx: icon.x + icon.width / 2,
                half: icon.iconSlotWidth / 2, artHalf: icon.iconSize / 2, growable: true })
        }
        return states
    }
    function require(value, reason) {
        if (!value) { console.log("SWEEP_FAIL " + reason); Qt.quit(); throw new Error(reason) }
        selectionChecks++
    }
    function checkSelection(container) {
        const states = iconStates()
        const cross = icons.itemAt(0).height / 2
        for (const scale of [1, 2, 3]) {
            for (let along = states[0].cx; along <= states[5].cx; along += 0.5) {
                host.frame = Magnification.layout(states, along, 1, scale, 220, row.spacing)
                const target = container.selectNameTarget(states, host.frame, Qt.point(along, cross), row)
                require(target !== null && target.dockNameEligible,
                    "mixed running/nonrunning or spacing produces blank at " + along)
            }
        }
        const along = states[1].cx
        host.frame = Magnification.layout(states, along, 0, 1, 220, row.spacing)
        const point = Qt.point(along, cross)
        require(container.selectNameTarget(states, host.frame, point, row) === icons.itemAt(1),
            "running app with exact hover false must be named")
        require(container.selectNameTarget(states, host.frame, Qt.point(along, -1000), row) === null,
            "normal-axis exit must not attract label")
        require(container.selectNameTarget(states, host.frame, Qt.point(-1000, cross), row) === null,
            "outside first icon must not attract label")
        DockModelService.activeContextMenu = popupStub
        require(container.selectNameTarget(states, host.frame, point, row) === null, "menu suppresses label")
        DockModelService.activeContextMenu = null
        icons.itemAt(1)._previewInstance = popupStub
        require(container.selectNameTarget(states, host.frame, point, row) === icons.itemAt(1),
            "unmapped preview must not suppress name")
        popupStub.visible = true
        require(container.selectNameTarget(states, host.frame, point, row) === null,
            "actually visible preview suppresses its own name")
        require(container.selectNameTarget(states, host.frame, Qt.point(states[2].cx, cross), row)
            === icons.itemAt(2), "neighbor preview must not suppress other names")
        popupStub.visible = false
        icons.itemAt(1)._previewInstance = null
        const barrier = { item: rigidStub, cx: (states[2].cx + states[3].cx) / 2, half: 3, growable: false }
        const separated = states.slice(0, 3).concat([barrier], states.slice(3))
        const flat = Magnification.layout(separated, barrier.cx, 0, 1, 220, row.spacing)
        require(container.selectNameTarget(separated, flat, Qt.point(barrier.cx, cross), row) === null,
            "divider/accessory gap must not be bridged")
    }
    FrameAnimation {
        running: !surface.finished
        onTriggered: {
            surface.elapsed += frameTime
            surface.frames++
            surface.largestFrame = Math.max(surface.largestFrame, frameTime)
            surface.intervals.push(frameTime)
            const container = surface.findContainer(surface.shippingProbe.contentItem)
            if (surface.frames === 2) surface.checkSelection(container)
            const states = surface.iconStates()
            if (states.length !== 6 || !container) return
            const span = states[5].cx - states[0].cx
            const speed = surface.elapsed < 0.75 ? 120 : 1800
            const along = states[0].cx + (surface.elapsed * speed) % span
            host.frame = Magnification.layout(states, along, 1, 2, 220, row.spacing)
            const local = Qt.point(along, icons.itemAt(0).height / 2)
            host.magnificationPointer = row.mapToItem(host, local.x, local.y)
            name.targetIcon = container.selectNameTarget(states, host.frame, local, row)
            name.updateGeometry()
            if (!name.targetIcon || !name.visible) {
                console.log("SWEEP_FAIL continuous name selection speed=" + speed)
                Qt.quit(); return
            }
            if (surface.elapsed >= 1.5) {
                surface.finished = true
                if (!container || container.nameLabel.parent !== surface.shippingProbe.contentItem
                        || container.nameLabel.enabled) {
                    console.log("SWEEP_FAIL shared label host/input ownership")
                    Qt.quit(); return
                }
                surface.require(surface.selectionChecks > 1800, "selection regression must run")
                container.nameLabelsEnabled = true
                container.nameLabelTarget = icons.itemAt(0)
                container.nameLabelsEnabled = false
                if (container.nameLabelTarget !== null || container.nameLabel.visible) {
                    console.log("SWEEP_FAIL hidden Dock retains name target")
                    Qt.quit(); return
                }
                console.log("SWEEP_PASS edge=" + surface.edge + " frames=" + surface.frames
                    + " selectionChecks=" + surface.selectionChecks
                    + " meanMs=" + (surface.elapsed * 1000 / surface.frames).toFixed(2)
                    + " maxMs=" + (surface.largestFrame * 1000).toFixed(2))
                Qt.quit()
            }
        }
    }
}
