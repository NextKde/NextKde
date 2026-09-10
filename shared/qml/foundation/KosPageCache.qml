pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "PageCachePolicy.js" as PageCachePolicy

FocusScope {
    id: root

    property int currentIndex: 0
    property var pages: []
    property int cacheLimit: 3
    property var pinnedIndexes: []
    property bool asynchronous: true

    readonly property Item currentItem: {
        const revision = root._loaderRevision
        const loader = pageRepeater.itemAt(root.currentIndex)
        return loader && loader.status === Loader.Ready ? loader.item : null
    }
    readonly property bool loading: {
        const revision = root._loaderRevision
        const loader = pageRepeater.itemAt(root.currentIndex)
        return loader && loader.status === Loader.Loading
    }

    signal pageLoaded(int index, var page)
    signal pageEvicted(int index)

    property var _lastUsed: ({})
    property int _useSerial: 0
    property int _cacheRevision: 0
    property int _loaderRevision: 0

    function validIndex(index) {
        return PageCachePolicy.validIndex(index, pages.length)
    }

    function isPinned(index) {
        return PageCachePolicy.isPinned(index, pinnedIndexes, pages.length)
    }

    function isCached(index) {
        const revision = _cacheRevision
        return validIndex(index)
            && (index === currentIndex || isPinned(index)
                || _lastUsed[String(index)] !== undefined)
    }

    function touch(index) {
        if (!validIndex(index))
            return

        const entries = ({})
        const keys = Object.keys(_lastUsed)
        for (let position = 0; position < keys.length; position++) {
            const key = keys[position]
            const cachedIndex = Number(key)
            if (validIndex(cachedIndex))
                entries[key] = _lastUsed[key]
        }
        entries[String(index)] = ++_useSerial
        for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
            if (isPinned(pageIndex)
                    && entries[String(pageIndex)] === undefined)
                entries[String(pageIndex)] = 0
        }
        _lastUsed = PageCachePolicy.trim(entries, currentIndex,
            pinnedIndexes, cacheLimit, pages.length)
        _cacheRevision++
    }

    function warm(index) {
        touch(index)
    }

    function pageAt(index) {
        const loader = pageRepeater.itemAt(index)
        return loader && loader.status === Loader.Ready ? loader.item : null
    }

    function reset() {
        _lastUsed = ({})
        _useSerial = 0
        touch(currentIndex)
    }

    onCurrentIndexChanged: touch(currentIndex)
    onPagesChanged: reset()
    onCacheLimitChanged: touch(currentIndex)
    onPinnedIndexesChanged: touch(currentIndex)
    Component.onCompleted: touch(currentIndex)

    Repeater {
        id: pageRepeater
        model: root.pages.length

        delegate: Loader {
            id: pageLoader
            required property int index

            anchors.fill: parent
            sourceComponent: root.pages[index]
            active: root.isCached(index)
            asynchronous: root.asynchronous && index !== root.currentIndex
            visible: index === root.currentIndex
            focus: visible

            onLoaded: root.pageLoaded(index, item)
            onActiveChanged: {
                if (!active)
                    root.pageEvicted(index)
                root._loaderRevision++
            }
            onStatusChanged: root._loaderRevision++
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: root.loading
        visible: running
        z: 10
    }
}
