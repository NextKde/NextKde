import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import Qt5Compat.GraphicalEffects
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications

// Top-right notification popup. One card per app group (newest on top).
//
// The window anchors top+right+bottom with a fixed bottom margin, so its
// surface size is constant -- it never resizes when cards enter/leave. That
// matters because a Wayland surface resize during the entrance x-slide showed
// up as a visible mid-animation hitch (the compositor's synchronous resize
// landed inside the 200ms slide). A constant surface eliminates it.
//
// A tall transparent Overlay window would normally intercept clicks across
// the whole right edge even when empty. We avoid that with `mask: Region`:
// the input region is shaped to the ListView's contentItem, so only the area
// actually covered by cards is clickable -- transparent gaps pass through.
//
// The ListModel carries only primitive roles; live Notification objects are
// fetched from groupService by groupKey (see NotificationGroupService --
// ListModel cannot store object arrays). Closing a card calls dismiss/expire
// on the group; the service rebuilds the model and ListView's own remove
// Transition plays the exit slide.
PanelWindow {
    id: root

    required property var groupService

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Fixed surface: top-anchored, enough vertical room for a stack of cards
    // growing downward. The mask keeps empty space click-through.
    anchors { top: true; right: true; bottom: true }
    margins { top: 48; right: 18; bottom: 48 }

    implicitWidth: 350

    // Shape the input region to the list content so the transparent parts of
    // the fixed-height surface don't swallow right-side clicks.
    mask: Region {
        item: notificationList.contentItem
    }

    // Blur the list content area so KWin's glass effect renders real liquid
    // glass behind each card. We track the real content height on a dedicated
    // `blurTrack` item, but only let its height *grow* with a delay (so the
    // glass fades in after a new card's entrance slide finishes, instead of
    // landing before the text arrives). Shrinking is immediate so removed
    // cards don't leave a lingering glass slab.
    Item {
        id: blurTrack
        anchors.top: notificationList.top
        anchors.left: notificationList.left
        width: notificationList.width
        height: blurTrackHeight.value

        QtObject {
            id: blurTrackHeight
            property real value: 0
            // Grow lazily (entrance slide is 200ms), shrink immediately.
            function sync(target) {
                if (target >= value) {
                    growTimer.targetValue = target
                    growTimer.restart()
                } else {
                    growTimer.stop()
                    value = target
                }
            }
            property Timer growTimer: Timer {
                property real targetValue: 0
                interval: 100
                onTriggered: blurTrackHeight.value = targetValue
            }
        }
    }
    BackgroundEffect.blurRegion: (root.visible && blurTrackHeight.value > 0) ? notifBlurRegionHolder : null

    Region {
        id: notifBlurRegionHolder
        RoundedBlurRegion {
            item: blurTrack
            radius: 28
        }
    }

    ListView {
        id: notificationList
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        model: root.groupService.groupsModel
        spacing: 10
        interactive: false
        clip: true
        onContentHeightChanged: blurTrackHeight.sync(contentHeight)

        // Entrance: opacity + x-slide. Surface size is constant, so no resize
        // lands mid-slide -- the slide stays smooth.
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; from: 120; to: 0; duration: 200; easing.type: Easing.InCubic }
            }
        }
        // Exit slide to the right.
        remove: Transition {
            NumberAnimation { property: "x"; from: 0; to: notificationList.width + 44; duration: 200; easing.type: Easing.InCubic }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: 200; easing.type: Easing.InOutCubic }
        }
        removeDisplaced: Transition {
            NumberAnimation { property: "y"; duration: 200; easing.type: Easing.InOutCubic }
        }

        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            readonly property string groupKey: modelData.groupKey
            readonly property int groupCount: modelData.count
            readonly property bool groupCollapsed: modelData.collapsed
            // Live newest Notification for this group. Depends on
            // sidecarRevision so it re-evaluates when the service rebuilds.
            readonly property var notification: {
                void root.groupService.sidecarRevision
                return root.groupService.latestForKey(card.groupKey)
            }
            // Snapshot of the last visible notification's display fields.
            // When the group is dying (count hits 0 during a dismiss), the
            // live notification is null but the card is still mid-exit-slide.
            // Without this snapshot the card's text collapses to empty and
            // you see a blank shell sliding away. We keep the last good
            // summary/body/appName/icon so the exiting card looks intact.
            property string _lastSummary: ""
            property string _lastBody: ""
            property string _lastAppName: ""
            property string _lastIconSource: ""
            property int _lastUrgency: 1
            onNotificationChanged: {
                if (card.notification) {
                    card._lastSummary = card.notification.summary || ""
                    card._lastBody = card.notification.body || ""
                    card._lastAppName = card.notification.appName || ""
                    card._lastUrgency = card.notification.urgency
                    card._lastIconSource = AppIdentityService._iconPath(
                        card.notification.image || card.notification.appIcon)
                }
            }
            // Display fields: use live notification, fall back to snapshot
            // when the group is dying (notification null but card visible).
            readonly property string displaySummary: card.notification
                ? (card.notification.summary.length > 0
                    ? card.notification.summary : card.notification.appName)
                : card._lastSummary
            readonly property string displayBody: card.notification
                ? card.notification.body : card._lastBody
            readonly property string displayAppName: card.notification
                ? card.notification.appName : card._lastAppName
            readonly property string displayIconSource: card.notification
                ? AppIdentityService._iconPath(card.notification.image || card.notification.appIcon)
                : card._lastIconSource
            readonly property bool isCritical: (card.notification
                ? card.notification.urgency : card._lastUrgency) === NotificationUrgency.Critical
            readonly property bool isLow: (card.notification
                ? card.notification.urgency : card._lastUrgency) === NotificationUrgency.Low
            readonly property bool expanded: !card.groupCollapsed && card.groupCount > 1
            readonly property color foregroundColor: ThemeService.foregroundColor
            readonly property color textOutlineColor: ThemeService.isDark
                ? Qt.rgba(0.05, 0.08, 0.12, 0.38)
                : Qt.rgba(1, 1, 1, 0.50)
            readonly property int textStyle: ThemeService.isDark ? Text.Outline : Text.Normal
            readonly property string iconSource: card.displayIconSource

            width: notificationList.width
            height: Math.floor(content.implicitHeight + 28)
            Behavior on height {
                NumberAnimation { duration: 200; easing.type: Easing.InOutCubic }
            }
            radius: 28
            color: "transparent"

            // ---- backgrounds ----
            // Frosted liquid glass backdrop adapting to theme
            LiquidGlassSurface {
                anchors.fill: parent
                radius: card.radius
                baseColor: ThemeService.isDark
                    ? Qt.rgba(0.08, 0.09, 0.12, 0.38)
                    : Qt.rgba(0.95, 0.95, 0.98, 0.55)
                blurStrength: AppearanceTokens.glass.launcherBlur
                liquidStrength: AppearanceTokens.glass.launcherLiquid
                ambientPrimary: WallpaperPaletteService.primary
                ambientSecondary: WallpaperPaletteService.secondary
                ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
                border.width: 1
                border.color: ThemeService.isDark
                    ? Qt.rgba(1, 1, 1, 0.12)
                    : Qt.rgba(0, 0, 0, 0.08)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: card.isCritical
                color: Qt.rgba(0.55, 0.10, 0.08, 0.22)
            }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                visible: card.isLow
                color: ThemeService.isDark
                    ? Qt.rgba(0.04, 0.05, 0.08, 0.12)
                    : Qt.rgba(0, 0, 0, 0.04)
            }
            Rectangle {
                visible: card.isCritical
                x: 4; y: parent.radius * 0.5
                width: 3; height: parent.height - parent.radius
                radius: 1.5
                color: Qt.rgba(1.0, 0.27, 0.23, 0.95)
            }
            Rectangle {
                x: Math.min(parent.width / 2, parent.radius + 2)
                y: 0.6
                width: Math.max(0, parent.width - x * 2)
                height: 1
                color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
            }

            // ---- close + auto-expire ----

            // Close the whole group at once (× button or auto-expire), not
            // just the latest notification -- otherwise a stacked group of N
            // needs N clicks. Single notifications are a group of 1, so this
            // covers both cases. Uses groupKey (stable across rebuilds) rather
            // than card.index (which can drift during a rebuild).
            function close(expired) {
                if (expired)
                    root.groupService.expireGroupByKey(card.groupKey)
                else
                    root.groupService.dismissGroupByKey(card.groupKey)
            }

            // Auto-expire timer. Started on completed; guarded for null.
            // FreeDesktop: expireTimeout is milliseconds; -1 = persistent;
            // 0 = server picks. We default to 7000ms.
            Timer {
                interval: {
                    const n = card.notification
                    return (n && n.expireTimeout > 0)
                        ? Math.max(1000, n.expireTimeout)
                        : 7000
                }
                running: card.notification !== null
                repeat: false
                onTriggered: card.close(true)
            }

            // ---- header ----

            Item {
                id: appMark
                width: 34; height: width
                anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 14 }

                Text {
                    anchors.centerIn: parent
                    visible: !iconMask.visible
                    text: card.displayAppName.length > 0
                        ? card.displayAppName.slice(0, 1).toUpperCase()
                        : "•"
                    color: card.foregroundColor
                    style: card.textStyle
                    styleColor: card.textOutlineColor
                    font { pixelSize: 16; bold: true }
                }
                Rectangle {
                    id: iconMask
                    anchors.centerIn: parent
                    width: 30; height: width
                    radius: width * 0.30
                    visible: card.iconSource.length > 0
                    color: "transparent"
                    // Rectangle.clip doesn't round-corner child Images reliably.
                    // Use layer + OpacityMask to actually crop the icon to the
                    // rounded rectangle (same pattern as DockWindowPreview).
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: iconMask.width
                            height: iconMask.height
                            radius: iconMask.radius
                            color: "black"
                            visible: false
                        }
                    }
                    IconImage {
                        anchors.fill: parent
                        source: card.iconSource
                        asynchronous: true
                        smooth: true
                    }
                }
            }

            Rectangle {
                id: countBadge
                visible: card.groupCount > 1
                width: badgeText.implicitWidth + 12
                height: 18; radius: 9
                anchors { right: closeButton.left; rightMargin: 8; top: parent.top; topMargin: 15 }
                color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: card.groupCount
                    color: card.foregroundColor
                    font { pixelSize: 11; bold: true }
                }
            }

            MouseArea {
                anchors {
                    left: parent.left; top: parent.top
                    right: countBadge.visible ? countBadge.left : closeButton.left
                    bottom: appMark.bottom
                }
                visible: card.groupCount > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: root.groupService.toggleCollapsed(card.index)
            }

            // ---- content ----

            Column {
                id: content
                anchors {
                    left: appMark.right; leftMargin: 10
                    right: closeButton.left; rightMargin: 8
                    top: parent.top; topMargin: 14
                    bottom: parent.bottom; bottomMargin: 14
                }
                spacing: 4

                Text {
                    width: parent.width
                    text: card.expanded
                        ? (modelData.appName.length > 0 ? modelData.appName : "Notifications")
                        : card.displaySummary
                    color: card.foregroundColor
                    style: card.textStyle
                    styleColor: card.textOutlineColor
                    font { pixelSize: 14; bold: true }
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    width: parent.width
                    visible: !card.expanded && text.length > 0
                    text: card.displayBody
                    color: card.foregroundColor
                    style: card.textStyle
                    styleColor: card.textOutlineColor
                    opacity: 0.78
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                // Expanded: one row per notification, newest first.
                Repeater {
                    model: {
                        void root.groupService.sidecarRevision
                        return card.expanded
                            ? root.groupService.notificationsForKey(card.groupKey).slice().reverse()
                            : []
                    }
                    Item {
                        width: content.width
                        height: Math.max(notifRowText.implicitHeight, 20)
                        visible: card.expanded
                        Text {
                            id: notifRowText
                            anchors {
                                left: parent.left
                                right: notifRowClose.left
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.summary.length > 0
                                ? modelData.summary
                                : (modelData.appName || "")
                            color: card.foregroundColor
                            style: card.textStyle
                            styleColor: card.textOutlineColor
                            font { pixelSize: 13; bold: true }
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Text {
                            id: notifRowClose
                            text: "×"
                            color: card.foregroundColor
                            style: card.textStyle
                            styleColor: card.textOutlineColor
                            opacity: notifRowCloseArea.containsMouse ? 0.9 : 0.45
                            font.pixelSize: 16
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            MouseArea {
                                id: notifRowCloseArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.groupService.dismissNotification(modelData)
                            }
                        }
                    }
                }

                // Action buttons (collapsed: latest notification).
                Row {
                    width: parent.width
                    spacing: 8
                    visible: !card.expanded
                        && card.notification && card.notification.actions
                        && card.notification.actions.length > 0
                    Repeater {
                        model: (card.notification && card.notification.actions)
                            ? card.notification.actions
                            : []
                        Rectangle {
                            height: 28
                            width: actionLabel.implicitWidth + 24
                            radius: 14
                            color: actionMouse.containsMouse
                                ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
                                : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.05))
                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                text: {
                                    const raw = modelData.text || modelData.identifier || ""
                                    // Some apps (e.g. QQ) send English action labels.
                                    // Map common ones to Chinese for display.
                                    const map = {
                                        "view": "查看",
                                        "View": "查看",
                                        "reply": "回复",
                                        "Reply": "回复",
                                        "open": "打开",
                                        "Open": "打开",
                                        "close": "关闭",
                                        "Close": "关闭",
                                        "mark as read": "标为已读",
                                        "Mark as read": "标为已读"
                                    }
                                    return map[raw] || raw
                                }
                                color: card.foregroundColor
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modelData.invoke()
                                    if (!card.notification.resident)
                                        card.close(false)
                                }
                            }
                        }
                    }
                }

                // Inline reply (collapsed: latest notification).
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 8
                    visible: !card.expanded
                        && card.notification && card.notification.hasInlineReply
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)
                    TextInput {
                        id: replyInput
                        anchors { fill: parent; margins: 6 }
                        verticalAlignment: Text.AlignVCenter
                        color: card.foregroundColor
                        font.pixelSize: 13
                        text: ""
                        Text {
                            visible: !replyInput.text && !replyInput.activeFocus
                            text: card.notification
                                ? (card.notification.inlineReplyPlaceholder || "Reply…")
                                : "Reply…"
                            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                            font.pixelSize: 13
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                        }
                        onAccepted: {
                            if (text.length > 0 && card.notification) {
                                card.notification.sendInlineReply(text)
                                text = ""
                                if (!card.notification.resident)
                                    card.close(false)
                            }
                        }
                    }
                }
            }

            // ---- close button ----

            Text {
                id: closeButton
                text: "×"
                color: card.foregroundColor
                style: card.textStyle
                styleColor: card.textOutlineColor
                opacity: 0.55
                font.pixelSize: 22
                anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 9 }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.close(false)
                }
            }
        }
    }
}
