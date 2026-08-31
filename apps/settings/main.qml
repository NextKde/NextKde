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
            subtitle: "显示",
            groups: []
        },
        {
            subtitle: "主题",
            groups: []
        },
        {
            subtitle: "Dock",
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
            implicitHeight: 54

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
                        SettingsNavBar {
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
                            // 4-char labels are wider than the tiny preset's 56px
                            // item; give each item a little more room (height and
                            // pill stay identical to the Dock 颜色 bar).
                            itemWidthOverride: 76
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
            if (!state || state.blurStrength === undefined
                    || state.liquidStrength === undefined)
                return
            blurStrength = Math.max(0, Math.min(1, Number(state.blurStrength)))
            liquidStrength = Math.max(0, Math.min(1, Number(state.liquidStrength)))
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

        function previewBlur(value) {
            blurStrength = Math.max(0, Math.min(1, value))
            blurDirty = true
        }

        function commitBlur() {
            if (!blurDirty || !bridge)
                return
            blurDirty = false
            applyState(bridge.updateBlurStrength(blurStrength))
            if (bridge.lastError)
                errorText = bridge.lastError
        }

        function previewLiquid(value) {
            liquidStrength = Math.max(0, Math.min(1, value))
            liquidDirty = true
        }

        function commitLiquid() {
            if (!liquidDirty || !bridge)
                return
            liquidDirty = false
            applyState(bridge.updateLiquidStrength(liquidStrength))
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
        property bool barIntegratedWithDock: false
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
            barIntegratedWithDock = Boolean(state.barIntegratedWithDock)
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

        function setBarIntegratedWithDock(enabled) {
            if (!bridge) {
                errorText = "尚未构建 Settings 桥接程序"
                return
            }
            applyState(bridge.updateBarIntegratedWithDock(enabled))
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
                    spacing: 18

                    Rectangle {
                        Layout.preferredWidth: 226
                        Layout.fillHeight: true
                        radius: 14
                        color: theme.dark ? "#101216" : "#e9edf4"
                        clip: true

                        Rectangle {
                            x: 18
                            y: 24
                            width: 78
                            height: 45
                            radius: modelData.id === "windows12" ? 8
                                : modelData.id === "material" ? 14 : 20
                            color: Qt.alpha(modelData.accent, 0.22)
                            border.width: 1
                            border.color: Qt.alpha(modelData.accent, 0.32)
                        }
                        Rectangle {
                            x: 104
                            y: 24
                            width: 52
                            height: 45
                            radius: modelData.id === "windows12" ? 8
                                : modelData.id === "material" ? 14 : 20
                            color: theme.dark ? "#2d3038" : "#ffffff"
                            opacity: 0.88
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: modelData.id === "windows12"
                                ? undefined : parent.top
                            anchors.bottom: modelData.id === "windows12"
                                ? parent.bottom : undefined
                            height: modelData.id === "windows12" ? 28 : 10
                            color: modelData.id === "material"
                                ? Qt.alpha(modelData.accent, 0.24)
                                : (theme.dark ? "#30333b" : "#f8f9fc")
                            opacity: modelData.id === "macos" ? 0.70 : 0.94
                        }

                        Rectangle {
                            visible: modelData.id !== "windows12"
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            width: modelData.id === "macos" ? 116 : 142
                            height: 26
                            radius: modelData.id === "macos" ? 13 : 10
                            color: modelData.id === "material"
                                ? Qt.alpha(modelData.accent, 0.38)
                                : (theme.dark ? "#454952" : "#ffffff")
                            border.width: 1
                            border.color: Qt.alpha("#ffffff", 0.25)
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: modelData.id === "windows12" ? 7 : 13
                            spacing: 7
                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: 10
                                    height: 10
                                    radius: styleCard.modelData.id === "material" ? 3 : 5
                                    color: index === 2
                                        ? styleCard.modelData.accent
                                        : (theme.dark ? "#d9dce3" : "#58606c")
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: theme.primaryText
                                font.pixelSize: 17
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                visible: themePage.shellStyle === modelData.id
                                width: 24
                                height: 24
                                radius: 12
                                color: modelData.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "white"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.description
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                        Item { Layout.fillHeight: true }
                        Text {
                            text: themePage.shellStyle === modelData.id
                                ? "当前形态" : "选择此形态"
                            color: modelData.accent
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
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
            text: "BAR 布局"
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 4
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            radius: 18
            color: theme.card

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
                    checked: themePage.barIntegratedWithDock
                    accentColor: "#0a84ff"
                    trackColor: theme.divider
                    onToggled: function(checked) {
                        themePage.setBarIntegratedWithDock(checked)
                    }
                }
            }
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
            text: "主题会立即更新 Dock。窗口动画会立即同步到 KWin；Bar 可通过上方开关选择独立顶栏或底部统一宿主。"
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
                    label: "Dock"
                    navSymbol: "▰"
                    navTint: "#0a84ff"
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
