import QtQuick

// Dynamic gallery preview host for any installed widget package on disk.
// Loads `$XDG_DATA_HOME/kos/widgets/<id>/Snapshot.qml`, calls
// `getSnapshot(widgetSize)`, and passes that plain snapshot object (along with
// a preview-only `host` stub whose `isPreview === true` and whose
// `invokeAction` is a no-op) into the package's `Widget.qml` BEFORE
// `Component.onCompleted` runs.
Item {
    id: root

    property string packageId: ""
    property string widgetEntry: ""
    property string snapshotEntry: ""
    property string packageRevision: ""
    property string containerType: "desktop"
    property string containerOrientation: "horizontal"
    property var widgetSize: [1, 1]
    property var appearance: WidgetHostService.widgetAppearance
    property string errorMessage: ""
    property bool failed: false

    property var backgroundSpec: null
    property string surfaceShape: "roundedRect"
    property bool useImplicitHeight: false
    readonly property bool ready: root._widgetItem !== null && !root.failed
    readonly property real preferredContentHeight: {
        if (!root._widgetItem) return 0
        const explicitH = root._widgetItem.popupHeight
        if (explicitH !== undefined && explicitH !== null
                && Number.isFinite(Number(explicitH)) && Number(explicitH) > 0)
            return Number(explicitH)
        return Number(root._widgetItem.implicitHeight) > 0
            ? Number(root._widgetItem.implicitHeight) : 0
    }

    property var _snapshotData: null
    property bool _completed: false
    property var _snapshotItem: null
    property var _snapshotComponent: null
    property Item _widgetItem: null
    property var _widgetComponent: null
    property bool _itemShadowsData: false
    property string _snapshotUrl: ""
    property string _widgetUrl: ""
    property int _snapshotToken: 0
    property int _widgetToken: 0

    function _toFileUrl(path, rev) {
        const p = String(path ?? "")
        if (p.length === 0) return ""
        const base = p.startsWith("file://") ? p : ("file://" + p)
        const r = String(rev ?? "")
        return r.length > 0 ? (base + "?rev=" + encodeURIComponent(r)) : base
    }

    function _plainSpan() {
        const s = root.widgetSize
        if (s != null && typeof s !== "string" && s.length === 2)
            return [Number(s[0]), Number(s[1])]
        return [1, 1]
    }

    // Preview-only host proxy: `isPreview === true` tells widgets that prefer
    // direct `host.<source>` access to render from `snapshot` (or legacy `data`)
    // instead of live desktop state, and disables reverse actions.
    QtObject {
        id: previewHostProxy
        readonly property int sdkVersion: WidgetHostService.sdkVersion
        readonly property int apiRevision: WidgetHostService.apiRevision
        readonly property string locale: WidgetHostService.locale
        readonly property var availableSources: WidgetHostService.availableSources
        readonly property bool isPreview: true
        readonly property bool active: false
        readonly property bool visible: root.visible
        readonly property string container: root.containerType
        readonly property string orientation: root.containerOrientation
        readonly property string packageId: root.packageId
        readonly property string instanceId: ""
        readonly property var clock: null
        readonly property var media: null
        readonly property var weather: null
        readonly property var system: null
        readonly property var activity: null
        readonly property var pim: null
        readonly property var settings: ({})
        readonly property var lastActionResult: null

        function hasAction(actionName) {
            return WidgetHostService.hasAction(actionName)
        }
        function invokeAction(actionName, payload) {
            return { ok: false, code: "unavailable", message: "Actions are disabled in gallery preview" }
        }
        function saveSettings(next) {
            return false
        }
        function patchSettings(partial) {
            return false
        }
    }

    Item {
        id: widgetContainer
        anchors.fill: parent
    }

    function _destroySnapshot() {
        root._snapshotToken++
        if (root._snapshotItem) {
            root._snapshotItem.destroy()
            root._snapshotItem = null
        }
        if (root._snapshotComponent) {
            root._snapshotComponent.destroy()
            root._snapshotComponent = null
        }
        root._snapshotUrl = ""
        root._snapshotData = null
    }

    function _destroyWidget() {
        root._widgetToken++
        root.backgroundSpec = null
        root.surfaceShape = "roundedRect"
        if (root._widgetItem) {
            root._widgetItem.destroy()
            root._widgetItem = null
        }
        if (root._widgetComponent) {
            root._widgetComponent.destroy()
            root._widgetComponent = null
        }
        root._itemShadowsData = false
        root._widgetUrl = ""
    }

    function _refreshSnapshot() {
        const snap = root._snapshotItem
        if (!snap || typeof snap.getSnapshot !== "function") {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = "Snapshot.qml must define getSnapshot(size)"
            root.failed = true
            return
        }
        try {
            root._snapshotData = snap.getSnapshot(root._plainSpan())
        } catch (err) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(err || "getSnapshot failed")
            root.failed = true
            console.warn("[WidgetPreviewHost] getSnapshot failed for", root.packageId, err)
            return
        }
        const expectedWidgetUrl = _toFileUrl(root.widgetEntry, root.packageRevision)
        if (root._widgetItem && root._widgetUrl === expectedWidgetUrl && !root.failed) {
            if ("snapshot" in root._widgetItem) root._widgetItem.snapshot = root._snapshotData
            if (root._itemShadowsData) root._widgetItem.data = root._snapshotData
        } else {
            root._loadWidget()
        }
    }

    function _finishSnapshot(component, token) {
        if (token !== root._snapshotToken || !component) return
        if (component.status === Component.Error) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "Snapshot.qml compile error"
            root.failed = true
            console.warn("[WidgetPreviewHost] Failed to load Snapshot.qml for", root.packageId, root.snapshotEntry, root.errorMessage)
            return
        }
        if (component.status !== Component.Ready) return
        const snap = component.createObject(root)
        if (!snap) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "Failed to instantiate Snapshot.qml"
            root.failed = true
            console.warn("[WidgetPreviewHost] Failed to instantiate Snapshot.qml for", root.packageId, root.errorMessage)
            return
        }
        root._snapshotItem = snap
        root.failed = false
        root.errorMessage = ""
        _refreshSnapshot()
    }

    function _loadSnapshot() {
        if (!root._completed) return
        const url = _toFileUrl(root.snapshotEntry, root.packageRevision)
        if (url.length === 0) {
            _destroySnapshot()
            _destroyWidget()
            root.failed = false
            root.errorMessage = ""
            return
        }
        if (WidgetCrashGuard.isBlocked(root.packageId, root.packageRevision)) {
            _destroyWidget()
            _destroySnapshot()
            root.failed = true
            root.errorMessage = "Paused after previous crash (edit file or re-enable to retry)"
            return
        }
        if (url === root._snapshotUrl && root._snapshotItem) {
            _refreshSnapshot()
            return
        }
        _destroySnapshot()
        const token = ++root._snapshotToken
        root._snapshotUrl = url
        root.failed = false
        root.errorMessage = ""
        WidgetCrashGuard.beginLoad(root.packageId, root.packageRevision)
        const component = Qt.createComponent(url)
        root._snapshotComponent = component
        if (component.status === Component.Loading) {
            component.statusChanged.connect(() => {
                if (token === root._snapshotToken)
                    root._finishSnapshot(component, token)
            })
        } else {
            _finishSnapshot(component, token)
        }
    }

    function _finishWidget(component, token) {
        if (token !== root._widgetToken || !component) return
        if (component.status === Component.Error) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "Widget.qml compile error"
            root.failed = true
            console.warn("[WidgetPreviewHost] Failed to load Widget.qml for", root.packageId, root.widgetEntry, root.errorMessage)
            return
        }
        if (component.status !== Component.Ready) return

        const span = root._plainSpan()
        const baseProps = {
            width: widgetContainer.width,
            snapshot: root._snapshotData,
            widgetSize: span,
            appearance: root.appearance,
            host: previewHostProxy
        }
        if (!root.useImplicitHeight)
            baseProps.height = widgetContainer.height
        let item = component.createObject(widgetContainer, baseProps)
        if (!item) {
            const err = String(component.errorString() ?? "").trim()
            if (err.indexOf("Required property data") >= 0) {
                item = component.createObject(widgetContainer, Object.assign({}, baseProps, {
                    data: root._snapshotData
                }))
            }
        }
        if (!item) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "Failed to instantiate Widget.qml"
            root.failed = true
            console.warn("[WidgetPreviewHost] Failed to instantiate Widget.qml for", root.packageId, root.widgetEntry, root.errorMessage)
            return
        }

        item.width = Qt.binding(() => widgetContainer.width)
        item.height = Qt.binding(() => root.useImplicitHeight
            ? (root.preferredContentHeight > 0 ? root.preferredContentHeight : widgetContainer.height)
            : widgetContainer.height)
        root._itemShadowsData = Object.prototype.toString.call(item.data) !== "[object QML List]"
        if (root._itemShadowsData) item.data = root._snapshotData

        root._widgetItem = item
        root.backgroundSpec = Qt.binding(() => item && item.backgroundSpec !== undefined ? item.backgroundSpec : null)
        root.surfaceShape = Qt.binding(() => {
            if (!item || item.surfaceShape === undefined || item.surfaceShape === null)
                return "roundedRect"
            const s = String(item.surfaceShape).trim()
            return s.length > 0 ? s : "roundedRect"
        })
        root.failed = false
        root.errorMessage = ""
        WidgetCrashGuard.finishLoad(root.packageId)
    }

    function _loadWidget() {
        if (!root._completed || root._snapshotData === null) return
        const url = _toFileUrl(root.widgetEntry, root.packageRevision)
        if (url.length === 0) {
            _destroyWidget()
            return
        }
        if (WidgetCrashGuard.isBlocked(root.packageId, root.packageRevision)) {
            _destroyWidget()
            root.failed = true
            root.errorMessage = "Paused after previous crash (edit file or re-enable to retry)"
            return
        }
        if (url === root._widgetUrl && (root._widgetItem || root.failed))
            return

        _destroyWidget()
        const token = ++root._widgetToken
        root._widgetUrl = url
        root.failed = false
        root.errorMessage = ""

        WidgetCrashGuard.beginLoad(root.packageId, root.packageRevision)
        const component = Qt.createComponent(url)
        root._widgetComponent = component
        if (component.status === Component.Loading) {
            component.statusChanged.connect(() => {
                if (token === root._widgetToken)
                    root._finishWidget(component, token)
            })
        } else {
            _finishWidget(component, token)
        }
    }

    onWidgetSizeChanged: {
        if (!root._completed) return
        if (root._snapshotItem) _refreshSnapshot()
        if (root._widgetItem && ("widgetSize" in root._widgetItem))
            root._widgetItem.widgetSize = root._plainSpan()
    }
    onAppearanceChanged: {
        if (root._widgetItem && ("appearance" in root._widgetItem))
            root._widgetItem.appearance = root.appearance
    }
    onSnapshotEntryChanged: _loadSnapshot()
    onPackageRevisionChanged: _loadSnapshot()
    onWidgetEntryChanged: {
        if (root._completed && root._snapshotData !== null) _loadWidget()
    }

    Component.onCompleted: {
        _completed = true
        _loadSnapshot()
    }
    Connections {
        target: WidgetCrashGuard
        function onRevisionChanged() {
            if (root.failed && !WidgetCrashGuard.isBlocked(root.packageId, root.packageRevision))
                root._loadSnapshot()
        }
    }
    Component.onDestruction: {
        _destroyWidget()
        _destroySnapshot()
    }

    Rectangle {
        anchors.fill: parent
        visible: root.failed
        radius: 14
        color: Qt.rgba(0.12, 0.08, 0.10, 0.78)
        border.width: 1
        border.color: Qt.rgba(1, 0.35, 0.35, 0.55)
        clip: true
        Text {
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 32)
            text: root.packageId + "\n" + (root.errorMessage || "Preview load error")
            color: "#ffffff"
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }
    }
}
