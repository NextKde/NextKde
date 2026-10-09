pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import "../components"

Item {
    id: page
    objectName: "playlistPage"

    property string filterText: ""
    readonly property var filteredPlaylists: {
        const rows = catalog ? catalog.onlinePlaylists || [] : []
        const term = filterText.trim().toLocaleLowerCase()
        return term.length ? rows.filter(row => String(row.title || row.name || "").toLocaleLowerCase().indexOf(term) >= 0) : rows
    }
    property var catalog
    property Item backdrop: null
    property bool darkMode: false
    property int selectedCategory: 0
    property int selectedMode: 1
    property string selectedFilter: qsTr("默认")
    property int shareSourceIndex: 0
    function saveNavigationState() {
        return { category: selectedCategory, mode: selectedMode, filter: selectedFilter,
                 shareSource: shareSourceIndex, y: gridPosition.saveNavigationState() }
    }
    function restoreNavigationState(state) {
        selectedCategory = state.category; selectedMode = state.mode; selectedFilter = state.filter
        shareSourceIndex = state.shareSource
        entrySlide.complete(); entryFade.complete()
        gridPosition.restoreNavigationState(state.y)
    }
    property bool filterOpen: false
    property bool shareOpen: false
    onShareOpenChanged: {
        if (shareOpen) shareDialog.open()
        else shareDialog.close()
    }
    property bool entered: false
    property var platformNames: [qsTr("酷我"),qsTr("酷狗"),"QQ",qsTr("网易云"),qsTr("咪咕")]
    readonly property var platformIds: ["kw","kg","tx","wy","mg"]
    readonly property var shareSources: platformNames
    readonly property var filterGroups: catalog ? catalog.tags : []

    signal openCollection(string kind, string title, color tint)
    signal collectionTransitionRequested(string kind, string title, color tint,
                                         rect frameRect, rect artworkRect,
                                         url artworkSource)
    signal filterChanged(string key, string value)
    signal shareLinkRequested(string source, string link)

    Component.onCompleted: {
        entered = true
        if (catalog && !catalog.recommendations.length) catalog.refresh()
        if (Qt.application.arguments.indexOf("playlist-filter") >= 0)
            filterOpen = true
        if (Qt.application.arguments.indexOf("playlist-share") >= 0)
            shareOpen = true
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    Item {
        id: toolbar
        x: 10
        y: page.entered ? 14 : -10
        width: parent.width - 18
        height: 48
        z: 12
        opacity: page.entered ? 1 : 0

        Behavior on y { NumberAnimation { id: entrySlide; duration: AppTheme.duration(280); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { id: entryFade; duration: AppTheme.duration(210); easing.type: Easing.OutCubic } }

        RoundIconButton {
            id: filterButton
            width: 44
            height: 44
            diameter: 44
            kind: "filter"
            darkMode: page.darkMode
            onClicked: page.filterOpen = !page.filterOpen
        }

        GlassSurface {
            x: 49; width: 115; height: 44; cornerRadius: 22
            backdrop: page.backdrop; opaqueBackdropBase: false; backdropBlur: 20; frosted: true
            tint: AppTheme.canvasDark ? "#20262c" : "#f2f4f6"
            tintStrength: AppTheme.canvasDark ? .12 : .16; shadowOpacity: 0
        }
        SegmentedTabBar {
            id: modeTabs
            x: 49
            width: 115
            height: 44
            model: [qsTr("最新"), qsTr("最热")]
            currentIndex: page.selectedMode
            cellWidth: 53.5
            cellHeight: 36
            outerPadding: 4
            radius: 22
            color: "transparent"
            textColor: AppTheme.canvasText
            border.width: 0
            border.color: AppTheme.border
            onSelected: function(index, value) {
                page.selectedMode = index
                page.selectedCategory = 0
                page.selectedFilter = qsTr("默认")
                page.filterChanged("sort", index === 0 ? "new" : "hot")
            }
        }

        Item {
            id: categoryTabs
            x: toolbar.width - width
            width: 383
            height: 44

            GlassSurface {
                anchors.fill: parent
                cornerRadius: 22
                backdrop: page.backdrop; opaqueBackdropBase: false; backdropBlur: 20; frosted: true
                tint: AppTheme.canvasDark ? "#20262c" : "#f2f4f6"
                tintStrength: AppTheme.canvasDark ? .12 : .16
                shadowOpacity: 0
            }

            SegmentedTabBar {
                anchors.fill: parent
                controlled: true
                model: page.platformNames
                currentIndex: page.catalog ? Math.max(0,page.platformIds.indexOf(page.catalog.platform)) : 0
                cellWidth: 75
                cellHeight: 36
                outerPadding: 4
                radius: 22
                color: "transparent"
                textColor: AppTheme.canvasText
                border.width: 0
                onSelected: function(index, value) {
                    const categories = page.platformIds
                    page.selectedCategory = index
                    page.selectedFilter = qsTr("默认")
                    if(page.catalog)page.catalog.platform=categories[index]
                }
            }
        }

        Item {
            x: categoryTabs.x - width - 12
            width: 104
            height: 44
            GlassSurface {
                anchors.fill: parent; cornerRadius: 22
                backdrop: page.backdrop; opaqueBackdropBase: false; backdropBlur: 20; frosted: true
                tint: AppTheme.canvasDark ? "#20262c" : "#f2f4f6"
                tintStrength: AppTheme.canvasDark ? .12 : .16; shadowOpacity: 0
            }
            UiButton {
                objectName: "playlistShareButton"
                anchors.fill: parent; radius: height / 2; border.width: 0
                label: qsTr("打开歌单"); foregroundColor: AppTheme.canvasText
                color: page.shareOpen ? "#35ffffff" : shareHover.hovered ? "#24ffffff" : "transparent"
                HoverHandler { id: shareHover }
                onClicked: {
                    page.shareSourceIndex = page.catalog ? Math.max(0,page.platformIds.indexOf(page.catalog.platform)) : 0
                    page.shareOpen = true
                }
            }
        }
    }

    Text {
        x: 22; y: 65; width: parent.width - 44
        text: page.catalog ? (page.catalog.busy ? qsTr("正在加载…") : page.catalog.error) : ""
        color: AppTheme.textSecondary; font.pixelSize: 12
    }
    Text {
        anchors.centerIn: parent
        visible: page.filterText.trim().length > 0 && !page.filteredPlaylists.length
        text: qsTr("当前平台的歌单中没有找到“") + page.filterText + "”"
        color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 16
    }
    GridView {
        id: playlistViewport
        ScrollPosition { id: gridPosition; view: playlistViewport; key: "playlists" }
        objectName: "onlinePlaylistGrid"
        x: 24; y: 100; width: parent.width-48; height: parent.height-y
        bottomMargin: 96
        cellWidth: width/5; cellHeight: tileSize + 43 + Math.max(0, Math.max(120,(height-bottomMargin)/3.5) - previousTileSize - 43)/3
        readonly property real previousTileSize: Math.min(cellWidth-32, Math.max(120,(height-bottomMargin)/3.5)-48)
        readonly property real tileSize: cellWidth - (cellWidth-previousTileSize)/3
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: page.filteredPlaylists
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: playlistViewport.cellWidth; height: playlistViewport.cellHeight
            ArtworkTile {
                id: card
                objectName: "onlinePlaylistCard" + cell.index
                anchors.horizontalCenter: parent.horizontalCenter
                size: playlistViewport.tileSize
                title: cell.modelData.title || ""
                subtitle: cell.modelData.subtitle || ""
                artworkSource: cell.modelData.artwork || ""
                onActivated: {
                    const p=card.mapToItem(page,0,0), a=card.artworkItem.mapToItem(page,0,0)
                    page.collectionTransitionRequested("Playlist",card.title,AppTheme.accent,
                        Qt.rect(p.x,p.y,card.width,card.height),Qt.rect(a.x,a.y,card.size,card.size),card.artworkSource,card.artworkItem)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 18
        visible: page.filterOpen
        onClicked: page.filterOpen = false
    }

    GlassSurface {
        id: filterPopover
        x: 10
        y: page.filterOpen ? 66 : 78
        width: Math.min(820, page.width - 20)
        height: 392
        cornerRadius: 16
        tint: AppTheme.cardStrong
        edgeColor: AppTheme.border
        shadowOpacity: .28
        z: 20
        visible: opacity > 0.001
        opacity: page.filterOpen ? 1 : 0
        scale: page.filterOpen ? 1 : .975
        transformOrigin: Item.TopLeft

        Behavior on y { NumberAnimation { duration: AppTheme.duration(240); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: AppTheme.duration(180); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: AppTheme.duration(240); easing.type: Easing.OutCubic } }
        TapHandler { onTapped: {} }

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            clip: true
            contentWidth: width
            contentHeight: filterColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: filterColumn
                width: parent.width
                spacing: 14

                FilterGroup {
                    title: ""
                    labels: [qsTr("默认")]
                }

                Repeater {
                    model: page.filterGroups
                    delegate: FilterGroup {
                        required property var modelData
                        title: modelData.title
                        labels: modelData.labels
                    }
                }
            }
        }
    }

    Basic.Popup {
        id: shareDialog
        objectName: "playlistSharePopup"
        parent: Basic.Overlay.overlay
        popupType: Basic.Popup.Item
        anchors.centerIn: parent
        width: Math.min(540, parent ? parent.width - 48 : 540)
        height: 290
        padding: 24
        modal: true; focus: true
        closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
        onOpened: { AppTheme.presentPopup(shareDialog); linkInput.forceActiveFocus() }
        onClosed: {
            page.shareOpen = false
            if (AppTheme.currentPopup === shareDialog) AppTheme.currentPopup = null
        }
        function submit() {
            const link = linkInput.text.trim()
            if (!link.length) return
            close()
            if(page.catalog)page.catalog.platform=page.platformIds[page.shareSourceIndex]
            page.shareLinkRequested(page.shareSources[page.shareSourceIndex], link)
        }
        background: GlassSurface {
            cornerRadius: 24; backdrop: page.backdrop; backdropBlur: 32; frosted: true
            tint: AppTheme.darkMode ? "#252d36" : "#f7f8fb"; tintStrength: .88
            shadowOpacity: .18
        }
        Basic.Overlay.modal: Rectangle {
            radius: AppTheme.windowCornerRadius
            color: "#580e1520"
            WheelHandler { onWheel: event => event.accepted = true }
        }
        contentItem: Item {
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: mouse => mouse.accepted = true; onWheel: wheel => wheel.accepted = true }
            Text { text: qsTr("打开歌单"); color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 23; font.weight: Font.DemiBold }
            Text { y: 36; text: qsTr("选择来源，粘贴歌单分享链接"); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
            RoundIconButton { objectName: "playlistShareClose"; anchors.right: parent.right; diameter: 30; kind: "close"; glyphColor: AppTheme.textPrimary; darkMode: AppTheme.darkMode; transparentSurface: true; onClicked: shareDialog.close() }
            SegmentedTabBar {
                objectName: "playlistShareSources"
                implicitWidth: 0
                y: 72; width: parent.width; height: 40
                model: page.shareSources; controlled: true; currentIndex: page.shareSourceIndex
                cellWidth: (width - 8) / 5; cellHeight: 32; outerPadding: 4
                darkMode: AppTheme.darkMode; textColor: AppTheme.textSecondary; accentColor: AppTheme.textPrimary
                color: AppTheme.control; border.width: 0
                onSelected: (index, value) => page.shareSourceIndex = index
            }
            Basic.TextField {
                id: linkInput
                objectName: "playlistShareLink"
                y: 128; width: parent.width; height: 44; leftPadding: 14; rightPadding: 14
                placeholderText: "https://…"; selectByMouse: true
                color: AppTheme.textPrimary; placeholderTextColor: AppTheme.textMuted
                font.family: AppTheme.fontFamily; font.pixelSize: 13
                background: Rectangle { radius: 14; color: AppTheme.field; border.color: linkInput.activeFocus ? AppTheme.textMuted : AppTheme.fieldBorder }
                onAccepted: shareDialog.submit()
            }
            Row {
                anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 10
                UiButton { label: qsTr("取消"); radius: height / 2; onClicked: shareDialog.close() }
                UiButton { objectName: "playlistShareSubmit"; label: qsTr("打开歌单"); radius: height / 2; enabled: linkInput.text.trim().length > 0; opacity: enabled ? 1 : .45; onClicked: shareDialog.submit() }
            }
        }
    }

    component FilterGroup: Item {
        id: groupRoot
        property string title: ""
        property var labels: []
        width: filterColumn.width
        height: (title.length > 0 ? 26 : 0) + labelFlow.height

        Text {
            visible: parent.title.length > 0
            text: parent.title
            color: AppTheme.textSecondary
            font.family: AppTheme.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        Flow {
            id: labelFlow
            y: parent.title.length > 0 ? 26 : 0
            width: parent.width
            height: childrenRect.height
            spacing: 8

            Repeater {
                model: groupRoot.labels
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    width: chipLabel.implicitWidth + 28
                    height: 32
                    radius: 10
                    color: page.selectedFilter === modelData ? Qt.rgba(.20, .61, .83, .20) : chipHover.hovered ? AppTheme.controlHover : AppTheme.control
                    border.width: 1
                    border.color: page.selectedFilter === modelData ? AppTheme.accent : AppTheme.fieldBorder
            Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }
                    Text { id: chipLabel; anchors.centerIn: parent; text: chip.modelData; color: AppTheme.textPrimary; font.pixelSize: 12 }
                    HoverHandler { id: chipHover }
                    TapHandler {
                        onTapped: {
                            page.selectedFilter = chip.modelData
                            page.selectedCategory = 0
                            page.filterOpen = false
                            page.filterChanged("tag", chip.modelData)
                        }
                    }
                }
            }
        }
    }
}
