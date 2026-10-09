pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import "../components"

Item {
    id: page
    objectName: "radioPage"
    property var service
    property var playerController
    property Item backdrop: null
    property string filterText: ""
    property bool darkMode: false
    function saveNavigationState() { return { y: stationList.contentY } }
    function restoreNavigationState(state) {
        stationList.forceLayout()
        stationList.contentY = Math.max(0, Math.min(state.y, stationList.contentHeight - stationList.height + stationList.bottomMargin))
    }
    signal trackActivated(var track, var playbackContext)
    signal podcastOpened()
    signal podcastClosed()
    readonly property bool programs: service && Object.keys(service.podcast).length > 0
    readonly property bool podcasts: service && service.provider === "netease" && service.mode === "podcast" && !programs
    readonly property var providers: ["icecast", "radiobrowser", "netease"]
    readonly property var names: ["Icecast", "Radio Browser", qsTr("网易云")]
    readonly property var descriptions: [qsTr("探索全球独立广播"), qsTr("按地区寻找喜欢的声音"), qsTr("实时广播与播客节目")]
    function selectProvider(provider) { if(service){service.provider=provider;service.search(filterText)} }
    Component.onCompleted: if (service) service.activate()
    onFilterTextChanged: searchDelay.restart()
    Timer { id: searchDelay; interval: 300; onTriggered: if(page.service) page.service.search(page.filterText) }

    Item {
        id: sources
        objectName: "radioSources"
        x: 24; y: 14; width: parent.width - 48; height: 72
        GlassSurface {
            anchors.fill: parent; cornerRadius: 22
            backdrop: page.backdrop; opaqueBackdropBase: false; frosted: true; backdropBlur: 20
            tint: AppTheme.canvasDark ? "#20262c" : "#f2f4f6"
            tintStrength: AppTheme.canvasDark ? .12 : .16; shadowOpacity: 0
        }
        Row {
            anchors.fill: parent; anchors.margins: 4
            Repeater {
                id: sourceRepeater
                model: page.providers
                delegate: Rectangle {
                    id: source
                    required property int index
                    required property string modelData
                    objectName: "radioSource" + index
                    readonly property bool selected: page.service && page.service.provider === modelData
                    property real weight: selected ? 2 : 1
                    Behavior on weight { NumberAnimation { duration: AppTheme.duration(260); easing.type: Easing.BezierSpline; easing.bezierCurve: [.32,.72,0,1,1,1] } }
                    width: (sources.width-8) * weight / 4
                    height: sources.height-8; radius: 18
                    color: selected ? AppTheme.tabSelected : sourceMouse.pressed ? AppTheme.canvasSelected : sourceMouse.containsMouse ? AppTheme.canvasHover : "transparent"
                    Behavior on color { ColorAnimation { duration: AppTheme.duration(150) } }
                    clip: true
                    Column {
                        x: 18; width: parent.width-36; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                        Text { width: parent.width; text: page.names[source.index]; font.family: AppTheme.fontFamily; font.pixelSize: 16; font.weight: Font.DemiBold; color: source.selected ? AppTheme.textPrimary : AppTheme.canvasText; elide: Text.ElideRight }
                        Text { width: parent.width; text: page.descriptions[source.index]; font.family: AppTheme.fontFamily; font.pixelSize: 11; color: source.selected ? AppTheme.textSecondary : AppTheme.canvasSecondary; elide: Text.ElideRight }
                    }
                    MouseArea { id: sourceMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.selectProvider(source.modelData) }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: page.names[index]
                    Accessible.selected: selected
                    Accessible.onPressAction: page.selectProvider(modelData)
                }
            }
        }
    }
    Item {
        id: filters
        x: 24; y: sources.y+sources.height+18; width: sources.width; height: 36
        TextMetrics { id: titleMetrics; font: radioTitle.font; text: radioTitle.text }
        Row {
            spacing: 8
            UiButton { objectName: "radioPodcastBack"; visible: page.programs; compact: true; iconText: "chevronRight"; rotation: 180; onClicked: { page.service.closePodcast();page.podcastClosed() } }
            Text {
                id: radioTitle
                anchors.verticalCenter: parent.verticalCenter; font.family: AppTheme.fontFamily; font.pixelSize: 20; font.weight: Font.DemiBold; color: AppTheme.canvasText
                width: Math.min(titleMetrics.advanceWidth,260,filters.width*.4); elide: Text.ElideRight
                text: page.programs ? page.service.podcast.title : page.service && page.service.favoritesOnly ? qsTr("收藏的电台") : page.podcasts ? qsTr("播客精选") : qsTr("正在广播")
            }
            SegmentedTabBar {
                visible: page.service && page.service.provider === "netease" && !page.programs
                model: [qsTr("广播"),qsTr("播客")]; cellWidth: 52; cellHeight: 28; outerPadding: 3; radius: 17
                color: AppTheme.canvasHover; textColor: AppTheme.canvasSecondary; border.width: 0
                currentIndex: page.service && page.service.mode === "podcast" ? 1 : 0
                onSelected: (index,value) => page.service.mode=index===0?"broadcast":"podcast"
            }
        }
        Row {
            anchors.right: parent.right; spacing: 8
            UiButton { objectName: "radioFavorites"; label: qsTr("收藏"); iconText: "heart"; radius: 18; height: 36; selected: page.service && page.service.favoritesOnly; foregroundColor: AppTheme.canvasText; onClicked: page.service.favoritesOnly=!page.service.favoritesOnly }
            UiButton { objectName: "radioRefresh"; compact: true; iconText: "repeat"; foregroundColor: AppTheme.canvasText; onClicked: page.service.refresh() }
        }
    }
    Flickable {
        id: categories
        x: 24; y: filters.y+filters.height+10; width: sources.width; height: page.service && page.service.categories.length && !page.programs ? 30 : 0
        visible: height>0; contentWidth: categoryRow.width; clip: true; boundsBehavior: Flickable.StopAtBounds
        Row {
            id: categoryRow; spacing: 6
            Repeater {
                model: page.service ? page.service.categories : []
                delegate: UiButton {
                    required property var modelData
                    label: modelData.name; radius: 15; height: 30
                    foregroundColor: selected ? AppTheme.textPrimary : AppTheme.canvasText
                    selected: page.service.category === String(modelData.id) || (!page.service.category && String(modelData.id)==="0")
                    color: selected ? AppTheme.tabSelected : AppTheme.canvasHover
                    border.width: 0; onClicked: page.service.category=String(modelData.id)
                }
            }
        }
    }
    Text {
        id: status
        x: 26; y: categories.y+categories.height+10; width: sources.width; height: 20
        color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight
        text: !page.service ? "" : page.service.busy ? qsTr("正在加载电台…") : page.service.error ||
              (page.service.total>=0 ? qsTr("共 %1 个 · ").arg(page.service.total) : "") +
              (page.programs ? qsTr("选择节目开始播放") : page.podcasts ? qsTr("打开播客浏览节目") : qsTr("点击收听，收藏喜欢的声音"))
    }
    GridView {
        id: stationList
        objectName: "radioList"
        x: 24; y: status.y+status.height+8; width: sources.width; height: parent.height-y
        model: page.service ? page.service.rows : []
        readonly property int columns: page.programs ? 1 : Math.max(1,Math.floor(width/360))
        cellWidth: width/columns; cellHeight: page.programs ? 66 : 98
        cacheBuffer: height; bottomMargin: 102; clip: true; boundsBehavior: Flickable.StopAtBounds
        onModelChanged: contentY=0
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: stationList.cellWidth; height: stationList.cellHeight
            Loader {
                anchors.fill: parent; anchors.rightMargin: stationList.columns>1 ? 10 : 0; anchors.bottomMargin: 8
                sourceComponent: page.programs ? programComponent : stationComponent
            }
            Component {
                id: programComponent
                SongRow {
                    track: cell.modelData; rowIndex: cell.index; canvasText: true
                    playerController: page.playerController; showDownload: false
                    onActivated: page.trackActivated(track, page.service ? page.service.rows : [])
                    onSelectedRequested: page.trackActivated(track, page.service ? page.service.rows : [])
                    onCommandRequested: command => {
                        if(command==="favorite")page.service.toggleFavorite(track)
                        else if(command==="play_next")page.playerController.enqueueTrack(track,true)
                    }
                }
            }
            Component {
                id: stationComponent
                Rectangle {
                    id: card
                    objectName: "radioCard" + cell.index
                    readonly property bool current: {
                        if(!page.playerController)return false
                        const revision=page.playerController.currentTrack
                        return page.playerController.isCurrentTrack(cell.modelData)
                    }
                    readonly property bool favorite: {
                        if(!page.service)return false
                        const revision=page.service.favoritesRevision
                        return page.service.isFavorite(cell.modelData)
                    }
                    radius: 14; color: current ? AppTheme.canvasSelected : cardMouse.containsMouse ? AppTheme.canvasHover : Qt.rgba(AppTheme.canvasText.r,AppTheme.canvasText.g,AppTheme.canvasText.b,.035)
                    MouseArea { id: cardMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if(cell.modelData.kind==="podcast"){page.podcastOpened();page.service.openPodcast(cell.modelData)}else page.trackActivated(cell.modelData, page.service ? page.service.rows : []) } }
                    CoverArt { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 64; height: 64; cornerRadius: 10; artworkTier: "Thumbnail"; source: cell.modelData.artwork || "" }
                    Column {
                        x: 86; width: Math.max(30,parent.width-x-48); anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Text { width: parent.width; text: cell.modelData.title || ""; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.Medium; color: AppTheme.canvasText; elide: Text.ElideRight }
                        Text { width: parent.width; text: cell.modelData.artist || cell.modelData.tags || qsTr("网络广播"); font.family: AppTheme.fontFamily; font.pixelSize: 11; color: AppTheme.canvasSecondary; elide: Text.ElideRight }
                        Text { width: parent.width; text: cell.modelData.kind==="podcast" ? qsTr("%1 个节目").arg(cell.modelData.programCount||0) : (card.current?qsTr("正在收听 · "):"") + (cell.modelData.codec||qsTr("直播")) + (cell.modelData.bitrate?" · "+cell.modelData.bitrate+" kbps":""); font.family: AppTheme.fontFamily; font.pixelSize: 10; color: AppTheme.canvasSecondary; elide: Text.ElideRight }
                    }
                    RoundIconButton { anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; width: 30; height: 30; diameter: 30; kind: card.favorite?"heartFilled":"heart"; darkMode: AppTheme.canvasDark; onClicked: page.service.toggleFavorite(cell.modelData) }
                }
            }
        }
        footer: Item {
            width: stationList.width; height: page.service && (page.service.page>1 || page.service.hasMore) ? 58 : 0
            Row {
                anchors.centerIn: parent; spacing: 8
                UiButton { label: qsTr("上一页"); radius: 17; height: 34; enabled: page.service && page.service.page>1 && !page.service.busy; opacity: enabled?1:.4; onClicked: page.service.goToPage(page.service.page-1) }
                Text { text: page.service ? String(page.service.page) : "1"; width: 28; height: 34; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: AppTheme.canvasText; font.pixelSize: 13 }
                UiButton { label: qsTr("下一页"); radius: 17; height: 34; enabled: page.service && page.service.hasMore && !page.service.busy; opacity: enabled?1:.4; onClicked: page.service.goToPage(page.service.page+1) }
            }
        }
        Text { anchors.centerIn: parent; visible: page.service && !page.service.busy && !page.service.rows.length; text: page.service.error ? qsTr("暂时无法加载，点击右上角重试") : page.service.favoritesOnly ? qsTr("点击电台旁的爱心，将它收藏在这里") : qsTr("没有找到电台，换个关键词试试"); color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 14 }
    }
}
