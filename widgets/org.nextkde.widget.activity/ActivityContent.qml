import QtQuick

Item {
    id: root

    required property var widgetSize
    required property var appearance
    required property var activityData

    property color headerInk: Qt.rgba(1, 1, 1, 0.88)
    property color primaryInk: Qt.rgba(1, 1, 1, 0.80)
    property color subtleInk: Qt.rgba(1, 1, 1, 0.50)
    property color heatmapBaseColor: Qt.rgba(0.33, 0.84, 0.58, 1.0)
    property color heatmapEmptyColor: Qt.rgba(1, 1, 1, 0.08)
    property color barTrackColor: Qt.rgba(1, 1, 1, 0.12)
    property color badgeFillColor: Qt.rgba(1, 1, 1, 0.18)
    property color badgeInk: "#ffffff"

    readonly property int spanCols: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[0]) : 2
    readonly property int spanRows: (widgetSize && widgetSize.length >= 2) ? Number(widgetSize[1]) : 1
    readonly property bool compact: spanCols <= 1
    readonly property bool tall: spanRows >= 2

    readonly property bool isZh: String(appearance?.locale ?? "").toLowerCase().startsWith("zh")
    readonly property bool outlineText: Boolean(appearance?.transparent)
    readonly property int textStyle: outlineText ? Text.Outline : Text.Normal
    readonly property color textStyleColor: appearance?.isDark
        ? Qt.rgba(0, 0, 0, 0.58) : Qt.rgba(1, 1, 1, 0.68)

    readonly property int todaySeconds: Number(activityData?.todayUptimeSeconds ?? 0)
    readonly property var days60: {
        const raw = activityData?.recentUptimeDays
        if (!raw || typeof raw === "string" || typeof raw.length !== "number") return []
        const list = []
        for (let i = 0; i < raw.length; ++i)
            list.push(raw[i])
        return list
    }
    readonly property var days30: days60.slice(Math.max(0, days60.length - 30))
    readonly property var topApps: {
        const raw = activityData?.todayApps
        if (!raw || typeof raw === "string" || typeof raw.length !== "number") return []
        const limit = root.tall ? 6 : 6
        const list = []
        for (let i = 0; i < Math.min(limit, raw.length); ++i)
            list.push(raw[i])
        return list
    }
    readonly property int maxAppSeconds: {
        let m = 1
        for (let i = 0; i < topApps.length; ++i)
            m = Math.max(m, Number(topApps[i]?.seconds ?? 0))
        return m
    }

    property var hoveredDay: null

    function formatDuration(sec) {
        const s = Math.max(0, Math.round(Number(sec) || 0))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (root.isZh) {
            if (h > 0) return h + "小时" + (m > 0 ? m + "分" : "")
            if (m > 0) return m + "分钟"
            return Math.max(1, s) + "秒"
        }
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return s + "s"
    }

    function iconSourceFor(raw) {
        const s = String(raw ?? "").trim()
        if (s.length === 0) return ""
        if (s.startsWith("image://") || s.startsWith("file://") || s.startsWith("qrc:/"))
            return s
        if (s.startsWith("/")) return "file://" + s
        return "image://icon/" + s
    }

    function heatColorFor(seconds) {
        const lvl = Math.max(0, Math.min(1, Number(seconds ?? 0) / (8 * 3600)))
        if (lvl <= 0) return root.heatmapEmptyColor
        const base = root.outlineText ? root.headerInk : root.heatmapBaseColor
        return Qt.rgba(base.r, base.g, base.b, 0.22 + lvl * 0.72)
    }

    component AppGlyph: Item {
        property string iconName: ""
        property string appLabel: ""
        readonly property string resolvedSrc: root.iconSourceFor(iconName)

        Image {
            id: img
            anchors.fill: parent
            source: parent.resolvedSrc
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            visible: parent.resolvedSrc.length > 0 && status === Image.Ready
        }

        Rectangle {
            anchors.fill: parent
            radius: Math.max(3, width * 0.28)
            visible: !img.visible
            color: root.badgeFillColor
            Text {
                anchors.centerIn: parent
                text: String(appLabel || "?").trim().slice(0, 1).toUpperCase()
                color: root.badgeInk
                font { pixelSize: Math.max(7, Math.round(parent.height * 0.58)); weight: Font.Bold }
            }
        }
    }

    // ── 1x1 Compact View ─────────────────────────────────────────────────
    Item {
        visible: root.compact
        anchors.fill: parent
        anchors.margins: 12

        Column {
            id: compactHeader
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 1

            Text {
                width: parent.width
                text: root.hoveredDay
                    ? String(root.hoveredDay.key ?? "")
                    : (root.isZh ? "今日在线" : "Today Uptime")
                color: root.subtleInk
                font { pixelSize: 10; weight: Font.Medium }
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }
            Text {
                width: parent.width
                text: root.hoveredDay
                    ? root.formatDuration(root.hoveredDay.seconds)
                    : root.formatDuration(root.todaySeconds)
                color: root.headerInk
                font { pixelSize: 20; weight: Font.DemiBold }
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }

        Item {
            id: compactHeatmap
            anchors {
                left: parent.left; right: parent.right
                top: compactHeader.bottom; bottom: parent.bottom
                topMargin: 8
            }

            Grid {
                anchors.centerIn: parent
                readonly property real cell: Math.max(4, Math.min(
                    (compactHeatmap.width - 5 * 3) / 6,
                    (compactHeatmap.height - 4 * 3) / 5))
                columns: 6
                spacing: 3

                Repeater {
                    model: root.days30
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.cell
                        height: width
                        radius: 2
                        color: root.heatColorFor(modelData?.seconds)

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: root.hoveredDay = modelData
                            onExited: root.hoveredDay = null
                        }
                    }
                }
            }
        }
    }

    // ── 2x1 Horizontal 50/50 Split View (matching main) ──────────────────
    Item {
        visible: !root.compact && !root.tall
        anchors.fill: parent
        anchors.margins: 14

        // Left 50%: Uptime + 60-day heatmap
        Item {
            id: splitLeftPane
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Math.max(1, (parent.width - 16) / 2)

            Item {
                id: splitHeader
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: Math.max(24, parent.height * 0.28)

                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    text: root.hoveredDay
                        ? (String(root.hoveredDay.key ?? "") + " · " + root.formatDuration(root.hoveredDay.seconds))
                        : ((root.isZh ? "在线：" : "Uptime: ") + root.formatDuration(root.todaySeconds))
                    color: root.headerInk
                    font { pixelSize: 13; weight: Font.DemiBold }
                    elide: Text.ElideRight
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }

            Item {
                anchors { left: parent.left; right: parent.right; top: splitHeader.bottom; bottom: parent.bottom }

                Grid {
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    columns: 10
                    spacing: 3

                    Repeater {
                        model: root.days60
                        delegate: Rectangle {
                            required property var modelData
                            width: Math.max(4, (splitLeftPane.width - 27) / 10)
                            height: width
                            radius: 2
                            color: root.heatColorFor(modelData?.seconds)

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                onEntered: root.hoveredDay = modelData
                                onExited: root.hoveredDay = null
                            }
                        }
                    }
                }
            }
        }

        // Right 50%: Today's top apps list
        Item {
            anchors {
                left: splitLeftPane.right; right: parent.right
                top: parent.top; bottom: parent.bottom
                leftMargin: 16
            }

            Column {
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Repeater {
                    model: root.topApps
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 17

                        AppGlyph {
                            id: appIcon
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 12; height: 12
                            iconName: String(modelData?.icon ?? "")
                            appLabel: String(modelData?.name || modelData?.id || "?")
                        }

                        Text {
                            id: appDur
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: root.formatDuration(modelData?.seconds ?? 0)
                            color: root.subtleInk
                            font.pixelSize: 9
                            style: root.textStyle
                            styleColor: root.textStyleColor
                        }

                        Text {
                            anchors {
                                left: appIcon.right; right: appDur.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 6; rightMargin: 6
                            }
                            text: String(modelData?.name || modelData?.id || "")
                            color: root.primaryInk
                            elide: Text.ElideRight
                            font.pixelSize: 10
                            style: root.textStyle
                            styleColor: root.textStyleColor
                        }
                    }
                }

                Text {
                    visible: root.topApps.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isZh ? "暂无应用使用记录" : "No app usage yet"
                    color: root.subtleInk
                    font.pixelSize: 10
                    style: root.textStyle
                    styleColor: root.textStyleColor
                }
            }
        }
    }

    // ── 2x2 Large Card View (Top Heatmap + Bottom App Breakdown Bars) ────
    Item {
        visible: root.tall
        anchors.fill: parent
        anchors.margins: 16

        Item {
            id: tallHeader
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 26

            Text {
                anchors { left: parent.left; right: tallSubtitle.left; verticalCenter: parent.verticalCenter; rightMargin: 8 }
                text: root.hoveredDay
                    ? (String(root.hoveredDay.key ?? "") + " · " + root.formatDuration(root.hoveredDay.seconds))
                    : ((root.isZh ? "今日在线：" : "Uptime: ") + root.formatDuration(root.todaySeconds))
                color: root.headerInk
                font { pixelSize: 15; weight: Font.DemiBold }
                elide: Text.ElideRight
                style: root.textStyle
                styleColor: root.textStyleColor
            }

            Text {
                id: tallSubtitle
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: root.isZh ? "近 60 天" : "60 days"
                color: root.subtleInk
                font.pixelSize: 11
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }

        Item {
            id: tallHeatmap
            anchors {
                left: parent.left; right: parent.right
                top: tallHeader.bottom; topMargin: 8
            }
            height: 5 * cellSize + 4 * 4
            readonly property real cellSize: Math.max(8, Math.min(20, (width - 11 * 4) / 12))

            Grid {
                anchors.centerIn: parent
                columns: 12
                spacing: 4

                Repeater {
                    model: root.days60
                    delegate: Rectangle {
                        required property var modelData
                        width: tallHeatmap.cellSize
                        height: width
                        radius: 4
                        color: root.heatColorFor(modelData?.seconds)

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            onEntered: root.hoveredDay = modelData
                            onExited: root.hoveredDay = null
                        }
                    }
                }
            }
        }

        Text {
            id: appsTitle
            anchors { left: parent.left; right: parent.right; top: tallHeatmap.bottom; topMargin: 12 }
            text: root.isZh ? "今日应用" : "Today's Apps"
            color: root.subtleInk
            font { pixelSize: 11; weight: Font.DemiBold }
            style: root.textStyle
            styleColor: root.textStyleColor
        }

        Column {
            anchors {
                left: parent.left; right: parent.right
                top: appsTitle.bottom; bottom: parent.bottom
                topMargin: 6
            }
            spacing: 5

            Repeater {
                model: root.topApps
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    readonly property int count: Math.max(1, root.topApps.length)
                    height: Math.min(24, Math.max(18, (parent.height - Math.max(0, count - 1) * parent.spacing) / count))
                    readonly property real ratio: Math.max(0.06, Math.min(1, Number(modelData?.seconds ?? 0) / root.maxAppSeconds))

                    AppGlyph {
                        id: tallIcon
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 15; height: 15
                        iconName: String(modelData?.icon ?? "")
                        appLabel: String(modelData?.name || modelData?.id || "?")
                    }

                    Text {
                        id: tallName
                        anchors { left: tallIcon.right; verticalCenter: parent.verticalCenter; leftMargin: 7 }
                        width: Math.min(parent.width * 0.38, 108)
                        text: String(modelData?.name || modelData?.id || "")
                        color: root.primaryInk
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }

                    Text {
                        id: tallDur
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 52
                        horizontalAlignment: Text.AlignRight
                        text: root.formatDuration(modelData?.seconds ?? 0)
                        color: root.subtleInk
                        font.pixelSize: 10
                        style: root.textStyle
                        styleColor: root.textStyleColor
                    }

                    Item {
                        anchors {
                            left: tallName.right; right: tallDur.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 8; rightMargin: 8
                        }
                        height: 6

                        Rectangle {
                            anchors.fill: parent
                            radius: 3
                            color: root.barTrackColor
                        }
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: Math.max(4, parent.width * ratio)
                            radius: 3
                            color: root.outlineText ? root.headerInk : root.heatmapBaseColor
                        }
                    }
                }
            }

            Text {
                visible: root.topApps.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.isZh ? "暂无应用使用记录" : "No app usage yet"
                color: root.subtleInk
                font.pixelSize: 11
                style: root.textStyle
                styleColor: root.textStyleColor
            }
        }
    }
}
