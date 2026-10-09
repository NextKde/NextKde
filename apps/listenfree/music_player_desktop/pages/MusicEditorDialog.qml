pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Basic
import "../components"

Item {
    id: root
    objectName: "musicEditorDialog"

    property bool open: false
    property var track: ({})
    property string draftArtwork: ""
    property int selectedTab: 0
    property bool darkMode: Qt.application.arguments.indexOf("--dark") >= 0
    property bool reduceMotion: false

    readonly property color primaryText: darkMode ? "#f2f4f6" : "#1d2226"
    readonly property color secondaryText: darkMode ? "#aeb6bd" : "#626a70"
    readonly property color dialogSurface: darkMode ? "#252d36" : "#f7f8fb"
    readonly property color contentSurface: darkMode ? "#303945" : "#ffffff"
    readonly property color fieldSurface: darkMode ? "#3a4552" : "#edf0f5"

    signal matchRequested
    signal metadataRequested(var draft)
    function metadataDraft() { return editorLoader.item ? editorLoader.item.metadataDraft() : Object.assign({}, track) }
    function fillMetadata(values) { if (open && editorLoader.item) editorLoader.item.fillMetadata(values) }
    function setLyrics(text) { if (open && editorLoader.item) editorLoader.item.setLyrics(text) }
    signal closeRequested
    signal saveRequested(var values)

    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("musiceditor") >= 0 ||
                Qt.application.arguments.indexOf("musiceditor-properties") >= 0)
            open = true
    }

    function bitrateText() {
        const value = Number(track.bitRate || track.bitrate || 0)
        if (!value)
            return qsTr("未知")
        return (value > 10000 ? Math.round(value / 1000) : Math.round(value)) + " kbps"
    }

    function sampleRateText() {
        const value = Number(track.sampleRate || track.samplerate || 0)
        if (!value)
            return qsTr("未知")
        return value >= 1000 ? (value / 1000).toFixed(value % 1000 === 0 ? 0 : 1) + " kHz"
                             : value + " Hz"
    }

    function fileSizeText() {
        const value = Number(track.fileSize || track.size || 0)
        if (!value)
            return qsTr("未知")
        return value >= 1024 * 1024 ? (value / (1024 * 1024)).toFixed(1) + " MB"
                                   : (value / 1024).toFixed(1) + " KB"
    }

    visible: open || opacity > .01
    opacity: open && editorLoader.status === Loader.Ready ? 1 : 0
    focus: open

    Behavior on opacity {
        NumberAnimation {
            duration: root.reduceMotion ? 0 : AppTheme.duration(200)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
        }
    }

    onOpenChanged: {
        if (!open)
            return
        AppTheme.closePopup()
        selectedTab = 0
        forceActiveFocus()
        draftArtwork = ""
        if (editorLoader.item) editorLoader.item.resetFields()
        // Screenshot/test hook only; normal launches still open on the editable tag page.
        if (Qt.application.arguments.indexOf("--editor-properties") >= 0 ||
                Qt.application.arguments.indexOf("musiceditor-properties") >= 0)
            selectedTab = 2
    }

    Keys.onEscapePressed: root.closeRequested()

    Rectangle {
        anchors.fill: parent
        color: root.darkMode ? "#a0080b0e" : "#68171b1e"
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted=true; onClicked: root.closeRequested() }
    }

    Loader {
        id: editorLoader
        anchors.fill: parent
        // Keep the original exit animation alive, including a quick reopen.
        active: root.open || root.opacity > 0
        asynchronous: true
        focus: root.open
        onLoaded: {
            item.resetFields()
            item.presented = true
        }
        sourceComponent: Item {
            id: editorContent
            property bool presented: false
            function metadataDraft() { return Object.assign({}, root.track, {title:titleField.text, artist:artistField.text, album:albumField.text, artwork:root.draftArtwork || root.track.artwork}) }
            function fillMetadata(values) {
                if (values.title && values.title.trim()) titleField.text = values.title
                if (values.artist && values.artist.trim()) artistField.text = values.artist
                if (values.album && values.album.trim()) albumField.text = values.album
                if (values.artwork) root.draftArtwork = values.artwork
                root.selectedTab = 0
            }
            function setLyrics(text) { lyricsEditor.text=text;root.selectedTab=1 }
            function resetFields() {
                titleField.text=root.track.title || "";artistField.text=root.track.artist || "";albumField.text=root.track.album || ""
                genreField.text=root.track.genre || "";yearField.text=root.track.year || "";trackField.text=root.track.track || ""
                discField.text=root.track.disc || "";albumArtistField.text=root.track.albumArtist || "";composerField.text=root.track.composer || "";commentField.text=root.track.comment || ""
                lyricsEditor.text=root.track.lyrics || ""
            }

            Rectangle {
                id: dialog
                objectName: "musicEditorSurface"
                anchors.centerIn: parent
                width: Math.min(1060, parent.width - 48, Math.max(850, parent.width * 850 / 1066))
                height: Math.min(720, parent.height - 48, Math.max(548, parent.height * 548 / 709))
                radius: 16
                color: root.dialogSurface
                border.width: 1
                border.color: root.darkMode ? "#55ffffff" : "#86ffffff"
                scale: root.open && editorContent.presented ? 1 : .96

                Behavior on scale {
                    NumberAnimation {
                        duration: root.reduceMotion ? 0 : AppTheme.duration(200)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onWheel: wheel => wheel.accepted=true
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                CoverArt {
                    x: 21
                    y: 11
                    width: 130
                    height: 130
                    cornerRadius: 12
                    showShadow: false
                    objectName: "musicEditorArtwork"
                    source: root.draftArtwork || root.track.artwork || ""
                }

                Column {
                    x: 183
                    y: 24
                    width: editorActions.x - x - 20
                    spacing: 5
                    Text {
                        width: parent.width
                        text: titleField.text || qsTr("未知歌曲")
                        color: root.primaryText
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: artistField.text || qsTr("未知艺术家")
                        color: root.secondaryText
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 18
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: editorActions
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    y: 8
                    spacing: 7

                    UiButton {
                        objectName: "musicEditorSaveButton"
                        width: 72
                        height: 36
                        label: qsTr("保存")
                        emphasized: true
                        onClicked: root.saveRequested(Object.assign({
                            title: titleField.text,
                            artist: artistField.text,
                            album: albumField.text,
                            genre: genreField.text,
                            year: yearField.text,
                            track: trackField.text,
                            disc: discField.text,
                            albumArtist: albumArtistField.text,
                            composer: composerField.text,
                            comment: commentField.text,
                            lyrics: lyricsEditor.text
                        }, root.draftArtwork ? {artwork: root.draftArtwork} : {}))
                    }
                    RoundIconButton {
                        objectName: "musicEditorCloseButton"
                        diameter: 36
                        kind: "close"
                        darkMode: root.darkMode
                        reducedMotion: root.reduceMotion
                        glyphColor: root.darkMode ? "#f2f4f6" : "#1d1d1f"
                        onClicked: root.closeRequested()
                    }
                }

                Rectangle {
                    id: tabRail
                    x: 20
                    y: 168
                    width: 48
                    height: 240
                    radius: 24
                    color: root.darkMode ? "#80303942" : "#70eeeeef"
                    border.width: 1
                    border.color: root.darkMode ? "#45ffffff" : "#96ffffff"

                    Rectangle {
                        x: 4
                        y: 4
                        width: 40
                        height: 74
                        radius: 20
                        color: root.darkMode ? "#d33c4852" : "#ececec"
                        transform: Translate {
                            y: root.selectedTab * 78
                            Behavior on y {
                                NumberAnimation {
                                    duration: root.reduceMotion ? 0 : AppTheme.duration(220)
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                                }
                            }
                        }
                    }

                    Column {
                        x: 4
                        y: 4
                        Repeater {
                            model: [qsTr("基本信息"), qsTr("歌词"), qsTr("文件信息")]
                            delegate: Item {
                                id: tabItem
                                objectName: "musicEditorTab" + index
                                required property int index
                                required property string modelData
                                width: 40
                                height: 78

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 20
                                    color: tabHover.hovered && root.selectedTab !== tabItem.index
                                           ? (root.darkMode ? "#18ffffff" : "#20ffffff") : "transparent"
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: tabItem.modelData.split("").join("\n")
                                    color: root.selectedTab === tabItem.index
                                           ? AppTheme.accent : root.primaryText
                                    font.family: AppTheme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: root.selectedTab === tabItem.index ? Font.Bold : Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    lineHeight: .86
                                }
                                HoverHandler { id: tabHover }
                                // These tabs overlap the sidebar. A passive TapHandler
                                // lets the same click reach navigation beneath the dialog.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedTab = tabItem.index
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: contentFrame
                    objectName: "musicEditorContent"
                    x: 82
                    y: 159
                    width: parent.width - x - 30
                    height: parent.height - y - 32
                    radius: 12
                    color: root.contentSurface
                    border.width: 1
                    border.color: root.darkMode ? "#35ffffff" : "#48ffffff"
                    clip: true

                    Row {
                        width: contentFrame.width * 3
                        height: contentFrame.height
                        transform: Translate {
                            x: -root.selectedTab * contentFrame.width
                            Behavior on x {
                                NumberAnimation {
                                    duration: root.reduceMotion ? 0 : AppTheme.duration(220)
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                                }
                            }
                        }

                        Item {
                            width: contentFrame.width
                            height: contentFrame.height
                            Column {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 9
                                Row {
                                    spacing: 12
                                    UiButton { objectName: "musicEditorMetadataButton"; height: 30; label: qsTr("搜索基本信息"); onClicked: root.metadataRequested(root.metadataDraft()) }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("查找歌曲版本，预览后填入"); color: root.secondaryText; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                                }
                                Row {
                                    spacing: 12
                                    EditableField { id: titleField; objectName: "musicEditorTitle"; label: qsTr("歌曲名"); initialText: root.track.title || "" }
                                    EditableField { id: artistField; objectName: "musicEditorArtist"; label: qsTr("艺术家"); initialText: root.track.artist || "" }
                                }
                                Row {
                                    spacing: 12
                                    EditableField { id: albumField; objectName: "musicEditorAlbum"; label: qsTr("专辑名"); initialText: root.track.album || "" }
                                    EditableField { id: genreField; label: qsTr("流派"); initialText: root.track.genre || "" }
                                }
                                Row {
                                    spacing: 12
                                    EditableField { id: yearField; objectName: "musicEditorYear"; label: qsTr("年份"); initialText: root.track.year || "" }
                                    EditableField { id: trackField; label: "Track"; initialText: root.track.track || "" }
                                }
                                Row { spacing: 12
                                    EditableField { id: discField; label: "Disc"; initialText: root.track.disc || "" }
                                    EditableField { id: albumArtistField; label: qsTr("专辑艺术家"); initialText: root.track.albumArtist || "" }
                                }
                                Row { spacing: 12
                                    EditableField { id: composerField; label: qsTr("作曲"); initialText: root.track.composer || "" }
                                    EditableField { id: commentField; label: qsTr("备注"); initialText: root.track.comment || "" }
                                }
                            }
                        }

                        Item {
                            width: contentFrame.width
                            height: contentFrame.height
                            Text {
                                x: 16
                                y: 12
                                text: qsTr("当前歌词 · 可直接编辑")
                                color: root.primaryText
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            UiButton { anchors.right: parent.right; anchors.rightMargin: 16; y: 5; height: 30; label: qsTr("歌词匹配"); onClicked: root.matchRequested() }
                            Rectangle {
                                x: 16
                                y: 40
                                width: parent.width - 32
                                height: parent.height - 56
                                radius: 8
                                color: root.fieldSurface
                                border.width: 1
                                border.color: root.darkMode ? "#32ffffff" : "#3a9da8af"
                                Basic.ScrollView { anchors.fill: parent; anchors.margins: 8; clip: true
                                Basic.ScrollBar.vertical.policy: Basic.ScrollBar.AlwaysOff
                                Basic.ScrollBar.horizontal.policy: Basic.ScrollBar.AlwaysOff
                                Basic.TextArea {
                                    id: lyricsEditor
                                    text: root.track.lyrics || ""
                                    color: root.primaryText
                                    selectionColor: "#606b747d"
                                    wrapMode: TextEdit.Wrap
                                    font.pixelSize: 13
                                }
                                }
                            }
                        }

                        Item {
                            width: contentFrame.width
                            height: contentFrame.height
                            Column {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 9
                                Row {
                                    spacing: 12
                                    PropertyField { label: qsTr("格式"); value: String(root.track.format || root.track.codec || qsTr("未知")).toUpperCase() }
                                    PropertyField { label: qsTr("比特率"); value: root.bitrateText() }
                                }
                                Row {
                                    spacing: 12
                                    PropertyField { label: qsTr("采样率"); value: root.sampleRateText() }
                                    PropertyField { label: qsTr("位深"); value: root.track.bitDepth ? root.track.bitDepth + " bit" : qsTr("未知") }
                                }
                                Row {
                                    spacing: 12
                                    PropertyField { label: qsTr("声道"); value: root.track.channels ? root.track.channels + qsTr(" 声道") : qsTr("未知") }
                                    PropertyField { label: qsTr("文件大小"); value: root.fileSizeText() }
                                }
                                Row { spacing: 12
                                    PropertyField { label: qsTr("时长"); value: String(root.track.duration || qsTr("未知")) }
                                    PropertyField { label: qsTr("修改时间"); value: String(root.track.modified || qsTr("未知")) }
                                }
                                Row { spacing: 12
                                    EditableField { width: contentFrame.width - 32; label: qsTr("文件路径"); initialText: root.track.localPath || ""; readOnly: true }
                                }
                            }
                        }
                    }
                }
            }

            component EditableField: Column {
                id: editableField
                property string label: qsTr("字段")
                property string initialText: ""
                property bool readOnly: false
                property alias text: input.text
                width: (contentFrame.width - 44) / 2
                spacing: 3
                Text {
                    text: parent.label
                    color: root.secondaryText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 7
                    color: root.fieldSurface
                    border.width: parent.readOnly ? 1 : 0
                    border.color: root.darkMode ? "#32ffffff" : "#389da8af"
                    TextInput {
                        id: input
                        objectName: "musicEditorInput"
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: editableField.initialText
                        readOnly: editableField.readOnly
                        color: editableField.readOnly ? root.secondaryText : root.primaryText
                        selectionColor: "#606b747d"
                        font.pixelSize: 13
                        clip: true
                    }
                }
            }

            component PropertyField: Column {
                id: propertyField
                property string label: qsTr("属性")
                property string value: "未知"
                width: (contentFrame.width - 44) / 2
                spacing: 3
                Text {
                    text: parent.label
                    color: root.secondaryText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 7
                    color: root.fieldSurface
                    border.width: 1
                    border.color: root.darkMode ? "#32ffffff" : "#389da8af"
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: propertyField.value
                        color: root.secondaryText
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
