pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Popup {
    id: popup
    objectName: "lyricsMatchPopup"
    property var controller: null
    property var track: ({})
    property bool intoEditor: false
    property string selectedKey: ""
    property string sourceFilter: "all"
    readonly property var results: controller ? controller.lyricCandidates : []
    readonly property var visibleResults: sourceFilter==="all" ? results : results.filter(row=>row.lyricSource===sourceFilter)
    readonly property int selectedIndex: results.findIndex(row=>row.key===selectedKey)
    readonly property var selected: selectedIndex>=0 && selectedIndex<results.length ? results[selectedIndex] : ({})
    readonly property var sourceStates: [{id:"all",label:qsTr("全部"),count:results.length,done:true}].concat(controller ? controller.lyricMatchSources : [])
    signal acceptedLyrics(string text, bool intoEditor)
    function search() {
        selectedKey=""
        if(controller)controller.searchLyricMatches(track,query.text)
        candidates.contentY=0
    }
    function match(song, editor) {
        track=controller ? controller.lyricMatchSeed(song) : song;intoEditor=editor
        query.text=track.query || [track.title || "",track.artist || ""].join(" ").trim()
        sourceFilter="all";open();search()
    }
    function time(milliseconds) {
        if(milliseconds===undefined)return ""
        const seconds=Math.floor(milliseconds/1000)
        return Math.floor(seconds/60)+":"+String(seconds%60).padStart(2,"0")
    }
    parent: Basic.Overlay.overlay
    popupType: Basic.Popup.Item
    anchors.centerIn: parent
    width: Math.min(940, parent ? parent.width-48 : 940)
    height: Math.min(680, parent ? parent.height-48 : 680)
    padding: 24
    modal: true; focus: true
    closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
    onOpened: AppTheme.presentPopup(popup)
    onClosed: {
        if(controller)controller.releaseLyricMatch()
        selectedKey="";sourceFilter="all";track=({});query.text=""
        if(AppTheme.currentPopup===popup)AppTheme.currentPopup=null
    }
    background: Rectangle { radius: 24; color: AppTheme.darkMode ? "#252d36" : "#f7f8fb"; border.color: AppTheme.border }
    // Popup modality and the disabled application surface block background input.
    Basic.Overlay.modal: Rectangle { color: "#780e1520"; radius: AppTheme.windowCornerRadius }
    contentItem: Item {
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: mouse=>mouse.accepted=true; onWheel: wheel=>wheel.accepted=true }
        UiButton { id: communityOriginal; anchors.left: parent.left; anchors.bottom: parent.bottom; height: 36; label: qsTr("查看社区原稿"); visible: !!popup.selected.sourceUrl; onClicked: Qt.openUrlExternally(popup.selected.sourceUrl) }
        Text { text: qsTr("歌词匹配"); color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 23; font.weight: Font.DemiBold }
        Text { y: 34; text: qsTr("多来源歌词与社区 TTML · 结果陆续显示，可随时预览和使用"); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
        RoundIconButton { anchors.right: parent.right; diameter: 30; kind: "close"; glyphColor: AppTheme.textPrimary; transparentSurface: true; onClicked: popup.close() }
        Row {
            y: 64; width: parent.width; spacing: 10
            Basic.TextField {
                id: query
                objectName: "lyricMatchQuery"
                width: parent.width-(stopSearch.visible ? 176 : 96); height: 38; leftPadding: 38; rightPadding: 12
                placeholderText: qsTr("歌曲标题 / 艺术家"); selectByMouse: true
                color: AppTheme.textPrimary; placeholderTextColor: AppTheme.textMuted
                font.family: AppTheme.fontFamily; font.pixelSize: 13
                selectionColor: AppTheme.accent; selectedTextColor: "white"
                background: Rectangle { radius: 12; color: AppTheme.darkMode ? "#353e49" : "#e9edf3"; border.width: query.activeFocus ? 1 : 0; border.color: AppTheme.accent }
                IconGlyph { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; kind: "search"; glyphColor: AppTheme.textSecondary }
                onAccepted: popup.search()
            }
            UiButton { objectName: "lyricSearchButton"; width: 86; height: 38; label: qsTr("搜索"); onClicked: popup.search() }
            UiButton { id: stopSearch; objectName: "lyricStopButton"; visible: !!popup.controller && popup.controller.lyricMatchBusy; width: 70; height: 38; label: qsTr("停止"); onClicked: popup.controller.cancelLyricMatch() }
        }
        Flickable {
            y: 113; width: parent.width; height: 34; clip: true
            contentWidth: sourceTabs.width; contentHeight: height; boundsBehavior: Flickable.StopAtBounds
            Row {
                id: sourceTabs; spacing: 6
                Repeater {
                    model: popup.sourceStates
                    delegate: Rectangle {
                        id: sourceTab
                        required property var modelData
                        readonly property bool selected: popup.sourceFilter===modelData.id
                        activeFocusOnTab: true
                        Keys.onReturnPressed: { popup.sourceFilter=modelData.id;candidates.contentY=0 }
                        Keys.onSpacePressed: { popup.sourceFilter=modelData.id;candidates.contentY=0 }
                        width: sourceLabel.implicitWidth+20; height: 28; radius: 9
                        color: selected ? AppTheme.accent : (AppTheme.darkMode ? "#353e49" : "#e9edf3")
                        Text {
                            id: sourceLabel; anchors.centerIn: parent
                            text: sourceTab.modelData.label+(sourceTab.modelData.count ? " "+sourceTab.modelData.count : sourceTab.modelData.done ? "" : " ···")
                            color: sourceTab.selected ? "white" : AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11
                        }
                        TapHandler { onTapped: { popup.sourceFilter=sourceTab.modelData.id;candidates.contentY=0 } }
                        HoverHandler { id: sourceHover }
                        Basic.ToolTip.visible: sourceHover.hovered && sourceTab.modelData.id!=="all"
                        Basic.ToolTip.text: [sourceTab.modelData.state,sourceTab.modelData.detail].filter(Boolean).join(" · ")
                        Basic.ToolTip.delay: 250
                    }
                }
            }
        }
        Text { y: 157; text: qsTr("匹配结果")+(popup.visibleResults.length ? "  ·  "+popup.visibleResults.length : ""); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11; font.weight: Font.Medium }
        ListView {
            id: candidates
            objectName: "lyricMatchCandidates"
            x: 0; y: 180; width: Math.round(parent.width*.39); height: parent.height-236
            clip: true; spacing: 8; boundsBehavior: Flickable.StopAtBounds
            model: popup.visibleResults
            delegate: Rectangle {
                id: result
                required property var modelData
                required property int index
                objectName: "lyricCandidate-"+modelData.key
                readonly property bool selected: popup.selectedKey===modelData.key
                width: candidates.width; height: 102; radius: 12
                color: selected ? (AppTheme.darkMode ? "#3b444e" : "#e5e9ee") : AppTheme.darkMode ? "#303945" : "white"
                border.width: 1
                border.color: selected ? AppTheme.accent : AppTheme.darkMode ? "#485361" : "#dce2ea"
                activeFocusOnTab: true
                function selectResult() { popup.selectedKey=modelData.key;popup.controller.previewLyricMatch(popup.selectedIndex) }
                Keys.onReturnPressed: selectResult()
                Keys.onSpacePressed: selectResult()
                Column {
                    x: 13; y: 11; width: parent.width-26; spacing: 5
                    Row {
                        width: parent.width
                        Text { width: parent.width-46; text: result.modelData.title; elide: Text.ElideRight; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { width: 46; horizontalAlignment: Text.AlignRight; text: result.modelData.score+"%"; color: result.selected ? AppTheme.accent : AppTheme.textSecondary; font.pixelSize: 11 }
                    }
                    Text { width: parent.width; text: [result.modelData.artist, result.modelData.album].filter(Boolean).join(" · "); elide: Text.ElideRight; color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                    Text { width: parent.width; elide: Text.ElideRight; text: [result.modelData.duration,result.modelData.creator].filter(Boolean).join(" · "); color: AppTheme.textMuted; font.pixelSize: 10 }
                    Row {
                        spacing: 5
                        Repeater {
                            model: [result.modelData.sourceLabel || ""].concat(result.modelData.features || [])
                            Rectangle {
                                required property string modelData
                                width: badge.implicitWidth+12; height: 19; radius: 5
                                color: modelData===qsTr("逐字") ? (AppTheme.darkMode ? "#675042" : "#fff0dc") : (AppTheme.darkMode ? "#485361" : "#eaf0f6")
                                Text { id: badge; anchors.centerIn: parent; text: parent.modelData; color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 9 }
                            }
                        }
                    }
                }
                TapHandler { onTapped: result.selectResult() }
            }
            Basic.ScrollBar.vertical: StableScrollBar {}
            Text { anchors.centerIn: parent; width: parent.width-20; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; text: popup.controller && popup.controller.lyricMatchBusy ? qsTr("正在搜索并验证歌词…") : qsTr("此来源暂无可用歌词\n可切换来源或调整关键词"); visible: !popup.visibleResults.length; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
        }
        Rectangle {
            id: previewPanel
            x: candidates.width+14; y: 157; width: parent.width-x; height: parent.height-y-56; radius: 14
            color: AppTheme.darkMode ? "#202731" : "white"
            border.color: AppTheme.darkMode ? "#3f4b5a" : "#e0e5ec"
            Text { x: 18; y: 14; width: parent.width-36; text: popup.selected.title || qsTr("歌词预览"); elide: Text.ElideRight; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
            Text { x: 18; y: 37; width: parent.width-36; text: popup.selected.artist || qsTr("选择左侧结果，查看原文与译文"); elide: Text.ElideRight; color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 10 }
            Rectangle { x: 18; y: 61; width: parent.width-36; height: 1; color: AppTheme.divider; opacity: .5 }
            ListView {
                id: preview
                objectName: "lyricMatchPreview"
                x: 18; y: 76; width: parent.width-28; height: parent.height-y-16
                clip: true; boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                spacing: 18
                reuseItems: true
                cacheBuffer: Math.max(0, height)
                currentIndex: -1
                model: popup.visible && popup.controller ? popup.controller.lyricPreviewLines : []
                onModelChanged: positionViewAtBeginning()
                Component.onCompleted: contentItem.objectName="lyricMatchPreviewLines"
                MouseArea {
                    parent: preview
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        preview.cancelFlick()
                        const delta=event.pixelDelta.y || event.angleDelta.y/120*64
                        const bottom=preview.originY+Math.max(0,preview.contentHeight-preview.height)
                        preview.contentY=Math.max(preview.originY,Math.min(bottom,preview.contentY-delta))
                        event.accepted=true
                    }
                }
                // Keep the gutter stable during scrolling; reclaim it only when
                // the user explicitly hides all scrollbars.
                delegate: Row {
                    id: line
                    required property var modelData
                    required property int index
                    objectName: "lyricMatchPreviewLine"
                    width: preview.width; spacing: 12
                    Text { width: 33; y: 3; text: popup.time(line.modelData.timeMs); color: AppTheme.textMuted; font.family: "Consolas"; font.pixelSize: 10 }
                    Column {
                        width: parent.width-45; spacing: 5
                        Text { width: parent.width; text: line.modelData.text || "♪"; wrapMode: Text.Wrap; color: AppTheme.textPrimary; font.family: AppTheme.fontFamily; font.pixelSize: 14; lineHeight: 1.25 }
                        Text { width: parent.width; visible: text.length>0; text: line.modelData.translation || ""; wrapMode: Text.Wrap; color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12; lineHeight: 1.15 }
                        Text { width: parent.width; visible: text.length>0; text: line.modelData.romanization || ""; wrapMode: Text.Wrap; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 11; lineHeight: 1.15 }
                    }
                }
                Basic.ScrollBar.vertical: StableScrollBar { objectName: "lyricMatchPreviewScrollbar" }
            }
            Text { anchors.centerIn: preview; text: qsTr("选择候选，预览歌词"); visible: !popup.controller || !popup.controller.lyricPreview.length; color: AppTheme.textMuted; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
        }
        Text {
            anchors.bottom: parent.bottom; x: communityOriginal.visible ? communityOriginal.width+12 : 0; width: parent.width-x-250; height: 36
            verticalAlignment: Text.AlignVCenter
            text: popup.controller ? popup.controller.lyricMatchError : ""
            color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11; wrapMode: Text.WordWrap
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 8
            UiButton { label: qsTr("取消"); onClicked: popup.close() }
            UiButton {
                objectName: "lyricApplyButton"
                label: popup.intoEditor ? qsTr("使用此歌词") : qsTr("应用并保存"); emphasized: true
                opacity: enabled ? 1 : .45
                enabled: popup.controller && popup.selectedIndex>=0 && popup.controller.lyricPreview.trim().length>0
                onClicked: { popup.acceptedLyrics(popup.controller.lyricPreview,popup.intoEditor);popup.close() }
            }
        }
    }
    component StableScrollBar: Basic.ScrollBar {
        policy: Basic.ScrollBar.AlwaysOff
        visible: false; width: 0
    }
}
