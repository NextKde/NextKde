pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

Item {
    id: panel

    property bool darkMode: AppTheme.darkMode || Qt.application.arguments.indexOf("--dark") >= 0
    property string title: qsTr("评论")
    property string activeSortMode: "latest"
    property var comments: []
    property bool busy: false
    property string errorMessage: ""
    signal moreRequested()
    signal retryRequested()

    signal sortModeChanged(string mode)

    implicitWidth: 430
    implicitHeight: 720
    clip: true

    function userName(comment) {
        return String(comment && (comment.user || comment.name) || qsTr("匿名用户"))
    }

    function commentText(comment) {
        return String(comment && (comment.body || comment.text) || "")
    }

    function likeCount(comment) {
        if (!comment)
            return "0"
        const value = comment.likes !== undefined ? comment.likes : comment.likeCount
        return String(value === undefined ? 0 : value)
    }

    function initials(comment) {
        const name = userName(comment).trim()
        return name.length ? name.slice(0, 1).toUpperCase() : "?"
    }

    function selectSortMode(mode) {
        if (activeSortMode === mode)
            return
        activeSortMode = mode
        sortModeChanged(mode)
    }

    GlassSurface {
        anchors.fill: parent
        cornerRadius: 22
        tint: panel.darkMode ? "#b3212935" : "#cceef2f7"
        edgeColor: AppTheme.border
        shadowOpacity: .08
    }

    Item {
        id: header
        x: 24
        y: 18
        width: parent.width - 48
        height: 48

        Text {
            id: titleLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: panel.title
            color: AppTheme.textPrimary
            font.family: AppTheme.fontFamily
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }

        SegmentedTabBar {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            model: [
                { label: qsTr("最新"), mode: "latest" },
                { label: qsTr("最热"), mode: "popular" }
            ]
            currentIndex: panel.activeSortMode === "popular" ? 1 : 0
            cellWidth: 58
            cellHeight: 30
            cellRadius: 15
            outerPadding: 2
            radius: 17
            textColor: AppTheme.textPrimary
            darkMode: panel.darkMode
            onSelected: function(index, value) {
                panel.selectSortMode(value.mode)
            }
        }
    }

    Rectangle {
        x: 24
        y: 70
        width: parent.width - 48
        height: 1
        color: AppTheme.divider
    }

    component CommentAvatar: Item {
        id: avatar

        required property var commentData
        property real avatarSize: 38

        width: avatarSize
        height: avatarSize

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: avatar.commentData && avatar.commentData.avatarColor
                   ? avatar.commentData.avatarColor
                   : (panel.darkMode ? "#5c47748f" : "#84b7d9")

            Text {
                anchors.centerIn: parent
                text: panel.initials(avatar.commentData)
                color: "white"
                font.family: AppTheme.fontFamily
                font.pixelSize: avatar.avatarSize * .38
                font.weight: Font.DemiBold
            }
        }

        Image {
            id: avatarImage
            anchors.fill: parent
            source: avatar.commentData && avatar.commentData.avatar
                    ? String(avatar.commentData.avatar) : ""
            sourceSize.width: 128
            sourceSize.height: 128
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            visible: false
        }

        Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: avatarImage
            visible: avatarImage.status === Image.Ready
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: .5
            maskSpreadAtMin: 1
        }
    }

    component CommentEntry: Item {
        id: entry

        required property var commentData
        property bool nested: false

        implicitHeight: Math.max(commentAvatar.height, entryContent.implicitHeight) + 12

        Rectangle {
            visible: entry.nested
            x: -8
            y: -6
            width: parent.width + 8
            height: parent.height
            radius: 11
            color: AppTheme.control
            border.width: 1
            border.color: AppTheme.divider
        }

        CommentAvatar {
            id: commentAvatar
            commentData: entry.commentData
            avatarSize: entry.nested ? 30 : 38
        }

        Column {
            id: entryContent
            x: commentAvatar.width + 12
            width: parent.width - x
            spacing: 6

            Item {
                width: parent.width
                height: 19

                Text {
                    id: userLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - likeRow.width - 78)
                    text: panel.userName(entry.commentData)
                    textFormat: Text.PlainText
                    color: AppTheme.textPrimary
                    font.family: AppTheme.fontFamily
                    font.pixelSize: entry.nested ? 12 : 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    anchors.left: userLabel.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(entry.commentData && entry.commentData.time || "")
                    color: AppTheme.textMuted
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 10
                }

                Row {
                    id: likeRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    IconGlyph {
                        width: 13
                        height: 13
                        kind: "heart"
                        glyphColor: AppTheme.textMuted
                        strokeWidth: 1.35
                    }
                    Text {
                        text: panel.likeCount(entry.commentData)
                        color: AppTheme.textMuted
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }

            Text {
                width: parent.width
                text: panel.commentText(entry.commentData)
                textFormat: Text.PlainText
                color: AppTheme.textPrimary
                font.family: AppTheme.fontFamily
                font.pixelSize: entry.nested ? 11 : 12
                lineHeight: 1.35
                wrapMode: Text.Wrap
            }
        }
    }

    ListView {
        id: commentsList
        footer: Item {
            width: commentsList.width; height: panel.comments.length ? 44 : 0
            Text {
                anchors.centerIn: parent
                text: panel.busy ? qsTr("正在加载…") : panel.errorMessage || qsTr("加载更多评论")
                font.family: AppTheme.fontFamily; font.pixelSize: 12; color: AppTheme.textSecondary
            }
            TapHandler { enabled: !panel.busy; onTapped: panel.moreRequested() }
        }
        x: 18
        y: 82
        width: parent.width - 36
        height: parent.height - y - 16
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        model: panel.comments || []

        delegate: Item {
            id: commentDelegate
            required property int index
            required property var modelData

            width: commentsList.width
            height: primaryComment.implicitHeight
                    + (replyColumn.visible ? replyColumn.implicitHeight + 8 : 0) + 17

            CommentEntry {
                id: primaryComment
                x: 6
                width: parent.width - 12
                height: implicitHeight
                commentData: commentDelegate.modelData
            }

            Column {
                id: replyColumn
                visible: replyRepeater.count > 0
                x: 56
                y: primaryComment.height + 4
                width: parent.width - x - 8
                spacing: 8

                Repeater {
                    id: replyRepeater
                    model: commentDelegate.modelData && commentDelegate.modelData.replies
                           ? commentDelegate.modelData.replies : []

                    delegate: CommentEntry {
                        required property var modelData
                        width: replyColumn.width
                        height: implicitHeight
                        commentData: modelData
                        nested: true
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 56
                height: 1
                color: AppTheme.divider
            }
        }
    }

    Text {
        visible: !panel.comments || panel.comments.length === 0
        anchors.centerIn: commentsList
        text: panel.busy ? qsTr("正在加载评论…") : panel.errorMessage || qsTr("暂无评论")
        TapHandler { onTapped: if (!panel.busy) panel.retryRequested() }
        color: AppTheme.textSecondary
        font.family: AppTheme.fontFamily
        font.pixelSize: 13
    }
}
