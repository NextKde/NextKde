import QtQuick

Item {
    id: table
    objectName: "songTable"

    property bool darkMode: AppTheme.darkMode
    property bool canvasText: true
    property bool lightText: false
    readonly property color headingColor: canvasText ? AppTheme.canvasSecondary : lightText ? "#c8d1da" : AppTheme.textSecondary
    property var rows: []
    property url fallbackArtwork: ""
    // Optional QAbstractItemModel. It has exclusive precedence over rows.
    property var sourceModel: null
    property bool compact: false
    property bool playlistMode: false
    property string scrollKey: ""
    property Component footer: null
    property bool scrollRestorePending: true
    property var navigationScrollPosition: undefined
    function saveNavigationState() {
        const list = sourceModel !== null ? backendList : mockList
        rememberScroll(list)
        return { position: list.contentY, sortColumn: sortColumn, sortOrder: sortOrder }
    }
    function restoreNavigationState(state) {
        sortColumn = state.sortColumn
        sortOrder = state.sortOrder
        refreshRows()
        navigationScrollPosition = state.position
        scrollRestorePending = true
        restoreScroll(sourceModel !== null ? backendList : mockList)
    }
    function resetScroll() { mockList.positionViewAtBeginning(); backendList.positionViewAtBeginning() }
    function rememberScroll(list) {
        if (scrollKey.length && typeof backendSettingsController !== "undefined" && backendSettingsController.value("list.rememberScrollPosition", true))
            backendSettingsController.setValue("scroll." + scrollKey, list.contentY)
    }
    function restoreScroll(list) {
        if (!scrollRestorePending || list.count === 0 || list.height <= 0) return
        list.forceLayout()
        let position = 0
        if (scrollKey.length && typeof backendSettingsController !== "undefined" && backendSettingsController.value("list.rememberScrollPosition", true)) {
            position = Number(backendSettingsController.value("scroll." + scrollKey, 0))
        }
        if (navigationScrollPosition !== undefined) position = Number(navigationScrollPosition)
        list.contentY = Math.max(0, Math.min(position, list.contentHeight - list.height))
        scrollRestorePending = false
        navigationScrollPosition = undefined
    }
    Connections {
        target: typeof backendSettingsController !== "undefined" ? backendSettingsController : null
        function onValueChanged(key,value){if(key==="list.rememberScrollPosition" && !value)table.resetScroll()}
    }

    Timer {
        id: restoreTimer
        interval: 0
        onTriggered: table.restoreScroll(table.sourceModel !== null ? backendList : mockList)
    }
    onScrollKeyChanged: { scrollRestorePending = true; restoreTimer.restart() }
    onSourceModelChanged: { scrollRestorePending = true; restoreTimer.restart() }
    property int sortColumn: -1
    property int sortOrder: 0 // 0 none, 1 ascending, 2 descending
    property var displayRows: []
    property var contextTrack: null
    property int contextRowIndex: -1

    readonly property var columnKeys: ["title", "album", "duration"]
    readonly property var columnLabels: [qsTr("歌曲 / 艺术家"), qsTr("专辑"), qsTr("时长")]
    readonly property bool tight: compact || width < 620
    readonly property int rowHeight: tight ? 60 : 62
    readonly property real titleStart: tight ? 78 : 94
    readonly property real actionSpace: tight ? 84 : 102
    readonly property real timeSpace: tight ? 38 : 58
    readonly property real albumSpace: tight ? 0 : Math.max(115, width * .23)


    signal trackActivated(var row, var playbackContext)
    signal sortChanged(string column, string order)
    signal commandRequested(string command, var track, int rowIndex, var playbackContext)

    implicitHeight: header.height + (sourceModel !== null
                                     ? backendList.contentHeight : mockList.contentHeight)

    function columnWidth(column) {
        if (column === 0) return Math.max(36, width - titleStart - actionSpace - albumSpace - timeSpace - 16)
        if (column === 1) return albumSpace
        return timeSpace
    }
    function columnX(column) {
        if (column === 0) return titleStart
        if (column === 1) return titleStart + columnWidth(0) + actionSpace
        return width - timeSpace - 8
    }

    function durationValue(value) {
        if (typeof value === "number")
            return value >= 1000 ? value / 1000 : value
        const parts = String(value || "0:0").split(":")
        return (Number(parts[0]) || 0) * 60 + (Number(parts[1]) || 0)
    }

    function formatDuration(value) {
        if (typeof value !== "number")
            return String(value || "--:--")
        const seconds = Math.max(0, Math.floor(value >= 1000 ? value / 1000 : value))
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    }

    function refreshRows() {
        const source = rows ? rows.slice() : []
        // Changing an integer ListView model resets its viewport. Keep the live
        // offset for edits; saved settings only apply when opening a collection.
        const preserveScroll = mockList && sourceModel === null && !scrollRestorePending && source.length !== displayRows.length
        const position = preserveScroll ? mockList.contentY : 0
        if (sortColumn < 0 || sortOrder === 0) {
            displayRows = source
        } else {
            const key = columnKeys[sortColumn]
            source.sort(function(a, b) {
                const av = key === "duration" ? durationValue(a[key])
                                               : String(a[key] || "").toLocaleLowerCase()
                const bv = key === "duration" ? durationValue(b[key])
                                               : String(b[key] || "").toLocaleLowerCase()
                const result = av < bv ? -1 : av > bv ? 1 : 0
                return sortOrder === 2 ? -result : result
            })
            displayRows = source
        }
        if (preserveScroll) {
            mockList.forceLayout()
            mockList.contentY = Math.max(0, Math.min(position, mockList.contentHeight - mockList.height))
        }
    }

    // Build the source-model snapshot only when the user chooses to switch
    // playback to this list; ordinary enqueue actions keep their cheap path.
    function playbackRows() {
        if (sourceModel === null) return displayRows
        if (typeof sourceModel.snapshotRows === "function") return sourceModel.snapshotRows()
        const result = []
        for (let i = 0; i < sourceModel.count; ++i) result.push(sourceModel.get(i))
        return result
    }

    function cycleSort(column) {
        if (sortColumn !== column) {
            sortColumn = column
            sortOrder = 1
        } else {
            sortOrder = (sortOrder + 1) % 3
        }
        refreshRows()
        sortChanged(columnKeys[column], ["none", "ascending", "descending"][sortOrder])
    }

    function openContext(rowItem, mouseX, mouseY, index, track) {
        contextRowIndex = index
        contextTrack = track
        const point = rowItem.mapToItem(table, mouseX, mouseY)
        contextMenu.openAt(point.x, point.y, { track: track, rowIndex: index })
    }

    onRowsChanged: refreshRows()
    Component.onCompleted: refreshRows()

    Item {
        id: header
        width: parent.width; height: 34
        Text { x: 10; width: table.tight ? 18 : 26; height: parent.height; text: "#"; color: table.headingColor; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 12 }
        Repeater {
            model: table.columnLabels
            delegate: Item {
                id: heading
                required property int index
                required property string modelData
                x: table.columnX(index); width: table.columnWidth(index); height: header.height
                visible: !(table.tight && index === 1)
                Text {
                    anchors.fill: parent
                    text: heading.modelData + (table.sortColumn === heading.index ? (table.sortOrder === 1 ? "  ↑" : table.sortOrder === 2 ? "  ↓" : "") : "")
                    color: table.headingColor; font.family: AppTheme.fontFamily; font.pixelSize: 11
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: heading.index === 2 ? Text.AlignRight : Text.AlignLeft; elide: Text.ElideRight
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: table.cycleSort(heading.index) }
            }
        }
    }
    ListView {
        id: mockList
        objectName: "songTableList"
        visible: table.sourceModel === null
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: header.bottom; anchors.bottom: parent.bottom
        clip: true; reuseItems: true
        cacheBuffer: 0
        interactive: contentHeight > height
        footer: visible ? table.footer : null
        boundsBehavior: Flickable.StopAtBounds
        onMovementEnded: table.rememberScroll(this)
        onCountChanged: if (table.scrollRestorePending) restoreTimer.restart()
        onHeightChanged: if (table.scrollRestorePending) restoreTimer.restart()
        // Keep delegate identity while metadata/artwork arrives. Replacing a
        // JS-array model resets ListView's scroll position on every cover.
        model: table.sourceModel === null ? table.displayRows.length : 0
        delegate: SongRow {
            canvasText: table.canvasText; lightText: table.lightText
            id: mockRow
            required property int index
            width: mockList.width; compact: table.tight
            rowIndex: index; track: table.displayRows[index] || ({})
            fallbackArtwork: table.fallbackArtwork
            onActivated: table.trackActivated(track, table)
            onCommandRequested: command => table.commandRequested(command,track,index,table)
            onContextRequested: (mx,my) => table.openContext(mockRow,mx,my,index,track)
        }
    }
    ListView {
        id: backendList
        objectName: "songTableBackendList"
        visible: table.sourceModel !== null
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: header.bottom; anchors.bottom: parent.bottom
        clip: true; reuseItems: true
        cacheBuffer: 0
        interactive: contentHeight > height
        footer: visible ? table.footer : null
        boundsBehavior: Flickable.StopAtBounds
        onMovementEnded: table.rememberScroll(this)
        onCountChanged: if (table.scrollRestorePending) restoreTimer.restart()
        onHeightChanged: if (table.scrollRestorePending) restoreTimer.restart()
        model: table.sourceModel
        delegate: SongRow {
            canvasText: table.canvasText; lightText: table.lightText
            id: backendRow
            required property int index
            required property string trackId
            required property string title
            required property string artist
            required property string album
            required property var duration
            required property string localPath
            required property string artwork
            width: backendList.width; compact: table.tight
            rowIndex: index
            fallbackArtwork: table.fallbackArtwork
            track: ({ trackId: trackId, title: title, artist: artist, album: album, duration: duration, localPath: localPath, artwork: artwork, source: "Local" })
            onActivated: table.trackActivated(track, table)
            onCommandRequested: command => table.commandRequested(command,track,index,table)
            onContextRequested: (mx,my) => table.openContext(backendRow,mx,my,index,track)
        }
    }

    SongContextMenu {
        id: contextMenu
        anchors.fill: parent
        z: 100
        darkMode: table.darkMode
        playlistMode: table.playlistMode
        onCommandTriggered: function(command, contextData) {
            if (contextData)
                table.commandRequested(command, contextData.track, contextData.rowIndex, table)
        }
    }
}
