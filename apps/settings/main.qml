import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls

ApplicationWindow {
    id: window

    width: 1100
    height: 720
    minimumWidth: 840
    minimumHeight: 560
    visible: true
    title: "kos设置界面"
    color: theme.background

    property int currentPage: 0
    property string searchText: ""

    // Qt updates SystemPalette when the desktop colour scheme changes. We use
    // it only to select the system appearance, then apply the matching iPadOS
    // palette so both modes keep a coherent Settings visual language.
    SystemPalette {
        id: systemPalette
        colorGroup: SystemPalette.Active
    }

    QtObject {
        id: theme

        readonly property bool dark: {
            const color = systemPalette.window
            return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
        }
        readonly property color background: dark ? "#000000" : "#f2f2f7"
        readonly property color sidebar: dark ? "#1c1c1e" : "#fafbff"
        readonly property color contentSurface: dark ? "#000000" : "#fafbff"
        readonly property color primaryText: dark ? "#f5f5f7" : "#1c1c1e"
        readonly property color secondaryText: dark ? "#98989d" : "#6d6d72"
        readonly property color tertiaryText: dark ? "#8e8e93" : "#8e8e93"
        readonly property color card: dark ? "#1c1c1e" : "#ffffff"
        readonly property color separator: dark ? "#38383a" : "#e5e5ea"
        readonly property color divider: dark ? "#2c2c2e" : "#d1d1d6"
        readonly property color searchField: dark ? "#2c2c2e" : "#e3e3e8"
        readonly property color selected: dark ? "#0a84ff" : "#d9e9ff"
        readonly property color sidebarHover: dark
            ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.045)
        readonly property color chevron: dark ? "#636366" : "#c7c7cc"
        readonly property color iconForeground: "#ffffff"
        readonly property color floatingBorder: dark
            ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0, 0, 0, 0.055)
        readonly property color floatingShadow: dark
            ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0.17, 0.21, 0.30, 0.16)
        readonly property color previewPane: dark ? "#14151a" : "#eef2f7"
        readonly property color previewBar: dark ? "#2c2d35" : "#ffffff"
        readonly property color previewTaskbar: dark ? "#1e2028" : "#ffffff"
        readonly property color previewDock: dark ? "#323540" : "#ffffff"
        readonly property color previewIcon: dark ? "#a0a4b0" : "#7c8290"
    }
    readonly property var contentByPage: [
        {
            subtitle: "显示",
            groups: []
        },
        {
            subtitle: "主题",
            groups: []
        },
        {
            subtitle: "顶栏",
            groups: []
        },
        {
            subtitle: "Dock",
            groups: []
        },
        {
            subtitle: "启动台",
            groups: []
        },
        {
            subtitle: "接入状态",
            groups: []
        }
    ]

    component SettingIcon: Rectangle {
        required property string symbol
        required property color tint
        width: 29
        height: 29
        radius: 10
        color: tint
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -0.5
            text: symbol
            color: theme.iconForeground
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }

    component SidebarEntry: ItemDelegate {
        required property int pageIndex
        required property string label
        required property string navSymbol
        required property color navTint
        width: parent ? parent.width : 0
        height: 40
        leftPadding: 10
        rightPadding: 10
        highlighted: window.currentPage === pageIndex
        visible: window.searchText.length === 0
            || label.toLowerCase().indexOf(window.searchText.toLowerCase()) >= 0
        background: Rectangle {
            radius: 18
            color: parent.highlighted ? theme.selected
                : (parent.hovered ? theme.sidebarHover : "transparent")
        }
        contentItem: Item {
            implicitHeight: 40
            SettingIcon {
                id: sidebarIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                symbol: navSymbol
                tint: navTint
            }
            Text {
                anchors.left: sidebarIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: theme.primaryText
                font.pixelSize: 13
                font.weight: window.currentPage === pageIndex
                    ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }
        onClicked: window.currentPage = pageIndex
    }

    // One visual contract for every segmented choice in Settings. Individual
    // rows only provide model/currentIndex and content-driven width overrides.
    component SettingsNavBar: LiquidControls.LiquidNavBar {
        size: "tiny"
        accentColor: theme.dark ? "#64b5ff" : "#0066cc"
        itemColor: theme.dark ? "#ffffff" : "#1c1c1e"
        trackColor: theme.dark
            ? Qt.rgba(1, 1, 1, 0.10) : "#d1d1d6"
        labelFontPixelSize: 10
        labelFontWeight: Font.DemiBold
    }

    component SettingRow: Item {
        required property var row
        width: ListView.view ? ListView.view.width : parent.width
        height: 48

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 13
            spacing: 11
            SettingIcon { symbol: row.icon; tint: row.tint }
            Text {
                Layout.fillWidth: true
                text: row.title
                color: theme.primaryText
                font.pixelSize: 14
                elide: Text.ElideRight
            }
            Text {
                text: row.detail
                color: theme.tertiaryText
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.maximumWidth: 180
            }
            Text {
                text: "›"
                color: theme.chevron
                font.pixelSize: 24
                font.weight: Font.Light
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 53
            anchors.bottom: parent.bottom
            height: 1
            color: theme.separator
            visible: index < ListView.view.count - 1
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }
    }

    component IntegrationStatusPage: ColumnLayout {
        id: integrationPage

        Layout.fillWidth: true
        spacing: 8
        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property var snapshot: ({})
        property string errorText: ""

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            snapshot = bridge.integrationSnapshot()
            errorText = bridge.lastError || ""
        }

        function notificationState() {
            const provider = snapshot.notificationProvider || "none"
            if (provider === "kos")
                return { label: "KOS 已接管", color: "#30d158",
                    detail: "通知将显示在 KOS 通知中心" }
            if (provider === "plasma")
                return { label: "Plasma 接管", color: "#ff9f0a",
                    detail: "KOS 正在等待 org.freedesktop.Notifications 所有权" }
            if (provider === "other")
                return { label: "其他程序接管", color: "#ff9f0a",
                    detail: snapshot.notificationCommand || snapshot.notificationOwner || "未知通知服务" }
            return { label: "未注册", color: "#ff453a",
                detail: "当前没有可用的桌面通知服务" }
        }

        function statusRow(icon, tint, title, ready, readyLabel, detail) {
            return { icon: icon, tint: tint, title: title,
                label: ready ? readyLabel : "未连接",
                color: ready ? "#30d158" : "#ff453a", detail: detail }
        }

        readonly property var notification: notificationState()
        readonly property var rows: [
            statusRow("K", "#0a84ff", "KOS Shell", !!snapshot.shellReady,
                "运行中", "设置页与 Quickshell IPC 通道"),
            statusRow("↔", "#5ac8fa", "平台桥接", !!snapshot.platformConnected,
                "已连接", "窗口、网络、音频与系统操作"),
            statusRow("D", "#34c759", "数据服务", !!snapshot.dataConnected,
                "已连接", "系统指标、活动记录与桌面文件"),
            statusRow("▦", "#af52de", "桌面组件", !!snapshot.desktopWidgetsVisible,
                "已显示", snapshot.desktopFilesReady
                    ? "时钟、天气、资源卡片与桌面文件已就绪"
                    : "组件层已显示，桌面文件仍在同步"),
            { icon: "N", tint: "#ff9500", title: "通知接管",
                label: notification.label, color: notification.color,
                detail: notification.detail },
            statusRow("G", "#64d2ff", "Glass 特效", !!snapshot.glassLoaded,
                "已加载", "KWin 模糊与液态玻璃效果"),
            statusRow("A", "#ff375f", "Dock 窗口动画",
                !!snapshot.dockAnimationLoaded, "已加载", "KWin Dock 缩放／Genie 动画"),
            statusRow("I", "#bf5af2", "桌面输入桥接",
                !!snapshot.contextMenuInputLoaded, "已加载", "全局点击与菜单收起事件")
        ]

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13

            Text {
                Layout.fillWidth: true
                text: snapshot.updatedAt
                    ? "最后检查 " + snapshot.updatedAt : "正在读取实时状态…"
                color: theme.secondaryText
                font.pixelSize: 12
            }

            Rectangle {
                implicitWidth: 72
                implicitHeight: 30
                radius: 15
                color: refreshPointer.containsMouse
                    ? theme.sidebarHover : theme.card
                border.width: 1
                border.color: theme.floatingBorder

                Text {
                    anchors.centerIn: parent
                    text: "刷新"
                    color: theme.primaryText
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: refreshPointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: integrationPage.refresh()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: statusColumn.implicitHeight + 8
            radius: 24
            color: theme.card

            Column {
                id: statusColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4

                Repeater {
                    model: integrationPage.rows

                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: statusColumn.width
                        height: 62

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 11

                            SettingIcon {
                                symbol: modelData.icon
                                tint: modelData.tint
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: modelData.title
                                    color: theme.primaryText
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.detail
                                    color: theme.secondaryText
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                implicitWidth: statusLabel.implicitWidth + 18
                                implicitHeight: 24
                                radius: 12
                                color: theme.dark
                                    ? Qt.rgba(1, 1, 1, 0.09)
                                    : Qt.rgba(0, 0, 0, 0.055)
                                Text {
                                    id: statusLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: modelData.color
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 49
                            anchors.bottom: parent.bottom
                            height: 1
                            color: theme.separator
                            visible: index < integrationPage.rows.length - 1
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: errorText.length > 0
            text: errorText
            color: "#ff453a"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        Timer {
            interval: 5000
            repeat: true
            running: integrationPage.visible
            onTriggered: integrationPage.refresh()
        }
        Component.onCompleted: refresh()
    }

    component DockSettingsPage: ColumnLayout {
        id: dockPage

        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined") ? settingsBridge : null
        property real dockHeight: 60
        property int dockPositionIndex: 0
        readonly property var dockPositions: ["bottom", "left", "right"]
        property int iconModeIndex: 0
        readonly property var iconModes: ["color", "grayscale", "tint"]
        property int visibilityModeIndex: 0
        readonly property var visibilityModes: ["always", "smart", "persistent"]
        property int windowGroupingIndex: 0
        readonly property var windowGroupings: ["grouped", "separate"]
        property real iconOpacity: 0.5
        property string iconTintColor: "#a855f7"
        readonly property var tintPresets: [
            { label: "紫色", color: "#a855f7" },
            { label: "红色", color: "#ef4444" },
            { label: "蓝色", color: "#3b82f6" },
            { label: "橙色", color: "#f97316" }
        ]
        property real tintHuePosition: 0.75
        property real tintTonePosition: 0.5
        readonly property color pureTintHue: Qt.hsva(tintHuePosition, 1, 1, 1)
        readonly property color selectedTintColor: toneColor(tintTonePosition)
        readonly property var hueRamp: [
            Qt.hsva(0 / 6, 1, 1, 1), Qt.hsva(1 / 6, 1, 1, 1),
            Qt.hsva(2 / 6, 1, 1, 1), Qt.hsva(3 / 6, 1, 1, 1),
            Qt.hsva(4 / 6, 1, 1, 1), Qt.hsva(5 / 6, 1, 1, 1),
            Qt.hsva(6 / 6, 1, 1, 1)
        ]
        readonly property var toneRamp: [
            Qt.rgba(1, 1, 1, 1), blend(Qt.rgba(1, 1, 1, 1), pureTintHue, 1 / 3),
            blend(Qt.rgba(1, 1, 1, 1), pureTintHue, 2 / 3), pureTintHue,
            blend(pureTintHue, Qt.rgba(0, 0, 0, 1), 1 / 3),
            blend(pureTintHue, Qt.rgba(0, 0, 0, 1), 2 / 3), Qt.rgba(0, 0, 0, 1)
        ]
        property bool iconOpacityDirty: false
        property string errorText: ""
        property bool layoutDirty: false

        property bool dockBlurInherit: true
        property real dockBlurStrength: 0.42
        property real dockLiquidStrength: 1.0
        property bool dockBlurDirty: false
        property bool dockLiquidDirty: false

        function percentage(value) {
            return Math.round(value * 100) + "%"
        }

        function setDockBlurInherit(enabled) {
            if (!bridge) return
            applyAppearanceState(bridge.updateDockBlurInherit(enabled))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Timer {
            id: liveDockBlurDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (dockPage.bridge && dockPage.dockBlurDirty) {
                    dockPage.bridge.updateDockBlurStrength(dockPage.dockBlurStrength)
                }
            }
        }

        Timer {
            id: liveDockLiquidDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (dockPage.bridge && dockPage.dockLiquidDirty) {
                    dockPage.bridge.updateDockLiquidStrength(dockPage.dockLiquidStrength)
                }
            }
        }

        function previewDockBlur(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(dockBlurStrength - clamped) < 0.005)
                return
            dockBlurStrength = clamped
            dockBlurDirty = true
            liveDockBlurDebounce.restart()
        }

        function commitDockBlur() {
            liveDockBlurDebounce.stop()
            if (!dockBlurDirty || !bridge)
                return
            dockBlurDirty = false
            applyAppearanceState(bridge.updateDockBlurStrength(dockBlurStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewDockLiquid(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(dockLiquidStrength - clamped) < 0.005)
                return
            dockLiquidStrength = clamped
            dockLiquidDirty = true
            liveDockLiquidDebounce.restart()
        }

        function commitDockLiquid() {
            liveDockLiquidDebounce.stop()
            if (!dockLiquidDirty || !bridge)
                return
            dockLiquidDirty = false
            applyAppearanceState(bridge.updateDockLiquidStrength(dockLiquidStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function applyAppearanceState(state) {
            if (!state) return
            dockBlurInherit = state.dockBlurInherit !== undefined ? Boolean(state.dockBlurInherit) : true
            dockBlurStrength = Number.isFinite(Number(state.dockBlurStrength)) ? Number(state.dockBlurStrength) : 0.42
            dockLiquidStrength = Number.isFinite(Number(state.dockLiquidStrength)) ? Number(state.dockLiquidStrength) : 1.0
            dockBlurDirty = false
            dockLiquidDirty = false
        }

        function positionIndexFromString(position) {
            const idx = dockPositions.indexOf(position)
            return idx >= 0 ? idx : 0
        }

        function iconModeIndexFromString(mode) {
            if (mode === "duotone")
                mode = "tint"
            const idx = iconModes.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function visibilityModeIndexFromString(mode) {
            const idx = visibilityModes.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function windowGroupingIndexFromString(mode) {
            const idx = windowGroupings.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function colorHex(color) {
            function channel(value) {
                return Math.round(value * 255).toString(16).padStart(2, "0")
            }
            return "#" + channel(color.r) + channel(color.g) + channel(color.b)
        }

        function colorFromHex(value) {
            const hex = String(value).replace("#", "")
            if (hex.length !== 6)
                return Qt.rgba(0.66, 0.33, 0.97, 1)
            return Qt.rgba(
                parseInt(hex.slice(0, 2), 16) / 255,
                parseInt(hex.slice(2, 4), 16) / 255,
                parseInt(hex.slice(4, 6), 16) / 255,
                1)
        }

        function blend(first, second, amount) {
            return Qt.rgba(
                first.r + (second.r - first.r) * amount,
                first.g + (second.g - first.g) * amount,
                first.b + (second.b - first.b) * amount,
                1)
        }

        function toneColor(position) {
            if (position <= 0.5)
                return blend(Qt.rgba(1, 1, 1, 1), pureTintHue, position * 2)
            return blend(pureTintHue, Qt.rgba(0, 0, 0, 1), (position - 0.5) * 2)
        }

        function hueForColor(color) {
            const maximum = Math.max(color.r, color.g, color.b)
            const minimum = Math.min(color.r, color.g, color.b)
            const delta = maximum - minimum
            if (delta < 0.0001)
                return tintHuePosition
            let hue = 0
            if (maximum === color.r)
                hue = ((color.g - color.b) / delta) % 6
            else if (maximum === color.g)
                hue = (color.b - color.r) / delta + 2
            else
                hue = (color.r - color.g) / delta + 4
            return ((hue / 6) + 1) % 1
        }

        function nearestToneForColor(color) {
            let closestPosition = 0.5
            let closestDistance = Number.MAX_VALUE
            for (let step = 0; step <= 200; step++) {
                const position = step / 200
                const candidate = toneColor(position)
                const distance = Math.pow(candidate.r - color.r, 2)
                    + Math.pow(candidate.g - color.g, 2)
                    + Math.pow(candidate.b - color.b, 2)
                if (distance < closestDistance) {
                    closestDistance = distance
                    closestPosition = position
                }
            }
            return closestPosition
        }

        function syncTintControls(color) {
            tintHuePosition = hueForColor(color)
            tintTonePosition = nearestToneForColor(color)
        }

        function presetMatches(preset) {
            return preset.color === iconTintColor
        }

        function tintPresetIndex() {
            for (let index = 0; index < tintPresets.length; index++) {
                if (presetMatches(tintPresets[index]))
                    return index
            }
            return 0
        }

        function applyState(state) {
            if (!state || state.baseHeight === undefined)
                return
            dockHeight = Number(state.baseHeight)
            dockPositionIndex = positionIndexFromString(state.position)
            iconModeIndex = iconModeIndexFromString(state.iconMode)
            iconOpacity = Number(state.iconOpacity)
            iconTintColor = String(state.iconTintColor || "#a855f7").toLowerCase()
            syncTintControls(colorFromHex(iconTintColor))
            visibilityModeIndex = visibilityModeIndexFromString(state.visibilityMode)
            windowGroupingIndex = windowGroupingIndexFromString(state.windowGrouping)
            iconOpacityDirty = false
            layoutDirty = false
            errorText = ""
        }

        function savePosition(index) {
            if (!bridge)
                return
            const position = dockPositions[index]
            applyState(bridge.updateDockPosition(position))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveIconMode(index) {
            if (!bridge)
                return
            const mode = iconModes[index]
            applyState(bridge.updateDockIconMode(mode))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveTintColor(color) {
            if (!bridge)
                return
            applyState(bridge.updateDockIconTintColor(color))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveVisibilityMode(index) {
            if (!bridge)
                return
            const mode = visibilityModes[index]
            applyState(bridge.updateDockVisibilityMode(mode))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveWindowGrouping(index) {
            if (!bridge)
                return
            const mode = windowGroupings[index]
            applyState(bridge.updateDockWindowGrouping(mode))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function applyTintPreset(index) {
            saveTintColor(tintPresets[index].color)
        }

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.dockSnapshot())
            applyAppearanceState(bridge.appearanceSnapshot())
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveLayout() {
            if (!bridge)
                return
            applyState(bridge.updateDockLayout(dockHeight))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewDockHeight(position) {
            const nextHeight = Math.round(40 + position * 60)
            if (nextHeight === dockHeight)
                return
            dockHeight = nextHeight
            layoutDirty = true
        }

        function commitLayout() {
            if (!layoutDirty)
                return
            layoutDirty = false
            saveLayout()
        }

        function previewIconOpacity(position) {
            const nextOpacity = Math.max(0.1, Math.round(position * 100) / 100)
            if (Math.abs(iconOpacity - nextOpacity) < 0.001)
                return
            iconOpacity = nextOpacity
            iconOpacityDirty = true
        }

        function commitIconOpacity() {
            if (!iconOpacityDirty || !bridge)
                return
            iconOpacityDirty = false
            applyState(bridge.updateDockIconOpacity(iconOpacity))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Component.onCompleted: refresh()

        Text {
            text: "大小和位置".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: 97

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "▰"; tint: "#0a84ff" }
                        Text {
                            text: "Dock 高度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(dockPage.dockHeight) + " pt"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: (dockPage.dockHeight - 40) / 60
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                dockPage.previewDockHeight(position)
                            }
                            onCommitRequested: dockPage.commitLayout()
                        }
                    }
                }
            }
        }

        Text {
            text: "窗口".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: 54

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                SettingIcon { symbol: "▦"; tint: "#5856d6" }
                Text {
                    text: "是否按应用合并窗口"
                    color: theme.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                LiquidControls.LiquidGlassSwitch {
                    id: windowGroupingSwitch
                    checked: dockPage.windowGroupingIndex === 0
                    accentColor: "#0a84ff"
                    trackColor: theme.divider
                    onToggled: function(checked) {
                        const requestedIndex = checked ? 0 : 1
                        if (requestedIndex !== dockPage.windowGroupingIndex) {
                            dockPage.saveWindowGrouping(requestedIndex)
                        }
                        // The shared switch owns its checked state after a
                        // click. Put it back to the IPC-confirmed value.
                        windowGroupingSwitch.checked = dockPage.windowGroupingIndex === 0
                    }
                }
            }
        }

        Text {
            text: "DOCK 程序栏".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: 111

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "▣"; tint: "#0a84ff" }
                        Text {
                            text: "Dock 位置"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: positionNavBar
                            model: [
                                { id: "bottom", icon: "↓" },
                                { id: "left",   icon: "←" },
                                { id: "right",  icon: "→" }
                            ]
                            currentIndex: dockPage.dockPositionIndex
                            onSelectionChanged: function(index) {
                                dockPage.savePosition(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◉"; tint: "#0a84ff" }
                        Text {
                            text: "Dock 显示方式"
                            color: theme.primaryText
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: visibilityNavBar
                            model: [
                                { id: "always", label: "始终显示" },
                                { id: "smart", label: "智能隐藏" },
                                { id: "persistent", label: "持续隐藏" }
                            ]
                            itemWidthOverride: 76
                            currentIndex: dockPage.visibilityModeIndex
                            onSelectionChanged: function(index) {
                                dockPage.saveVisibilityMode(index)
                            }
                        }
                    }
                }
            }
        }

        Text {
            text: "图标风格".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: iconOpacityColumn.implicitHeight

            Column {
                id: iconOpacityColumn
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◐"; tint: "#af52de" }
                        Text {
                            text: "Dock 颜色"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: iconModeNavBar
                            model: [
                                { id: "color", label: "彩色" },
                                { id: "grayscale", label: "黑白" },
                                { id: "tint", label: "染色" }
                            ]
                            currentIndex: dockPage.iconModeIndex

                            Connections {
                                target: iconModeNavBar
                                function onSelectionChanged(index) {
                                    dockPage.saveIconMode(index)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                    visible: dockPage.iconModeIndex > 0
                }

                Item {
                    id: iconOpacityRow
                    width: parent.width
                    height: dockPage.iconModeIndex > 0 ? 48 : 0
                    visible: dockPage.iconModeIndex > 0
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◔"; tint: "#5ac8fa" }
                        Text {
                            text: "不透明度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(dockPage.iconOpacity * 100) + "%"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: dockPage.iconOpacity
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                dockPage.previewIconOpacity(position)
                            }
                            onCommitRequested: dockPage.commitIconOpacity()
                        }
                    }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                    visible: dockPage.iconModeIndex === 2
                }

                Item {
                    width: parent.width
                    height: dockPage.iconModeIndex === 2 ? 58 : 0
                    visible: dockPage.iconModeIndex === 2
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8
                        SettingIcon { symbol: "▦"; tint: "#ff9f0a" }
                        Text {
                            text: "快速方案"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: tintPresetNavBar
                            model: [
                                { id: "purple", label: "紫色" },
                                { id: "red", label: "红色" },
                                { id: "blue", label: "蓝色" },
                                { id: "orange", label: "橙色" }
                            ]
                            currentIndex: dockPage.tintPresetIndex()
                            onSelectionChanged: function(index) {
                                dockPage.applyTintPreset(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                    visible: dockPage.iconModeIndex === 2
                }

                Item {
                    width: parent.width
                    height: dockPage.iconModeIndex === 2 ? 48 : 0
                    visible: dockPage.iconModeIndex === 2
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 9
                        SettingIcon { symbol: "●"; tint: dockPage.iconTintColor }
                        Text {
                            text: "自定义颜色"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: tintPreview
                            width: 28
                            height: 28
                            radius: 9
                            color: dockPage.iconTintColor
                            border.width: 1
                            border.color: theme.dark ? "#55ffffff" : "#22000000"
                        }
                        Text {
                            text: "›"
                            color: theme.chevron
                            font.pixelSize: 24
                            font.weight: Font.Light
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                    visible: dockPage.iconModeIndex === 2
                }

                Item {
                    width: parent.width
                    height: dockPage.iconModeIndex === 2 ? 48 : 0
                    visible: dockPage.iconModeIndex === 2
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        Item { Layout.fillWidth: true }
                        LiquidControls.ColorRampSlider {
                            Layout.preferredWidth: 190
                            value: dockPage.tintHuePosition
                            rampColors: dockPage.hueRamp
                            thumbColor: dockPage.pureTintHue
                            onPreviewChanged: function(position) {
                                dockPage.tintHuePosition = position
                            }
                            onCommitRequested: dockPage.saveTintColor(
                                dockPage.colorHex(dockPage.selectedTintColor))
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                    visible: dockPage.iconModeIndex === 2
                }

                Item {
                    width: parent.width
                    height: dockPage.iconModeIndex === 2 ? 48 : 0
                    visible: dockPage.iconModeIndex === 2
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        Item { Layout.fillWidth: true }
                        LiquidControls.ColorRampSlider {
                            Layout.preferredWidth: 190
                            value: dockPage.tintTonePosition
                            rampColors: dockPage.toneRamp
                            thumbColor: dockPage.selectedTintColor
                            onPreviewChanged: function(position) {
                                dockPage.tintTonePosition = position
                            }
                            onCommitRequested: dockPage.saveTintColor(
                                dockPage.colorHex(dockPage.selectedTintColor))
                        }
                    }
                }

            }
        }

        Text {
            text: "外观与模糊效果".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
            visible: false
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: dockBlurCol.implicitHeight
            visible: false
            radius: 18
            color: theme.card

            Column {
                id: dockBlurCol
                anchors.left: parent.left
                anchors.right: parent.right

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "⎘"; tint: "#30d158" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "跟随显示设置"
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "关闭后可为 Dock 单独自定义背景模糊与液态强度"
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        LiquidControls.LiquidGlassSwitch {
                            checked: dockPage.dockBlurInherit
                            accentColor: "#30d158"
                            trackColor: theme.divider
                            onToggled: function(checked) {
                                dockPage.setDockBlurInherit(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !dockPage.dockBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !dockPage.dockBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◌"; tint: "#5ac8fa" }
                        Text {
                            text: "Dock 模糊强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: dockPage.percentage(dockPage.dockBlurStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: dockPage.dockBlurStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                dockPage.previewDockBlur(position)
                            }
                            onCommitRequested: dockPage.commitDockBlur()
                        }
                    }
                }

                Rectangle {
                    visible: !dockPage.dockBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !dockPage.dockBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "≈"; tint: "#af52de" }
                        Text {
                            text: "Dock 液态强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: dockPage.percentage(dockPage.dockLiquidStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: dockPage.dockLiquidStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                dockPage.previewDockLiquid(position)
                            }
                            onCommitRequested: dockPage.commitDockLiquid()
                        }
                    }
                }
            }
        }
    }

    component DisplaySettingsPage: ColumnLayout {
        id: displayPage

        Layout.fillWidth: true
        spacing: 7

        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property real blurStrength: 0.42
        property real liquidStrength: 1.0
        property bool blurDirty: false
        property bool liquidDirty: false
        property string errorText: ""

        function percentage(value) {
            return Math.round(value * 100) + "%"
        }

        function applyState(state) {
            if (!state)
                return
            const rawBlur = state.globalBlurStrength !== undefined
                ? state.globalBlurStrength : state.blurStrength
            const rawLiquid = state.globalLiquidStrength !== undefined
                ? state.globalLiquidStrength : state.liquidStrength
            if (rawBlur === undefined || rawLiquid === undefined)
                return
            blurStrength = Math.max(0, Math.min(1, Number(rawBlur)))
            liquidStrength = Math.max(0, Math.min(1, Number(rawLiquid)))
            blurDirty = false
            liquidDirty = false
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.appearanceSnapshot())
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Timer {
            id: liveBlurDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (displayPage.bridge && displayPage.blurDirty) {
                    displayPage.bridge.updateGlobalBlurStrength(displayPage.blurStrength)
                }
            }
        }

        Timer {
            id: liveLiquidDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (displayPage.bridge && displayPage.liquidDirty) {
                    displayPage.bridge.updateGlobalLiquidStrength(displayPage.liquidStrength)
                }
            }
        }

        function previewBlur(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(blurStrength - clamped) < 0.005)
                return
            blurStrength = clamped
            blurDirty = true
            liveBlurDebounce.restart()
        }

        function commitBlur() {
            liveBlurDebounce.stop()
            if (!blurDirty || !bridge)
                return
            blurDirty = false
            applyState(bridge.updateGlobalBlurStrength(blurStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewLiquid(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(liquidStrength - clamped) < 0.005)
                return
            liquidStrength = clamped
            liquidDirty = true
            liveLiquidDebounce.restart()
        }

        function commitLiquid() {
            liveLiquidDebounce.stop()
            if (!liquidDirty || !bridge)
                return
            liquidDirty = false
            applyState(bridge.updateGlobalLiquidStrength(liquidStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function setSystemAppearance(index) {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            if (!bridge.applySystemAppearance(index === 1)) {
                errorText = bridge.lastError
                return
            }
            errorText = ""
        }

        Component.onCompleted: refresh()

        Text {
            text: "系统外观".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            radius: 18
            color: theme.card

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                SettingIcon { symbol: "◐"; tint: "#5ac8fa" }
                Text {
                    text: "色彩模式"
                    color: theme.primaryText
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                SettingsNavBar {
                    id: systemAppearanceNavBar
                    model: [
                        { id: "light", label: "明亮" },
                        { id: "dark", label: "暗色" }
                    ]
                    currentIndex: theme.dark ? 1 : 0
                    onSelectionChanged: function(index) {
                        displayPage.setSystemAppearance(index)
                    }
                }
            }
        }

        Text {
            text: "液态玻璃".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 97
            radius: 18
            color: theme.card

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 48

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        SettingIcon { symbol: "◌"; tint: "#5ac8fa" }
                        Text {
                            text: "模糊强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: displayPage.percentage(displayPage.blurStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: displayPage.blurStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                displayPage.previewBlur(position)
                            }
                            onCommitRequested: displayPage.commitBlur()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 48

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        SettingIcon { symbol: "≈"; tint: "#af52de" }
                        Text {
                            text: "液态强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: displayPage.percentage(displayPage.liquidStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: displayPage.liquidStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                displayPage.previewLiquid(position)
                            }
                            onCommitRequested: displayPage.commitLiquid()
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: displayPage.errorText.length > 0
            text: displayPage.errorText
            color: "#ff453a"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    component ThemeSettingsPage: ColumnLayout {
        id: themePage

        Layout.fillWidth: true
        spacing: 10

        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property string shellStyle: "macos"
        property string dockWindowAnimationStyle: "scale"
        property string errorText: ""
        readonly property var styles: [
            {
                id: "windows12",
                name: "Windows 12",
                description: "居中任务栏、轻亚克力表面与紧凑圆角组件",
                accent: "#3b82f6"
            },
            {
                id: "macos",
                name: "macOS",
                description: "悬浮 Dock、通透顶部栏与更柔和的大圆角组件",
                accent: "#0a84ff"
            },
            {
                id: "material",
                name: "Material Design",
                description: "Tonal 表面、状态指示和标准化层级与动效",
                accent: "#6750a4"
            }
        ]

        function isValidStyle(style) {
            return style === "windows12" || style === "macos"
                || style === "material"
        }

        function isValidDockWindowAnimationStyle(style) {
            return style === "scale" || style === "genie"
        }

        function applyState(state) {
            if (!state || !isValidStyle(state.shellStyle))
                return
            shellStyle = state.shellStyle
            if (isValidDockWindowAnimationStyle(state.dockWindowAnimationStyle))
                dockWindowAnimationStyle = state.dockWindowAnimationStyle
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.appearanceSnapshot())
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function selectStyle(style) {
            if (!bridge || !isValidStyle(style)) {
                errorText = bridge ? "未知的主题形态" : "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.updateShellStyle(style))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function setDockWindowAnimationStyle(style) {
            if (!bridge || !isValidDockWindowAnimationStyle(style)) {
                errorText = bridge ? "未知的窗口动画" : "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.updateDockWindowAnimationStyle(style))
            if (bridge.lastError)
                errorText = bridge.lastError
        }
        Component.onCompleted: refresh()

        Text {
            text: "界面形态".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Repeater {
            model: themePage.styles

            delegate: Rectangle {
                id: styleCard
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 148
                radius: 22
                color: theme.card
                border.width: themePage.shellStyle === modelData.id ? 2 : 1
                border.color: themePage.shellStyle === modelData.id
                    ? modelData.accent : theme.floatingBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 156
                        Layout.fillHeight: true
                        radius: 14
                        color: theme.previewPane
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 14
                            color: theme.previewBar
                            visible: styleCard.modelData.id !== "windows12"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 4
                                radius: 2
                                color: styleCard.modelData.accent
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: styleCard.modelData.id === "macos" ? 8 : 0
                            width: styleCard.modelData.id === "windows12"
                                ? parent.width : (styleCard.modelData.id === "macos" ? 112 : 92)
                            height: styleCard.modelData.id === "windows12" ? 18 : 16
                            radius: styleCard.modelData.id === "windows12"
                                ? 0 : (styleCard.modelData.id === "macos" ? 8 : 4)
                            color: styleCard.modelData.id === "windows12"
                                ? theme.previewTaskbar : theme.previewDock

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                Repeater {
                                    model: 4
                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: styleCard.modelData.id === "macos" ? 4 : 2
                                        color: index === 0
                                            ? styleCard.modelData.accent : theme.previewIcon
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: styleCard.modelData.name
                                color: theme.primaryText
                                font.pixelSize: 17
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                visible: themePage.shellStyle === styleCard.modelData.id
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 20
                                radius: 10
                                color: Qt.rgba(0.04, 0.52, 1, 0.16)

                                Text {
                                    anchors.centerIn: parent
                                    text: "当前"
                                    color: styleCard.modelData.accent
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: styleCard.modelData.description
                            color: theme.secondaryText
                            font.pixelSize: 13
                            wrapMode: Text.Wrap
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            text: themePage.shellStyle === styleCard.modelData.id
                                ? "已应用到桌面" : "点击切换此形态"
                            color: themePage.shellStyle === styleCard.modelData.id
                                ? styleCard.modelData.accent : theme.tertiaryText
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: themePage.selectStyle(styleCard.modelData.id)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            text: "选择界面形态会立即切换桌面组件的圆角、间距与表面质感规范。"
            color: theme.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        Text {
            text: "窗口动画"
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 4
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 82
            radius: 18
            color: theme.card

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                SettingIcon { symbol: "◒"; tint: "#af52de" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "窗口显示/隐藏"
                        color: theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: themePage.dockWindowAnimationStyle === "genie"
                            ? "水滴形变缩入图标；打开窗口仍使用常规展开"
                            : "等比例缩放到图标；最小化与恢复均保持平直路径"
                        color: theme.secondaryText
                        font.pixelSize: 11
                    }
                }
                SettingsNavBar {
                    Layout.preferredWidth: 148
                    Layout.preferredHeight: 30
                    // LiquidNavBar delegates expect { id, label, icon }.
                    // A string model leaves modelData.label undefined, so the
                    // previous control had no visible text despite rendering
                    // its track and thumb.
                    size: "tiny"
                    barHeight: 30
                    itemWidthOverride: 74
                    model: [
                        { id: "scale", label: "缩放" },
                        { id: "genie", label: "水滴" }
                    ]
                    currentIndex: themePage.dockWindowAnimationStyle === "genie" ? 1 : 0
                    onSelectionChanged: function(index) {
                        themePage.setDockWindowAnimationStyle(
                            index === 1 ? "genie" : "scale")
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            text: "窗口动画会立即同步到 KWin；顶栏与 Dock 的布局在各自设置页中管理。"
            color: theme.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: themePage.errorText.length > 0
            text: themePage.errorText
            color: "#ff453a"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    component BarSettingsPage: ColumnLayout {
        id: barPage

        Layout.fillWidth: true
        spacing: 10

        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property bool barIntegratedWithDock: false
        property int barVisibilityModeIndex: 0
        readonly property var barVisibilityModes: ["always", "smart", "persistent"]
        property int barLayoutModeIndex: 0
        readonly property var barLayoutModes: ["full", "floating"]
        property bool barBlurInherit: true
        property real barBlurStrength: 0.42
        property real barLiquidStrength: 1.0
        property bool barBlurDirty: false
        property bool barLiquidDirty: false
        property string errorText: ""

        function percentage(value) {
            return Math.round(value * 100) + "%"
        }

        function barVisibilityModeIndexFromString(mode) {
            const idx = barVisibilityModes.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function barLayoutModeIndexFromString(mode) {
            const idx = barLayoutModes.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function applyState(state) {
            if (!state) return
            barIntegratedWithDock = Boolean(state.barIntegratedWithDock)
            barVisibilityModeIndex = barVisibilityModeIndexFromString(state.barVisibilityMode)
            barLayoutModeIndex = barLayoutModeIndexFromString(state.barLayoutMode)
            barBlurInherit = state.barBlurInherit !== undefined
                ? Boolean(state.barBlurInherit)
                : (state.barBlurInheritDock !== undefined ? Boolean(state.barBlurInheritDock) : true)
            barBlurStrength = Number.isFinite(Number(state.barBlurStrength)) ? Number(state.barBlurStrength) : 0.42
            barLiquidStrength = Number.isFinite(Number(state.barLiquidStrength)) ? Number(state.barLiquidStrength) : 1.0
            barBlurDirty = false
            barLiquidDirty = false
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.appearanceSnapshot())
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function setBarIntegratedWithDock(enabled) {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.updateBarIntegratedWithDock(enabled))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveBarVisibilityMode(index) {
            if (!bridge)
                return
            const mode = barVisibilityModes[index]
            applyState(bridge.updateBarVisibilityMode(mode))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveBarLayoutMode(index) {
            if (!bridge)
                return
            const mode = barLayoutModes[index]
            applyState(bridge.updateBarLayoutMode(mode))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function setBarBlurInherit(enabled) {
            if (!bridge) return
            applyState(bridge.updateBarBlurInherit(enabled))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Timer {
            id: liveBarBlurDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (barPage.bridge && barPage.barBlurDirty) {
                    barPage.bridge.updateBarBlurStrength(barPage.barBlurStrength)
                }
            }
        }

        Timer {
            id: liveBarLiquidDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (barPage.bridge && barPage.barLiquidDirty) {
                    barPage.bridge.updateBarLiquidStrength(barPage.barLiquidStrength)
                }
            }
        }

        function previewBarBlur(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(barBlurStrength - clamped) < 0.005)
                return
            barBlurStrength = clamped
            barBlurDirty = true
            liveBarBlurDebounce.restart()
        }

        function commitBarBlur() {
            liveBarBlurDebounce.stop()
            if (!barBlurDirty || !bridge)
                return
            barBlurDirty = false
            applyState(bridge.updateBarBlurStrength(barBlurStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewBarLiquid(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(barLiquidStrength - clamped) < 0.005)
                return
            barLiquidStrength = clamped
            barLiquidDirty = true
            liveBarLiquidDebounce.restart()
        }

        function commitBarLiquid() {
            liveBarLiquidDebounce.stop()
            if (!barLiquidDirty || !bridge)
                return
            barLiquidDirty = false
            applyState(bridge.updateBarLiquidStrength(barLiquidStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Component.onCompleted: refresh()

        Text {
            text: "显示与布局".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: barLayoutCol.implicitHeight
            radius: 18
            color: theme.card

            Column {
                id: barLayoutCol
                anchors.left: parent.left
                anchors.right: parent.right

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "⎍"; tint: "#5ac8fa" }
                        Text {
                            text: "顶栏形态"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: barLayoutNavBar
                            model: [
                                { id: "full", label: "全宽贴边" },
                                { id: "floating", label: "悬浮胶囊" }
                            ]
                            itemWidthOverride: 76
                            currentIndex: barPage.barLayoutModeIndex
                            onSelectionChanged: function(index) {
                                barPage.saveBarLayoutMode(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◉"; tint: "#0a84ff" }
                        Text {
                            text: "Bar 显示方式"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: barVisibilityNavBar
                            model: [
                                { id: "always", label: "始终显示" },
                                { id: "smart", label: "智能隐藏" },
                                { id: "persistent", label: "持续隐藏" }
                            ]
                            itemWidthOverride: 76
                            currentIndex: barPage.barVisibilityModeIndex
                            onSelectionChanged: function(index) {
                                barPage.saveBarVisibilityMode(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 64
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "⇲"; tint: "#ff9f0a" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "Bar 融入 Dock"
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "仅在 Dock 位于底部时生效；侧边 Dock 自动保留顶部 Bar"
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        LiquidControls.LiquidGlassSwitch {
                            checked: barPage.barIntegratedWithDock
                            accentColor: "#0a84ff"
                            trackColor: theme.divider
                            onToggled: function(checked) {
                                barPage.setBarIntegratedWithDock(checked)
                            }
                        }
                    }
                }
            }
        }

        Text {
            text: "外观与模糊效果".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 4
            visible: false
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: barBlurCol.implicitHeight
            visible: false
            radius: 18
            color: theme.card

            Column {
                id: barBlurCol
                anchors.left: parent.left
                anchors.right: parent.right

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "⎘"; tint: "#30d158" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "跟随显示设置"
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "关闭后可为顶栏及控制中心单独自定义背景模糊与液态强度"
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        LiquidControls.LiquidGlassSwitch {
                            checked: barPage.barBlurInherit
                            accentColor: "#30d158"
                            trackColor: theme.divider
                            onToggled: function(checked) {
                                barPage.setBarBlurInherit(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !barPage.barBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !barPage.barBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◌"; tint: "#5ac8fa" }
                        Text {
                            text: "顶栏模糊强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: barPage.percentage(barPage.barBlurStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: barPage.barBlurStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                barPage.previewBarBlur(position)
                            }
                            onCommitRequested: barPage.commitBarBlur()
                        }
                    }
                }

                Rectangle {
                    visible: !barPage.barBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !barPage.barBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "≈"; tint: "#af52de" }
                        Text {
                            text: "顶栏液态强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: barPage.percentage(barPage.barLiquidStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: barPage.barLiquidStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                barPage.previewBarLiquid(position)
                            }
                            onCommitRequested: barPage.commitBarLiquid()
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            text: "Bar 保持通透液态外观，可在上方选择跟随 Dock 模糊基准或在此独立定制。"
            visible: false
            color: theme.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: barPage.errorText.length > 0
            text: barPage.errorText
            color: "#ff453a"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    component LauncherSettingsPage: ColumnLayout {
        id: launcherPage

        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined") ? settingsBridge : null
        property string displayMode: "bottom"
        readonly property var displayModes: ["bottom", "center", "fullscreen"]
        property int displayModeIndex: 0
        property real iconSize: 52
        property real iconSpacing: 24
        property real fontSize: 11
        property string fontWeight: "normal"
        readonly property var fontWeights: ["normal", "medium", "bold"]
        property int fontWeightIndex: 0
        property string errorText: ""

        property bool launcherBlurInherit: true
        property real launcherBlurStrength: 0.42
        property real launcherLiquidStrength: 1.0
        property bool launcherBlurDirty: false
        property bool launcherLiquidDirty: false

        function percentage(value) {
            return Math.round(value * 100) + "%"
        }

        function applyAppearanceSnapshot(snapshot) {
            if (!snapshot) return
            launcherBlurInherit = snapshot.launcherBlurInherit !== undefined
                ? Boolean(snapshot.launcherBlurInherit)
                : (snapshot.launcherBlurInheritDock !== undefined ? Boolean(snapshot.launcherBlurInheritDock) : true)
            launcherBlurStrength = Number.isFinite(Number(snapshot.launcherBlurStrength))
                ? Number(snapshot.launcherBlurStrength) : 0.42
            launcherLiquidStrength = Number.isFinite(Number(snapshot.launcherLiquidStrength))
                ? Number(snapshot.launcherLiquidStrength) : 1.0
            launcherBlurDirty = false
            launcherLiquidDirty = false
        }

        function applySnapshot(snapshot) {
            if (!snapshot) return
            if (snapshot.displayMode !== undefined) {
                displayMode = snapshot.displayMode
                const idx = displayModes.indexOf(displayMode)
                displayModeIndex = idx >= 0 ? idx : 0
            }
            if (snapshot.iconSize !== undefined) {
                iconSize = snapshot.iconSize
            }
            if (snapshot.iconSpacing !== undefined) {
                iconSpacing = snapshot.iconSpacing
            }
            if (snapshot.fontSize !== undefined) {
                fontSize = snapshot.fontSize
            }
            if (snapshot.fontWeight !== undefined) {
                fontWeight = snapshot.fontWeight
                const idx = fontWeights.indexOf(fontWeight)
                fontWeightIndex = idx >= 0 ? idx : 0
            }
        }

        function reloadFromBridge() {
            if (!bridge) return
            const snap = bridge.launcherSnapshot()
            applySnapshot(snap)
            const appSnap = bridge.appearanceSnapshot()
            applyAppearanceSnapshot(appSnap)
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function setLauncherBlurInherit(enabled) {
            if (!bridge) return
            const snap = bridge.updateLauncherBlurInherit(enabled)
            applyAppearanceSnapshot(snap)
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        Timer {
            id: liveLauncherBlurDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (launcherPage.bridge && launcherPage.launcherBlurDirty) {
                    launcherPage.bridge.updateLauncherBlurStrength(launcherPage.launcherBlurStrength)
                }
            }
        }

        Timer {
            id: liveLauncherLiquidDebounce
            interval: 60
            repeat: false
            onTriggered: {
                if (launcherPage.bridge && launcherPage.launcherLiquidDirty) {
                    launcherPage.bridge.updateLauncherLiquidStrength(launcherPage.launcherLiquidStrength)
                }
            }
        }

        function previewLauncherBlur(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(launcherBlurStrength - clamped) < 0.005)
                return
            launcherBlurStrength = clamped
            launcherBlurDirty = true
            liveLauncherBlurDebounce.restart()
        }

        function commitLauncherBlur() {
            liveLauncherBlurDebounce.stop()
            if (!launcherBlurDirty || !bridge)
                return
            launcherBlurDirty = false
            const snap = bridge.updateLauncherBlurStrength(launcherBlurStrength)
            applyAppearanceSnapshot(snap)
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewLauncherLiquid(value) {
            const clamped = Math.max(0, Math.min(1, value))
            if (Math.abs(launcherLiquidStrength - clamped) < 0.005)
                return
            launcherLiquidStrength = clamped
            launcherLiquidDirty = true
            liveLauncherLiquidDebounce.restart()
        }

        function commitLauncherLiquid() {
            liveLauncherLiquidDebounce.stop()
            if (!launcherLiquidDirty || !bridge)
                return
            launcherLiquidDirty = false
            const snap = bridge.updateLauncherLiquidStrength(launcherLiquidStrength)
            applyAppearanceSnapshot(snap)
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function saveDisplayMode(index) {
            displayModeIndex = index
            displayMode = displayModes[index] || "bottom"
            if (bridge) {
                const snap = bridge.updateLauncherDisplayMode(displayMode)
                applySnapshot(snap)
                if (bridge.lastError)
                    errorText = bridge.lastError
            }
        }

        function saveFontWeight(index) {
            fontWeightIndex = index
            fontWeight = fontWeights[index] || "normal"
            if (bridge) {
                const snap = bridge.updateLauncherFontWeight(fontWeight)
                applySnapshot(snap)
                if (bridge.lastError)
                    errorText = bridge.lastError
            }
        }

        function previewIconSize(position) {
            iconSize = Math.round(40 + position * 40)
        }

        function commitIconSize() {
            if (bridge) {
                const snap = bridge.updateLauncherIconSize(iconSize)
                applySnapshot(snap)
                if (bridge.lastError)
                    errorText = bridge.lastError
            }
        }

        function previewIconSpacing(position) {
            iconSpacing = Math.round(10 + position * 38)
        }

        function commitIconSpacing() {
            if (bridge) {
                const snap = bridge.updateLauncherIconSpacing(iconSpacing)
                applySnapshot(snap)
                if (bridge.lastError)
                    errorText = bridge.lastError
            }
        }

        function previewFontSize(position) {
            fontSize = Math.round(9 + position * 9)
        }

        function commitFontSize() {
            if (bridge) {
                const snap = bridge.updateLauncherFontSize(fontSize)
                applySnapshot(snap)
                if (bridge.lastError)
                    errorText = bridge.lastError
            }
        }

        Component.onCompleted: reloadFromBridge()

        Text {
            text: "显示形态".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: 54

            Item {
                anchors.fill: parent
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    SettingIcon { symbol: "❖"; tint: "#ff9500" }
                    Text {
                        text: "启动台形态"
                        color: theme.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    SettingsNavBar {
                        id: launcherModeNavBar
                        model: [
                            { id: "bottom",     label: "底部吸附" },
                            { id: "center",     label: "屏幕居中" },
                            { id: "fullscreen", label: "全屏覆盖" }
                        ]
                        itemWidthOverride: 76
                        currentIndex: launcherPage.displayModeIndex
                        onSelectionChanged: function(index) {
                            launcherPage.saveDisplayMode(index)
                        }
                    }
                }
            }
        }

        Text {
            text: "网格、图标与文字".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: 221

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◉"; tint: "#ff9500" }
                        Text {
                            text: "图标尺寸"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(launcherPage.iconSize) + " px"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: (launcherPage.iconSize - 40) / 40
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                launcherPage.previewIconSize(position)
                            }
                            onCommitRequested: launcherPage.commitIconSize()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "↔"; tint: "#ff9500" }
                        Text {
                            text: "图标间距"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(launcherPage.iconSpacing) + " px"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: (launcherPage.iconSpacing - 10) / 38
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                launcherPage.previewIconSpacing(position)
                            }
                            onCommitRequested: launcherPage.commitIconSpacing()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "T"; tint: "#ff9500" }
                        Text {
                            text: "字体大小"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(launcherPage.fontSize) + " px"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: (launcherPage.fontSize - 9) / 9
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                launcherPage.previewFontSize(position)
                            }
                            onCommitRequested: launcherPage.commitFontSize()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "B"; tint: "#ff9500" }
                        Text {
                            text: "字体粗细"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: launcherFontWeightNavBar
                            model: [
                                { id: "normal", label: "常规" },
                                { id: "medium", label: "中黑" },
                                { id: "bold",   label: "粗体" }
                            ]
                            itemWidthOverride: 56
                            currentIndex: launcherPage.fontWeightIndex
                            onSelectionChanged: function(index) {
                                launcherPage.saveFontWeight(index)
                            }
                        }
                    }
                }
            }
        }

        Text {
            text: "外观与模糊效果".toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
            visible: false
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: launcherBlurCol.implicitHeight
            visible: false
            radius: 18
            color: theme.card

            Column {
                id: launcherBlurCol
                anchors.left: parent.left
                anchors.right: parent.right

                Item {
                    width: parent.width
                    height: 54
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "⎘"; tint: "#30d158" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: "跟随显示设置"
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: "关闭后可为启动台单独自定义背景模糊与液态强度"
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        LiquidControls.LiquidGlassSwitch {
                            checked: launcherPage.launcherBlurInherit
                            accentColor: "#30d158"
                            trackColor: theme.divider
                            onToggled: function(checked) {
                                launcherPage.setLauncherBlurInherit(checked)
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !launcherPage.launcherBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !launcherPage.launcherBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◌"; tint: "#5ac8fa" }
                        Text {
                            text: "启动台模糊强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: launcherPage.percentage(launcherPage.launcherBlurStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: launcherPage.launcherBlurStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                launcherPage.previewLauncherBlur(position)
                            }
                            onCommitRequested: launcherPage.commitLauncherBlur()
                        }
                    }
                }

                Rectangle {
                    visible: !launcherPage.launcherBlurInherit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    color: theme.separator
                }

                Item {
                    visible: !launcherPage.launcherBlurInherit
                    width: parent.width
                    height: 48
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "≈"; tint: "#af52de" }
                        Text {
                            text: "启动台液态强度"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: launcherPage.percentage(launcherPage.launcherLiquidStrength)
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                        }
                        LiquidControls.LiquidSlider {
                            Layout.preferredWidth: 190
                            value: launcherPage.launcherLiquidStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                launcherPage.previewLauncherLiquid(position)
                            }
                            onCommitRequested: launcherPage.commitLauncherLiquid()
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: launcherPage.errorText.length > 0
            text: launcherPage.errorText
            color: "#ff453a"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: sidebar
            x: 0
            y: 0
            width: 302
            height: parent.height
            radius: 0
            color: theme.sidebar

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 22
                anchors.bottomMargin: 16
                spacing: 0

                Text {
                    text: "设置"
                    color: theme.primaryText
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 8
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    Layout.bottomMargin: 10

                    LiquidControls.LiquidTextField {
                        anchors.fill: parent
                        leftPadding: 36
                        rightPadding: 10
                        placeholderText: "搜索"
                        glassColor: theme.searchField
                        focusColor: "#0a84ff"
                        textColor: theme.primaryText
                        mutedTextColor: theme.secondaryText
                        font.pixelSize: 13
                        onTextChanged: window.searchText = text
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        color: theme.secondaryText
                        font.pixelSize: 16
                        z: 1
                    }
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    pageIndex: 0
                    label: "显示"
                    navSymbol: "▱"
                    navTint: "#34c759"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 1
                    label: "主题"
                    navSymbol: "◈"
                    navTint: "#af52de"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 2
                    label: "顶栏"
                    navSymbol: "⎍"
                    navTint: "#5ac8fa"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 3
                    label: "Dock"
                    navSymbol: "▰"
                    navTint: "#0a84ff"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 4
                    label: "启动台"
                    navSymbol: "❖"
                    navTint: "#ff9500"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 5
                    label: "接入状态"
                    navSymbol: "✓"
                    navTint: "#30d158"
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Rectangle {
            id: contentSurface
            x: sidebar.width
            y: 0
            width: parent.width - x
            height: parent.height
            radius: 0
            color: theme.background

            Flickable {
                id: pageScroll
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                anchors.topMargin: 24
                anchors.bottomMargin: 24
                contentWidth: Math.max(width, pageContent.width)
                contentHeight: pageContent.implicitHeight
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: pageContent
                    readonly property real maximumWidth: 700
                    width: Math.max(0, Math.min(pageScroll.width, maximumWidth))
                    x: Math.max(0, Math.round((pageScroll.width - width) / 2))
                    spacing: 0

                    Text {
                        text: window.contentByPage[window.currentPage].subtitle
                        color: theme.primaryText
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        Layout.bottomMargin: 18
                    }
                    Repeater {
                        model: (window.currentPage >= 0 && window.currentPage <= 5)
                            ? [] : window.contentByPage[window.currentPage].groups
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5
                            Text {
                                text: modelData.header.toUpperCase()
                                color: theme.secondaryText
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.leftMargin: 13
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: settingsList.contentHeight
                                radius: 28
                                color: theme.card
                                ListView {
                                    id: settingsList
                                    width: parent.width
                                    height: contentHeight
                                    interactive: false
                                    model: modelData.rows
                                    delegate: SettingRow { row: modelData }
                                }
                            }
                            Item { Layout.preferredHeight: 14 }
                        }
                    }

                    LauncherSettingsPage {
                        visible: window.currentPage === 4
                    }

                    IntegrationStatusPage {
                        visible: window.currentPage === 5
                    }

                    DockSettingsPage {
                        visible: window.currentPage === 3
                    }

                    BarSettingsPage {
                        visible: window.currentPage === 2
                    }

                    ThemeSettingsPage {
                        visible: window.currentPage === 1
                    }

                    DisplaySettingsPage {
                        visible: window.currentPage === 0
                    }
                }
            }
        }
    }
}
