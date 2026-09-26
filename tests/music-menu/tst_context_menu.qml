import QtQuick
import QtQuick.Controls
import QtTest
import "../../apps/music/qml"

TestCase {
    id: suite
    name: "MusicContextMenus"
    when: windowShown
    visible: true
    width: 640
    height: 520

    QtObject {
        id: controller
        property int currentTrackId: 9
        property int queueIndex: 0
        property string playbackState: "Paused"
        property string lastAction: ""
        property bool queued: false
        signal queueChanged()
        function isTrackQueued(id) { return queued }
        function trackDeletionInfo(id) { return {id:id, path:"/fixture/song.wav", title:"测试歌曲", localFile:true} }
        function deleteTrack(id, path) { lastAction = "delete:" + id + ":" + path }
        function playTrack(id) { lastAction = "play:" + id }
        function playQueueRow(row) { lastAction = "queue-play:" + row }
        function playPlaylistRow(row) { lastAction = "playlist-play:" + row }
        function playOnlineRow(row) { lastAction = "online-play:" + row }
        function playTrackNext(id) { lastAction = "next:" + id }
        function playOnlineNext(row) { lastAction = "online-next:" + row }
        function moveQueueRowNext(row) { lastAction = "queue-next:" + row }
        function enqueueTrack(id) { lastAction = "append:" + id }
        function enqueueOnlineRow(row) { lastAction = "online-append:" + row }
        function removeQueueRow(row) { lastAction = "queue-remove:" + row }
        function removeTrackFromPlaylist(playlist, id) { lastAction = "playlist-remove:" + id }
    }
    ListModel {
        id: tracks
        ListElement { trackId:1; title:"测试歌曲"; artist:"歌手"; album:"专辑"; durationText:"3:25"; artworkUrl:""; format:"WAV" }
    }
    Component {
        id: listComponent
        TrackListView { width:600; height:450; musicController:controller; trackModel:tracks }
    }
    Component {
        id: qualityComponent
        MusicComboBox { x:30; y:20; width:200; model:["128k", "320k", "flac"] }
    }
    Component {
        id: dialogComponent
        MusicDialog { width:320; title:"创建歌单"; standardButtons:Dialog.Ok | Dialog.Cancel }
    }
    function init() { controller.lastAction = ""; controller.queued = false; controller.currentTrackId = 9 }
    function labels(menu) {
        const result = []
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i)
            if (item && item.visible && item.text) result.push(item.text)
        }
        return result
    }
    function itemWithText(menu, text) {
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i)
            if (item && item.visible && item.text === text) return item
        }
        return null
    }
    function test_contexts_data() {
        return [
            {tag:"Songs", mode:"library", row:2, labels:["立即播放","下一首播放","加入播放队列","删除音乐…"]},
            {tag:"Queue", mode:"queue", row:2, labels:["立即播放","移到下一首","从队列移除"]},
            {tag:"Queue-current", mode:"queue", row:0, labels:["立即播放","从队列移除"]},
            {tag:"Queue-next", mode:"queue", row:1, labels:["立即播放","从队列移除"]},
            {tag:"Online", mode:"online", row:2, labels:["立即播放","下一首播放","加入播放队列"]},
            {tag:"Playlist", mode:"playlist", row:2, labels:["立即播放","下一首播放","加入播放队列","从歌单移除"]}
        ]
    }
    function test_contexts(data) {
        const list = createTemporaryObject(listComponent, suite, {contextMode:data.mode})
        verify(list)
        list.openTrackMenu(data.row, 1, "测试歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        compare(labels(menu), data.labels)
        verify(menu.background.radius > 0)
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i)
            if (item && item.visible && item.text) verify(item.background.radius > 0)
        }
        menu.close()
        tryCompare(menu, "opened", false)
    }
    function test_onlineNextDiffersFromAppend() {
        const list = createTemporaryObject(listComponent, suite, {contextMode:"online"})
        list.openTrackMenu(2, -1, "搜索歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        mouseClick(itemWithText(menu, "下一首播放"))
        compare(controller.lastAction, "online-next:2")
        tryCompare(menu, "visible", false)
        list.openTrackMenu(2, -1, "搜索歌曲", list)
        tryCompare(menu, "opened", true)
        mouseClick(itemWithText(menu, "加入播放队列"))
        compare(controller.lastAction, "online-append:2")
    }
    function test_noDuplicateQueueAction() {
        controller.queued = true
        const list = createTemporaryObject(listComponent, suite)
        list.openTrackMenu(2, 1, "测试歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        compare(labels(menu), ["立即播放","下一首播放","删除音乐…"])
        menu.close()
    }
    function test_onlineMenuWithEmptyQueue() {
        controller.currentTrackId = -1
        const list = createTemporaryObject(listComponent, suite, {contextMode:"online"})
        list.openTrackMenu(0, -1, "搜索歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        compare(labels(menu), ["立即播放","下一首播放","加入播放队列"])
        menu.close()
    }
    function test_removalStaysInContext_data() {
        return [{tag:"Queue", mode:"queue", label:"从队列移除", action:"queue-remove:2"},
                {tag:"Playlist", mode:"playlist", label:"从歌单移除", action:"playlist-remove:1"}]
    }
    function test_removalStaysInContext(data) {
        const list = createTemporaryObject(listComponent, suite, {contextMode:data.mode, playlistId:5})
        list.openTrackMenu(2, 1, "测试歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        mouseClick(itemWithText(menu, data.label))
        compare(controller.lastAction, data.action)
        verify(!findChild(list, "deleteMusicDialog").visible)
    }
    function test_roundedQualitySelection() {
        const combo = createTemporaryObject(qualityComponent, suite)
        verify(combo.background.radius > 0)
        mouseClick(combo)
        tryCompare(combo.popup, "opened", true)
        verify(combo.popup.background.radius > 0)
        const choices = combo.popup.contentItem
        tryCompare(choices, "count", 3)
        tryVerify(() => choices.itemAtIndex(2) !== null)
        mouseClick(choices.itemAtIndex(2))
        compare(combo.currentText, "flac")
        tryCompare(combo.popup, "visible", false)
    }
    function test_dialogButtonsWork() {
        const dialog = createTemporaryObject(dialogComponent, suite)
        dialog.open()
        tryCompare(dialog, "opened", true)
        const button = dialog.standardButton(Dialog.Ok)
        verify(button)
        verify(button.background.radius > 0)
        mouseClick(button)
        tryCompare(dialog, "visible", false)
        compare(dialog.result, Dialog.Accepted)
    }
    function test_deleteRequiresConfirmation() {
        const list = createTemporaryObject(listComponent, suite)
        list.openTrackMenu(2, 1, "测试歌曲", list)
        const menu = findChild(list, "trackContextMenu")
        tryCompare(menu, "opened", true)
        mouseClick(itemWithText(menu, "删除音乐…"))
        const dialog = findChild(list, "deleteMusicDialog")
        tryCompare(dialog, "opened", true)
        verify(dialog.background.radius > 0)
        compare(controller.lastAction, "")
        dialog.reject()
        compare(controller.lastAction, "")
        dialog.open()
        tryCompare(dialog, "opened", true)
        dialog.accept()
        compare(controller.lastAction, "delete:1:/fixture/song.wav")
    }
}
