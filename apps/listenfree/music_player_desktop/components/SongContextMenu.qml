pragma ComponentBehavior: Bound

import QtQuick

ContextMenu {
    id: menu
    objectName: "songContextMenu"
    property bool playlistMode: false
    readonly property var contextTrack: contextData ? contextData.track : null

    function isLocalTrack(track) {
        if (!track)
            return false
        return String(track.localPath || "").length > 0
                || String(track.source || "").toLowerCase() === "local"
    }

    actions: [
        { label: qsTr("立即播放"), command: "play_now" },
        { label: qsTr("下一首播放"), command: "play_next" },
        { label: qsTr("收藏 / 取消收藏"), command: "favorite" },
        { label: qsTr("加入队尾"), command: "add_to_queue" },
        { label: qsTr("添加到歌单"), command: "add_to_playlist", enabled: !menu.contextTrack || !menu.contextTrack.radioId },
        { label: qsTr("下载歌曲"), command: "download", enabled: !menu.isLocalTrack(menu.contextTrack) && (!menu.contextTrack || !menu.contextTrack.radioId) },
        { label: qsTr("编辑信息"), command: "edit_tags", separatorBefore: true,
          enabled: menu.isLocalTrack(menu.contextTrack) },
        { label: qsTr("在资源管理器中显示"), command: "show_in_explorer",
          enabled: menu.isLocalTrack(menu.contextTrack) },
        { label: menu.playlistMode ? qsTr("从歌单移除") : qsTr("从资料库移除"), command: menu.playlistMode ? "remove_from_playlist" : "remove_from_library", separatorBefore: true },
        { label: qsTr("从磁盘删除"), command: "delete_from_disk", destructive: true,
          enabled: menu.isLocalTrack(menu.contextTrack) }
    ]
}
