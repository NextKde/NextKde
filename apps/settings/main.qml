import Kos.Demo as Demo
import QtQuick
import "pages" as Pages
import "components" as SettingsControls
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/foundation" as Foundation
import "../../shared/qml/colorize/MaterialColorScheme.mjs" as Mcu
import "../../shared/qml/i18n"

ApplicationWindow {
    id: window
    onClosing: function(event) {
        if (typeof appStore !== "undefined" && appStore.music.busy) {
            event.accepted = false
            window.currentPage = 9
        }
    }

    width: 850
    height: 650
    minimumWidth: 600
    minimumHeight: 540
    font.pixelSize: 13
    visible: true
    title: I18n.tr("KOS settings")
    color: "transparent"
    background: Item {}
    readonly property alias settingsScene: settingsScene
    readonly property bool liquidEnabled: !materialForm && !Foundation.AppTheme.reduceTransparency
        && GraphicsInfo.api !== GraphicsInfo.Software
    Binding { target: Demo.AppTheme; property: "appearanceMode"; value: theme.dark ? "dark" : "light" }
    Binding { target: Demo.AppTheme; property: "compactDesign"; value: true }
    Binding { target: Demo.AppTheme; property: "reduceMotion"; value: Foundation.AppTheme.reduceMotion }
    Binding { target: Demo.AppTheme; property: "reduceTransparency"; value: Foundation.AppTheme.reduceTransparency }
    Binding { target: Demo.ControlForm; property: "materialForm"; value: !window.liquidEnabled }

    // 永远无边框(CSD):顶部 30px 保留带承载拖拽/双击最大化/窗口按钮。
    // 按钮有两层:右上的自绘简单按钮(常驻、永远可点),以及 kos-bridge
    // 在 KOS 装饰器选中时盖印在完全相同位置上的不透明面板(其 KWin 输入
    // 过滤器先行拦截,点的是面板)。装饰器切走 → 面板消失 → 自绘按钮
    // 露出来接着用。窗口在任何装饰器下都保持同一形态,无切换逻辑。
    readonly property int chromeStrip: 30
    flags: Qt.Window | Qt.FramelessWindowHint

    property int currentPage: 1
    property var pageHistory: [1]
    property int historyIndex: 0
    property bool navigationReady: false
    property bool restoringHistory: false
    readonly property bool canGoBack: historyIndex > 0
    readonly property bool canGoForward: historyIndex < pageHistory.length - 1
    Component.onCompleted: {
        pageHistory = [currentPage]
        historyIndex = 0
        navigationReady = true
    }
    onCurrentPageChanged: {
        if (!navigationReady || restoringHistory)
            return
        const next = pageHistory.slice(0, historyIndex + 1)
        next.push(currentPage)
        pageHistory = next
        historyIndex = next.length - 1
    }
    function navigateHistory(offset) {
        const index = historyIndex + offset
        if (index < 0 || index >= pageHistory.length)
            return
        restoringHistory = true
        historyIndex = index
        currentPage = pageHistory[index]
        restoringHistory = false
    }
    Shortcut { sequence: "Alt+Left"; enabled: window.canGoBack; onActivated: window.navigateHistory(-1) }
    Shortcut { sequence: "Alt+Right"; enabled: window.canGoForward; onActivated: window.navigateHistory(1) }
    readonly property int displayedPage: pageMotion.displayedPage === ""
        ? currentPage : pageMotion.displayedPage
    property string searchText: ""
    function matchingNavigationCount(item) {
        if (item.label !== undefined)
            return String(item.label).toLowerCase().includes(searchText.toLowerCase()) ? 1 : 0
        let count = 0
        for (const child of item.children ?? []) count += matchingNavigationCount(child)
        return count
    }

    Foundation.KosPageMotion {
        id: pageMotion
        page: window.currentPage
        onDisplayedPageChanged: {
            if (pageScroll)
                pageScroll.contentY = 0
        }
    }

    // The shell owns the style; the pages read it from here and so does this
    // window's own palette. `materialSeed` is the accent the shell derived from
    // the wallpaper, which is enough for the shared implementation to rebuild
    // the same Material 3 roles the shell is using instead of this window
    // hard-coding a second, drifting palette.
    property string shellStyle: "macos"
    readonly property bool materialForm: shellStyle === "material"
    property string materialSeed: ""
    // Material 3 palette, rebuilt from that accent by the same implementation
    // the shell derives its own with. The shared colorize singleton cannot be
    // used here: it pulls in Quickshell, and this application is plain Qt.
    //
    // Known limit: only the Monet branch is reproduced. If the shell is set to a
    // traditional colour source, its swatches are table colours and this window
    // falls back to Monet's derivation of the same accent.
    readonly property var materialPalette: {
        if (!materialForm || materialSeed === "")
            return ({})
        return Mcu.buildScheme(materialSeed, { dark: theme.dark })
    }

    // Qt updates SystemPalette when the desktop colour scheme changes. We use
    // it only to select the system appearance, then apply the matching iPadOS
    // palette so both modes keep a coherent Settings visual language.
    SystemPalette {
        id: systemPalette
        colorGroup: SystemPalette.Active
    }

    readonly property var notificationTheme: theme
    readonly property var glassStyleOptions: glassStyles

    QtObject {
        id: theme

        readonly property bool dark: {
            const color = systemPalette.window
            return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
        }
        // One role, two forms. The tonal form takes the shared Material 3 scheme
        // (rebuilt from the accent the shell sent); the iPadOS form keeps exactly
        // the literal this window was designed with -- switching the shell style
        // repaints the whole app, and nothing drifts in between.
        // Role names are the shared implementation's own (ROLE_SPEC keys:
        // surface_container_low, on_surface_variant, ...), not camelCase. They
        // have to be spelled the way MaterialColorScheme.mjs builds them: a name
        // it does not emit resolves to undefined, and every one of those used to
        // fall back to the iPadOS literal, which left the whole window looking
        // like the other form while claiming to be Material.
        function role(name, iPadOSValue) {
            if (!window.materialForm)
                return iPadOSValue
            const value = window.materialPalette[name]
            return value === undefined ? iPadOSValue : value
        }
        // Opaque neutral planes; optical material belongs to floating controls.
        readonly property color background: role("surface", dark ? "#242426" : "#f7f7f7")
        readonly property color sidebar: role("surface_container_low", dark ? "#242426" : "#ececeb")
        readonly property color contentSurface: role("surface_container_low", dark ? "#1C1C1E" : "#FFFFFF")
        readonly property color primaryText: role("on_surface", dark ? "#F2F2F2" : "#262626")
        readonly property color secondaryText: role("on_surface_variant", dark ? "#ABABAB" : "#737373")
        readonly property color tertiaryText: role("outline", dark ? "#858585" : "#858585")
        readonly property color card: role("surface_container", dark ? "#242426" : "#f7f7f7")
        readonly property color separator: role("outline_variant", dark ? "#38383a" : "#e5e5ea")
        readonly property color divider: role("outline_variant", dark ? "#2c2c2e" : "#d1d1d6")
        readonly property color searchField: role("surface_container_high", dark ? "#3A3A3C" : "#EDEDF0")
        readonly property color selected: role("primary", "#007AFF")
        // The container a selected item sits in. M3 carries selection with
        // secondaryContainer; the iPadOS form keeps the translucent wash.
        readonly property color selectedContainer: role("secondary_container", dark
            ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.06))
        readonly property color sidebarHover: role("surface_container_high", dark
            ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.045))
        readonly property color chevron: role("outline", dark ? "#636366" : "#c7c7cc")
        readonly property color iconForeground: role("on_surface", "#ffffff")
        // M3's navigation drawer carries a selected item as a secondaryContainer
        // pill with onSecondaryContainer ink, and leaves unselected icons
        // monochrome -- the coloured chip under each icon is the iPadOS form's
        // own furniture, so it only exists there.
        readonly property color iconMuted: role("on_surface_variant", dark ? "#98989d" : "#6d6d72")
        readonly property color selectedForeground: role("on_secondary_container", "#FFFFFF")
        // Controls that take a single accent (sliders, switches) read this.
        readonly property color accent: role("primary", "#0a84ff")
        readonly property color floatingBorder: role("outline", dark
            ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0, 0, 0, 0.055))
        readonly property color floatingShadow: dark
            ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(0.17, 0.21, 0.30, 0.16)
        readonly property color previewPane: dark ? "#14151a" : "#eef2f7"
        readonly property color previewBar: dark ? "#2c2d35" : "#ffffff"
        readonly property color previewTaskbar: dark ? "#1e2028" : "#ffffff"
        readonly property color previewDock: dark ? "#323540" : "#ffffff"
        readonly property color previewIcon: dark ? "#a0a4b0" : "#7c8290"
    }

    // The one ordered list of 材质风格 glass styles. Both the 材质风格 row (which
    // renders it) and the 玻璃调试 page (which names the preset it edits) read it
    // here, so a new style is added in this list and nowhere else. The ids must
    // stay in step with AppearanceConfigService.isValidGlassStyle.
    QtObject {
        id: glassStyles
        readonly property var options: [
            { id: "liquid", label: I18n.tr("Liquid glass") },
            { id: "soft", label: I18n.tr("Soft-light glass") },
            { id: "frosted", label: I18n.tr("Frosted glass") }
        ]
        function indexOf(rawStyle) {
            const style = String(rawStyle)
            for (let i = 0; i < options.length; ++i) {
                if (options[i].id === style)
                    return i
            }
            return -1
        }
        function labelOf(rawStyle) {
            const index = indexOf(rawStyle)
            return index >= 0 ? options[index].label : String(rawStyle)
        }
    }

    // Whether the pages on screen came from a checkout -- which is also what
    // makes them hot-reloadable. Reported by the standalone bridge from the
    // entry point it loaded, not from the session it ends up talking to: a
    // .desktop launch (app grid, KRunner) shows the installed copy even when a
    // checkout Shell is the one answering IPC, and the banner must not claim
    // otherwise. A missing bridge (older binary, plain QML preview) reads as
    // false, which keeps the banner out of the way.
    readonly property bool sourceTreeEntry: (typeof settingsBridge !== "undefined")
        ? settingsBridge.sourceTreeEntry === true : false
    readonly property string sessionShellDir: (typeof settingsBridge !== "undefined")
        ? settingsBridge.sessionShellDir : ""

    // The banner states how this window was loaded, which closing it cannot
    // change -- so the close control hides the notice for this run only. The
    // flag lives on the bridge rather than here on purpose: every QML edit
    // rebuilds this window, and a banner that returns after each save would
    // defeat the control. Reopening Settings shows it again.
    readonly property bool developmentBannerVisible: window.sourceTreeEntry
        && !((typeof settingsBridge !== "undefined")
            ? settingsBridge.developmentBannerDismissed === true : false)

    function dismissDevelopmentBanner() {
        if (typeof settingsBridge !== "undefined")
            settingsBridge.developmentBannerDismissed = true
    }

    readonly property var contentByPage: [
        {
            subtitle: I18n.tr("Show")
        },
        {
            subtitle: I18n.tr("Theme")
        },
        {
            subtitle: I18n.tr("Top bar")
        },
        {
            subtitle: "Dock"
        },
        {
            subtitle: I18n.tr("Launcher")
        },
        {
            subtitle: I18n.tr("Shortcuts")
        },
        {
            subtitle: I18n.tr("Integration status")
        },
        {
            subtitle: I18n.tr("Glass debugging")
        },
        {
            subtitle: I18n.tr("Wallpaper")
        },
        {
            subtitle: I18n.tr("Extensions and services")
        },
        {
            subtitle: I18n.tr("Stage scheduling")
        },
        { subtitle: I18n.tr("Windows and animations") },
        { subtitle: I18n.tr("Notifications") },
        { subtitle: I18n.tr("Power") }
    ]

    // Shown only while a development session drives this window. Every value on
    // these pages then belongs to that session's own state directory: the
    // settings are live in the checkout Shell the user is looking at and are not
    // the ones the installed desktop reads at login. Conflating the two is the
    // mistake this banner exists to prevent.
    // Deliberately loud. A development window and the installed desktop render
    // identically, so this band is the only thing between "I just tuned my dock"
    // and "I just tuned a copy nobody logs into". A quiet note would be read as
    // decoration and skipped, which is exactly the outcome it exists to prevent.
    // Solid fill in fixed colours rather than theme tints: the contrast then
    // holds in either theme, and it cannot be mistaken for one more card.
    // Two short lines, not a paragraph: the warning has to land while the user
    // is looking past it at whatever they came here to change.
    component DevelopmentBanner: Rectangle {
        Layout.fillWidth: true
        Layout.bottomMargin: 22
        implicitHeight: bannerText.implicitHeight + 34
        radius: 16
        color: "#ff9f0a"

        Rectangle {
            id: bannerBadge
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            width: 28
            height: 28
            radius: 14
            color: "#241700"

            Text {
                anchors.centerIn: parent
                text: "!"
                color: "#ff9f0a"
                font.pixelSize: 17
                font.weight: Font.Bold
            }
        }

        // Closing is not "never warn me again": a fresh window is a fresh load
        // and shows the banner again. This only clears the band out of the way
        // of someone who already knows, for as long as that window is open.
        Rectangle {
            id: bannerClose
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 14
            width: 28
            height: 28
            radius: 14
            color: bannerCloseHit.containsMouse
                ? Qt.rgba(0.14, 0.09, 0, 0.18) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: "#241700"
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            MouseArea {
                id: bannerCloseHit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: window.dismissDevelopmentBanner()
            }
        }

        Column {
            id: bannerText
            anchors.left: bannerBadge.right
            anchors.right: bannerClose.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 3

            Text {
                text: I18n.tr("kos-settings developer hot-reload mode")
                color: "#241700"
                font.pixelSize: 17
                font.weight: Font.Bold
            }

            Text {
                width: parent.width
                text: I18n.tr("differs from the install mode loaded by the launcher")
                color: Qt.rgba(0.14, 0.09, 0, 0.78)
                font.pixelSize: 13
            }
        }
    }

    component SidebarEntry: ItemDelegate {
        id: sidebarEntry
        required property int pageIndex
        required property string label
        required property string navIcon
        required property string navSymbol
        required property color navTint
        // Launch-only rows are plain links: no hover wash, no selection
        // state, the click runs the action instead of switching pages.
        property bool launchOnly: false
        signal launch()
        width: parent ? parent.width : 0
        Layout.minimumHeight: 30
        Layout.preferredHeight: 30
        Layout.maximumHeight: 30
        height: 30
        Accessible.name: label
        Demo.KosToolTip {
            target: sidebarEntry
            text: sidebarEntry.label
            onlyWhenTruncated: true
            truncated: sidebarLabel.truncated
        }
        leftPadding: 10
        rightPadding: 10
        highlighted: !launchOnly && window.currentPage === pageIndex
        hoverEnabled: !launchOnly
        visible: window.searchText.length === 0
            || label.toLowerCase().indexOf(window.searchText.toLowerCase()) >= 0
        background: Rectangle {
            // M3's drawer items are full-round pills that carry selection in
            // secondaryContainer; the macOS form uses a blue rounded row.
            // Launch-only rows stay completely inert.
            radius: window.materialForm ? height / 2 : 6
            border.width: parent.activeFocus ? 2 : 0
            border.color: theme.accent
            color: parent.launchOnly ? "transparent"
                : (parent.highlighted
                    ? (window.materialForm ? theme.selectedContainer : theme.selected)
                    : (parent.hovered ? theme.sidebarHover : "transparent"))
        }
        contentItem: Item {
            implicitHeight: 28
            SettingsControls.NavigationIcon {
                colors: window.notificationTheme
                materialForm: window.materialForm
                id: sidebarIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                iconName: navIcon
                symbol: navSymbol
                tint: navTint
                highlighted: window.currentPage === pageIndex
            }
            Text {
                id: sidebarLabel
                anchors.left: sidebarIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: window.currentPage === pageIndex
                    ? theme.selectedForeground : theme.primaryText
                font.pixelSize: 13
                font.weight: Font.Normal
                elide: Text.ElideRight
            }
        }
        onClicked: {
            if (launchOnly) {
                launch()
                return
            }
            window.currentPage = pageIndex
        }
    }

    Demo.LiquidBackdrop {
        id: helpBackdrop
        sourceItem: settingsScene
        registerAsDefault: false
        active: !Foundation.AppTheme.reduceTransparency
    }

    // ── 台前调度（fg-sched）页 ──────────────────────────────────────
    // 冻结默认全面停用：后台只做资源限制（nice/效率核/IO，异构才限核）。本页管理：
    // ① 冻结开关（重开时最小化窗口 180s 后 SIGSTOP）
    // ② "后台全资源运行"名单（never_demote_apps——名单内应用切后台后
    //    保持前台档参数，不降级不限核）
    // ③ 台前侧栏与切换动画的全部可调参数（stage-config IPC 实时生效）
    // 资源配置写 ~/.config/fg-sched/config.json，root 守护 mtime 轮询 ≤5s
    // 生效；动画/侧栏参数走 shell 的 stage-config IPC，即时生效。

    Item {
        id: settingsScene
        readonly property alias toolTipBackdrop: helpBackdrop
        anchors.fill: parent

        Item {
            id: planes
            anchors.fill: parent
        Rectangle {
            id: sidebarPlane
            objectName: "settingsSidebarPlane"
            width: sidebar.width
            height: parent.height
            color: theme.sidebar
            opacity: window.liquidEnabled ? 0.98 : 1
        }
        Rectangle {
            x: sidebar.width
            width: parent.width - x
            height: parent.height
            color: theme.contentSurface
        }
        }
        Demo.LiquidBackdrop {
            id: sidebarBackdrop
            sourceItem: planes
            active: window.liquidEnabled
        }

        Rectangle {
            id: sidebar
            x: 0
            y: 0
            width: 214
            height: parent.height
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                // 两侧对称 24:内容区已顶天立地(无 inset),卡片不再需要
                // 叠加内容面板的 inset 来凑视觉居中。
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.topMargin: 38
                anchors.bottomMargin: 16
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.bottomMargin: 10

                    Demo.LiquidTextField {
                        id: sidebarSearch
                        objectName: "settingsSearch"
                        anchors.fill: parent
                        leftPadding: 30
                        rightPadding: 10
                        placeholderText: I18n.tr("Search")
                        Accessible.name: placeholderText
                        font.pixelSize: 11
                        liquidFinish: true
                        liquidIntensity: "strong"
                        materialForm: !window.liquidEnabled
                        backdrop: sidebarBackdrop
                        focusedOutlineColor: materialForm ? Foundation.AppTheme.focusRing : "transparent"
                        onTextChanged: window.searchText = text
                    }

                    LiquidControls.VectorIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        color: theme.secondaryText
                        size: 14
                        z: 1
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.bottomMargin: visible ? 8 : 0
                    visible: window.searchText.length > 0 && window.matchingNavigationCount(navigation) === 0
                    text: I18n.tr("No results")
                    color: theme.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                Flickable {
                    id: navigationScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: navigation.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ColumnLayout {
                        id: navigation
                        width: navigationScroll.width
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 0
                            color: "transparent"
                            radius: 0
                            implicitHeight: navGroup1.implicitHeight

                            ColumnLayout {
                                id: navGroup1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 0
                                spacing: 0

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 1
                                    label: I18n.tr("Theme")
                                    navIcon: "appearance"
                                    navSymbol: "◈"
                                    navTint: "#af52de"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 11
                                    label: I18n.tr("Windows and animations")
                                    navIcon: "desktop-dock"
                                    navSymbol: "▣"
                                    navTint: "#af52de"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 8
                                    label: I18n.tr("Wallpaper")
                                    navIcon: "wallpaper"
                                    navSymbol: "▧"
                                    navTint: "#64d2ff"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 2
                                    label: I18n.tr("Top bar")
                                    navIcon: "menu-bar"
                                    navSymbol: "⎍"
                                    navTint: "#5ac8fa"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 3
                                    label: I18n.tr("Dock")
                                    navIcon: "desktop-dock"
                                    navSymbol: "▰"
                                    navTint: "#0a84ff"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 13
                                    label: I18n.tr("Power")
                                    navIcon: "battery"
                                    navSymbol: "ϟ"
                                    navTint: "#34c759"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 12
                                    label: I18n.tr("Notifications")
                                    navIcon: "notifications"
                                    navSymbol: "●"
                                    navTint: "#ff3b30"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 4
                                    label: I18n.tr("Launcher")
                                    navIcon: "spotlight"
                                    navSymbol: "❖"
                                    navTint: "#ff9500"
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 0
                            color: "transparent"
                            radius: 0
                            implicitHeight: navGroup2.implicitHeight

                            ColumnLayout {
                                id: navGroup2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 0
                                spacing: 0

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 5
                                    label: I18n.tr("Shortcuts")
                                    navIcon: "keyboard"
                                    navSymbol: "⌘"
                                    navTint: "#5856d6"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 6
                                    label: I18n.tr("Integration status")
                                    navIcon: "network"
                                    navSymbol: "✓"
                                    navTint: "#30d158"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 9
                                    label: I18n.tr("Extensions and services")
                                    navIcon: "general"
                                    navSymbol: "◇"
                                    navTint: "#5ac8fa"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 7
                                    label: I18n.tr("Glass debugging")
                                    navIcon: "appearance"
                                    navSymbol: "⚙"
                                    navTint: "#64d2ff"
                                }

                                SidebarEntry {
                                    Layout.fillWidth: true
                                    pageIndex: 10
                                    label: I18n.tr("Stage scheduling")
                                    navIcon: "desktop-dock"
                                    navSymbol: "⏵"
                                    navTint: "#ff9f0a"
                                }
                            }
                        }



                    }
                    Foundation.KosKineticScroll { flickable: navigationScroll }
                }
            }
        }

        Rectangle {
            id: contentSurface
            // 右侧内容面顶天立地:从侧栏右缘一直铺到窗口上/右/下边缘,不留
            // inset、不做圆角——与侧栏形成两栏平面分割(窗口永远无边框,顶部
            // chromeStrip 保留带落在内容面色上,拖拽/红绿灯都在这一带)。
            x: sidebar.width
            y: 0
            width: parent.width - x
            height: parent.height
            color: "transparent"

            Flickable {
                id: pageScroll
                opacity: pageMotion.progress
                enabled: pageMotion.interactive
                transform: Translate { x: Foundation.AppTheme.reduceMotion ? 0 : 12 * (1 - pageMotion.progress) }
                objectName: "settings-page-scroll"
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                // Leave a compact gap below the fixed title and navigation row.
                anchors.topMargin: window.chromeStrip + 18
                anchors.bottomMargin: 16
                contentWidth: Math.max(width, pageContent.width)
                contentHeight: pageContent.implicitHeight
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                ColumnLayout {
                    id: pageContent
                    // Grow up to the comfortable reading width; narrow windows reflow.
                    width: Math.min(740, pageScroll.width)
                    x: Math.max(0, Math.round((pageScroll.width - width) / 2))
                    spacing: 0

                    // Invisible rows are left out of a Layout, so an installed
                    // session shows no gap where this sits, and neither does a
                    // development one once the banner has been closed.
                    DevelopmentBanner {
                        visible: window.developmentBannerVisible
                    }

                    // Every page used to be instantiated at startup, so its
                    // Component.onCompleted refresh spawned a `quickshell ipc
                    // call` on the UI thread; with the shell down that froze
                    // the window for tens of seconds. Each Loader now creates
                    // its page only when the page is first opened, and the
                    // refreshes themselves are asynchronous.
                    //
                    // `visible: active` is part of that contract, not
                    // decoration: deactivating a Loader destroys its item but
                    // leaves the Loader's own implicit size at whatever the
                    // page last measured, and a Layout skips only *invisible*
                    // items -- so without it a page the user has left keeps its
                    // whole height as a blank slab between the title and the
                    // page actually being shown.
                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 13
                        visible: active
                        sourceComponent: Pages.PowerSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            backend: typeof powerSettings !== "undefined" ? powerSettings : null
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 12
                        visible: active
                        sourceComponent: NotificationsSettingsPage {
                            theme: window.notificationTheme
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        objectName: "windowPageLoader"
                        active: window.displayedPage === 11
                        visible: active
                        sourceComponent: Pages.WindowAnimationSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            backend: typeof windowSettings !== "undefined" ? windowSettings : null
                        }
                    }

                    Loader {
                        objectName: "LauncherSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 4
                        visible: active
                        sourceComponent: Pages.LauncherSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "ShortcutsSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 5
                        visible: active
                        sourceComponent: Pages.ShortcutsSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "IntegrationStatusPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 6
                        visible: active
                        sourceComponent: Pages.IntegrationStatusPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "GlassDebugPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 7
                        visible: active
                        sourceComponent: Pages.GlassDebugPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                            glassStyles: window.glassStyleOptions
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 9
                        visible: active
                        sourceComponent: ServicesSettingsPage {
                            store: typeof appStore !== "undefined" ? appStore : null
                            bridge: (typeof settingsBridge !== "undefined") ? settingsBridge : null
                            colors: theme
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 8
                        visible: active
                        sourceComponent: WallpaperSettingsPage {
                            scrollViewport: pageScroll
                            bridge: (typeof settingsBridge !== "undefined")
                                ? settingsBridge : null
                            colors: theme
                            onDesktopPreviewFinished: {
                                window.showNormal()
                                window.requestActivate()
                            }
                        }
                    }

                    Loader {
                        objectName: "FgSchedSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 10
                        visible: active
                        sourceComponent: Pages.FgSchedSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "DockSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 3
                        visible: active
                        sourceComponent: Pages.DockSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "BarSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 2
                        visible: active
                        sourceComponent: Pages.BarSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                        }
                    }

                    Loader {
                        objectName: "ThemeSettingsPageLoader"
                        Layout.fillWidth: true
                        active: window.displayedPage === 1
                        visible: active
                        sourceComponent: Pages.ThemeSettingsPage {
                            colors: window.notificationTheme
                            materialForm: window.materialForm
                            bridge: typeof settingsBridge !== "undefined" ? settingsBridge : null
                            glassStyles: window.glassStyleOptions
                            onShellStyleObserved: style => window.shellStyle = style
                            onMaterialSeedObserved: seed => window.materialSeed = seed
                        }
                    }

                }

                // 设置页正文：浏览器式惯性滚动。禁用态（页面切换动画期间
                // enabled: pageMotion.interactive）会连同 wheel 一起失效。
                Foundation.KosKineticScroll { flickable: pageScroll }
            }
        }

        // ── 窗口框(常驻,窗口永远无边框)────────────────────────────
        // 顶部保留带:整条可拖拽移动,双击切换最大化。移动手势必须在指针
        // 真正移动超过阈值后才启动:startSystemMove 会在合成器侧抓取指针
        // 手势,若在按下的瞬间就启动,双击的最大化请求会撞进进行中的手势,
        // KWin 的最大化摆放会整体偏移(顶缝/压 dock)。
        MouseArea {
            id: titlebarDrag
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: window.chromeStrip
            onPressed: mouse => {
                pressPos = Qt.point(mouse.x, mouse.y)
                moveArmed = true
            }
            onPositionChanged: mouse => {
                if (!moveArmed)
                    return
                if (Math.abs(mouse.x - pressPos.x) > 4
                    || Math.abs(mouse.y - pressPos.y) > 4) {
                    moveArmed = false
                    window.startSystemMove()
                }
            }
            onDoubleClicked: {
                moveArmed = false
                window.visibility === Window.Maximized
                    ? window.showNormal() : window.showMaximized()
            }
            property point pressPos
            property bool moveArmed: false
        }

        // 自绘窗口按钮:几何与 bridge 面板对齐(offset 10,6 + padding 4.5),
        // KOS 装饰器选中时被面板完整盖住(输入走面板),面板不在时它们就是
        // 窗口控件。
        Row {
            id: windowControls
            objectName: "settingsWindowControls"
            anchors {
                right: parent.right
                rightMargin: 14.5   // 面板 offset.x 10 + panelPaddingX 4.5
                top: parent.top
                topMargin: 12.5     // offset.y 6 + panelPadding 4.5
            }
            spacing: 14
            Repeater {
                model: [
                    { color: "#28c840", act: "max" },
                    { color: "#febc2e", act: "min" },
                    { color: "#ff5f57", act: "close" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: 14; height: 14; radius: 7
                    color: modelData.color
                    opacity: 0.85
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.act === "min" ? window.showMinimized()
                            : modelData.act === "max"
                            ? (window.visibility === Window.Maximized
                                ? window.showNormal() : window.showMaximized())
                            : window.close()
                    }
                }
            }
        }

        Demo.LiquidActionButton {
            id: kdeSettingsButton
            objectName: "settingsOpenKdeSettings"
            anchors.right: windowControls.left
            anchors.rightMargin: 22
            anchors.verticalCenter: windowControls.verticalCenter
            width: 26
            height: 26
            z: 2
            iconOnly: true
            contentItem: Item {
                implicitWidth: 16
                implicitHeight: 16
                Image {
                    objectName: "settingsKdeLogo"
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: theme.dark ? Qt.resolvedUrl("icons/kde-symbolic-dark.svg")
                        : Qt.resolvedUrl("icons/kde-symbolic.svg")
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    opacity: kdeSettingsButton.enabled ? 1 : 0.38
                }
            }
            materialForm: !window.liquidEnabled
            backdrop: sidebarBackdrop
            focusRingColor: materialForm ? Foundation.AppTheme.focusRing : "transparent"
            enabled: typeof settingsBridge !== "undefined"
                && typeof settingsBridge.launchSystemSettings === "function"
            Accessible.name: I18n.tr("KDE System Settings")
            Demo.KosToolTip {
                target: kdeSettingsButton
                text: I18n.tr("Open KDE System Settings")
            }
            onClicked: settingsBridge.launchSystemSettings()
        }

        RowLayout {
            id: pageToolbar
            objectName: "settingsPageToolbar"
            x: contentSurface.x + 20
            y: windowControls.y + (windowControls.height - height) / 2
            width: Math.max(0, kdeSettingsButton.x - x - 12)
            height: 26
            spacing: 10
            z: 2

            Demo.LiquidActionButtonGroup {
                objectName: "settingsHistoryNavigation"
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: 26
                buttonSize: 26
                icons: ["back", "forward"]
                labels: [I18n.tr("Previous page"), I18n.tr("Next page")]
                enabledActions: [window.canGoBack, window.canGoForward]
                materialForm: !window.liquidEnabled
                backdrop: sidebarBackdrop
                onTriggered: index => window.navigateHistory(index === 0 ? -1 : 1)
            }

            Text {
                objectName: "settingsPageTitle"
                Layout.fillWidth: true
                text: window.contentByPage[window.displayedPage].subtitle
                color: theme.primaryText
                font.pixelSize: 16
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        WindowResizeHandles { targetWindow: window }
    }
}
