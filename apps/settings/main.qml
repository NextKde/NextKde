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
    }
    readonly property var contentByPage: [
        {
            subtitle: "Dock",
            summary: "调整停靠栏的内容、尺寸和窗口交互。",
            groups: []
        },
        {
            subtitle: "显示",
            summary: "显示器设置将逐步替换 KDE 的显示配置模块。",
            groups: [
                { header: "显示器", rows: [
                    { icon: "▱", tint: "#34c759", title: "显示器布局", detail: "即将支持" },
                    { icon: "↔", tint: "#34c759", title: "分辨率与缩放", detail: "即将支持" },
                    { icon: "⟳", tint: "#34c759", title: "刷新率与旋转", detail: "即将支持" }
                ] }
            ]
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
        readonly property var visibilityDescriptions: [
            "Dock 始终显示，并为应用窗口保留一条边缘空间",
            "有窗口覆盖或停靠 Dock 边缘时才收起 Dock，窗口移开后自动恢复显示",
            "平时收起只留一条小白条，鼠标滑到屏幕边缘或点击白条可唤起 Dock"
        ]
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

        function applyTintPreset(index) {
            saveTintColor(tintPresets[index].color)
        }

        function refresh() {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.dockSnapshot())
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
                        SettingIcon { symbol: "▣"; tint: "#0a84ff" }
                        Text {
                            text: "Dock 位置"
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidNavBar {
                            id: positionNavBar
                            model: [
                                { id: "bottom", icon: "↓" },
                                { id: "left",   icon: "←" },
                                { id: "right",  icon: "→" }
                            ]
                            size: "tiny"
                            accentColor: "#0a84ff"
                            currentIndex: dockPage.dockPositionIndex
                            onSelectionChanged: function(index) {
                                dockPage.savePosition(index)
                            }
                        }
                    }
                }
            }
        }

        Text {
            text: "Dock 显示".toUpperCase()
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
            implicitHeight: 97

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
                        SettingIcon { symbol: "◉"; tint: "#0a84ff" }
                        Text {
                            text: "显示方式"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidNavBar {
                            id: visibilityNavBar
                            model: [
                                { id: "always", label: "始终显示" },
                                { id: "smart", label: "智能隐藏" },
                                { id: "persistent", label: "持续隐藏" }
                            ]
                            // Text-only + "tiny", matching the Dock 颜色 bar's
                            // height so the two segmented controls read as one
                            // consistent set — no stacked icon+label to overflow
                            // the pill.
                            size: "tiny"
                            // 4-char labels are wider than the tiny preset's 56px
                            // item; give each item a little more room (height and
                            // pill stay identical to the Dock 颜色 bar).
                            itemWidthOverride: 76
                            accentColor: "#0a84ff"
                            labelFontPixelSize: 10
                            labelFontWeight: Font.DemiBold
                            currentIndex: dockPage.visibilityModeIndex

                            Connections {
                                target: visibilityNavBar
                                function onSelectionChanged(index) {
                                    dockPage.saveVisibilityMode(index)
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
                }

                Item {
                    width: parent.width
                    height: 42
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        Text {
                            text: dockPage.visibilityDescriptions[dockPage.visibilityModeIndex]
                            color: theme.secondaryText
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            verticalAlignment: Text.AlignVCenter
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
                        LiquidControls.LiquidNavBar {
                            id: iconModeNavBar
                            model: [
                                { id: "color", label: "彩色" },
                                { id: "grayscale", label: "黑白" },
                                { id: "tint", label: "染色" }
                            ]
                            size: "tiny"
                            accentColor: "#0a84ff"
                            labelFontPixelSize: 10
                            labelFontWeight: Font.DemiBold
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
                        LiquidControls.LiquidNavBar {
                            id: tintPresetNavBar
                            model: [
                                { id: "purple", label: "紫色" },
                                { id: "red", label: "红色" },
                                { id: "blue", label: "蓝色" },
                                { id: "orange", label: "橙色" }
                            ]
                            size: "tiny"
                            accentColor: "#0a84ff"
                            labelFontPixelSize: 10
                            labelFontWeight: Font.DemiBold
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
                    label: "Dock"
                    navSymbol: "▰"
                    navTint: "#0a84ff"
                }

                SidebarEntry {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    pageIndex: 1
                    label: "显示"
                    navSymbol: "▱"
                    navTint: "#34c759"
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
                contentWidth: width
                contentHeight: pageContent.implicitHeight
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: pageContent
                    width: Math.min(pageScroll.width, 700)
                    spacing: 0

                    Text {
                        text: window.contentByPage[window.currentPage].subtitle
                        color: theme.primaryText
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        Layout.bottomMargin: 4
                    }
                    Text {
                        Layout.fillWidth: true
                        text: window.contentByPage[window.currentPage].summary
                        color: theme.secondaryText
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        Layout.bottomMargin: 12
                    }

                    Repeater {
                        model: window.currentPage === 0
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

                    DockSettingsPage {
                        visible: window.currentPage === 0
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: window.currentPage !== 0
                        text: "部分项目仍在准备中。设置应用会通过明确的配置或 IPC 接口与桌面环境通信。"
                        color: theme.tertiaryText
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.topMargin: -5
                    }
                }
            }
        }
    }
}
