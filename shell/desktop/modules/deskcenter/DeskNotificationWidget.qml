import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications

Item {
    id: widget
    anchors.fill: parent
    anchors.margins: 12

    readonly property bool onGlass: !AppearanceTokens.surface.paintInQml
        && AppearanceConfigService.widgetStyle === "glass"
    readonly property color foregroundColor: AppearanceTokens.content.ink("#f7f9fc")
    readonly property color chromeForegroundColor: onGlass ? "white" : foregroundColor
    readonly property color actionFill: AppearanceTokens.content.onBackdrop
        ? AppearanceTokens.colors.primaryContainer : "#83c7ff"
    readonly property color actionInk: AppearanceTokens.content.onBackdrop
        ? AppearanceTokens.colors.primaryContainerForeground : "#102239"
    readonly property color messageSurfaceColor: {
        if (!onGlass) return ink(0.06)
        const c = ThemeService.backgroundColor
        return Qt.rgba(c.r, c.g, c.b, AppearanceTokens.isDarkTheme ? 0.74 : 0.64)
    }
    function ink(alpha) {
        const c = foregroundColor
        return Qt.rgba(c.r, c.g, c.b, alpha === undefined ? 1 : alpha)
    }
    function textInk(alpha) {
        return ink(Math.max(0.94, alpha))
    }

    component NotificationText: GlassText {
        color: widget.foregroundColor
        style: Text.Normal
    }

    component PanelText: NotificationText {
        color: widget.chromeForegroundColor
    }

    readonly property string widgetSize: DeskCenterConfigService.sizeFor("notifications")
    property string selectedCategory: "全部"
    property ListModel filteredHistory: ListModel {}
    property var expandedGroups: ({})
    property string groupMembership: ""
    property int groupEpoch: 0
    property real pendingScrollPosition: 0

    // Parent-owned timers cancel deferred work when a desktop repack destroys
    // this loader. Queuing its methods with Qt.callLater can outlive the QML
    // context during a resize or a size/side change.
    Timer {
        id: historyRebuild
        interval: 0
        onTriggered: widget.rebuildFilteredHistory()
    }
    Timer {
        id: restoreScroll
        interval: 0
        onTriggered: notifList.contentY = Math.max(0, Math.min(
            widget.pendingScrollPosition, notifList.contentHeight - notifList.height))
    }

    function groupExpanded(key) { return expandedGroups[key] === groupEpoch }

    function toggleGroup(key) {
        const next = Object.assign({}, expandedGroups)
        next[key] = groupExpanded(key) ? -1 : groupEpoch
        expandedGroups = next
    }

    function rebuildFilteredHistory() {
        if (!notifList) return
        let scrollPosition = notifList.contentY
        filteredHistory.clear()
        const history = ControlCenterService.notificationHistory
        const groups = []
        const byKey = new Map()
        for (let i = 0; i < history.count; i++) {
            const row = history.get(i)
            const category = ControlCenterService.notificationCategory(row.appName, row.desktopEntry)
            if (selectedCategory !== "全部" && category !== selectedCategory) continue
            // Each other application has its own preview budget, so one busy
            // sender cannot hide all the other applications in that category.
            const key = category === "其他" ? "app:" + (row.desktopEntry || row.appName || "系统通知") : category
            let group = byKey.get(key)
            if (!group) {
                group = {key: key, name: category === "其他" ? (row.appName || "系统通知") : category,
                    items: []}
                byKey.set(key, group)
                groups.push(group)
            }
            // ListModel.get() returns a live model object. Copy its fields
            // before a subsequent history update can remove that object.
            group.items.push({notifId: row.notifId, appName: row.appName, appIcon: row.appIcon,
                image: row.image || "", desktopEntry: row.desktopEntry, summary: row.summary,
                body: row.body, timestamp: row.timestamp, actionLabel: row.actionLabel, hasAction: row.hasAction})
        }
        const membership = JSON.stringify(groups.map(group => group.key).sort())
        if (membership !== groupMembership) {
            groupMembership = membership
            groupEpoch++
            scrollPosition = 0
        }
        // Share the visible space between applications. A lone application
        // shows everything while it fits, then reserves room for "more" and
        // keeps only the newest rows in the automatic preview.
        const rowHeight = widgetSize === "large" ? 94 : 76
        const singleCapacity = Math.max(1, Math.floor((notifList.height - 30) / rowHeight))
        const availableRows = Math.max(groups.length,
            Math.floor((notifList.height - groups.length * 64) / rowHeight))
        const previewLimit = Math.max(1, Math.min(5,
            Math.floor(availableRows / Math.max(1, groups.length))))
        for (const group of groups) {
            const limit = groups.length === 1
                ? (group.items.length <= singleCapacity ? group.items.length : availableRows)
                : previewLimit
            const metadata = {groupKey: group.key, groupName: group.name,
                totalCount: group.items.length, hiddenCount: Math.max(0, group.items.length - limit)}
            const placeholder = {notifId: -1, appName: "", appIcon: "", image: "", desktopEntry: "",
                summary: "", body: "", timestamp: 0, actionLabel: "", hasAction: false}
            filteredHistory.append(Object.assign({}, placeholder, metadata, {rowKind: "header"}))
            const count = groupExpanded(group.key) ? group.items.length : Math.min(limit, group.items.length)
            for (let i = 0; i < count; i++)
                filteredHistory.append(Object.assign({}, group.items[i], metadata, {rowKind: "message"}))
            if (metadata.hiddenCount > 0)
                filteredHistory.append(Object.assign({}, placeholder, metadata, {rowKind: "more"}))
        }
        pendingScrollPosition = scrollPosition
        restoreScroll.restart()
    }
    onExpandedGroupsChanged: rebuildFilteredHistory()
    onHeightChanged: historyRebuild.restart()
    onWidgetSizeChanged: historyRebuild.restart()
    onSelectedCategoryChanged: {
        notifList.contentY = 0
        rebuildFilteredHistory()
    }
    Component.onCompleted: rebuildFilteredHistory()
    Connections {
        target: ControlCenterService
        function onHistoryRevisionChanged() { widget.rebuildFilteredHistory() }
    }

    readonly property int notifCount: ControlCenterService.notificationHistory.count

    function formatTime(ts) {
        if (!ts) return ""
        const d = new Date(ts)
        const h = String(d.getHours()).padStart(2, '0')
        const m = String(d.getMinutes()).padStart(2, '0')
        return h + ":" + m
    }

    function openNotification(notifId, appName, desktopEntry) {
        ControlCenterService.openNotification(notifId, appName, desktopEntry)
    }

    // Header
    Item {
        id: headerRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 24

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            BundledIcon {
                objectName: "notification-centre-icon"
                name: "notification-bell"
                size: 15
                color: widget.chromeForegroundColor
                anchors.verticalCenter: parent.verticalCenter
            }

            PanelText {
                text: "通知中心"
                font { pixelSize: 13; weight: Font.DemiBold }
                anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
                visible: widget.notifCount > 0
                width: badgeText.implicitWidth + 8
                height: 16
                radius: 8
                color: widget.ink(0.14)
                anchors.verticalCenter: parent.verticalCenter
                PanelText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: widget.notifCount
                    font { pixelSize: 9; weight: Font.Bold }
                }
            }
        }

        // Clear button
        Rectangle {
            visible: widget.notifCount > 0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: clearLabel.implicitWidth + 12
            height: 20
            radius: 10
            color: widget.ink(clearMouse.containsMouse ? 0.16 : 0.08)

            PanelText {
                id: clearLabel
                anchors.centerIn: parent
                text: "清空"
                font { pixelSize: 10; family: "Noto Sans CJK SC" }
                color: clearMouse.containsMouse ? AppearanceTokens.colors.error : widget.chromeForegroundColor
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    ControlCenterService.clearAllNotifications()
                }
            }
        }
    }

    Row {
        id: categoryRow
        anchors.top: headerRow.bottom
        anchors.topMargin: 7
        spacing: 4
        Repeater {
            model: ["全部", "QQ", "微信", "Telegram", "其他"]
            Rectangle {
                required property string modelData
                width: categoryLabel.implicitWidth + 12
                height: 24
                radius: AppearanceTokens.shape.small
                color: widget.selectedCategory === modelData && AppearanceTokens.content.onBackdrop
                    ? AppearanceTokens.colors.primaryContainer
                    : Qt.rgba(widget.chromeForegroundColor.r, widget.chromeForegroundColor.g,
                        widget.chromeForegroundColor.b, widget.selectedCategory === modelData
                            ? 0.20 : (categoryMouse.containsMouse ? 0.12 : 0.08))
                PanelText {
                    id: categoryLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: widget.selectedCategory === modelData && AppearanceTokens.content.onBackdrop
                        ? AppearanceTokens.colors.primaryContainerForeground : widget.chromeForegroundColor
                    font.pixelSize: 10
                }
                MouseArea {
                    id: categoryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: widget.selectedCategory = modelData
                }
            }
        }
    }

    // Body
    // Empty state
    Item {
        id: emptyState
        visible: widget.filteredHistory.count === 0
        anchors {
            left: parent.left
            right: parent.right
            top: categoryRow.bottom
            bottom: parent.bottom
        }

        Column {
            anchors.centerIn: parent
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🔔"
                font.pixelSize: widgetSize === "large" ? 28 : 22
                opacity: 0.45
            }

            PanelText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: widget.selectedCategory === "全部" ? "暂无新通知" : "暂无" + widget.selectedCategory + "通知"
                font { pixelSize: 11; weight: Font.Medium; family: "Noto Sans CJK SC" }
            }

            PanelText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "新消息将在此处汇总，点击可打开"
                font { pixelSize: 9; family: "Noto Sans CJK SC" }
            }
        }
    }

    // Notification List
    ListView {
        id: notifList
        objectName: "desk-notification-list"
        visible: widget.notifCount > 0
        anchors {
            left: parent.left
            right: parent.right
            top: categoryRow.bottom
            topMargin: 8
            bottom: parent.bottom
        }
        clip: true
        spacing: 6
        model: widget.filteredHistory
        Controls.ScrollBar.vertical: Controls.ScrollBar {
            width: 5
            policy: Controls.ScrollBar.AsNeeded
            visible: size < 1
            background: null
            contentItem: Rectangle {
                implicitWidth: 5
                radius: 2.5
                color: widget.ink(parent.pressed ? 0.55 : 0.28)
            }
        }

        delegate: Rectangle {
            id: itemCard
            required property string appName
            required property string appIcon
            required property string image
            required property string desktopEntry
            required property string summary
            required property string body
            required property var notifId
            required property var timestamp
            required property var actionLabel
            required property bool hasAction
            required property int index
            required property string rowKind
            required property string groupKey
            required property string groupName
            required property int totalCount
            required property int hiddenCount

            property bool isExpanded: false
            readonly property bool isMessage: rowKind === "message"
            readonly property bool isHovered: itemMouse.containsMouse || openMouse.containsMouse || delMouse.containsMouse

            objectName: rowKind + "-" + groupKey + (isMessage ? "-" + notifId : "")
            width: notifList.width - 8
            height: rowKind === "header" ? 24 : rowKind === "more" ? 28 : Math.max(58, itemContentCol.implicitHeight + 14)
            radius: AppearanceTokens.shape.small
            color: rowKind === "header" ? "transparent" : Qt.rgba(widget.messageSurfaceColor.r,
                widget.messageSurfaceColor.g, widget.messageSurfaceColor.b,
                widget.messageSurfaceColor.a + (isHovered ? 0.08 : 0))
            border.width: rowKind === "header" ? 0 : 1
            border.color: widget.ink(isHovered ? 0.22 : 0.08)

            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            // Base MouseArea for clicking anywhere on the card
            MouseArea {
                id: itemMouse
                objectName: "notification-history-body"
                anchors.fill: parent
                hoverEnabled: true
                enabled: itemCard.rowKind !== "header"
                cursorShape: itemCard.rowKind === "more" || itemCard.hasAction
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (itemCard.rowKind === "more") widget.toggleGroup(itemCard.groupKey)
                    else if (itemCard.hasAction) widget.openNotification(notifId, appName, desktopEntry)
                }
            }

            PanelText {
                anchors.left: parent.left
                anchors.leftMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                visible: itemCard.rowKind === "header"
                text: itemCard.groupName + " · " + itemCard.totalCount + " 条"
                font { pixelSize: 11; weight: Font.DemiBold }
            }

            NotificationText {
                anchors.centerIn: parent
                visible: itemCard.rowKind === "more"
                text: widget.groupExpanded(itemCard.groupKey)
                    ? "收起 " + itemCard.groupName + " 消息 ▴"
                    : "更多 " + itemCard.groupName + " 消息（" + itemCard.hiddenCount + " 条） ▾"
                font { pixelSize: 11; weight: Font.Medium }
            }

            IconImage {
                id: messageAvatar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 8
                width: 34; height: 34
                source: image || AppIdentityService._iconPath(appIcon)
                asynchronous: false
                visible: itemCard.isMessage && source.toString().length > 0
                layer.enabled: true
                layer.effect: SquircleMask {
                    cornerRadius: 7
                    cornerExponent: AppearanceTokens.shape.cornerExponent
                    maskWidth: messageAvatar.width
                    maskHeight: messageAvatar.height
                }
            }

            // Content column - fixed margins so its layout and text wrapping NEVER jitter
            Column {
                id: itemContentCol
                visible: itemCard.isMessage
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: messageAvatar.visible ? 50 : 8
                    rightMargin: 26  // Fixed right margin to leave room for the top-right delete button
                    topMargin: 6
                }
                spacing: 3

                Item {
                    width: parent.width
                    height: 14

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        IconImage {
                            width: 12; height: 12
                            source: AppIdentityService._iconPath(appIcon)
                            visible: appIcon.length > 0
                            asynchronous: false
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "💬"
                            font.pixelSize: 10
                            visible: appIcon.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        NotificationText {
                            text: ControlCenterService.notificationCategory(appName, desktopEntry) === "其他" ? (appName || "系统通知") : ControlCenterService.notificationCategory(appName, desktopEntry)
                            font { pixelSize: 9; weight: Font.DemiBold }
                            color: widget.textInk(0.80)
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Timestamp shown when NOT hovered (top-right close button replaces it when hovered)
                    NotificationText {
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: widget.formatTime(timestamp)
                        font { pixelSize: 8 }
                        color: widget.textInk(0.72)
                        visible: !itemCard.isHovered && !!timestamp
                    }
                }

                NotificationText {
                    width: parent.width
                    text: summary || ""
                    font { pixelSize: 12; weight: Font.DemiBold }
                    color: widget.foregroundColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    visible: !!summary
                }

                NotificationText {
                    width: parent.width
                    text: body || ""
                    font { pixelSize: 11 }
                    color: widget.textInk(0.88)
                    elide: itemCard.isExpanded ? Text.ElideNone : Text.ElideRight
                    maximumLineCount: itemCard.isExpanded ? 10 : (widgetSize === "large" ? 2 : 1)
                    wrapMode: Text.Wrap
                    visible: !!body
                }
            }

            // Top-right delete button ("×")
            Rectangle {
                id: deleteBtn
                objectName: "notification-history-delete"
                z: 2
                anchors {
                    right: parent.right
                    top: parent.top
                    margins: 5
                }
                width: 18; height: 18
                radius: 9
                visible: itemCard.isMessage && itemCard.isHovered
                color: delMouse.containsMouse ? AppearanceTokens.colors.error : widget.ink(0.12)

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: delMouse.containsMouse ? AppearanceTokens.colors.errorForeground : widget.foregroundColor
                    font { pixelSize: 12; weight: Font.Bold }
                }

                MouseArea {
                    id: delMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ControlCenterService.removeHistoryById(notifId)
                    }
                }
            }

            // Bottom-right open button ("打开 ↗")
            Rectangle {
                id: openBtn
                objectName: "notification-history-open"
                z: 2
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: 5
                }
                width: openLabel.implicitWidth + 10
                height: 18
                radius: 9
                visible: itemCard.isMessage && itemCard.hasAction && itemCard.isHovered
                color: openMouse.containsMouse ? Qt.lighter(widget.actionFill, 1.08) : widget.actionFill

                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    id: openLabel
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        text: (itemCard.actionLabel && String(itemCard.actionLabel).length > 0)
                            ? ControlCenterService.notificationActionLabel({text: itemCard.actionLabel})
                            : (itemCard.hasAction ? "查看" : "打开")
                        color: widget.actionInk
                        font { pixelSize: 9; weight: Font.Medium; family: "Noto Sans CJK SC" }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "↗"
                        color: widget.actionInk
                        font { pixelSize: 9; weight: Font.Bold }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        widget.openNotification(notifId, appName, desktopEntry)
                    }
                }
            }
        }
    }
}
