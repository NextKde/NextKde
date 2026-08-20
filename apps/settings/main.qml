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
        readonly property var iconModes: ["color", "grayscale"]
        property real iconOpacity: 0.5
        property bool iconOpacityDirty: false
        property string errorText: ""
        property bool layoutDirty: false

        function positionIndexFromString(position) {
            const idx = dockPositions.indexOf(position)
            return idx >= 0 ? idx : 0
        }

        function iconModeIndexFromString(mode) {
            const idx = iconModes.indexOf(mode)
            return idx >= 0 ? idx : 0
        }

        function applyState(state) {
            if (!state || state.baseHeight === undefined)
                return
            dockHeight = Number(state.baseHeight)
            dockPositionIndex = positionIndexFromString(state.position)
            iconModeIndex = iconModeIndexFromString(state.iconMode)
            iconOpacity = Number(state.iconOpacity)
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
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidNavBar {
                            id: iconModeNavBar
                            model: [
                                { id: "color", label: "彩色" },
                                { id: "grayscale", label: "黑白" }
                            ]
                            size: "tiny"
                            accentColor: "#af52de"
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
                    visible: dockPage.iconModeIndex === 1
                }

                Item {
                    id: iconOpacityRow
                    width: parent.width
                    height: dockPage.iconModeIndex === 1 ? 48 : 0
                    visible: dockPage.iconModeIndex === 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◓"; tint: "#af52de" }
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
