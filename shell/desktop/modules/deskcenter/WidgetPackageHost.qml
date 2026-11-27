import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common

// Dynamic runtime host wrapper for any installed widget package loaded from
// disk (`$XDG_DATA_HOME/kos/widgets/<id>/Widget.qml`).
//
// Under the in-process, user-audited trust model:
// - Passes a read-only `host` proxy into `Widget.qml` BEFORE
//   `Component.onCompleted` runs (when declared as `property var host: null`),
//   carrying live reactive R1 snapshots (`clock`, `media`, `weather`, `system`,
//   `activity`, `pim`), per-instance persisted `settings`, `invokeAction(...)`,
//   `hasAction(...)`, `saveSettings(...)`, `patchSettings(...)`, and runtime
//   version/visibility metadata (`sdkVersion`, `apiRevision`, `active`,
//   `visible`).
// - Also binds `widgetSize`, `appearance` (including Material `palette`),
//   `snapshot` (plus legacy `data` fallback only when Widget.qml explicitly
//   shadows `Item.data`), `lastActionResult`, and optional `actionRequested`.
Item {
    id: root

    property string packageId: ""
    property string instanceId: ""
    property string widgetEntry: ""
    property string settingsEntry: ""
    property string packageRevision: ""
    property string containerType: "desktop"
    property string containerOrientation: "horizontal"
    property bool hasSettings: false
    property bool hostActive: true
    property var widgetSize: [1, 1]
    property var appearance: WidgetHostService.widgetAppearance
    property var lastActionResult: null
    property string errorMessage: ""
    property bool hasError: false

    property var backgroundSpec: null
    property string surfaceShape: "roundedRect"
    property bool useImplicitHeight: false
    property real surfaceOriginX: 0
    property real surfaceOriginY: 0
    readonly property Item widgetItem: root._loadedItem
    readonly property real preferredContentHeight: {
        if (!root._loadedItem) return 0
        const explicitH = root._loadedItem.popupHeight
        if (explicitH !== undefined && explicitH !== null
                && Number.isFinite(Number(explicitH)) && Number(explicitH) > 0)
            return Number(explicitH)
        return Number(root._loadedItem.implicitHeight) > 0
            ? Number(root._loadedItem.implicitHeight) : 0
    }

    // Per-instance persisted JSON configuration shared between Widget.qml and
    // optional Settings.qml. Keyed by instanceId so multiple placements of the
    // same package keep independent settings across restarts (R4).
    property var settingsData: ({})
    readonly property string _settingsKey: root.instanceId.length > 0 ? root.instanceId : root.packageId
    property bool _completed: false
    property Item _loadedItem: null
    property var _loadedComponent: null
    property bool _itemShadowsData: false
    property string _loadedUrl: ""
    property int _loadToken: 0

    // Legacy per-file settings kept solely for one-time migration into
    // DeskCenterConfigService (deskcenter-widgets.ini).
    Settings {
        id: legacyInstanceSettings
        location: "file://" + Quickshell.stateDir + "/widget-instance-"
            + encodeURIComponent(root._settingsKey || "unknown") + ".ini"
        category: "Settings"
        property string configJson: "{}"
    }

    function _loadSettings() {
        const stored = DeskCenterConfigService.instanceConfigFor(root._settingsKey)
        if (stored !== null) {
            root.settingsData = stored
            return
        }
        try {
            const parsed = JSON.parse(legacyInstanceSettings.configJson)
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed)
                    && Object.keys(parsed).length > 0) {
                DeskCenterConfigService.saveInstanceConfig(root._settingsKey, parsed)
                root.settingsData = parsed
                return
            }
        } catch (_) {}
        root.settingsData = ({})
    }

    function applySettings(next) {
        if (!DeskCenterConfigService.saveInstanceConfig(root._settingsKey, next))
            return false
        root.settingsData = DeskCenterConfigService.instanceConfigFor(root._settingsKey) ?? ({})
        return true
    }

    Connections {
        target: DeskCenterConfigService
        function onInstanceConfigChanged(changedId) {
            if (root._completed && changedId === root._settingsKey)
                root._loadSettings()
        }
    }

    function patchSettings(partial) {
        if (!partial || typeof partial !== "object" || Array.isArray(partial)) return false
        const merged = Object.assign({}, root.settingsData, partial)
        return applySettings(merged)
    }

    function dispatchAction(actionName, payload) {
        const result = WidgetHostService.invokeAction(actionName, payload)
        root.lastActionResult = result
        return result
    }

    readonly property var _liveData: ({
        status: "ready",
        settings: root.settingsData
    })

    // Read-only SDK host proxy passed directly into Widget.qml before
    // Component.onCompleted. Provides reactive R1 snapshots, capability
    // probing, per-instance settings, and the R11 reverse action channel.
    QtObject {
        id: hostProxy
        readonly property int sdkVersion: WidgetHostService.sdkVersion
        readonly property int apiRevision: WidgetHostService.apiRevision
        readonly property string locale: WidgetHostService.locale
        readonly property var availableSources: WidgetHostService.availableSources
        readonly property bool isPreview: false
        readonly property bool active: root.visible && root.hostActive
        readonly property bool visible: root.visible && root.hostActive
        readonly property string container: root.containerType
        readonly property string orientation: root.containerOrientation
        readonly property string packageId: root.packageId
        readonly property string instanceId: root.instanceId
        readonly property var clock: WidgetHostService.clock
        readonly property var media: WidgetHostService.media
        readonly property var weather: WidgetHostService.weather
        readonly property var system: WidgetHostService.system
        readonly property var activity: WidgetHostService.activity
        readonly property var pim: WidgetHostService.pim
        readonly property var pointer: WidgetHostService.pointer
        readonly property var settings: root.settingsData
        readonly property var lastActionResult: root.lastActionResult

        function globalCenter() {
            const p = root.mapToItem(null, root.width / 2, root.height / 2)
            return { x: root.surfaceOriginX + p.x, y: root.surfaceOriginY + p.y }
        }
        function hasAction(actionName) {
            return WidgetHostService.hasAction(actionName)
        }
        function invokeAction(actionName, payload) {
            return root.dispatchAction(actionName, payload)
        }
        function saveSettings(next) {
            return root.applySettings(next)
        }
        function patchSettings(partial) {
            return root.patchSettings(partial)
        }
    }

    Item {
        id: widgetContainer
        anchors.fill: parent
    }

    function _entryUrl() {
        const p = String(root.widgetEntry ?? "")
        if (p.length === 0) return ""
        const base = p.startsWith("file://") ? p : ("file://" + p)
        const rev = String(root.packageRevision ?? "")
        return rev.length > 0 ? (base + "?rev=" + encodeURIComponent(rev)) : base
    }

    function _destroyLoaded() {
        root._loadToken++
        root.backgroundSpec = null
        root.surfaceShape = "roundedRect"
        if (root._loadedItem) {
            root._loadedItem.destroy()
            root._loadedItem = null
        }
        if (root._loadedComponent) {
            root._loadedComponent.destroy()
            root._loadedComponent = null
        }
        root._itemShadowsData = false
        root._loadedUrl = ""
    }

    function _finishCreate(component, token) {
        if (token !== root._loadToken || !component) return
        if (component.status === Component.Error) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "QML compile error"
            root.hasError = true
            console.warn("[WidgetPackageHost] Failed to load widget", root.packageId, root.widgetEntry, root.errorMessage)
            return
        }
        if (component.status !== Component.Ready) return

        // Do NOT pass `data` unconditionally: Qt Quick Item defines `list<QtObject> data`
        // as its default child list, so setting `data` on a widget that did not shadow it
        // silently removes all its visual children.
        const baseProps = {
            width: widgetContainer.width,
            snapshot: root._liveData,
            widgetSize: root.widgetSize,
            appearance: root.appearance,
            host: hostProxy,
            lastActionResult: root.lastActionResult
        }
        if (!root.useImplicitHeight)
            baseProps.height = widgetContainer.height
        let item = component.createObject(widgetContainer, baseProps)
        if (!item) {
            const err = String(component.errorString() ?? "").trim()
            if (err.indexOf("Required property data") >= 0) {
                item = component.createObject(widgetContainer, Object.assign({}, baseProps, {
                    data: root._liveData
                }))
            }
        }
        if (!item) {
            WidgetCrashGuard.clearPending(root.packageId)
            root.errorMessage = String(component.errorString() ?? "").trim() || "Failed to instantiate Widget.qml"
            root.hasError = true
            console.warn("[WidgetPackageHost] Failed to instantiate widget", root.packageId, root.widgetEntry, root.errorMessage)
            return
        }

        item.width = Qt.binding(() => widgetContainer.width)
        item.height = Qt.binding(() => root.useImplicitHeight
            ? (root.preferredContentHeight > 0 ? root.preferredContentHeight : widgetContainer.height)
            : widgetContainer.height)
        root._itemShadowsData = Object.prototype.toString.call(item.data) !== "[object QML List]"
        if (root._itemShadowsData) item.data = root._liveData
        if (item.actionRequested !== undefined && typeof item.actionRequested.connect === "function")
            item.actionRequested.connect(root.dispatchAction)

        root._loadedItem = item
        root.backgroundSpec = Qt.binding(() => item && item.backgroundSpec !== undefined ? item.backgroundSpec : null)
        root.surfaceShape = Qt.binding(() => {
            if (!item || item.surfaceShape === undefined || item.surfaceShape === null)
                return "roundedRect"
            const s = String(item.surfaceShape).trim()
            return s.length > 0 ? s : "roundedRect"
        })
        root.hasError = false
        root.errorMessage = ""
        WidgetCrashGuard.finishLoad(root.packageId)
    }

    function _loadWidget() {
        if (!root._completed) return
        const url = _entryUrl()
        if (url.length === 0) {
            _destroyLoaded()
            root.hasError = false
            root.errorMessage = ""
            return
        }
        if (WidgetCrashGuard.isBlocked(root.packageId, root.packageRevision)) {
            _destroyLoaded()
            root.hasError = true
            root.errorMessage = "Paused after previous crash"
            return
        }
        if (url === root._loadedUrl && (root._loadedItem || root.hasError))
            return

        _destroyLoaded()
        const token = ++root._loadToken
        root._loadedUrl = url
        root.hasError = false
        root.errorMessage = ""

        WidgetCrashGuard.beginLoad(root.packageId, root.packageRevision)
        const component = Qt.createComponent(url)
        root._loadedComponent = component
        if (component.status === Component.Loading) {
            component.statusChanged.connect(() => {
                if (token === root._loadToken)
                    root._finishCreate(component, token)
            })
        } else {
            _finishCreate(component, token)
        }
    }

    on_SettingsKeyChanged: if (root._completed) _loadSettings()
    onWidgetEntryChanged: _loadWidget()
    onPackageRevisionChanged: _loadWidget()
    on_LiveDataChanged: {
        if (!root._loadedItem) return
        if ("snapshot" in root._loadedItem) root._loadedItem.snapshot = root._liveData
        if (root._itemShadowsData) root._loadedItem.data = root._liveData
    }
    onWidgetSizeChanged: {
        if (root._loadedItem && ("widgetSize" in root._loadedItem))
            root._loadedItem.widgetSize = root.widgetSize
    }
    onAppearanceChanged: {
        if (root._loadedItem && ("appearance" in root._loadedItem))
            root._loadedItem.appearance = root.appearance
    }
    onLastActionResultChanged: {
        if (root._loadedItem && ("lastActionResult" in root._loadedItem))
            root._loadedItem.lastActionResult = root.lastActionResult
    }

    Component.onCompleted: {
        _loadSettings()
        _completed = true
        _loadWidget()
    }
    Connections {
        target: WidgetCrashGuard
        function onRevisionChanged() {
            if (root.hasError && !WidgetCrashGuard.isBlocked(root.packageId, root.packageRevision))
                root._loadWidget()
        }
    }
    Component.onDestruction: _destroyLoaded()

    // Fallback hint if a widget package's Widget.qml fails to compile/load.
    Item {
        anchors.fill: parent
        clip: true
        visible: root.hasError
        Text {
            anchors.centerIn: parent
            width: Math.max(1, parent.width - 20)
            text: root.packageId + "\n" + (root.errorMessage || "QML load error")
            color: root.appearance?.foreground ?? "#ffffff"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }
    }
}
