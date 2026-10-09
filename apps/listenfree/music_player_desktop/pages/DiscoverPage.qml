pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import "../components"

Item {
    id: page
    objectName: "discoverPage"
    property var searchController: null
    property var catalog: null
    property bool darkMode: false
    property bool allCharts: false
    property real chartsProgress: allCharts ? 1 : 0
    property var recommendationRows: []
    property var pendingRecommendations: []
    property bool restoringNavigationState: false
    function saveNavigationState() {
        return { allCharts: allCharts, y: scrollPosition.saveNavigationState(), chartsX: chartGrid.contentX, dailyX: daily.contentX }
    }
    function restoreNavigationState(state) {
        restoringNavigationState = true
        allCharts = state.allCharts
        chartGrid.forceLayout(); daily.forceLayout()
        chartGrid.contentX = Math.max(0, Math.min(state.chartsX, chartGrid.contentWidth - chartGrid.width))
        daily.contentX = Math.max(0, Math.min(state.dailyX, daily.contentWidth - daily.width))
        // Positioners normally settle on the next frame. Resolve their heights
        // before clamping the restored viewport, so the first frame is correct.
        recommendationGrid.forceLayout(); recommendationsSection.forceLayout()
        dailySection.forceLayout(); historyPills.forceLayout(); historySection.forceLayout()
        sections.forceLayout()
        scrollPosition.restoreNavigationState(state.y)
        restoringNavigationState = false
    }
    signal searchRequested(string term, string platform)
    signal collectionRequested(var collection)
    signal collectionTransitionRequested(var collection, rect frameRect, rect artworkRect, url artworkSource, var artworkItem)
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    Component.onCompleted: {
        updateRecommendations()
        if(catalog)catalog.refreshHome()
    }
    Connections {
        target: page.catalog
        function onHomeRecommendationsChanged() { page.updateRecommendations() }
    }
    function updateRecommendations() {
        const rows = catalog ? catalog.homeRecommendations.slice(0,12) : []
        if (JSON.stringify(rows) === JSON.stringify(pendingRecommendations)) return
        pendingRecommendations = rows
        recommendationTransition.stop()
        if (!visible || !AppTheme.motionEnabled) {
            recommendationRows = rows
            recommendationGrid.opacity = 1
        } else {
            recommendationTransition.start()
        }
    }
    SequentialAnimation {
        id: recommendationTransition
        NumberAnimation { target: recommendationGrid; property: "opacity"; to: 0; duration: AppTheme.duration(page.recommendationRows.length ? 100 : 0) }
        ScriptAction { script: page.recommendationRows = page.pendingRecommendations }
        NumberAnimation { target: recommendationGrid; property: "opacity"; to: 1; duration: AppTheme.duration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: [.32,.72,0,1,1,1] }
    }
    Behavior on chartsProgress {
        enabled: !page.restoringNavigationState
        NumberAnimation { duration: AppTheme.duration(280); easing.type: Easing.BezierSpline; easing.bezierCurve: [.32,.72,0,1,1,1] }
    }
    function playCount(value) {
        const n=Number(value || 0)
        return n>=100000000 ? (n/100000000).toFixed(1)+qsTr("亿播放") : n>=10000 ? (n/10000).toFixed(1)+qsTr("万播放") : n+qsTr("次播放")
    }
    function horizontalWheel(view,event) {
        const delta=event.pixelDelta.x || event.pixelDelta.y || (event.angleDelta.x || event.angleDelta.y)*.8
        view.contentX=Math.max(0,Math.min(Math.max(0,view.contentWidth-view.width),view.contentX-delta))
        event.accepted=true
    }
    component Heading: Text {
        color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 22; font.weight: Font.DemiBold
    }
    component CollectionCard: Column {
        id: card
        property var entry: ({})
        property string caption: ""
        spacing: 6
        CoverArt {
            id: artwork
            width: card.width; height: width; source: card.entry.artwork || ""
            sourcePixelSize: 320; cornerRadius: 12; showShadow: false
            scale: tap.pressed ? .98 : 1
            Behavior on scale { NumberAnimation { duration: AppTheme.duration(100) } }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: tap
                onTapped: {
                    const frame = card.mapToItem(page,0,0), art = artwork.mapToItem(page,0,0)
                    page.collectionTransitionRequested(card.entry,
                        Qt.rect(frame.x,frame.y,card.width,card.height),
                        Qt.rect(art.x,art.y,artwork.width,artwork.height),artwork.source,artwork)
                }
            }
        }
        Text { width: parent.width; text: card.entry.title || ""; color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
        Text { width: parent.width; text: card.caption; color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight }
    }
    Flickable {
        id: scroll
        objectName: "discoverScroll"
        anchors.fill: parent; anchors.leftMargin: 26; anchors.rightMargin: 26; anchors.topMargin: 18
        contentWidth: width; contentHeight: sections.implicitHeight+128
        clip: true; boundsBehavior: Flickable.StopAtBounds
        Basic.ScrollBar.vertical: Basic.ScrollBar { objectName: "discoverScrollbar"; width: 0; visible: false; policy: Basic.ScrollBar.AlwaysOff }
        Column {
            id: sections
            width: scroll.width; spacing: 28
            Column {
                id: recommendationsSection
                width: parent.width; spacing: 18
                Item {
                    width: parent.width; height: 34
                    Heading { text: qsTr("推荐歌单"); anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.right: refresh.left; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: qsTr("网易云音乐"); color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
                    RoundIconButton { id: refresh; objectName: "discoverRefresh"; anchors.right: parent.right; diameter: 32; kind: "repeat"; transparentSurface: true; glyphColor: AppTheme.canvasText; enabled: page.catalog && !page.catalog.homeBusy; tooltip: qsTr("刷新推荐"); onClicked: page.catalog.refreshHome(true) }
                }
                Text { visible: text.length>0; width: parent.width; text: page.catalog ? page.catalog.homeError : ""; wrapMode: Text.Wrap; color: AppTheme.canvasSecondary; font.pixelSize: 12 }
                Grid {
                    id: recommendationGrid
                    objectName: "discoverRecommendations"
                    width: parent.width; columns: 6; columnSpacing: 18; rowSpacing: 20
                    enabled: !recommendationTransition.running
                    Repeater {
                        model: page.recommendationRows
                        delegate: CollectionCard {
                            required property var modelData
                            objectName: "discoverRecommendation"
                            width: (recommendationGrid.width-5*recommendationGrid.columnSpacing)/6
                            entry: modelData; caption: page.playCount(modelData.playCount)
                        }
                    }
                }
                Text { visible: page.catalog && !page.catalog.homeRecommendations.length; text: page.catalog && page.catalog.homeBusy ? qsTr("正在加载推荐歌单…") : qsTr("暂时没有推荐歌单"); color: AppTheme.canvasSecondary; font.pixelSize: 13 }
            }
            Item {
                id: chartStage
                objectName: "discoverChartStage"
                width: parent.width; height: 382; clip: true
                Row {
                    objectName: "discoverChartPreviews"
                    x: -page.chartsProgress*(chartStage.width+24)
                    width: parent.width; height: parent.height; spacing: 20
                    enabled: !page.allCharts
                    Repeater {
                        model: page.catalog ? page.catalog.homePreviews : []
                        delegate: Rectangle {
                            id: preview
                            required property var modelData
                            width: (chartStage.width-20)/2; height: chartStage.height; radius: 18
                            color: AppTheme.canvasDark ? "#20ffffff" : "#26ffffff"
                            Heading { x: 20; y: 20; text: preview.modelData.title }
                            UiButton { objectName: "discoverMoreCharts"; anchors.right: parent.right; anchors.rightMargin: 16; y: 18; height: 30; radius: 15; label: qsTr("查看更多"); foregroundColor: AppTheme.canvasSecondary; color: "transparent"; border.width: 0; onClicked: page.allCharts=true }
                            Column {
                                x: 10; y: 68; width: parent.width-20
                                Repeater {
                                    model: preview.modelData.tracks || []
                                    delegate: SongRow {
                                        required property var modelData
                                        required property int index
                                        width: preview.width-20; track: modelData; rowIndex: index; canvasText: true
                                        onActivated: page.trackActivated(track, preview.modelData.tracks || [])
                                        onCommandRequested: command=>page.trackCommandRequested(command,track,index,preview.modelData.tracks || [])
                                        onContextRequested: (mx,my)=>{const p=mapToItem(page,mx,my);songMenu.openAt(p.x,p.y,{track:track,rowIndex:index,rows:preview.modelData.tracks || []})}
                                    }
                                }
                            }
                            Text { visible: !(preview.modelData.tracks || []).length; anchors.centerIn: parent; text: page.catalog && page.catalog.homeBusy ? qsTr("正在加载榜单…") : qsTr("榜单暂时无法加载"); color: AppTheme.canvasSecondary; font.pixelSize: 13 }
                        }
                    }
                }
                Item {
                    objectName: "discoverAllCharts"
                    x: (1-page.chartsProgress)*(chartStage.width+24)
                    width: parent.width; height: parent.height
                    enabled: page.allCharts
                    RoundIconButton { objectName: "discoverChartsBack"; diameter: 30; kind: "chevronRight"; glyphRotation: 180; transparentSurface: true; glyphColor: AppTheme.canvasText; onClicked: page.allCharts=false }
                    Heading { x: 40; text: qsTr("网易云榜单"); font.pixelSize: 20 }
                    Text { anchors.right: parent.right; y: 6; text: qsTr("横向滚动，发现更多榜单"); color: AppTheme.canvasSecondary; font.pixelSize: 11 }
                    GridView {
                        id: chartGrid
                        objectName: "discoverChartsGrid"
                        y: 40; width: parent.width; height: parent.height-y
                        model: page.catalog ? page.catalog.homeCharts : []
                        flow: GridView.FlowTopToBottom; cellWidth: 146; cellHeight: height/2
                        clip: true; reuseItems: true; cacheBuffer: cellWidth; boundsBehavior: Flickable.StopAtBounds
                        delegate: CollectionCard {
                            required property var modelData
                            width: Math.min(chartGrid.cellWidth-18,chartGrid.cellHeight-50)
                            entry: modelData; caption: modelData.subtitle || ""
                        }
                        WheelHandler { target: null; onWheel: event=>page.horizontalWheel(chartGrid,event) }
                    }
                }
            }
            Column {
                id: dailySection
                objectName: "discoverDailySection"
                width: parent.width; spacing: 16
                Item {
                    width: parent.width; height: 30
                    Heading { text: qsTr("每日推荐") }
                    Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: page.catalog ? page.catalog.dailySource : ""; color: AppTheme.canvasSecondary; font.pixelSize: 12 }
                }
                ListView {
                    id: daily
                    objectName: "discoverDailyTracks"
                    width: parent.width; height: 208
                    model: page.catalog ? page.catalog.dailyTracks : []
                    orientation: ListView.Horizontal; spacing: 18
                    clip: true; reuseItems: true; cacheBuffer: 180; boundsBehavior: Flickable.StopAtBounds
                    delegate: Column {
                        id: dailyCard
                        required property var modelData
                        required property int index
                        width: 156; spacing: 6
                        CoverArt {
                            width: 156; height: 156; cornerRadius: 12; source: dailyCard.modelData.artwork || ""; sourcePixelSize: 256; showShadow: false
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.trackActivated(dailyCard.modelData, page.catalog ? page.catalog.dailyTracks : []) }
                            TapHandler { acceptedButtons: Qt.RightButton; onTapped: eventPoint=>{const p=dailyCard.mapToItem(page,eventPoint.position.x,eventPoint.position.y);songMenu.openAt(p.x,p.y,{track:dailyCard.modelData,rowIndex:dailyCard.index,rows:page.catalog ? page.catalog.dailyTracks : []})} }
                        }
                        Text { width: parent.width; text: dailyCard.modelData.title || ""; color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { width: parent.width; text: dailyCard.modelData.artist || ""; color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                    WheelHandler { target: null; onWheel: event=>page.horizontalWheel(daily,event) }
                    Text { visible: !daily.count; anchors.centerIn: parent; text: page.catalog && page.catalog.homeBusy ? qsTr("正在加载每日推荐…") : qsTr("每日推荐暂时无法加载"); color: AppTheme.canvasSecondary; font.pixelSize: 13 }
                }
            }
            Column {
                id: historySection
                objectName: "discoverHistorySection"
                width: parent.width; spacing: 16
                Item {
                    width: parent.width; height: 30
                    Heading { text: qsTr("搜索历史") }
                    UiButton { objectName: "discoverClearHistory"; anchors.right: parent.right; label: qsTr("清除"); height: 30; radius: 15; foregroundColor: AppTheme.canvasSecondary; enabled: page.searchController && page.searchController.searchHistory.length>0; opacity: enabled ? 1 : .4; onClicked: page.searchController.clearSearchHistory() }
                }
                Flow {
                    id: historyPills
                    objectName: "discoverHistoryPills"
                    width: parent.width; spacing: 8
                    Repeater {
                        model: page.searchController ? page.searchController.searchHistory : []
                        delegate: UiButton { required property string modelData; objectName: "discoverHistoryPill"; label: modelData; height: 32; radius: 16; foregroundColor: AppTheme.canvasText; onClicked: page.searchRequested(modelData,"") }
                    }
                }
                Text { visible: !page.searchController || !page.searchController.searchHistory.length; text: qsTr("搜索过的关键词会留在这里"); color: AppTheme.canvasSecondary; font.pixelSize: 12 }
            }
        }
    }
    ScrollPosition { id: scrollPosition; view: scroll; key: "discover" }
    SongContextMenu { id: songMenu; anchors.fill: parent; onCommandTriggered: (command,data)=>page.trackCommandRequested(command,data.track,data.rowIndex,data.rows || []) }
}
