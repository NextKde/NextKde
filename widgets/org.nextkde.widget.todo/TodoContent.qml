import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var pimData
    property var host: null

    property color accentColor: "#007aff"
    property color iconForeground: "#ffffff"
    property color primaryInk: "#1c1c1e"
    property color subtleInk: "#8e8e93"
    property color circleBorderColor: "#c7c7cc"
    property color hairlineColor: "#e5e5ea"
    property color overdueInk: "#ff3b30"

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compact: spanCols <= 1
    readonly property bool tall: spanRows >= 2

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    readonly property bool available: Boolean(pimData?.available) || Boolean(pimData?.ready)
    readonly property bool ready: Boolean(pimData?.ready)
    readonly property bool cached: Boolean(pimData?.cached)
    readonly property string todayStr: String(pimData?.today ?? "")
    readonly property string errorMessage: String(pimData?.errorMessage ?? "")

    readonly property var allPending: {
        const raw = pimData?.pendingTodos
        if (!raw || typeof raw === "string" || typeof raw.length !== "number") return []
        const list = []
        for (let i = 0; i < raw.length; ++i) {
            const item = raw[i]
            if (item && !Boolean(item.completed))
                list.push(item)
        }
        return list
    }
    readonly property int pendingCount: allPending.length
    readonly property int itemLimit: compact ? 2 : (tall ? 6 : 3)
    readonly property var visibleTasks: allPending.slice(0, itemLimit)
    readonly property string titleText: isZh ? "提醒事项" : "Reminders"

    component RemindersBadge: Rectangle {
        property real badgeSize: 22
        property color badgeColor: root.accentColor
        property color glyphColor: root.iconForeground
        width: badgeSize
        height: badgeSize
        radius: badgeSize / 2
        color: root.outlineText
            ? Qt.rgba(root.primaryInk.r, root.primaryInk.g, root.primaryInk.b, 0.18)
            : badgeColor

        Column {
            anchors.centerIn: parent
            spacing: Math.max(2, parent.height * 0.12)
            Repeater {
                model: 3
                delegate: Row {
                    spacing: Math.max(2, badgeSize * 0.10)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, badgeSize * 0.10)
                        height: width
                        radius: width / 2
                        color: root.outlineText ? root.primaryInk : glyphColor
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(6, badgeSize * 0.36)
                        height: Math.max(1.5, badgeSize * 0.08)
                        radius: height / 2
                        color: root.outlineText ? root.primaryInk : glyphColor
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.host || root.host.isPreview || typeof root.host.invokeAction !== "function")
                return
            root.host.invokeAction("app.open-calendar", { view: "reminders" })
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: root.compact ? 12 : 14

        // ── 1x1 Compact Header (Count left + Icon badge right, Blue title below) ──
        Item {
            id: compactHeader
            visible: root.compact
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 46

            Text {
                anchors { left: parent.left; top: parent.top }
                height: 28
                verticalAlignment: Text.AlignVCenter
                text: root.available ? String(root.pendingCount) : "—"
                color: root.primaryInk
                font { pixelSize: 26; weight: Font.Bold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }

            RemindersBadge {
                anchors { right: parent.right; top: parent.top; topMargin: 2 }
                badgeSize: 24
            }

            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                text: root.titleText
                color: root.outlineText ? root.primaryInk : root.accentColor
                elide: Text.ElideRight
                font { pixelSize: 12; weight: Font.Bold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }

        // ── 2x1 / 2x2 Header (Blue icon + Title left, Count right) ─────────────
        Item {
            id: wideHeader
            visible: !root.compact
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: root.tall ? 32 : 26

            Row {
                anchors { left: parent.left; right: wideCount.left; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                spacing: 8

                RemindersBadge {
                    anchors.verticalCenter: parent.verticalCenter
                    badgeSize: root.tall ? 26 : 22
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, parent.width - (root.tall ? 34 : 30))
                    text: root.titleText
                    color: root.outlineText ? root.primaryInk : root.accentColor
                    elide: Text.ElideRight
                    font { pixelSize: root.tall ? 16 : 14; weight: Font.Bold }
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }

            Text {
                id: wideCount
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.available ? String(root.pendingCount) : "—"
                color: root.primaryInk
                font { pixelSize: root.tall ? 24 : 20; weight: Font.Bold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }

        // Subtle header divider line on 2x1 / 2x2
        Rectangle {
            id: headerRule
            visible: !root.compact
            anchors {
                left: parent.left; right: parent.right
                top: wideHeader.bottom; topMargin: 5
            }
            height: 1
            color: root.hairlineColor
        }

        // ── Task Rows ──────────────────────────────────────────────────────────
        Column {
            anchors {
                left: parent.left; right: parent.right
                top: root.compact ? compactHeader.bottom : headerRule.bottom
                bottom: parent.bottom
                topMargin: root.compact ? 6 : 4
            }
            spacing: 0

            Repeater {
                model: root.visibleTasks
                delegate: Item {
                    id: taskRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    readonly property int rowCount: Math.max(1, root.visibleTasks.length)
                    readonly property real maxRowH: root.compact ? 32 : (root.tall ? 38 : 30)
                    height: Math.min(maxRowH, Math.max(22, parent.height / rowCount))
                    readonly property string dueDate: String(modelData?.due ?? "").slice(0, 10)
                    readonly property bool isOverdue: dueDate.length > 0 && root.todayStr.length > 0 && dueDate < root.todayStr
                    readonly property string taskId: String(modelData?.id ?? modelData?.seriesId ?? "")
                    readonly property real circleSize: root.compact ? 11 : (root.tall ? 15 : 13)

                    Rectangle {
                        id: checkboxRing
                        width: taskRow.circleSize
                        height: taskRow.circleSize
                        radius: taskRow.circleSize / 2
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        color: "transparent"
                        border.width: 1.5
                        border.color: root.outlineText
                            ? root.primaryInk
                            : (taskRow.isOverdue ? root.overdueInk : root.circleBorderColor)
                    }

                    Text {
                        anchors {
                            left: checkboxRing.right
                            right: root.compact ? parent.right : dueLabel.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: root.compact ? 7 : 9
                            rightMargin: root.compact ? 0 : 8
                        }
                        text: String(taskRow.modelData?.title || (root.isZh ? "未命名待办" : "Untitled task"))
                        color: root.primaryInk
                        elide: Text.ElideRight
                        font { pixelSize: root.compact ? 10 : (root.tall ? 13 : 12); weight: Font.Normal }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }

                    Text {
                        id: dueLabel
                        visible: !root.compact && taskRow.dueDate.length > 0
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: taskRow.dueDate
                        color: taskRow.isOverdue && !root.outlineText ? root.overdueInk : root.subtleInk
                        font.pixelSize: root.tall ? 11 : 10
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }

                    // Indented 1px hairline separator (macOS Reminders style)
                    Rectangle {
                        visible: taskRow.index < taskRow.rowCount - 1
                        anchors {
                            left: parent.left; right: parent.right; bottom: parent.bottom
                            leftMargin: taskRow.circleSize + (root.compact ? 7 : 9)
                        }
                        height: 1
                        color: root.hairlineColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.host || root.host.isPreview || typeof root.host.invokeAction !== "function")
                                return
                            const payload = taskRow.taskId.length > 0
                                ? { view: "reminders", item: taskRow.taskId }
                                : { view: "reminders" }
                            root.host.invokeAction("app.open-calendar", payload)
                        }
                    }
                }
            }

            Item {
                visible: root.visibleTasks.length === 0
                width: parent.width
                height: parent.height

                Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: (root.ready && root.errorMessage.length === 0)
                        ? (root.isZh ? "没有待办事项" : "No Reminders")
                        : (root.errorMessage || (root.isZh ? "待办服务未连接" : "Todo service not connected"))
                    color: root.subtleInk
                    font.pixelSize: root.compact ? 10 : 12
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }
        }
    }
}
