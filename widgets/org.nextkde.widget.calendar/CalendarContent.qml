import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var pimData
    property string isoDate: ""
    property var host: null

    property color headerBackground: "#ff5d66"
    property color headerInk: "#ffffff"
    property color rightPaneBackground: "#fafafa"
    property color dividerColor: Qt.rgba(0, 0, 0, 0.10)
    property color primaryInk: "#15151a"
    property color subtleInk: "#4d4d55"
    property color mutedInk: Qt.rgba(0.60, 0.60, 0.64, 0.72)
    property color weekdayInk: "#5d5d65"
    property color weekendInk: "#e95a63"
    property color dayInk: "#29292f"
    property color todayCircleColor: "#ef5661"
    property color todayInk: "#ffffff"
    property real cardCornerRadius: 24

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compact: spanCols <= 1
    readonly property bool tall: spanRows >= 2

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    readonly property date activeDate: {
        const src = String(root.isoDate || root.pimData?.today || "").trim()
        const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(src)
        if (m)
            return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
        return new Date()
    }
    readonly property int year: activeDate.getFullYear()
    readonly property int month: activeDate.getMonth()
    readonly property int dayOfMonth: activeDate.getDate()
    readonly property int weekday: activeDate.getDay()
    // Monday-first grid: Monday -> 0 ... Sunday -> 6
    readonly property int firstWeekday: (new Date(year, month, 1).getDay() + 6) % 7
    readonly property int daysInMonth: new Date(year, month + 1, 0).getDate()
    readonly property int weekCount: Math.max(4, Math.ceil((firstWeekday + daysInMonth) / 7))
    readonly property int headerHeight: compact ? 34 : 38

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
    readonly property string statusText: {
        if (todayEvents.length > 0) return ""
        const err = String(pimData?.errorMessage ?? "").trim()
        if (!Boolean(pimData?.ready) && err.length > 0) return err
        return root.isZh ? "今日无日程" : "No events today"
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

    // Pale right pane for 2x1 / 2x2 split macOS card layout
    Rectangle {
        visible: !root.compact && !root.outlineText && root.rightPaneBackground.a > 0
        anchors {
            top: parent.top; bottom: parent.bottom; right: parent.right; left: parent.left
            topMargin: root.headerHeight
            leftMargin: Math.round(parent.width * 0.42)
        }
        color: root.rightPaneBackground
    }

    // Top rounded header banner matching main DeskCenterWindow calendar header
    Canvas {
        id: calendarHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.headerHeight
        visible: !root.outlineText && root.headerBackground.a > 0
        readonly property color fillCol: root.headerBackground
        onFillColChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0 || fillCol.a <= 0) return
            const corner = Math.min(root.cardCornerRadius, height)
            ctx.fillStyle = fillCol.toString()
            ctx.beginPath()
            ctx.moveTo(0, height)
            ctx.lineTo(0, corner)
            ctx.quadraticCurveTo(0, 0, corner, 0)
            ctx.lineTo(width - corner, 0)
            ctx.quadraticCurveTo(width, 0, width, corner)
            ctx.lineTo(width, height)
            ctx.closePath()
            ctx.fill()
        }
    }

    Text {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.headerHeight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.headerText
        color: root.outlineText ? root.primaryInk : root.headerInk
        font { pixelSize: root.compact ? 14 : 15; weight: Font.Bold }
        style: root.textStyle
        styleColor: root.textStyleColor
    }

    // Glass-mode subtle header rule
    Rectangle {
        visible: root.outlineText || root.headerBackground.a <= 0
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: root.headerHeight; leftMargin: 12; rightMargin: 12 }
        height: 1
        color: root.dividerColor
    }

    // Vertical pane divider on 2x1 / 2x2
    Rectangle {
        visible: !root.compact
        anchors {
            left: parent.left; top: parent.top; bottom: parent.bottom
            leftMargin: Math.round(parent.width * 0.42)
            topMargin: root.headerHeight
            bottomMargin: 0
        }
        width: 1
        color: root.dividerColor
    }

    // ── 1x1 Compact View ─────────────────────────────────────────────────
    Item {
        visible: root.compact
        anchors {
            left: parent.left; right: parent.right
            top: parent.top; bottom: parent.bottom
            topMargin: root.headerHeight
            leftMargin: 12; rightMargin: 12; bottomMargin: 10
        }

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 2

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: String(root.dayOfMonth)
                color: root.primaryInk
                font { pixelSize: 40; weight: Font.DemiBold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.weekdayLabel
                color: root.subtleInk
                font { pixelSize: 11; weight: Font.DemiBold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.todayEvents.length > 0
                ? ("• " + String(root.todayEvents[0]?.title || (root.isZh ? "日程" : "Event")))
                : root.statusText
            color: root.todayEvents.length > 0 ? root.subtleInk : root.mutedInk
            font.pixelSize: 10
            style: root.textStyle
            styleColor: root.textStyleColor
        }
    }

    // ── 2x1 / 2x2 Split View (Left: Day + Events, Right: Month Grid) ─────
    Item {
        visible: !root.compact
        anchors {
            left: parent.left; right: parent.right
            top: parent.top; bottom: parent.bottom
            topMargin: root.headerHeight
        }

        // Left day & events pane
        Item {
            id: leftPane
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.42

            Text {
                anchors { left: parent.left; top: parent.top; leftMargin: 15; topMargin: root.tall ? 12 : 7 }
                text: String(root.dayOfMonth)
                color: root.primaryInk
                font { pixelSize: root.tall ? 40 : 32; weight: Font.DemiBold }
                style: root.textStyle
                styleColor: root.textStyleColor
            }
            Text {
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: 16; rightMargin: 8; topMargin: root.tall ? 58 : 46
                }
                text: root.subtitleText
                color: root.subtleInk
                font { pixelSize: root.tall ? 11 : 10; weight: Font.DemiBold }
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }

            Column {
                anchors {
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: 15; rightMargin: 8; bottomMargin: 10
                }
                spacing: root.tall ? 5 : 2

                Repeater {
                    model: root.todayEvents
                    delegate: Text {
                        required property var modelData
                        width: parent.width
                        readonly property string evtTime: String(modelData?.time ?? "")
                        readonly property string evtTitle: String(modelData?.title || (root.isZh ? "日程" : "Event"))
                        text: "• " + (root.tall && evtTime.length > 0 ? (evtTime + " " + evtTitle) : evtTitle)
                        color: root.subtleInk
                        elide: Text.ElideRight
                        font.pixelSize: root.tall ? 11 : 9
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                }
                Text {
                    visible: root.todayEvents.length === 0 && root.statusText.length > 0
                    width: parent.width
                    text: root.statusText
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    color: root.mutedInk
                    elide: Text.ElideRight
                    font.pixelSize: root.tall ? 10 : 9
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }
        }

        // Right Monday-first month grid
        Item {
            id: monthGrid
            anchors {
                left: leftPane.right; right: parent.right
                top: parent.top; bottom: parent.bottom
                leftMargin: 10; rightMargin: 10
                topMargin: root.tall ? 12 : 6
                bottomMargin: root.tall ? 12 : 7
            }

            Row {
                width: parent.width
                height: root.tall ? 20 : 15
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
                        color: index >= 5 ? root.weekendInk : root.weekdayInk
                        font { pixelSize: root.tall ? 11 : 10; weight: Font.Bold }
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }
                }
            }

            Grid {
                anchors {
                    left: parent.left; right: parent.right
                    top: parent.top; bottom: parent.bottom
                    topMargin: root.tall ? 22 : 15
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
                            width: root.tall ? 22 : 16
                            height: width
                            radius: width / 2
                            visible: parent.isToday
                            color: root.todayCircleColor
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: parent.validDay
                            text: String(parent.dayNum)
                            color: parent.isToday ? root.todayInk
                                : (parent.isWeekend ? root.weekendInk : root.dayInk)
                            font {
                                pixelSize: root.tall ? 12 : 10
                                weight: parent.isToday ? Font.Bold : Font.DemiBold
                            }
                            style: root.textStyle
                            styleColor: root.textStyleColor
                        }
                    }
                }
            }
        }
    }
}
