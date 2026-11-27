import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compact: spanCols <= 1
    readonly property bool tall: spanRows >= 2
    // 1x1 defaults to standard roundedRect; expressive wrappers pass shapeOverride.
    property string shapeOverride: ""
    readonly property string surfaceShape: compact ? (shapeOverride || "roundedRect") : "roundedRect"

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var pimData: liveMode ? (host.pim ?? snapshot) : snapshot
    readonly property string isoDate: liveMode ? String(host.clock?.isoDate ?? "") : String(snapshot?.today ?? "")
    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")

    readonly property var pal: appearance?.palette ?? ({})
    readonly property color onSurface: pal.onSurface ?? appearance?.foreground ?? "#1e293b"
    readonly property color onSurfaceVariant: pal.onSurfaceVariant ?? "#64748b"
    readonly property color accentCol: pal.primary ?? "#2563eb"
    readonly property color onAccentInk: pal.onPrimary ?? "#ffffff"
    readonly property color weekendCol: pal.error ?? "#e95a63"

    readonly property date activeDate: {
        const src = String(root.isoDate || root.pimData?.today || "").trim()
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(src)
        if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
        return new Date()
    }
    readonly property int year: activeDate.getFullYear()
    readonly property int month: activeDate.getMonth()
    readonly property int dayOfMonth: activeDate.getDate()
    readonly property int weekday: activeDate.getDay()
    readonly property int firstWeekday: (new Date(year, month, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property int weekCount: Math.max(4, Math.ceil((firstWeekday + daysInMonth) / 7))

    readonly property string headerText: year + "/" + (month + 1 < 10 ? "0" : "") + (month + 1)
    readonly property string weekdayLabel: {
        const zh = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        const en = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (isZh ? zh : en)[((weekday % 7) + 7) % 7]
    }
    readonly property string subtitleText: isZh
        ? (weekdayLabel + " · " + (month + 1) + "月" + dayOfMonth + "日")
        : (weekdayLabel + " · " + (month + 1) + "/" + dayOfMonth)

    readonly property var todayEvents: {
        const raw = pimData?.todayEvents
        if (!raw || typeof raw === "string" || typeof raw.length !== "number") return []
        const maxItems = root.compact ? 1 : (root.tall ? 4 : 2)
        const list = []
        for (let i = 0; i < Math.min(maxItems, raw.length); ++i)
            list.push(raw[i])
        return list
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.host || root.host.isPreview || typeof root.host.invokeAction !== "function")
                return
            root.host.invokeAction("app.open-calendar", { view: "month" })
        }
    }

    // ── 1x1 Arch Silhouette Foreground (host paints arch surface) ────────
    Item {
        visible: root.compact
        anchors.fill: parent

        Text {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: parent.height * 0.14 }
            horizontalAlignment: Text.AlignHCenter
            text: root.headerText
            color: root.accentCol
            font { pixelSize: 13; weight: Font.Bold }
        }

        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.37 }
            width: Math.max(1, parent.width - 24)
            spacing: 1

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.dayOfMonth)
                color: root.onSurface
                font { pixelSize: 38; weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.weekdayLabel
                color: root.accentCol
                font { pixelSize: 12; weight: Font.DemiBold }
            }
        }

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 12; leftMargin: 16; rightMargin: 16 }
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.todayEvents.length > 0
                ? ("• " + String(root.todayEvents[0]?.title || ""))
                : (root.isZh ? "今日无日程" : "No events")
            color: root.onSurfaceVariant
            font.pixelSize: 10
        }
    }

    // ── 2x1 / 2x2 Unified Material Card Two-Column Layout ────────────────
    Item {
        visible: !root.compact
        anchors.fill: parent
        anchors.margins: root.tall ? 16 : 13

        Item {
            id: leftCol
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.round((parent.width - 17) * 0.39)

            Text {
                id: splitMonthLabel
                anchors { left: parent.left; right: parent.right; top: parent.top }
                text: root.headerText
                color: root.accentCol
                font { pixelSize: root.tall ? 14 : 12; weight: Font.Bold }
            }

            Text {
                id: splitDayNum
                anchors { left: parent.left; top: splitMonthLabel.bottom; topMargin: root.tall ? 6 : 2 }
                text: String(root.dayOfMonth)
                color: root.onSurface
                font { pixelSize: root.tall ? 44 : 36; weight: Font.Bold }
            }

            Text {
                anchors { left: parent.left; right: parent.right; top: splitDayNum.bottom; topMargin: 1 }
                text: root.subtitleText
                color: root.onSurfaceVariant
                elide: Text.ElideRight
                font { pixelSize: root.tall ? 12 : 10; weight: Font.DemiBold }
            }

            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                spacing: root.tall ? 4 : 2

                Repeater {
                    model: root.todayEvents
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        text: "• " + String(modelData?.title || (root.isZh ? "日程" : "Event"))
                        color: root.onSurface
                        opacity: 0.86
                        elide: Text.ElideRight
                        font.pixelSize: root.tall ? 11 : 10
                    }
                }

                Text {
                    visible: root.todayEvents.length === 0
                    width: parent.width
                    text: root.isZh ? "今日无日程" : "No events today"
                    color: root.onSurfaceVariant
                    elide: Text.ElideRight
                    font.pixelSize: root.tall ? 11 : 10
                }
            }
        }

        Rectangle {
            id: colDivider
            anchors { left: leftCol.right; leftMargin: 8; top: parent.top; bottom: parent.bottom }
            width: 1
            color: Qt.rgba(root.onSurface.r, root.onSurface.g, root.onSurface.b, 0.14)
        }

        Item {
            anchors {
                left: colDivider.right; leftMargin: 8
                right: parent.right; top: parent.top; bottom: parent.bottom
            }

            Row {
                id: weekdayRow
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: root.tall ? 20 : 16
                Repeater {
                    model: root.isZh
                        ? ["一", "二", "三", "四", "五", "六", "日"]
                        : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                    delegate: Text {
                        required property var modelData
                        required property int index
                        width: parent.width / 7
                        text: modelData
                        horizontalAlignment: Text.AlignHCenter
                        color: index >= 5 ? root.weekendCol : root.onSurfaceVariant
                        font { pixelSize: root.tall ? 11 : 10; weight: Font.Bold }
                    }
                }
            }

            Grid {
                anchors {
                    left: parent.left; right: parent.right
                    top: weekdayRow.bottom; bottom: parent.bottom
                    topMargin: 4
                }
                columns: 7
                Repeater {
                    model: root.weekCount * 7
                    delegate: Item {
                        required property int index
                        width: parent.width / 7
                        height: parent.height / root.weekCount
                        readonly property int dayNum: index - root.firstWeekday + 1
                        readonly property bool validDay: dayNum > 0 && dayNum <= root.daysInMonth
                        readonly property bool isToday: validDay && dayNum === root.dayOfMonth
                        readonly property bool isWeekend: (index % 7) >= 5

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.tall ? 24 : 18
                            height: width
                            radius: width / 2
                            visible: parent.isToday
                            color: root.accentCol
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: parent.validDay
                            text: String(parent.dayNum)
                            color: parent.isToday ? root.onAccentInk
                                : (parent.isWeekend ? root.weekendCol : root.onSurface)
                            font {
                                pixelSize: root.tall ? 12 : 10
                                weight: parent.isToday ? Font.Bold : Font.DemiBold
                            }
                        }
                    }
                }
            }
        }
    }
}
