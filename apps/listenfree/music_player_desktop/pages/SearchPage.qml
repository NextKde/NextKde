pragma ComponentBehavior: Bound
import QtQuick
import "../components"

Item {
    id: page
    objectName: "searchPage"
    property bool darkMode: AppTheme.darkMode
    property var sourceController: null
    property bool lxSearch: false
    onLxSearchChanged: if (onlineController) onlineController.searchMode = lxSearch ? "lx" : "platform"
    Component.onCompleted: if (onlineController) onlineController.searchMode = lxSearch ? "lx" : "platform"
    signal manageSourcesRequested()
    property var catalog
    property var onlineController
    property Item backdrop: null
    property string query: ""
    property var platformNames: [qsTr("酷我"), qsTr("酷狗"), "QQ", qsTr("网易云"), qsTr("咪咕")]
    readonly property bool bilibiliEnabled: !lxSearch && !!onlineController && !!onlineController.bilibiliSourceEnabled
    readonly property bool bilibiliSelected: !!onlineController && onlineController.platform === "bili"
    readonly property var platformIds: ["kw", "kg", "tx", "wy", "mg"].concat(bilibiliEnabled ? ["bili"] : [])
    readonly property var searchPlatformNames: platformNames.concat(bilibiliEnabled ? [qsTr("哔哩哔哩")] : [])
    readonly property var categoryIds: bilibiliSelected ? ["songs", "playlists"] : ["songs", "playlists", "albums"]
    readonly property bool hasOnlineQuery: !!onlineController && query.trim().length > 0
    readonly property var resultRows: hasOnlineQuery ? onlineController.searchResults || [] : []
    readonly property string category: onlineController ? onlineController.searchCategory : "songs"
    readonly property int currentPage: onlineController ? onlineController.searchPage : 1
    readonly property int pageCount: onlineController ? onlineController.searchPageCount : 1
    readonly property bool busy: !!onlineController && onlineController.busy
    readonly property string datasetKey: query + ":" + (onlineController ? onlineController.platform : "kw") + ":" + (lxSearch ? onlineController.searchSourceId : "platform") + ":" + category + ":" + currentPage
    function saveNavigationState() { return { dataset: datasetKey,
        songs: category === "songs" ? resultTable.saveNavigationState() : null, y: gridPosition.saveNavigationState() } }
    function restoreNavigationState(state) {
        if (state.dataset !== datasetKey) return
        if (state.songs) resultTable.restoreNavigationState(state.songs)
        gridPosition.restoreNavigationState(state.y)
    }
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    signal trackSortRequested(string column, string order)
    signal collectionActivated(var collection)

    onDatasetKeyChanged: { if (resultTable) resultTable.resetScroll(); if (collectionGrid) collectionGrid.positionViewAtBeginning() }
    component ToolbarGlass: GlassSurface {
        backdrop: page.backdrop
        opaqueBackdropBase: false
        backdropBlur: 20
        frosted: true
        tint: AppTheme.canvasDark ? "#20262c" : "#f2f4f6"
        tintStrength: AppTheme.canvasDark ? .12 : .16
        shadowOpacity: .04
        shadowOffset: 1
        cornerRadius: height / 2
    }
    component SearchTabs: SegmentedTabBar {
        controlled: true
        cellHeight: 28
        outerPadding: 4
        color: "transparent"
        border.width: 0
        textColor: AppTheme.canvasText
        hoverBackground: "#18ffffff"
    }
    Row {
        x: 14; y: 8; spacing: 8
        UiButton { label: qsTr("平台搜索"); height: 32; selected: !page.lxSearch; onClicked: page.lxSearch = false }
        UiButton {
            objectName: "lxSearchEntry"
            label: qsTr("洛雪音乐"); height: 32; selected: page.lxSearch
            onClicked: page.lxSearch = true
        }
    }
    Row {
        x: 14; y: 48; height: 32; spacing: 10; visible: page.lxSearch
        SettingsSelect {
            objectName: "lxSourceSelector"
            width: Math.min(230, page.width * .35)
            darkMode: page.darkMode
            options: page.sourceController ? page.sourceController.sources.map(function(s) { return {label: s.name + (s.id === page.sourceController.defaultId ? qsTr(" · 默认") : ""), value:s.id} }) : []
            currentIndex: page.sourceController ? Math.max(0, options.findIndex(function(s) {return s.value === page.onlineController.searchSourceId})) : 0
            onValueSelected: (value, index) => page.onlineController.searchSourceId = value
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(80, page.width * .35)
            elide: Text.ElideRight
            text: {
                const sources = page.sourceController ? page.sourceController.sources : []
                const source = sources.find(s => s.id === (page.onlineController ? page.onlineController.searchSourceId : ""))
                return source ? (source.capabilityText || qsTr("搜索时检测脚本能力")) : qsTr("请先导入洛雪音源")
            }
            color: AppTheme.canvasSecondary; font.pixelSize: 11
        }
        UiButton { label: qsTr("音源设置"); height: 30; onClicked: page.manageSourcesRequested() }
    }
    Item {
        id: platforms
        objectName: "searchPlatformToolbar"
        visible: !page.lxSearch
        x: 14; y: 48; width: Math.min(page.bilibiliEnabled ? 462 : 383, page.width * (page.bilibiliEnabled ? .64 : .56)); height: 36
        ToolbarGlass { anchors.fill: parent }
        SearchTabs {
            anchors.fill: parent
            model: page.searchPlatformNames
            cellWidth: (platforms.width - 8) / page.platformIds.length
            currentIndex: page.onlineController ? Math.max(0, page.platformIds.indexOf(page.onlineController.platform)) : 0
            onSelected: (index, value) => { if (page.onlineController) page.onlineController.platform = page.platformIds[index] }
        }
    }
    Item {
        id: categories
        visible: !page.lxSearch
        objectName: "searchCategoryToolbar"
        anchors.right: parent.right; anchors.rightMargin: 14
        y: platforms.y; width: Math.min(page.bilibiliSelected ? 152 : 224, page.width - platforms.width - 42); height: platforms.height
        ToolbarGlass { anchors.fill: parent }
        SearchTabs {
            anchors.fill: parent
            model: page.bilibiliSelected ? [qsTr("歌曲"), qsTr("歌单")] : [qsTr("歌曲"), qsTr("歌单"), qsTr("专辑")]
            cellWidth: (categories.width - 8) / page.categoryIds.length
            currentIndex: Math.max(0, page.categoryIds.indexOf(page.category))
            onSelected: (index, value) => { if (page.onlineController) page.onlineController.searchCategory = page.categoryIds[index] }
        }
    }
    SongTable {
        id: resultTable
        scrollKey: "search.songs"
        x: 4; y: platforms.y + 48; width: parent.width - 8; height: Math.max(0, parent.height - y)
        visible: page.category === "songs"
        rows: visible ? page.resultRows : []
        footer: visible && page.hasOnlineQuery ? paginationFooter : null
        darkMode: page.darkMode
        onTrackActivated: (row, playbackContext) => page.trackActivated(row, playbackContext)
        onCommandRequested: (command, track, rowIndex, playbackContext) => page.trackCommandRequested(command, track, rowIndex, playbackContext)
        onSortChanged: (column, order) => page.trackSortRequested(column, order)
    }
    GridView {
        id: collectionGrid
        ScrollPosition { id: gridPosition; view: collectionGrid; key: "search."+page.category }
        objectName: "searchCollectionGrid"
        x: 8; y: platforms.y + 50; width: parent.width - 16; height: Math.max(0, parent.height - y)
        visible: page.category !== "songs"
        model: visible ? page.resultRows : []
        footer: visible && page.hasOnlineQuery ? paginationFooter : null
        clip: true; reuseItems: true; cacheBuffer: 120
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: width / Math.max(3, Math.min(5, Math.floor(width / 145)))
        cellHeight: cellWidth - 28/3 + 54
        delegate: Item {
            id: cell
            required property var modelData
            width: collectionGrid.cellWidth; height: collectionGrid.cellHeight
            ArtworkTile {
                objectName: "searchCollectionCard"
                x: 14/3; y: 2; size: cell.width - 28/3
                title: cell.modelData.title || ""
                subtitle: cell.modelData.subtitle || ""
                artworkSource: cell.modelData.artwork || ""
                darkMode: page.darkMode
                onActivated: page.collectionActivated(cell.modelData)
            }
        }
    }
    Component {
      id: paginationFooter
      Item {
        objectName: "searchInlineFooter"
        width: page.category === "songs" ? resultTable.width : collectionGrid.width
        // Pagination follows the final row. Extra space AFTER the controls is
        // scrollable, so the floating player cannot cover them at the end.
        height: 56 + 110
        Text {
            anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: pager.verticalCenter
            text: page.busy ? qsTr("搜索中…") : ((page.onlineController && page.onlineController.searchTotal >= 0) ? page.onlineController.searchTotal + qsTr(" 条结果") : page.resultRows.length + qsTr(" 条结果"))
            color: AppTheme.canvasSecondary; font.pixelSize: 11; font.family: AppTheme.fontFamily
        }
        Item {
            id: pager
            objectName: "searchPaginationToolbar"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            width: pageButtons.width + 8; height: 32
            readonly property var pages: {
                const result = [1], first = Math.max(2, page.currentPage - 2), last = Math.min(page.pageCount - 1, Math.max(5, page.currentPage + 2))
                if (first > 2) result.push(0)
                for (let i = first; i <= last; ++i) result.push(i)
                if (last < page.pageCount - 1) result.push(0)
                if (page.pageCount > 1) result.push(page.pageCount)
                return [-1].concat(result, [-2])
            }
            ToolbarGlass { anchors.fill: parent }
            Row {
                id: pageButtons
                x: 4; y: 2; spacing: 2
                Repeater {
                    model: pager.pages
                    delegate: Rectangle {
                        id: number
                        required property var modelData
                        objectName: "searchPageButton" + modelData
                        readonly property int destination: modelData === -1 ? page.currentPage - 1 : modelData === -2 ? page.currentPage + 1 : modelData
                        readonly property bool selected: modelData === page.currentPage
                        width: 28; height: 28; radius: 14
                        enabled: modelData !== 0 && destination >= 1 && destination <= page.pageCount
                        color: selected ? "#45ffffff" : hover.hovered ? "#20ffffff" : "transparent"
                        scale: tap.pressed ? .91 : 1
                        opacity: enabled || modelData === 0 ? 1 : .3
                        Behavior on scale { NumberAnimation { duration: AppTheme.duration(100) } }
                        Text {
                            anchors.centerIn: parent
                            text: number.modelData === -1 ? "‹" : number.modelData === -2 ? "›" : number.modelData === 0 ? "…" : String(number.modelData)
                            color: AppTheme.canvasText; font.family: AppTheme.fontFamily
                            font.pixelSize: number.modelData < 0 ? 19 : 11
                            font.weight: number.selected ? Font.DemiBold : Font.Normal
                        }
                        HoverHandler { id: hover }
                        TapHandler { id: tap; onTapped: { if (page.onlineController) page.onlineController.goToSearchPage(number.destination) } }
                    }
                }
            }
        }
      }
    }
    Column {
        visible: (page.hasOnlineQuery || page.lxSearch) && page.resultRows.length === 0 && !page.busy
        width: Math.max(100, page.width - 64)
        anchors.centerIn: parent; spacing: 8
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            text: page.onlineController && page.onlineController.searchError ? page.onlineController.searchError : !page.hasOnlineQuery ? qsTr("选择音源，输入关键词搜索") : qsTr("没有找到“") + page.query + "”"
            color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 16
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: page.lxSearch ? qsTr("使用所选脚本的搜索能力；仅解析音源请在平台搜索中使用。") : qsTr("换一个关键词，或切换平台和分类。")
            color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12
        }
    }
}
