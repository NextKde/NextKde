pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: memory
    visible: false
    property var view: null
    property string key: ""
    property var store: typeof backendSettingsController !== "undefined" ? backendSettingsController : null
    property bool pending: true
    readonly property bool remember: {
        const revision=store ? store.revision : 0
        return store && store.value("list.rememberScrollPosition",true)
    }
    function restore() {
        if(!pending || !view || !key.length || !remember || view.contentHeight<=view.height)return
        view.contentY=Math.max(view.originY || 0,Math.min(Number(store.value("scroll."+key,0)),view.contentHeight-view.height))
        pending=false
    }
    function save() {
        if(view && key.length && remember && !pending)store.setValue("scroll."+key,view.contentY)
    }
    function saveNavigationState() {
        save()
        return view ? view.contentY : 0
    }
    function restoreNavigationState(position) {
        if (!view) return
        if (typeof view.forceLayout === "function") view.forceLayout()
        pending = false
        view.contentY = Math.max(view.originY || 0, Math.min(Number(position),
            Math.max(view.originY || 0, view.contentHeight - view.height + (view.bottomMargin || 0))))
    }
    onKeyChanged: { pending=true; Qt.callLater(restore) }
    onRememberChanged: {
        if(!remember && view){view.contentY=view.originY || 0;pending=false}
    }
    Component.onCompleted: Qt.callLater(restore)
    Component.onDestruction: save()
    Connections {
        target: memory.view
        ignoreUnknownSignals: true
        function onContentHeightChanged(){Qt.callLater(memory.restore)}
        function onHeightChanged(){Qt.callLater(memory.restore)}
        function onVisibleChanged(){if(memory.view.visible)Qt.callLater(memory.restore);else memory.save()}
        function onMovementStarted(){memory.pending=false}
        function onMovementEnded(){memory.pending=false;memory.save()}
        function onContentYChanged(){if(!memory.pending)saveTimer.restart()}
    }
    Timer { id: saveTimer; interval: 250; onTriggered: memory.save() }
}
