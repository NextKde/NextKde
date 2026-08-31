import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.applauncher
import qs.desktop.modules.common

// Free-slot desktop surface. Grid placement stays self-contained here while
// filesystem and menu actions are delegated to the host window.
Item {
    id: root

    property real validX: 0
    property real validY: 0
    property real validWidth: width
    property real validHeight: height
    property real cellWidth: 112
    property real cellHeight: 114
    property real cellGap: 16
    property real iconVisualSize: 68
    readonly property real iconVisualTop: 8
    readonly property real columnPitch: cellWidth + cellGap
    readonly property real rowPitch: cellHeight + cellGap
    readonly property int columnCount: Math.max(1,
        Math.floor((validWidth + cellGap) / columnPitch))
    readonly property int rowCount: Math.max(1,
        Math.floor((validHeight + cellGap) / rowPitch))
    readonly property int capacity: columnCount * rowCount
    readonly property real gridWidth: columnCount * cellWidth
        + Math.max(0, columnCount - 1) * cellGap
    readonly property real gridOriginX: validX + validWidth - gridWidth
    // `slots` is the durable layout. `previewSlots` is a private drag-time
    // layout: delegates animate it immediately, but it becomes durable only
    // when a valid drop is committed.
    property var slots: ({})
    property var previewSlots: ({})
    property bool dragActive: false
    property bool layoutResetPending: false
    property bool initialized: false
    property var lastDropId: null
    property var selectedIds: []
    property bool selectionBoxActive: false
    property bool externalDragActive: false
    property int externalDragAction: Qt.CopyAction
    property int outboundDropAction: Qt.IgnoreAction
    property string outboundDragSourceId: ""
    property bool outboundDragStarted: false
    property bool outboundDragPending: false
    property var outboundDragItem: null
    property var outboundDragImage: null
    property int outboundDragSerial: 0
    property point selectionStart: Qt.point(0, 0)
    property point selectionEnd: Qt.point(0, 0)
    property var selectionBase: []
    property var activeDragIds: []
    property string activeDragSourceId: ""
    property int activeDragAnchorIndex: 0
    property point activeDragStartCenter: Qt.point(0, 0)
    property point groupDragOffset: Qt.point(0, 0)
    property point dragCenter: Qt.point(0, 0)
    // Real desktop entries are supplied by DesktopFilesService through the
    // host window. This isolated surface deliberately does not add selection,
    // context menus, open actions, or filesystem mutations.
    property var entries: []
    property bool showExtensions: true
    property var folderCustomizations: ({})
    property var renameCallback: null
    property string renamingId: ""
    readonly property var entryIds: entries.map(function(entry) { return entry.path })
    readonly property var folderIds: entries.filter(function(entry) {
        return entry.kind === "folder"
    }).map(function(entry) { return entry.path })
    property string targetFolder: ""
    property string dragMode: "none" // none, addToFolder, reorderActive
    // Folder merging follows the complete grid item, including its title.
    // The circle is centred on the cell and spans its shorter dimension.
    readonly property real folderMergeRadius: Math.min(cellWidth, cellHeight) * 0.30
    readonly property int reorderHoverDelay: 500
    property int reorderHoverSlot: -1
    property int reorderCandidateSlot: -1
    property int reorderResolvedSlot: -1
    property string reorderCandidateId: ""
    // Delegates render the preview during a drag, otherwise the committed map.
    readonly property var visibleSlots: dragActive ? previewSlots : slots
    signal moveIntoFolderRequested(var sourceEntries, var targetFolder)
    signal contextMenuRequested(var entry, point pos)
    signal openRequested(var entry)
    signal activityRequested()
    signal externalUrlsDropped(var urls, int action)

    function acceptedExternalDropAction(dragEvent) {
        // DragEvent exposes QFlags<DropAction>. Convert it explicitly before
        // testing bits; strict JS equality can otherwise reject a valid
        // MoveAction and make Qt fall back to CopyAction.
        const proposed = Number(dragEvent.proposedAction)
        const supported = Number(dragEvent.supportedActions)
        if ((proposed & Qt.MoveAction) !== 0)
            return Qt.MoveAction
        if ((proposed & Qt.CopyAction) !== 0)
            return Qt.CopyAction
        if ((supported & Qt.MoveAction) !== 0)
            return Qt.MoveAction
        if ((supported & Qt.CopyAction) !== 0)
            return Qt.CopyAction
        return Qt.IgnoreAction
    }

    function externalDragUrls() {
        return activeDragIds.map(function(id) {
            return "file://" + encodeURIComponent(id).replace(/%2F/gi, "/")
        })
    }

    function completeActiveDesktopDrag(sourceId) {
        if (!dragActive || activeDragSourceId !== sourceId)
            return
        const mergeFolder = targetFolder
        const shouldMerge = dragMode === "addToFolder"
            && isMergeTargetValid(sourceId, mergeFolder)
        if (shouldMerge)
            mergeIntoFolder(activeDragIds, mergeFolder)
        else if (activeDragIds.length > 1)
            commitGroupDrop(dragCenter.x, dragCenter.y)
        else
            commitDrop(sourceId, dragCenter.x, dragCenter.y)
        finishDrag()
    }

    function isOwnSystemDrag(dragEvent) {
        return outboundDragItem !== null
            && dragEvent.source === outboundDragItem
    }

    function updateOwnSystemDrag(dropArea, dragEvent) {
        if (!dragActive || outboundDragSourceId === "")
            return
        const point = dropArea.mapToItem(root, dragEvent.x, dragEvent.y)
        groupDragOffset = Qt.point(point.x - activeDragStartCenter.x,
            point.y - activeDragStartCenter.y)
        dragCenter = point
        updateDrag(outboundDragSourceId, point)
        dragEvent.accept(Qt.MoveAction)
    }

    function clearOutboundDrag(item) {
        if (item && outboundDragItem !== item)
            return
        outboundDragStarted = false
        outboundDragPending = false
        outboundDragSourceId = ""
        outboundDragItem = null
        outboundDragImage = null
        outboundDragSerial += 1
    }

    function finishOutboundDrag(item, dropAction) {
        if (outboundDragItem !== item)
            return
        outboundDropAction = Number(dropAction)
        clearOutboundDrag(item)
        // A drop on this desktop is committed by DropArea.onDropped before
        // dragFinished arrives. External drops and cancellations only need to
        // discard the local preview; the receiving application owns the file
        // operation for a successful external drop.
        if (dragActive)
            finishDrag()
    }

    function isSelected(id) {
        return selectedIds.indexOf(id) >= 0
    }

    function isActiveDragItem(id) {
        return dragActive && activeDragIds.indexOf(id) >= 0
    }

    function selectOnly(id) {
        selectedIds = [id]
    }

    function toggleSelected(id) {
        const next = selectedIds.slice()
        const index = next.indexOf(id)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(id)
        selectedIds = next
    }

    function updateBoxSelection() {
        const minX = Math.min(selectionStart.x, selectionEnd.x)
        const maxX = Math.max(selectionStart.x, selectionEnd.x)
        const minY = Math.min(selectionStart.y, selectionEnd.y)
        const maxY = Math.max(selectionStart.y, selectionEnd.y)
        const next = selectionBase.slice()
        const visualWidth = 108
        const visualHeight = 104
        for (let index = 0; index < entryIds.length; ++index) {
            const id = entryIds[index]
            const slot = visibleSlots[id]
            if (slot === undefined)
                continue
            const point = pointForSlot(slot)
            const itemX = point.x + (cellWidth - visualWidth) / 2
            const itemY = point.y + 3
            const intersects = itemX < maxX && itemX + visualWidth > minX
                && itemY < maxY && itemY + visualHeight > minY
            if (intersects && next.indexOf(id) < 0)
                next.push(id)
        }
        selectedIds = next
    }

    function isFolderId(id) {
        return folderIds.indexOf(id) >= 0
    }

    function entryFor(id) {
        for (let index = 0; index < entries.length; ++index) {
            if (entries[index].path === id)
                return entries[index]
        }
        return null
    }

    function displayName(entry) {
        const path = entry && entry.path ? entry.path : ""
        const name = (entry && (entry.title || entry.name))
            || path.split("/").pop() || "未命名"
        if (showExtensions || (entry && entry.kind === "folder"))
            return name
        const extensionIndex = name.lastIndexOf(".")
        return extensionIndex > 0 ? name.slice(0, extensionIndex) : name
    }

    function folderCustomFor(id) {
        return folderCustomizations && folderCustomizations[id]
            ? folderCustomizations[id] : null
    }

    function beginRename(id) {
        if (!entryFor(id))
            return
        selectOnly(id)
        renamingId = id
    }

    function renameSelectionEnd(entry) {
        const name = entry && entry.name ? entry.name : ""
        if (entry && entry.kind === "folder")
            return name.length
        const extensionIndex = name.lastIndexOf(".")
        return extensionIndex > 0 ? extensionIndex : name.length
    }

    function iconFor(kind) {
        if (kind === "folder") return ""
        if (kind === "image") return ""
        if (kind === "pdf") return ""
        if (kind === "code") return ""
        if (kind === "text") return "󰈙"
        if (kind === "launcher") return ""
        return ""
    }

    function themeIconName(kind) {
        if (kind === "folder") return "folder"
        if (kind === "pdf") return "application-pdf"
        if (kind === "code") return "text-x-script"
        if (kind === "text") return "text-x-generic"
        return "application-octet-stream"
    }

    function themeIconSource(entry) {
        if (!entry || entry.kind === "image")
            return ""
        if (entry.kind === "launcher") {
            // AppLauncherConfigService publishes overrides asynchronously
            // after its tiny startup config read. Depend on the revision so
            // existing desktop delegates update when that read completes.
            AppPresentationService.revision
            const launcherId = entry.name || entry.path.split("/").pop()
            const override = AppPresentationService.overrideFor(launcherId,
                launcherId)
            return AppPresentationService.iconSource(override.icon || entry.icon)
        }
        try {
            return Quickshell.iconPath(themeIconName(entry.kind), true) || ""
        } catch (_) {
            return ""
        }
    }

    function folderAtSlot(slot) {
        const owner = ownersFor(visibleSlots)[slot]
        return owner !== undefined && isFolderId(owner) ? owner : ""
    }

    function folderAtPoint(pointX, pointY, sourceId) {
        // Grid gutters are reorder corridors: they never mean “merge”, but
        // slotAt() still maps them to a neighbouring cell for insertion.
        if (pointInGap(pointX, pointY))
            return ""
        const slot = slotAt(pointX, pointY)
        const folderId = folderAtSlot(slot)
        if (!folderId || folderId === sourceId || activeDragIds.indexOf(folderId) >= 0)
            return ""

        const cellPoint = pointForSlot(slot)
        const centerX = cellPoint.x + cellWidth / 2
        const centerY = cellPoint.y + cellHeight / 2
        const dx = pointX - centerX
        const dy = pointY - centerY
        return dx * dx + dy * dy <= folderMergeRadius * folderMergeRadius ? folderId : ""
    }

    function isMergeTargetValid(fileId, folderId) {
        return folderId !== ""
            && folderAtPoint(dragCenter.x, dragCenter.y, fileId) === folderId
    }

    function mergeIntoFolder(sourceIds, folderId) {
        const targetEntry = entryFor(folderId)
        if (!targetEntry || targetEntry.kind !== "folder")
            return
        const sourceEntries = []
        for (let index = 0; index < sourceIds.length; ++index) {
            const entry = entryFor(sourceIds[index])
            if (entry)
                sourceEntries.push(entry)
        }
        if (sourceEntries.length > 0)
            moveIntoFolderRequested(sourceEntries, targetEntry)
    }

    function copySlots(source) {
        const next = ({})
        const keys = Object.keys(source)
        for (let i = 0; i < keys.length; ++i)
            next[keys[i]] = source[keys[i]]
        return next
    }

    function pointForSlot(slot) {
        const column = columnCount - 1 - Math.floor(slot / rowCount)
        const row = slot % rowCount
        return Qt.point(gridOriginX + column * columnPitch, validY + row * rowPitch)
    }

    function slotAt(pointX, pointY) {
        if (pointX < validX || pointY < validY
                || pointX >= validX + validWidth || pointY >= validY + validHeight)
            return -1
        const localX = pointX - gridOriginX
        const localY = pointY - validY
        const column = Math.floor(localX / columnPitch)
        const row = Math.floor(localY / rowPitch)
        if (column < 0 || column >= columnCount || row < 0 || row >= rowCount)
            return -1
        return (columnCount - 1 - column) * rowCount + row
    }

    function pointInGap(pointX, pointY) {
        const localX = pointX - gridOriginX
        const localY = pointY - validY
        const column = Math.floor(localX / columnPitch)
        const row = Math.floor(localY / rowPitch)
        if (column < 0 || column >= columnCount || row < 0 || row >= rowCount)
            return false
        return localX - column * columnPitch >= cellWidth
            || localY - row * rowPitch >= cellHeight
    }

    function ownersFor(map) {
        const owners = ({})
        const keys = Object.keys(map)
        for (let i = 0; i < keys.length; ++i)
            owners[map[keys[i]]] = keys[i]
        return owners
    }

    // Empty slots update one entry. For an occupied target, shift the
    // collision chain toward the source slot: this is insertion, not a
    // fixed "push forward", so it never leaves a hole on the wrong side.
    function layoutAfterDrop(sourceSlots, id, pointX, pointY, occupiedOnly) {
        const target = slotAt(pointX, pointY)
        if (target < 0 || target >= capacity)
            return sourceSlots
        const next = copySlots(sourceSlots)
        const owners = ownersFor(next)
        const source = next[id]
        const occupant = owners[target]
        if (occupant === undefined || occupant === id) {
            if (occupiedOnly)
                return sourceSlots
            next[id] = target
            return next
        }

        delete next[id]
        delete owners[source]
        const direction = source > target ? 1 : -1
        let freeSlot = -1
        for (let slot = target + direction;
                slot >= 0 && slot < capacity;
                slot += direction) {
            if (owners[slot] === undefined) {
                freeSlot = slot
                break
            }
        }
        // No free slot in the insertion direction: preserve the layout.
        if (freeSlot < 0) {
            return sourceSlots
        }
        if (direction > 0) {
            for (let slot = freeSlot; slot > target; --slot) {
                const previous = owners[slot - 1]
                if (previous !== undefined) {
                    next[previous] = slot
                    owners[slot] = previous
                    delete owners[slot - 1]
                }
            }
        } else {
            for (let slot = freeSlot; slot < target; ++slot) {
                const nextOwner = owners[slot + 1]
                if (nextOwner !== undefined) {
                    next[nextOwner] = slot
                    owners[slot] = nextOwner
                    delete owners[slot + 1]
                }
            }
        }
        next[id] = target
        return next
    }

    function applyPreview(id, pointX, pointY) {
        // Real-time reorder: only the transient layout changes here.
        const next = layoutAfterDrop(previewSlots, id, pointX, pointY, true)
        if (next !== previewSlots) {
            lastDropId = id
            previewSlots = next
        }
    }

    function layoutAfterGroupDrop(sourceSlots, ids, anchorIndex, targetSlot) {
        if (ids.length === 0 || targetSlot < 0 || targetSlot >= capacity)
            return sourceSlots
        const startSlot = Math.max(0, Math.min(capacity - ids.length,
            targetSlot - anchorIndex))
        const anchorId = ids[anchorIndex]
        const moveTowardHigherSlots = sourceSlots[anchorId] < targetSlot
        let next = sourceSlots
        if (moveTowardHigherSlots) {
            for (let index = ids.length - 1; index >= 0; --index) {
                const point = pointForSlot(startSlot + index)
                next = layoutAfterDrop(next, ids[index],
                    point.x + cellWidth / 2, point.y + cellHeight / 2, false)
            }
        } else {
            for (let index = 0; index < ids.length; ++index) {
                const point = pointForSlot(startSlot + index)
                next = layoutAfterDrop(next, ids[index],
                    point.x + cellWidth / 2, point.y + cellHeight / 2, false)
            }
        }
        return next
    }

    function applyGroupPreview(targetSlot) {
        const next = layoutAfterGroupDrop(previewSlots, activeDragIds,
            activeDragAnchorIndex, targetSlot)
        if (next !== previewSlots) {
            lastDropId = activeDragIds[activeDragAnchorIndex]
            previewSlots = next
        }
    }

    function commitDrop(id, pointX, pointY) {
        // The sole ordinary-drop commit point. Invalid desktop coordinates
        // intentionally keep `slots` unchanged.
        if (slotAt(pointX, pointY) < 0)
            return
        const next = layoutAfterDrop(previewSlots, id, pointX, pointY, false)
        lastDropId = id
        slots = next
        previewSlots = next
    }

    function commitGroupDrop(pointX, pointY) {
        const targetSlot = slotAt(pointX, pointY)
        if (targetSlot < 0 || activeDragIds.length === 0)
            return
        const anchorId = activeDragIds[activeDragAnchorIndex]
        if (previewSlots[anchorId] !== targetSlot)
            previewSlots = layoutAfterGroupDrop(previewSlots, activeDragIds,
                activeDragAnchorIndex, targetSlot)
        lastDropId = anchorId
        slots = previewSlots
    }

    function resetLayout(sourceEntries) {
        if (dragActive) {
            layoutResetPending = true
            return
        }
        const currentEntries = sourceEntries || []
        const initial = ({})
        // Use the signal's current entries directly. A derived `entryIds`
        // binding may still contain the previous value while onEntriesChanged
        // is running, which would make every filesystem update one step late.
        for (let index = 0; index < currentEntries.length && index < capacity; ++index)
            initial[currentEntries[index].path] = index
        selectedIds = selectedIds.filter(function(id) {
            return initial[id] !== undefined
        })
        if (renamingId && initial[renamingId] === undefined)
            renamingId = ""
        slots = initial
        previewSlots = initial
        layoutResetPending = false
        initialized = true
    }

    function clearFolderTarget() {
        targetFolder = ""
        if (dragMode === "addToFolder")
            dragMode = "none"
    }

    function cancelReorderCandidate() {
        reorderDelayTimer.stop()
        reorderCandidateId = ""
        reorderCandidateSlot = -1
    }

    function resetReorderTracking() {
        cancelReorderCandidate()
        reorderHoverSlot = -1
        reorderResolvedSlot = -1
    }

    function canGroupReorder(slot) {
        if (slot < 0 || slot >= capacity)
            return false
        const owner = ownersFor(previewSlots)[slot]
        return owner !== undefined && activeDragIds.indexOf(owner) < 0
    }

    function scheduleReorder(id, slot) {
        if (slot === reorderResolvedSlot)
            return
        if (reorderCandidateId === id && reorderCandidateSlot === slot
                && reorderDelayTimer.running)
            return
        reorderCandidateId = id
        reorderCandidateSlot = slot
        reorderDelayTimer.restart()
    }

    Timer {
        id: reorderDelayTimer
        interval: root.reorderHoverDelay
        repeat: false
        onTriggered: {
            const id = root.reorderCandidateId
            const slot = root.reorderCandidateSlot
            root.reorderCandidateId = ""
            root.reorderCandidateSlot = -1

            // Pointer movement may have changed while the timer was queued.
            // Only the still-current edge/cell candidate may rearrange items.
            if (!root.dragActive || slot !== root.reorderHoverSlot
                    || root.slotAt(root.dragCenter.x, root.dragCenter.y) !== slot
                    || root.folderAtPoint(root.dragCenter.x,
                        root.dragCenter.y, id) !== "")
                return

            if (root.activeDragIds.length > 1) {
                if (!root.canGroupReorder(slot))
                    return
                root.applyGroupPreview(slot)
            } else {
                if (!root.canReorder(id, slot))
                    return
                const point = root.pointForSlot(slot)
                root.applyPreview(id, point.x + root.cellWidth / 2,
                    point.y + root.cellHeight / 2)
            }
            root.reorderResolvedSlot = slot
            root.dragMode = "reorderActive"
        }
    }

    function beginDrag(sourceId) {
        // A new drag always starts from the committed snapshot, never from a
        // preview that a prior drag abandoned.
        dragActive = true
        previewSlots = copySlots(slots)
        if (!isSelected(sourceId))
            selectOnly(sourceId)
        activeDragIds = selectedIds.filter(function(id) {
            return slots[id] !== undefined
        }).sort(function(left, right) {
            return slots[left] - slots[right]
        })
        activeDragSourceId = sourceId
        activeDragAnchorIndex = Math.max(0, activeDragIds.indexOf(sourceId))
        groupDragOffset = Qt.point(0, 0)
        lastDropId = null
        dragMode = "none"
        resetReorderTracking()
        clearFolderTarget()
    }

    function finishDrag() {
        // Discard any uncommitted preview after a drop or cancellation.
        resetReorderTracking()
        clearFolderTarget()
        dragActive = false
        if (layoutResetPending)
            resetLayout(entries)
        else
            previewSlots = slots
        activeDragIds = []
        activeDragSourceId = ""
        activeDragAnchorIndex = 0
        activeDragStartCenter = Qt.point(0, 0)
        groupDragOffset = Qt.point(0, 0)
        dragMode = "none"
    }

    function canReorder(id, slot) {
        if (slot < 0 || slot >= capacity)
            return false
        const owner = ownersFor(previewSlots)[slot]
        return owner !== undefined && owner !== id
    }

    function updateDrag(id, point) {
        const slot = slotAt(point.x, point.y)
        if (slot !== reorderHoverSlot) {
            cancelReorderCandidate()
            reorderHoverSlot = slot
            reorderResolvedSlot = -1
        }

        const folderId = folderAtPoint(point.x, point.y, id)
        if (folderId !== "") {
            // The centre zone wins immediately and cancels the pending edge
            // reorder. Re-entering the edge starts a fresh 500 ms dwell.
            cancelReorderCandidate()
            targetFolder = folderId
            dragMode = "addToFolder"
            return slot
        }

        clearFolderTarget()
        const reorderable = activeDragIds.length > 1
            ? canGroupReorder(slot) : canReorder(id, slot)
        if (reorderable)
            scheduleReorder(id, slot)
        else
            cancelReorderCandidate()
        return slot
    }

    MouseArea {
        id: backgroundSelection
        x: root.validX
        y: root.validY
        width: root.validWidth
        height: root.validHeight
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        z: 0

        function rootPoint(mouse) {
            return mapToItem(root, mouse.x, mouse.y)
        }

        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.selectedIds = []
                root.contextMenuRequested(null, rootPoint(mouse))
                return
            }
            // A plain desktop press must end inline editing. MouseArea does
            // not take keyboard focus by itself, so explicitly return focus
            // to the host; the TextInput's focus-loss handler commits first.
            if (root.renamingId !== "")
                root.activityRequested()
            const point = rootPoint(mouse)
            root.selectionStart = point
            root.selectionEnd = point
            root.selectionBoxActive = false
            root.selectionBase = (mouse.modifiers & Qt.ControlModifier)
                ? root.selectedIds.slice() : []
            if (!(mouse.modifiers & Qt.ControlModifier))
                root.selectedIds = []
        }
        onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton))
                return
            const point = rootPoint(mouse)
            root.selectionEnd = point
            if (!root.selectionBoxActive
                    && (Math.abs(point.x - root.selectionStart.x) > 4
                        || Math.abs(point.y - root.selectionStart.y) > 4))
                root.selectionBoxActive = true
            if (root.selectionBoxActive)
                root.updateBoxSelection()
        }
        onReleased: function(mouse) {
            if (root.selectionBoxActive) {
                root.selectionEnd = rootPoint(mouse)
                root.updateBoxSelection()
            }
            root.selectionBoxActive = false
        }
        onCanceled: root.selectionBoxActive = false
    }

    Rectangle {
        x: Math.min(root.selectionStart.x, root.selectionEnd.x)
        y: Math.min(root.selectionStart.y, root.selectionEnd.y)
        width: Math.abs(root.selectionEnd.x - root.selectionStart.x)
        height: Math.abs(root.selectionEnd.y - root.selectionStart.y)
        visible: root.selectionBoxActive
        color: Qt.rgba(0.20, 0.48, 0.92, 0.16)
        border.width: 1
        border.color: Qt.rgba(0.50, 0.72, 1, 0.72)
        z: 50
    }

    DropArea {
        id: desktopDropArea
        x: root.validX
        y: root.validY
        width: root.validWidth
        height: root.validHeight
        z: 200
        onEntered: function(drag) {
            if (root.isOwnSystemDrag(drag)) {
                root.externalDragActive = false
                root.updateOwnSystemDrag(desktopDropArea, drag)
                return
            }
            if (!drag.hasUrls || drag.source) {
                drag.accepted = false
                root.externalDragActive = false
                return
            }
            root.externalDragAction = root.acceptedExternalDropAction(drag)
            if (root.externalDragAction === Qt.IgnoreAction) {
                drag.accepted = false
                root.externalDragActive = false
                return
            }
            drag.accept(root.externalDragAction)
            root.externalDragActive = true
        }
        onPositionChanged: function(drag) {
            if (root.isOwnSystemDrag(drag)) {
                root.updateOwnSystemDrag(desktopDropArea, drag)
                return
            }
            if (!drag.hasUrls || drag.source)
                return
            root.externalDragAction = root.acceptedExternalDropAction(drag)
            if (root.externalDragAction === Qt.IgnoreAction)
                return
            // Ctrl/Shift may change Dolphin's proposed action after the
            // pointer has already entered the desktop.
            drag.accept(root.externalDragAction)
        }
        onExited: {
            root.externalDragActive = false
            root.externalDragAction = Qt.CopyAction
            if (root.dragActive && root.outboundDragStarted) {
                // Leaving the desktop cancels only the local preview. The
                // native drag remains active so any window under the pointer
                // (Dolphin, QQ, etc.) can negotiate the same URI-list drag.
                root.resetReorderTracking()
                root.clearFolderTarget()
                root.previewSlots = root.copySlots(root.slots)
                root.dragMode = "none"
            }
        }
        onDropped: function(drop) {
            root.externalDragActive = false
            if (root.isOwnSystemDrag(drop)) {
                root.updateOwnSystemDrag(desktopDropArea, drop)
                const sourceId = root.outboundDragSourceId
                root.completeActiveDesktopDrag(sourceId)
                drop.accept(Qt.MoveAction)
                root.externalDragAction = Qt.CopyAction
                return
            }
            if (!drop.hasUrls || drop.source) {
                drop.accepted = false
                return
            }
            const action = root.acceptedExternalDropAction(drop)
            if (action === Qt.IgnoreAction) {
                drop.accepted = false
                return
            }
            root.externalUrlsDropped(drop.urls, action)
            // Return the exact operation we perform to Dolphin, so its drag
            // cursor and source-side completion semantics stay consistent.
            drop.accept(action)
            root.externalDragAction = Qt.CopyAction
        }
    }

    Rectangle {
        x: root.validX
        y: root.validY
        width: root.validWidth
        height: root.validHeight
        visible: root.externalDragActive
        color: Qt.rgba(1, 1, 1, 0.06)
        border { width: 1; color: Qt.rgba(1, 1, 1, 0.32) }
        radius: 16
        z: 190
        Text {
            anchors.centerIn: parent
            text: root.externalDragAction === Qt.MoveAction
                ? "移动到桌面" : "复制到桌面"
            color: Qt.rgba(1, 1, 1, 0.78)
        }
    }

    // The desktop service publishes whole snapshots. Feeding those arrays
    // directly to Repeater destroys every delegate on each create/delete,
    // including unchanged image previews. This model is reconciled by path so
    // an unrelated filesystem update leaves existing delegates alive.
    ListModel {
        id: desktopEntryModel
    }

    function syncEntryModel(sourceEntries) {
        const next = sourceEntries || []
        const nextPaths = ({})
        for (let i = 0; i < next.length; ++i)
            nextPaths[next[i].path] = true

        for (let i = desktopEntryModel.count - 1; i >= 0; --i) {
            if (!nextPaths[desktopEntryModel.get(i).path])
                desktopEntryModel.remove(i)
        }

        for (let target = 0; target < next.length; ++target) {
            const entry = next[target]
            let current = -1
            for (let i = target; i < desktopEntryModel.count; ++i) {
                if (desktopEntryModel.get(i).path === entry.path) {
                    current = i
                    break
                }
            }
            if (current < 0) {
                desktopEntryModel.insert(target, { path: entry.path, entry: entry })
            } else {
                if (current !== target)
                    desktopEntryModel.move(current, target, 1)
                // Keep metadata fresh without replacing the delegate itself.
                desktopEntryModel.set(target, { path: entry.path, entry: entry })
            }
        }
    }

    Component.onCompleted: syncEntryModel(entries)
    onEntriesChanged: {
        resetLayout(entries)
        syncEntryModel(entries)
    }

    Repeater {
        model: desktopEntryModel
        delegate: Item {
            id: delegateRoot
            required property var entry
            readonly property string itemId: entry?.path || ""
            readonly property bool isFolder: entry && entry.kind === "folder"
            readonly property var folderCustom: root.folderCustomFor(itemId)
            readonly property bool usesCustomFolderVisual: isFolder
                && folderCustom && (!!folderCustom.color || !!folderCustom.emoji)
            readonly property string fileTitleIcon: folderCustom
                    && folderCustom.emoji
                ? folderCustom.emoji : ""
            property double previousTapTime: 0
            // Selected group members keep their committed origins while the
            // shared pointer translation moves their visuals. Only unselected
            // neighbours render preview slots and animate out of the way.
            readonly property int slot: root.isActiveDragItem(itemId)
                ? (root.slots[itemId] ?? -1) : (root.visibleSlots[itemId] ?? -1)
            readonly property point slotPoint: root.pointForSlot(slot)
            x: slotPoint.x
            y: slotPoint.y
            width: root.cellWidth
            height: root.cellHeight
            visible: slot >= 0
            Behavior on x {
                enabled: root.initialized && !root.isActiveDragItem(delegateRoot.itemId)
                    && root.lastDropId !== delegateRoot.itemId
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: root.initialized && !root.isActiveDragItem(delegateRoot.itemId)
                    && root.lastDropId !== delegateRoot.itemId
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Item {
                id: dragVisual
                width: root.cellWidth
                height: root.cellHeight
                opacity: root.outboundDragStarted
                        && root.isActiveDragItem(delegateRoot.itemId) ? 0 : 1
                z: dragHandler.active ? 100
                    : (root.isActiveDragItem(delegateRoot.itemId) ? 90 : 0)
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.onDragFinished: function(dropAction) {
                    root.finishOutboundDrag(dragVisual, dropAction)
                    dragVisual.Drag.mimeData = ({})
                    dragVisual.Drag.imageSource = ""
                }
                transform: Translate {
                    x: root.isActiveDragItem(delegateRoot.itemId)
                            && delegateRoot.itemId !== root.activeDragSourceId
                        ? root.groupDragOffset.x : 0
                    y: root.isActiveDragItem(delegateRoot.itemId)
                            && delegateRoot.itemId !== root.activeDragSourceId
                        ? root.groupDragOffset.y : 0
                }
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }
                states: State {
                    when: dragHandler.active
                    ParentChange { target: dragVisual; parent: root }
                    AnchorChanges {
                        target: dragVisual
                        anchors {
                            horizontalCenter: undefined
                            verticalCenter: undefined
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    width: Math.min(108, parent.width - 8)
                    height: Math.min(root.rowPitch - 4,
                        Math.max(104, fileNameLabel.y + fileNameLabel.implicitHeight + 6))
                    radius: 12
                    color: root.isSelected(delegateRoot.itemId)
                        ? Qt.rgba(0.18, 0.42, 0.78, 0.38)
                        : Qt.rgba(0, 0, 0, 0.24)
                    opacity: root.isSelected(delegateRoot.itemId)
                        || (hoverHandler.hovered && !dragHandler.active) ? 1 : 0
                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }

                Rectangle {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: root.iconVisualTop
                    }
                    width: root.iconVisualSize
                    height: root.iconVisualSize
                    radius: delegateRoot.isFolder ? 12 : 8
                    color: root.targetFolder === delegateRoot.itemId
                        ? Qt.rgba(1, 0.78, 0.26, 0.28) : "transparent"
                    border.width: root.targetFolder === delegateRoot.itemId ? 2 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.72)
                    scale: hoverHandler.hovered && !dragHandler.active ? 1.035 : 1
                    transform: Translate {
                        y: hoverHandler.hovered && !dragHandler.active ? -2 : 0
                        Behavior on y {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    Behavior on color { ColorAnimation { duration: 90 } }
                    Canvas {
                        id: customFolderCanvas
                        anchors.fill: parent
                        visible: delegateRoot.usesCustomFolderVisual
                        readonly property color baseColor: delegateRoot.folderCustom
                                && delegateRoot.folderCustom.color
                            ? delegateRoot.folderCustom.color : "#70b6ff"
                        onBaseColorChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        function shade(colorValue, factor) {
                            const c = Qt.color(colorValue)
                            const r = Math.max(0,
                                Math.min(255, Math.round(c.r * 255 * factor)))
                            const g = Math.max(0,
                                Math.min(255, Math.round(c.g * 255 * factor)))
                            const b = Math.max(0,
                                Math.min(255, Math.round(c.b * 255 * factor)))
                            return "rgba(" + r + "," + g + "," + b + "," + c.a + ")"
                        }

                        function roundRect(ctx, x, y, w, h, radius) {
                            ctx.beginPath()
                            ctx.moveTo(x + radius, y)
                            ctx.lineTo(x + w - radius, y)
                            ctx.arcTo(x + w, y, x + w, y + radius, radius)
                            ctx.lineTo(x + w, y + h - radius)
                            ctx.arcTo(x + w, y + h, x + w - radius,
                                y + h, radius)
                            ctx.lineTo(x + radius, y + h)
                            ctx.arcTo(x, y + h, x, y + h - radius, radius)
                            ctx.lineTo(x, y + radius)
                            ctx.arcTo(x, y, x + radius, y, radius)
                            ctx.closePath()
                        }

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const w = width
                            const h = height
                            const margin = w * 0.10
                            const tabHeight = h * 0.14
                            const bodyX = margin
                            const bodyY = margin + tabHeight
                            const bodyWidth = w - margin * 2
                            const bodyHeight = h - margin - bodyY
                            const corner = Math.min(bodyWidth, bodyHeight) * 0.18

                            ctx.fillStyle = shade(baseColor, 0.72)
                            ctx.globalAlpha = 0.92
                            ctx.beginPath()
                            ctx.moveTo(bodyX, bodyY)
                            ctx.lineTo(bodyX + bodyWidth * 0.42, bodyY)
                            ctx.lineTo(bodyX + bodyWidth * 0.42
                                + tabHeight * 0.7, bodyY - tabHeight)
                            ctx.lineTo(bodyX + bodyWidth * 0.72,
                                bodyY - tabHeight)
                            ctx.arcTo(bodyX + bodyWidth * 0.72 + corner,
                                bodyY - tabHeight,
                                bodyX + bodyWidth * 0.72 + corner,
                                bodyY - tabHeight + corner, corner)
                            ctx.lineTo(bodyX + bodyWidth * 0.72 + corner, bodyY)
                            ctx.closePath()
                            ctx.fill()

                            ctx.fillStyle = shade(baseColor, 1.0)
                            ctx.globalAlpha = 0.90
                            roundRect(ctx, bodyX, bodyY, bodyWidth,
                                bodyHeight, corner)
                            ctx.fill()

                            ctx.fillStyle = "rgba(255,255,255,0.18)"
                            ctx.globalAlpha = 1.0
                            ctx.beginPath()
                            ctx.moveTo(bodyX + corner, bodyY)
                            ctx.lineTo(bodyX + bodyWidth - corner, bodyY)
                            ctx.lineTo(bodyX + bodyWidth - corner,
                                bodyY + bodyHeight * 0.12)
                            ctx.lineTo(bodyX + corner,
                                bodyY + bodyHeight * 0.12)
                            ctx.closePath()
                            ctx.fill()

                            ctx.strokeStyle = "rgba(0,0,0,0.16)"
                            ctx.lineWidth = 1
                            roundRect(ctx, bodyX, bodyY, bodyWidth,
                                bodyHeight, corner)
                            ctx.stroke()
                        }
                    }
                    Item {
                        id: fileThumbnailFrame
                        anchors.fill: parent
                        anchors.margins: 4
                        visible: fileThumbnail.status === Image.Ready

                        Image {
                            id: fileThumbnail
                            anchors.fill: parent
                            source: delegateRoot.entry
                                    && delegateRoot.entry.kind === "image"
                                ? "file://" + delegateRoot.entry.path : ""
                            fillMode: Image.PreserveAspectCrop
                            // Desktop images can be many thousands of pixels
                            // wide, while this surface draws a ~60 px icon.
                            // Requesting a 2x thumbnail keeps enough detail
                            // for HiDPI displays without retaining the full
                            // decoded RGBA image in the QML image cache.
                            sourceSize.width: Math.max(1, Math.ceil(width * 2))
                            sourceSize.height: Math.max(1, Math.ceil(height * 2))
                            asynchronous: true
                            cache: true
                            smooth: true
                            // OpacityMask renders this source. Hiding only the
                            // source avoids drawing the same image twice.
                            visible: false
                        }
                        Rectangle {
                            id: fileThumbnailMask
                            anchors.fill: parent
                            radius: Math.min(width, height) * 0.05
                            visible: false
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: fileThumbnail
                            maskSource: fileThumbnailMask
                        }
                    }
                    IconImage {
                        id: fileThemeIcon
                        anchors.fill: parent
                        anchors.margins: 4
                        source: root.themeIconSource(delegateRoot.entry)
                        asynchronous: true
                        visible: source !== "" && status === Image.Ready
                            && !delegateRoot.usesCustomFolderVisual
                    }
                    Text {
                        anchors.centerIn: parent
                        text: root.iconFor(delegateRoot.entry ? delegateRoot.entry.kind : "")
                        visible: !fileThumbnailFrame.visible && !fileThemeIcon.visible
                            && !delegateRoot.usesCustomFolderVisual
                        color: "white"
                        style: Text.Outline
                        styleColor: Qt.rgba(0, 0, 0, 0.5)
                        font {
                            family: "LXGW WenKai Mono Nerd Font"
                            pixelSize: root.iconVisualSize * 0.68
                        }
                    }
                    Text {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            top: parent.top
                            topMargin: parent.height * 0.36
                        }
                        visible: delegateRoot.usesCustomFolderVisual
                            && !!delegateRoot.folderCustom.emoji
                        text: visible ? delegateRoot.folderCustom.emoji : ""
                        font {
                            family: "Noto Color Emoji"
                            pixelSize: root.iconVisualSize * 0.36
                        }
                    }
                }
                Item {
                    id: fileNameLabel
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: root.iconVisualTop + root.iconVisualSize + 3
                    }
                    width: Math.min(94, parent.width - 18)
                    implicitHeight: fileTitleText.implicitHeight
                    height: implicitHeight
                    visible: root.renamingId !== delegateRoot.itemId

                    Text {
                        id: fileTitleIcon
                        visible: delegateRoot.fileTitleIcon !== ""
                        width: visible ? implicitWidth : 0
                        anchors.verticalCenter: fileTitleText.verticalCenter
                        // Place the icon beside the text actually painted,
                        // rather than at the left edge of the label's box.
                        x: Math.max(0, fileTitleText.x
                            + (fileTitleText.width - fileTitleText.paintedWidth) / 2
                            - width - 2)
                        text: delegateRoot.fileTitleIcon
                        font {
                            family: "Noto Color Emoji"
                            pixelSize: Math.max(9, Math.round(
                                fileTitleText.font.pixelSize * 0.75))
                        }
                    }
                    Text {
                        id: fileTitleText
                        x: fileTitleIcon.visible
                            ? fileTitleIcon.implicitWidth + 2 : 0
                        width: parent.width - x
                        text: root.displayName(delegateRoot.entry)
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: delegateRoot.folderCustom
                                && delegateRoot.folderCustom.color
                            ? delegateRoot.folderCustom.color : "white"
                    }
                }
                Rectangle {
                    id: inlineRenameFrame
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: root.iconVisualTop + root.iconVisualSize + 1
                    }
                    width: Math.min(parent.width - 12,
                        Math.max(72, inlineRenameInput.contentWidth + 18))
                    height: 24
                    radius: 5
                    visible: root.renamingId === delegateRoot.itemId
                    color: "white"
                    border { width: 1; color: "#0a84ff" }
                    z: 110

                    function commit() {
                        if (root.renamingId !== delegateRoot.itemId)
                            return
                        const name = inlineRenameInput.text.trim()
                        if (!name)
                            return
                        if (root.renameCallback
                                && root.renameCallback(delegateRoot.entry, name))
                            root.renamingId = ""
                    }

                    onVisibleChanged: {
                        if (!visible)
                            return
                        inlineRenameInput.text = delegateRoot.entry
                            ? delegateRoot.entry.name : ""
                        inlineRenameInput.forceActiveFocus()
                        inlineRenameInput.select(0,
                            root.renameSelectionEnd(delegateRoot.entry))
                    }

                    TextInput {
                        id: inlineRenameInput
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        color: "#1d1d1f"
                        selectByMouse: true
                        selectionColor: "#252529"
                        selectedTextColor: "white"
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        onActiveFocusChanged: {
                            if (!activeFocus && inlineRenameFrame.visible)
                                inlineRenameFrame.commit()
                        }
                        Keys.onReturnPressed: function(event) {
                            inlineRenameFrame.commit()
                            event.accepted = true
                        }
                        Keys.onEscapePressed: function(event) {
                            root.renamingId = ""
                            event.accepted = true
                        }
                    }
                }
                Item {
                    id: interactionRegion
                    x: (parent.width - width) / 2
                    y: 2
                    width: Math.min(108, parent.width - 8)
                    height: Math.min(root.rowPitch - 4,
                        Math.max(104, fileNameLabel.y + fileNameLabel.implicitHeight + 6))
                    z: 109

                    HoverHandler {
                        id: hoverHandler
                        enabled: !dragHandler.active
                            && root.renamingId !== delegateRoot.itemId
                        cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.renamingId !== delegateRoot.itemId
                        acceptedButtons: Qt.RightButton
                        onPressed: function(mouse) {
                            if (!root.isSelected(delegateRoot.itemId))
                                root.selectOnly(delegateRoot.itemId)
                            root.activityRequested()
                            root.contextMenuRequested(delegateRoot.entry,
                                mapToItem(root, mouse.x, mouse.y))
                            mouse.accepted = true
                        }
                    }
                }
                TapHandler {
                    enabled: root.renamingId !== delegateRoot.itemId
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.NoModifier
                    onTapped: {
                        const wasSelected = root.isSelected(delegateRoot.itemId)
                        const now = Date.now()
                        const elapsed = now - delegateRoot.previousTapTime
                        delegateRoot.previousTapTime = now
                        root.selectOnly(delegateRoot.itemId)
                        root.activityRequested()
                        if (wasSelected && elapsed >= 350 && elapsed <= 1200)
                            root.beginRename(delegateRoot.itemId)
                    }
                    onDoubleTapped: root.openRequested(delegateRoot.entry)
                }
                TapHandler {
                    enabled: root.renamingId !== delegateRoot.itemId
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.ControlModifier
                    onTapped: {
                        root.toggleSelected(delegateRoot.itemId)
                        root.activityRequested()
                    }
                }
                DragHandler {
                    id: dragHandler
                    enabled: root.renamingId !== delegateRoot.itemId
                    cursorShape: Qt.ClosedHandCursor
                    onActiveChanged: {
                        if (active) {
                            root.beginDrag(delegateRoot.itemId)
                            root.dragCenter = root.mapFromItem(dragVisual,
                                dragVisual.width / 2, dragVisual.height / 2)
                            root.activeDragStartCenter = root.dragCenter
                            root.outboundDropAction = Qt.IgnoreAction
                            root.outboundDragSourceId = delegateRoot.itemId
                            root.outboundDragStarted = false
                            root.outboundDragPending = true
                            root.outboundDragItem = dragVisual
                            root.outboundDragSerial += 1
                            const dragSerial = root.outboundDragSerial
                            dragVisual.Drag.hotSpot = Qt.point(
                                Math.max(0, Math.min(dragVisual.width,
                                    dragHandler.centroid.position.x)),
                                Math.max(0, Math.min(dragVisual.height,
                                    dragHandler.centroid.position.y)))
                            dragVisual.Drag.mimeData = {
                                "text/uri-list": root.externalDragUrls()
                            }
                            // Qt's official Automatic-drag pattern snapshots
                            // the source before handing pointer ownership to
                            // the compositor. The native drag image then tracks
                            // the cursor in this desktop and in other apps.
                            dragVisual.grabToImage(function(result) {
                                if (root.outboundDragSerial !== dragSerial
                                        || !dragHandler.active
                                        || root.outboundDragItem !== dragVisual) {
                                    if (root.outboundDragSerial === dragSerial)
                                        root.outboundDragPending = false
                                    return
                                }
                                root.outboundDragImage = result
                                dragVisual.Drag.imageSource = result.url
                                root.outboundDragPending = false
                                root.outboundDragStarted = true
                                dragVisual.Drag.active = true
                            })
                        } else {
                            const sourceId = delegateRoot.itemId
                            if (root.outboundDragStarted)
                                dragVisual.Drag.active = false
                            // dragFinished normally owns system-DnD cleanup.
                            // The deferred fallback covers cancellation and a
                            // release before grabToImage has completed.
                            Qt.callLater(function() {
                                if (!root.dragActive)
                                    return
                                if (root.outboundDragStarted) {
                                    root.clearOutboundDrag(dragVisual)
                                    root.finishDrag()
                                    return
                                }
                                root.clearOutboundDrag(dragVisual)
                                dragVisual.Drag.mimeData = ({})
                                dragVisual.Drag.imageSource = ""
                                root.completeActiveDesktopDrag(sourceId)
                            })
                        }
                    }
                    onActiveTranslationChanged: {
                        if (active) {
                            root.groupDragOffset = activeTranslation
                            root.dragCenter = root.mapFromItem(dragVisual,
                                dragVisual.width / 2, dragVisual.height / 2)
                            // Before the native drag starts this preserves the
                            // zero-latency local response. Afterwards the
                            // desktop DropArea receives the system drag moves.
                            if (!root.outboundDragStarted)
                                root.updateDrag(delegateRoot.itemId,
                                    root.dragCenter)
                        }
                    }
                }
            }
        }
    }
}
