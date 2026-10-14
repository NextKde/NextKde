import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../shared/qml/controls" as LiquidControls
import "../../shared/qml/foundation" as Foundation
import "../../shared/qml/colorize/MaterialColorScheme.mjs" as Mcu
import "../../shared/qml/i18n"

ApplicationWindow {
    id: window

    width: 1100
    height: 720
    // 最小宽 = 侧栏 230 + 面板 inset 20×2 + 滚动区边距 30×2 + 内容列 700:
    // 内容列已锁死 700 固定宽,窗口再窄只会截切,这里保证永远放得下。
    minimumWidth: 1030
    minimumHeight: 560
    visible: true
    title: I18n.tr("KOS settings")
    color: theme.background

    property int currentPage: 1
    readonly property int displayedPage: pageMotion.displayedPage === ""
        ? currentPage : pageMotion.displayedPage
    property string searchText: ""

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
        // 窗口底色 + 左侧栏 = 同一块平面，右侧内容区是它上面一块圆角面板。
        // 底色**必须**是 #eff0f1，等于 BreezeLight 的 Window/BackgroundNormal(239,240,241)：
        // 窗口装饰 kos_decoration 的标题栏取的就是 client->palette().color(QPalette::Window)
        // （kwin/kos-decoration/kosdecoration.cpp:157），两边同色标题栏才和
        // 内容连成一块无缝的面。**永远不要动这个值**（2026-09-28 改过一次，标题栏立刻裂出色差）。
        //   右侧面板 = #e3e5e7，即 Breeze 同组的 Window/BackgroundAlternate(227,229,231)
        // 圆角要看得见只能靠面板比底色深：ΔRGB (12,11,10)、对比度约 1.11:1。
        // （试过 #f2f2f7：ΔRGB 只有 (3,2,6)/1.023:1，肉眼分不出边界。加阴影已被否，
        //  因为读起来是"浮起"不是"分栏"。）
        // 深色沿用同一套结构：底色 #202326，右侧面板 #2a2d31（比底色浅一档，
        // 圆角才看得见），分组卡片 #1c1c1e 沉在面板里（面板 < 卡片的亮度，
        // 卡片才是"深黑"的那一层）。
        readonly property color background: role("surface", dark ? "#202326" : "#eff0f1")
        readonly property color sidebar: role("surface", dark ? "#202326" : "#eff0f1")
        readonly property color contentSurface: role("surface_container_low", dark
            ? "#2a2d31" : "#e3e5e7")
        readonly property color primaryText: role("on_surface", dark ? "#f5f5f7" : "#1c1c1e")
        readonly property color secondaryText: role("on_surface_variant", dark ? "#98989d" : "#6d6d72")
        readonly property color tertiaryText: role("outline", dark ? "#8e8e93" : "#8e8e93")
        readonly property color card: role("surface_container", dark ? "#1c1c1e" : "#ffffff")
        readonly property color separator: role("outline_variant", dark ? "#38383a" : "#e5e5ea")
        readonly property color divider: role("outline_variant", dark ? "#2c2c2e" : "#d1d1d6")
        readonly property color searchField: role("surface_container_high", dark ? "#2c2c2e" : "#e3e3e8")
        readonly property color selected: role("primary", dark ? "#0a84ff" : "#d9e9ff")
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
        readonly property color selectedForeground: role("on_secondary_container", dark ? "#ffffff" : "#00325b")
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
            subtitle: I18n.tr("Show"),
            groups: []
        },
        {
            subtitle: I18n.tr("Theme"),
            groups: []
        },
        {
            subtitle: I18n.tr("Top bar"),
            groups: []
        },
        {
            subtitle: "Dock",
            groups: []
        },
        {
            subtitle: I18n.tr("Launcher"),
            groups: []
        },
        {
            subtitle: I18n.tr("Shortcuts"),
            groups: []
        },
        {
            subtitle: I18n.tr("Integration status"),
            groups: []
        },
        {
            subtitle: I18n.tr("Glass debugging"),
            groups: []
        },
        {
            subtitle: I18n.tr("Wallpaper"),
            groups: []
        },
        {
            subtitle: I18n.tr("Services and components"),
            groups: []
        },
        {
            subtitle: I18n.tr("Stage scheduling"),
            groups: []
        },
        { subtitle: I18n.tr("Windows and animations"), groups: [] },
        { subtitle: I18n.tr("Notifications"), groups: [] }
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

    component SettingIcon: Rectangle {
        required property string symbol
        required property color tint
        property bool highlighted: false
        // Content-page icons keep the designed 29px; the sidebar hands in 18 so
        // the chip matches the 13px label's line height instead of towering
        // over it. Radius and glyph scale off the size so both stay proportioned.
        property int size: 29
        readonly property bool flat: window.materialForm
        width: size
        height: size
        radius: flat ? 0 : size * 0.345
        color: flat ? "transparent" : tint
        LiquidControls.VectorIcon {
            anchors.centerIn: parent
            size: Math.round(parent.size * 0.58)
            name: ({"◈":"theme", "◇":"theme", "▧":"wallpaper", "⎍":"panel",
                "▰":"dock", "▭":"dock", "▣":"panel", "▦":"grid", "❖":"grid",
                "⌘":"keyboard", "✓":"check", "⚙":"settings", "♲":"trash",
                "↔":"arrows", "◉":"circle", "◌":"circle", "●":"circle",
                "◐":"contrast", "◔":"contrast", "◒":"contrast", "≈":"waves",
                "≋":"waves", "⧉":"copy", "⌂":"home", "⌕":"search",
                "⇲":"resize", "↺":"undo", "B":"bold",
                "▢":"corners", "◧":"shadow", "↓":"minimize", "×":"close"})[parent.symbol] || "settings"
            color: parent.flat
                ? (parent.highlighted ? theme.selectedForeground : theme.iconMuted)
                : theme.iconForeground
        }
    }

    component SidebarEntry: ItemDelegate {
        required property int pageIndex
        required property string label
        required property string navSymbol
        required property color navTint
        width: parent ? parent.width : 0
        // Compact rows: 28 (user-picked) pulls the titles tight; the icon (18)
        // sits level with the 14px label.
        height: 28
        leftPadding: 10
        rightPadding: 10
        highlighted: window.currentPage === pageIndex
        visible: window.searchText.length === 0
            || label.toLowerCase().indexOf(window.searchText.toLowerCase()) >= 0
        background: Rectangle {
            // M3's drawer items are full-round pills that carry selection in
            // secondaryContainer; the iPadOS form keeps its squircle of tinted
            // wash.
            radius: height / 2
            color: parent.highlighted
                ? (window.materialForm ? theme.selectedContainer : theme.selected)
                : (parent.hovered ? theme.sidebarHover : "transparent")
        }
        contentItem: Item {
            implicitHeight: 28
            SettingIcon {
                id: sidebarIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                symbol: navSymbol
                tint: navTint
                highlighted: window.currentPage === pageIndex
            }
            Text {
                anchors.left: sidebarIcon.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: label
                color: window.currentPage === pageIndex
                    && window.materialForm ? theme.selectedForeground : theme.primaryText
                font.pixelSize: 14
                font.weight: window.materialForm
                    ? (window.currentPage === pageIndex ? Font.DemiBold : Font.Medium)
                    : (window.currentPage === pageIndex ? Font.Bold : Font.Medium)
                elide: Text.ElideRight
            }
        }
        onClicked: window.currentPage = pageIndex
    }

    // One visual contract for every segmented choice in Settings. Individual
    // rows only provide model/currentIndex and content-driven width overrides.
    component SettingsNavBar: LiquidControls.LiquidNavBar {
        size: "tiny"
        accentColor: theme.role("primary", theme.dark ? "#64b5ff" : "#0066cc")
        selectedItemColor: window.materialForm
            ? theme.role("on_primary", "#ffffff") : accentColor
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

    // 滑杆行：拖动即时预览、松手才提交（LiquidSlider preview/commit 模型）。
    // current 绑定 IPC 快照值；提交后快照回读，_preview 归位。
    // （inline component 不能嵌套，放页面组件外层）
    component StageSliderRow: RowLayout {
        id: sliderRow
        property string label: ""
        property string unit: ""
        property real minV: 0
        property real maxV: 100
        property real current: 0
        // 小数位（0 = 整数步进与显示，现状；>0 用于倍率类参数如悬停放大）
        property int decimals: 0
        property bool active: true
        property var onCommit: null
        property real _preview: -1
        readonly property real _shown: _preview >= 0 ? _preview : current

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: sliderRow.label
            color: sliderRow.active ? theme.primaryText : theme.secondaryText
            font.pixelSize: 13
            Layout.preferredWidth: 148
        }
        Text {
            text: sliderRow.decimals > 0
                ? sliderRow._shown.toFixed(sliderRow.decimals) + sliderRow.unit
                : Math.round(sliderRow._shown) + sliderRow.unit
            color: theme.secondaryText
            font.pixelSize: 12
            Layout.preferredWidth: 46
            horizontalAlignment: Text.AlignRight
        }
        LiquidControls.LiquidSlider {
            accentColor: theme.accent
            trackColor: theme.divider
            Layout.fillWidth: true
            opacity: sliderRow.active ? 1.0 : 0.4
            enabled: sliderRow.active
            // Ctrl+滚轮一档 = 一个能显示出来的单位（整数就 1，小数按 decimals），
            // 换成归一化行程。倍率这类窄区间（0.9~1.1）才不会每档都被舍掉。
            wheelStep: {
                const span = sliderRow.maxV - sliderRow.minV
                if (span <= 0)
                    return 0.01
                const unit = sliderRow.decimals > 0
                    ? Math.pow(10, -sliderRow.decimals) : 1
                return Math.min(1, unit / span)
            }
            value: sliderRow.maxV > sliderRow.minV
                ? (sliderRow._shown - sliderRow.minV)
                  / (sliderRow.maxV - sliderRow.minV) : 0
            onPreviewChanged: function(position) {
                sliderRow._preview = sliderRow.minV
                    + position * (sliderRow.maxV - sliderRow.minV)
            }
            onCommitRequested: function(position) {
                sliderRow._preview = -1
                if (sliderRow.onCommit) {
                    const v = sliderRow.minV
                        + position * (sliderRow.maxV - sliderRow.minV)
                    sliderRow.onCommit(sliderRow.decimals > 0
                        ? Number(v.toFixed(sliderRow.decimals))
                        : Math.round(v))
                }
            }
        }
    }

    // ── 台前调度（fg-sched）页 ──────────────────────────────────────
    // 冻结默认全面停用：后台只做资源限制（nice/效率核/IO，异构才限核）。本页管理：
    // ① 冻结开关（重开时最小化窗口 180s 后 SIGSTOP）
    // ② "后台全资源运行"名单（never_demote_apps——名单内应用切后台后
    //    保持前台档参数，不降级不限核）
    // ③ 台前侧栏与切换动画的全部可调参数（stage-config IPC 实时生效）
    // 资源配置写 ~/.config/fg-sched/config.json，root 守护 mtime 轮询 ≤5s
    // 生效；动画/侧栏参数走 shell 的 stage-config IPC，即时生效。
    component FgSchedSettingsPage: ColumnLayout {
        id: fgSchedPage

        Layout.fillWidth: true
        spacing: 8
        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property var snapshot: ({})
        property var stageSnapshot: ({})
        property var runningApps: []
        property string newApp: ""

        // 类名 → 人类可读名（运行清单里查得到就显示应用名）
        function appNameFor(cls) {
            const apps = runningApps
            for (let i = 0; i < apps.length; i++) {
                if (apps[i].appId === cls)
                    return apps[i].name
            }
            return cls
        }

        function stageSet(key, value) {
            if (bridge)
                bridge.stageConfigSet(key, String(value))
        }

        // ── 台前侧栏简单面：3 预设 + 3 主参数；全量参数收进「高级自定义」──
        property bool stageAdvanced: false

        readonly property var stagePresets: [
            { id: "lite", name: I18n.tr("Lithe"), detail: I18n.tr("Compact cards · slight tilt · crisp motion"),
              values: { cardHeight: 145, cardSpacing: 14, tiltAngle: 16,
                        deckRestTilt: 16, hoverScale: 1.0,
                        cardEnterDuration: 190, tiltAnimDuration: 220,
                        animDuration: 340, cardGlow: 0.08, cardDepth: 0.28 } },
            { id: "standard", name: I18n.tr("Standard"), detail: I18n.tr("Medium cards · moderate tilt · balanced motion"),
              values: { cardHeight: 170, cardSpacing: 20, tiltAngle: 28,
                        deckRestTilt: 28, hoverScale: 1.0,
                        cardEnterDuration: 240, tiltAnimDuration: 280,
                        animDuration: 400, cardGlow: 0.14, cardDepth: 0.40 } },
            // 「立体」= 用户 2026-09-30 定稿手感（204/28/40×2，悬停放大关）
            { id: "vivid", name: I18n.tr("Dimensional"), detail: I18n.tr("Large cards · strong tilt · relaxed motion"),
              values: { cardHeight: 204, cardSpacing: 28, tiltAngle: 40,
                        deckRestTilt: 40, hoverScale: 1.0,
                        cardEnterDuration: 280, tiltAnimDuration: 340,
                        animDuration: 430, cardGlow: 0.20, cardDepth: 0.50 } },
        ]

        // 预设命中 = 全部键与当前快照一致（拖过主参数/高级项即脱离高亮）
        function stagePresetActive(p): bool {
            const s = stageSnapshot
            for (const k in p.values)
                if (s[k] !== p.values[k])
                    return false
            return true
        }

        function stageApplyPreset(p) {
            for (const k in p.values)
                stageSet(k, p.values[k])
        }

        function refresh() {
            if (!bridge)
                return
            bridge.fgSchedSnapshot()
            bridge.fgSchedRunningApps()
            bridge.fgSchedMemStatus()
            bridge.stageConfigSnapshot()
        }

        function gb(kb) {
            return (kb / 1048576).toFixed(1) + " GB"
        }

        Connections {
            target: fgSchedPage.bridge
            enabled: fgSchedPage.bridge !== null
            function onFgSchedSnapshotChanged(snap) {
                fgSchedPage.snapshot = snap || {}
            }
            function onFgSchedRunningAppsChanged(apps) {
                fgSchedPage.runningApps = apps || []
            }
            function onFgSchedMemStatusChanged(st) {
                fgSchedPage.memStatus = st || {}
            }
            function onStageConfigChanged(snap) {
                fgSchedPage.stageSnapshot = snap || {}
            }
        }

        property var memStatus: ({})

        // 内存状态 5s 轮询（页面激活期间）；顺带回读 fg-sched 快照——
        // stage-mode flag 会被 shell 单独改写（重启对齐/控制中心开关），
        // 纯事件驱动的快照会陈旧，轻量轮询（本地文件读取，无 IPC）兜底
        Timer {
            interval: 5000
            repeat: true
            running: fgSchedPage.bridge !== null
            onTriggered: {
                if (fgSchedPage.bridge === null)
                    return
                fgSchedPage.bridge.fgSchedMemStatus()
                fgSchedPage.bridge.fgSchedSnapshot()
            }
        }

        Component.onCompleted: refresh()

        // ── 说明卡 ──
        Rectangle {
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: introColumn.implicitHeight + 32

            ColumnLayout {
                id: introColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 4

                Text {
                    text: I18n.tr("Stage scheduling")
                    color: theme.primaryText
                    font { pixelSize: 15; weight: Font.DemiBold }
                }
                Text {
                    Layout.fillWidth: true
                    text: !fgSchedPage.snapshot.resourceSchedulingAvailable
                        ? I18n.tr("The stage sidebar works on its own. Resource scheduling additionally requires fg-schedd to be installed and running; it was not detected.")
                        : I18n.tr("While the external scheduler daemon runs, foreground apps get high CPU priority and kill protection; 10 seconds after going to the background ")
                          + I18n.tr("Lower resource priority automatically (nice ")
                          + (fgSchedPage.snapshot.bgNice !== undefined ? "+" + fgSchedPage.snapshot.bgNice : "+5")
                          + I18n.tr(" and disk I/O is lowered in priority")
                          + I18n.tr("; on hybrid CPUs background is limited to efficiency cores automatically).")
                          + I18n.tr("Apps on the list stay at full speed in the background. Changes apply within about 5 seconds.")
                    color: theme.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 台前侧栏（开关 + 侧栏卡动效，全部即时生效） ──
        Rectangle {
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: stageColumn.implicitHeight + 32

            ColumnLayout {
                id: stageColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Stage sidebar")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Enable stage-manager sidebar")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("A window-card rail docked to the screen edge (left/right): tap a card to promote it, collected apps shrink into glass cards")
                                  + I18n.tr(" (also toggleable from the control center in the top right).")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.snapshot.stageEnabled === true
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.bridge.stageSidebarSet(checked)
                            // 开关自持；快照回读经完好绑定回写（原"回读
                            // 确认"行是参数遮蔽 no-op，已删——勿改写成对
                            // checked 属性赋值，会砸掉绑定）
                        }
                    }
                }

                // ── 风格预设：一键套用整组观感（三张等宽卡） ──
                Text {
                    text: I18n.tr("Style preset")
                    color: theme.primaryText
                    font { pixelSize: 13; weight: Font.Medium }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: fgSchedPage.stagePresets

                        delegate: Rectangle {
                            id: presetCard
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: presetColumn.implicitHeight + 20
                            radius: 12
                            property bool isActive:
                                fgSchedPage.stagePresetActive(modelData)
                            color: isActive
                                ? theme.selectedContainer
                                : (presetMouse.containsMouse
                                    ? theme.searchField : theme.sidebar)
                            border.width: isActive ? 2 : 0
                            border.color: theme.accent

                            ColumnLayout {
                                id: presetColumn
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                anchors.margins: 10
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: presetCard.modelData.name
                                    color: presetCard.isActive
                                        ? theme.selectedForeground
                                        : theme.primaryText
                                    font { pixelSize: 13; weight: Font.Medium }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: presetCard.modelData.detail
                                    color: theme.secondaryText
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                id: presetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.stageApplyPreset(
                                    presetCard.modelData)
                            }
                        }
                    }
                }

                // ── 快速调节：三个主参数（其余全在高级自定义） ──
                StageSliderRow {
                    label: I18n.tr("Card size")
                    unit: " px"
                    minV: 100
                    maxV: 220
                    current: fgSchedPage.stageSnapshot.cardHeight !== undefined
                        ? fgSchedPage.stageSnapshot.cardHeight : 148
                    onCommit: function(v) { fgSchedPage.stageSet("cardHeight", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Card width")
                    unit: " px"
                    minV: 120
                    maxV: 320
                    active: true
                    current: fgSchedPage.stageSnapshot.cardWidth !== undefined
                        ? fgSchedPage.stageSnapshot.cardWidth : 216
                    onCommit: function(v) { fgSchedPage.stageSet("cardWidth", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Tilt strength")
                    unit: "°"
                    minV: 0
                    maxV: 40
                    decimals: 1
                    // 读当前模式的"活键"：scroll 的可见倾角是静置倾斜角，
                    // adaptive 才是悬停倾角——读另一个会"拖了没反应/反应
                    // 减半"。写两键同值（用户手感即两键同档，不分静置/悬停）
                    current: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                        ? (fgSchedPage.stageSnapshot.tiltAngle !== undefined
                            ? fgSchedPage.stageSnapshot.tiltAngle : 22)
                        : (fgSchedPage.stageSnapshot.deckRestTilt !== undefined
                            ? fgSchedPage.stageSnapshot.deckRestTilt : 10)
                    onCommit: function(v) {
                        fgSchedPage.stageSet("tiltAngle", v)
                        fgSchedPage.stageSet("deckRestTilt", v)
                    }
                }

                StageSliderRow {
                    label: I18n.tr("Motion speed")
                    unit: "×"
                    minV: 0.5
                    maxV: 1.6
                    decimals: 2
                    // 倍率对**当前值**等比缩放（factor = 新倍率/当前倍率）：
                    // 保留用户调过的三个时长配比；锚点 240 只是显示基准。
                    // 三个目标值先从同一份快照取齐再写，防逐键回读互相污染
                    current: (fgSchedPage.stageSnapshot.cardEnterDuration !== undefined
                        ? fgSchedPage.stageSnapshot.cardEnterDuration : 240) / 240
                    onCommit: function(v) {
                        const s = fgSchedPage.stageSnapshot
                        const enter = s.cardEnterDuration !== undefined
                            ? s.cardEnterDuration : 240
                        const tilt = s.tiltAnimDuration !== undefined
                            ? s.tiltAnimDuration : 250
                        const win = s.animDuration !== undefined
                            ? s.animDuration : 420
                        const f = enter > 0 ? v / (enter / 240) : 1
                        fgSchedPage.stageSet("cardEnterDuration",
                            Math.round(enter * f))
                        fgSchedPage.stageSet("tiltAnimDuration",
                            Math.round(tilt * f))
                        fgSchedPage.stageSet("animDuration",
                            Math.round(win * f))
                    }
                }

                // ── 高级自定义：现有全量参数的入口 ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Advanced customization")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Expand all parameters: layout and position, gesture and motion details, glass texture, ")
                                  + I18n.tr("collect timing and window-switch animations.")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.stageAdvanced
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageAdvanced = checked
                        }
                    }
                }

                // ── 全量参数（默认折叠；上面的预设/主参数即本组的高层快捷方式） ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: fgSchedPage.stageAdvanced
                    spacing: 10

                    // adaptive 专属（scroll 模式下不生效，按模式禁用防"调了没反应"）；
                    // 上限 40 = 特效 stageanim 的钳位（>40° 顶点镜像），schema 同步
                    StageSliderRow {
                        label: I18n.tr("Card tilt angle")
                    unit: "°"
                    minV: 0
                    maxV: 40
                    decimals: 1
                    active: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                    current: fgSchedPage.stageSnapshot.tiltAngle !== undefined
                        ? fgSchedPage.stageSnapshot.tiltAngle : 22
                    onCommit: function(v) { fgSchedPage.stageSet("tiltAngle", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Card spacing")
                    unit: " px"
                    minV: 4
                    maxV: 48
                    current: fgSchedPage.stageSnapshot.cardSpacing !== undefined
                        ? fgSchedPage.stageSnapshot.cardSpacing : 16
                    onCommit: function(v) { fgSchedPage.stageSet("cardSpacing", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Card height")
                    unit: " px"
                    minV: 100
                    maxV: 220
                    current: fgSchedPage.stageSnapshot.cardHeight !== undefined
                        ? fgSchedPage.stageSnapshot.cardHeight : 148
                    onCommit: function(v) { fgSchedPage.stageSet("cardHeight", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Hover zoom")
                    unit: "×"
                    minV: 1.0
                    maxV: 1.2
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.hoverScale !== undefined
                        ? fgSchedPage.stageSnapshot.hoverScale : 1.05
                    onCommit: function(v) { fgSchedPage.stageSet("hoverScale", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Click response delay")
                    unit: " ms"
                    minV: 60
                    maxV: 500
                    current: fgSchedPage.stageSnapshot.engageDelay !== undefined
                        ? fgSchedPage.stageSnapshot.engageDelay : 170
                    onCommit: function(v) { fgSchedPage.stageSet("engageDelay", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Hover dwell")
                    unit: " ms"
                    minV: 0
                    maxV: 800
                    current: fgSchedPage.stageSnapshot.hoverDwellDelay !== undefined
                        ? fgSchedPage.stageSnapshot.hoverDwellDelay : 200
                    onCommit: function(v) { fgSchedPage.stageSet("hoverDwellDelay", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Card entrance motion")
                    unit: " ms"
                    minV: 100
                    maxV: 800
                    current: fgSchedPage.stageSnapshot.cardEnterDuration !== undefined
                        ? fgSchedPage.stageSnapshot.cardEnterDuration : 240
                    onCommit: function(v) { fgSchedPage.stageSet("cardEnterDuration", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Tilt motion")
                    unit: " ms"
                    minV: 100
                    maxV: 800
                    current: fgSchedPage.stageSnapshot.tiltAnimDuration !== undefined
                        ? fgSchedPage.stageSnapshot.tiltAnimDuration : 250
                    onCommit: function(v) { fgSchedPage.stageSet("tiltAnimDuration", v) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Auto-collect background windows")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("After switching the active window, non-active windows are minimized into the sidebar automatically")
                                  + I18n.tr(" (windows of the same app are exempt).")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.stageSnapshot.autoMinimize !== false
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageSet("autoMinimize", checked)
                        }
                    }
                }

                StageSliderRow {
                    label: I18n.tr("Auto-collect delay")
                    unit: " ms"
                    minV: 200
                    maxV: 3000
                    active: fgSchedPage.stageSnapshot.autoMinimize !== false
                    current: fgSchedPage.stageSnapshot.autoMinDelay !== undefined
                        ? fgSchedPage.stageSnapshot.autoMinDelay : 650
                    onCommit: function(v) { fgSchedPage.stageSet("autoMinDelay", v) }
                }

                // （「保留侧栏条」开关已删：全屏浮层化后卡片恒为纯悬浮，
                // 该键零消费点，翻动只改 config 死值——schema 键保留兼容）

                Text {
                    text: I18n.tr("Card layout")
                    color: theme.primaryText
                    font.pixelSize: 13
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "scroll", label: I18n.tr("Continuous scrolling (default)"),
                              detail: I18n.tr("Cards shown in full and never overlapping; laid out with fixed spacing, scrolling continuously when they exceed the sidebar (position dots + window count at the bottom)") },
                            { id: "adaptive", label: I18n.tr("Adaptive shrink"),
                              detail: I18n.tr("All cards shown in full, scaling down as window count grows") },
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: layoutLabel.implicitWidth + 22
                            height: 28
                            radius: 9
                            property bool isActive: fgSchedPage.stageSnapshot.layoutMode === modelData.id
                            color: isActive
                                ? theme.selectedContainer
                                : (layoutMouse.containsMouse
                                    ? theme.searchField : theme.sidebar)
                            border.width: isActive ? 2 : 0
                            border.color: theme.accent

                            Text {
                                id: layoutLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.isActive
                                    ? theme.selectedForeground : theme.primaryText
                                font { pixelSize: 12; weight: Font.Medium }
                            }

                            MouseArea {
                                id: layoutMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.stageSet(
                                    "layoutMode", modelData.id)
                            }
                        }
                    }
                }

                Text {
                    text: I18n.tr("Sidebar position")
                    color: theme.primaryText
                    font.pixelSize: 13
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "left", label: I18n.tr("Left of screen (default)") },
                            { id: "right", label: I18n.tr("Right of screen") },
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: sideLabel.implicitWidth + 22
                            height: 28
                            radius: 9
                            property bool isActive: fgSchedPage.stageSnapshot.side === modelData.id
                            color: isActive
                                ? theme.selectedContainer
                                : (sideMouse.containsMouse
                                    ? theme.searchField : theme.sidebar)
                            border.width: isActive ? 2 : 0
                            border.color: theme.accent

                            Text {
                                id: sideLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.isActive
                                    ? theme.selectedForeground : theme.primaryText
                                font { pixelSize: 12; weight: Font.Medium }
                            }

                            MouseArea {
                                id: sideMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.stageSet(
                                    "side", modelData.id)
                            }
                        }
                    }
                }

                StageSliderRow {
                    label: I18n.tr("Merged card fan spacing")
                    unit: " px"
                    minV: 2
                    maxV: 24
                    active: true
                    current: fgSchedPage.stageSnapshot.fanSpacing !== undefined
                        ? fgSchedPage.stageSnapshot.fanSpacing : 8
                    onCommit: function(v) { fgSchedPage.stageSet("fanSpacing", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Fan spread on hover")
                    unit: " ×"
                    minV: 1.0
                    maxV: 2.0
                    decimals: 2
                    active: true
                    // 悬停/武装时扇叠间距的扩散系数（1.0=不扩散）；
                    // 静态快照与实时直绘两模式同源生效
                    current: fgSchedPage.stageSnapshot.fanHoverSpread !== undefined
                        ? fgSchedPage.stageSnapshot.fanHoverSpread : 1.4
                    onCommit: function(v) {
                        fgSchedPage.stageSet("fanHoverSpread", v)
                    }
                }

                StageSliderRow {
                    label: I18n.tr("Bottom-left icon size")
                    unit: " px"
                    minV: 16
                    maxV: 40
                    active: true
                    current: fgSchedPage.stageSnapshot.stripIconSize !== undefined
                        ? fgSchedPage.stageSnapshot.stripIconSize : 24
                    onCommit: function(v) { fgSchedPage.stageSet("stripIconSize", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Max icons per row")
                    unit: I18n.tr(" items")
                    minV: 3
                    maxV: 8
                    active: true
                    current: fgSchedPage.stageSnapshot.maxIconSlots !== undefined
                        ? fgSchedPage.stageSnapshot.maxIconSlots : 5
                    onCommit: function(v) { fgSchedPage.stageSet("maxIconSlots", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Merge dwell time")
                    unit: " ms"
                    minV: 200
                    maxV: 1200
                    active: true
                    current: fgSchedPage.stageSnapshot.mergeDwellMs !== undefined
                        ? fgSchedPage.stageSnapshot.mergeDwellMs : 450
                    onCommit: function(v) { fgSchedPage.stageSet("mergeDwellMs", v) }
                }

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: I18n.tr("Show card titles")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Off = immersive thumbnails: the card shows only window content without the title (the close button stays on hover)")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.stageSnapshot.showCardTitle !== false
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageSet("showCardTitle", checked)
                        }
                    }
                }

                StageSliderRow {
                    label: I18n.tr("Rest tilt angle")
                    unit: "°"
                    minV: 0
                    maxV: 40
                    decimals: 1
                    active: fgSchedPage.stageSnapshot.layoutMode === "scroll"
                    current: fgSchedPage.stageSnapshot.deckRestTilt !== undefined
                        ? fgSchedPage.stageSnapshot.deckRestTilt : 10
                    onCommit: function(v) { fgSchedPage.stageSet("deckRestTilt", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Retreat distance")
                    unit: " px"
                    minV: 4
                    maxV: 60
                    active: fgSchedPage.stageSnapshot.layoutMode === "scroll"
                    current: fgSchedPage.stageSnapshot.deckSidePeek !== undefined
                        ? fgSchedPage.stageSnapshot.deckSidePeek : 20
                    onCommit: function(v) { fgSchedPage.stageSet("deckSidePeek", v) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Dim retreated cards on focus")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Dim retreated cards on hover focus to emphasize the main one; off keeps them at normal brightness.")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.stageSnapshot.focusDim === true
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageSet("focusDim", checked)
                        }
                    }
                }

                // adaptive 专属（scroll 模式下卡在槽内本就居中，禁用防误导）
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    opacity: fgSchedPage.stageSnapshot.layoutMode === "adaptive" ? 1.0 : 0.45

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Center cards vertically")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Adaptive: cards center vertically when they fit; anchored to the top when full.")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        enabled: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                        checked: fgSchedPage.stageSnapshot.centerCards !== false
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageSet("centerCards", checked)
                        }
                    }
                }

                // ── 卡面画面模式（两态）：静态快照（关）/ 实时·合成器
                //    直绘（开）。遗留 PipeWire 流实验路径已从面板移除
                //   （本机触发宿主杀桌面；代码保留给强硬件、仅 IPC 可达），
                //    配置层互斥仍在 ──
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Card content mode — current: ")
                        + (fgSchedPage.stageSnapshot.thumbLiveEffect === true
                            ? I18n.tr("Live (compositor-drawn, window content keeps updating)")
                            : I18n.tr("Static snapshot (captured on collect; stable and power-efficient)"))
                    color: theme.accent
                    font { pixelSize: 12; weight: Font.Medium }
                    wrapMode: Text.WordWrap
                }

                // 合成器活体卡（stageanim 直绘）：隐藏窗经 KWin 离屏帧
                // 回调继续出帧（成本=窗口可见在桌面，无 screencast 管线），
                // 特效把窗口纹理按卡面透视直接画进卡里——所有卡常开实时
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: I18n.tr("Live cards (compositor-drawn)")
                            color: theme.primaryText
                            font { pixelSize: 13; weight: Font.Medium }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: I18n.tr("Windows collected into cards show their content live (video/terminal output keeps updating). Uses the compositor direct-draw path (no PipeWire); overhead only occurs when window content updates, comparable to keeping those apps on the desktop. Falls back to static snapshots automatically if effects are unavailable.")
                            color: theme.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    LiquidControls.LiquidGlassSwitch {
                        checked: fgSchedPage.stageSnapshot.thumbLiveEffect === true
                        accentColor: theme.accent
                        trackColor: theme.divider
                        onToggled: function(checked) {
                            fgSchedPage.stageSet("thumbLiveEffect", checked)
                        }
                    }
                }


                }
            }
        }

        // ── 玻璃质感（卡面：圆角/背板/受光/描边/辉光/纵深/缩略图清晰度；
        //     高级自定义的一部分，默认折叠） ──
        Rectangle {
            Layout.fillWidth: true
            visible: fgSchedPage.stageAdvanced
            radius: 14
            color: theme.card
            implicitHeight: glassColumn.implicitHeight + 32

            ColumnLayout {
                id: glassColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Glass texture")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }

                StageSliderRow {
                    label: I18n.tr("Card corner radius")
                    unit: " px"
                    minV: 0
                    maxV: 24
                    current: fgSchedPage.stageSnapshot.cardRadius !== undefined
                        ? fgSchedPage.stageSnapshot.cardRadius : 14
                    onCommit: function(v) { fgSchedPage.stageSet("cardRadius", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Backdrop density")
                    unit: ""
                    minV: 0.2
                    maxV: 0.95
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.cardTint !== undefined
                        ? fgSchedPage.stageSnapshot.cardTint : 0.55
                    onCommit: function(v) { fgSchedPage.stageSet("cardTint", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Top-lit")
                    unit: ""
                    minV: 0
                    maxV: 0.3
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.cardTopLight !== undefined
                        ? fgSchedPage.stageSnapshot.cardTopLight : 0.07
                    onCommit: function(v) { fgSchedPage.stageSet("cardTopLight", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Outline brightness")
                    unit: ""
                    minV: 0
                    maxV: 0.4
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.cardBorder !== undefined
                        ? fgSchedPage.stageSnapshot.cardBorder : 0.13
                    onCommit: function(v) { fgSchedPage.stageSet("cardBorder", v) }
                }

                StageSliderRow {
                    // 辉光是静态快照的扇叠背板效果（实时直绘模式无辉光
                    // pass，v57 撤）——实时模式下隐藏防"拖了没反应"
                    visible: fgSchedPage.stageSnapshot.thumbLiveEffect !== true
                    label: I18n.tr("Focus glow strength (static mode)")
                    unit: ""
                    minV: 0
                    maxV: 0.4
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.cardGlow !== undefined
                        ? fgSchedPage.stageSnapshot.cardGlow : 0.13
                    onCommit: function(v) { fgSchedPage.stageSet("cardGlow", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Depth dimming")
                    unit: ""
                    minV: 0
                    maxV: 0.6
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.cardDepth !== undefined
                        ? fgSchedPage.stageSnapshot.cardDepth : 0.38
                    onCommit: function(v) { fgSchedPage.stageSet("cardDepth", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Thumbnail sharpness")
                    unit: " px"
                    minV: 160
                    maxV: 640
                    current: fgSchedPage.stageSnapshot.thumbSize !== undefined
                        ? fgSchedPage.stageSnapshot.thumbSize : 320
                    onCommit: function(v) { fgSchedPage.stageSet("thumbSize", v) }
                }
            }
        }

        // ── 收编与刷新节拍（收编两拍延迟 / 桌面去抖 / 实时刷新间隔；
        //     高级自定义的一部分，默认折叠） ──
        Rectangle {
            Layout.fillWidth: true
            visible: fgSchedPage.stageAdvanced
            radius: 14
            color: theme.card
            implicitHeight: demoteColumn.implicitHeight + 32

            ColumnLayout {
                id: demoteColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Collect and refresh timing")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }

                StageSliderRow {
                    label: I18n.tr("Collect snapshot wait")
                    unit: " ms"
                    minV: 100
                    maxV: 1500
                    current: fgSchedPage.stageSnapshot.demoteCaptureDelay !== undefined
                        ? fgSchedPage.stageSnapshot.demoteCaptureDelay : 300
                    onCommit: function(v) { fgSchedPage.stageSet("demoteCaptureDelay", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Collect dispatch delay")
                    unit: " ms"
                    minV: 10
                    maxV: 200
                    current: fgSchedPage.stageSnapshot.demoteDispatchDelay !== undefined
                        ? fgSchedPage.stageSnapshot.demoteDispatchDelay : 30
                    onCommit: function(v) { fgSchedPage.stageSet("demoteDispatchDelay", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Desktop collect debounce")
                    unit: " ms"
                    minV: 50
                    maxV: 1000
                    current: fgSchedPage.stageSnapshot.desktopFocusDebounce !== undefined
                        ? fgSchedPage.stageSnapshot.desktopFocusDebounce : 150
                    onCommit: function(v) { fgSchedPage.stageSet("desktopFocusDebounce", v) }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Two-phase collect: wait for the snapshot first (multi-window captures take time), persist the rectangles, then dispatch the minimization")
                          + I18n.tr(" (matched against the expand animation).")
                    color: theme.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 窗口切换动画（时长 + 缓动曲线，reconfigure 即时生效；
        //     高级自定义的一部分，默认折叠） ──
        Rectangle {
            Layout.fillWidth: true
            visible: fgSchedPage.stageAdvanced
            radius: 14
            color: theme.card
            implicitHeight: animColumn.implicitHeight + 32

            ColumnLayout {
                id: animColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Window switch animation")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }

                StageSliderRow {
                    label: I18n.tr("Animation duration")
                    unit: " ms"
                    minV: 120
                    maxV: 2000
                    current: fgSchedPage.stageSnapshot.animDuration !== undefined
                        ? fgSchedPage.stageSnapshot.animDuration : 420
                    onCommit: function(v) { fgSchedPage.stageSet("animDuration", v) }
                }

                StageSliderRow {
                    label: I18n.tr("Flying glass opacity")
                    unit: "×"
                    minV: 0.3
                    maxV: 1.0
                    decimals: 2
                    current: fgSchedPage.stageSnapshot.glassOpacity !== undefined
                        ? fgSchedPage.stageSnapshot.glassOpacity : 0.65
                    onCommit: function(v) { fgSchedPage.stageSet("glassOpacity", v) }
                }

                Text {
                    text: I18n.tr("Easing curve")
                    color: theme.primaryText
                    font.pixelSize: 13
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "OutCubic", label: I18n.tr("Fast out, gentle stop (default)") },
                            { id: "OutQuad", label: I18n.tr("Gentler") },
                            { id: "InOutCubic", label: I18n.tr("Slow-fast-slow") },
                            { id: "OutBack", label: I18n.tr("End overshoot") },
                            { id: "InOutQuad", label: I18n.tr("Soft edges") },
                            { id: "Linear", label: I18n.tr("Linear") },
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: curveLabel.implicitWidth + 22
                            height: 28
                            radius: 9
                            property bool isActive: fgSchedPage.stageSnapshot.animEasing === modelData.id
                            color: isActive
                                ? theme.selectedContainer
                                : (curveMouse.containsMouse
                                    ? theme.searchField : theme.sidebar)
                            border.width: isActive ? 2 : 0
                            border.color: theme.accent

                            Text {
                                id: curveLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.isActive
                                    ? theme.selectedForeground : theme.primaryText
                                font { pixelSize: 12; weight: Font.Medium }
                            }

                            MouseArea {
                                id: curveMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.stageSet(
                                    "animEasing", modelData.id)
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Animation for windows growing out of / back into cards; duration and curve changes apply instantly, ")
                          + I18n.tr("Also adjustable temporarily via the stage-anim CLI. Flying glass opacity: ")
                          + I18n.tr("Windows are translucent mid-flight between card and desktop (desktop shows through), solidifying on landing; ")
                          + I18n.tr("1.00 disables the glass feel.")
                    color: theme.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 冻结开关 ──
        Rectangle {
            visible: fgSchedPage.snapshot.resourceSchedulingAvailable === true
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: freezeRow.implicitHeight + 32

            RowLayout {
                id: freezeRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Freeze minimized windows")
                        color: theme.primaryText
                        font { pixelSize: 14; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Suspends the whole tree after 3 minutes in the sidebar (saves CPU; restore may occasionally glitch).")
                            + I18n.tr("Off by default: the background is only resource-limited; processes are never frozen.")
                        color: theme.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    accentColor: theme.accent
                    checked: fgSchedPage.snapshot.freezeEnabled === true
                    onToggled: function(checked) {
                        fgSchedPage.bridge.fgSchedSetFreeze(checked)
                    }
                }
            }
        }

        // ── 后台内存节省 ──
        Rectangle {
            visible: fgSchedPage.snapshot.resourceSchedulingAvailable === true
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: reclaimColumn.implicitHeight + 32

            ColumnLayout {
                id: reclaimColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Background memory saving")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // 三档选择：关 / 标准 / 激进 / 极限
                    Repeater {
                        model: [
                            { id: "off", label: I18n.tr("Off"),
                              detail: I18n.tr("Leave background memory alone") },
                            { id: "once", label: I18n.tr("Standard"),
                              detail: I18n.tr("Compresses once after 60 seconds in the background (cold pages squeezed into zram; switching back is slightly slower)") },
                            { id: "aggressive", label: I18n.tr("Aggressive compression"),
                              detail: I18n.tr("Compresses continuously in the background (recompressed every 5 minutes), minimizing memory use") },
                            { id: "kill", label: I18n.tr("Extreme"),
                              detail: I18n.tr("Compresses continuously, then kills the app after 10 minutes in the background — memory goes to zero. Unsaved work is lost (browsers can restore sessions); add apps you want spared to the list below") }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: reclaimLabel.implicitHeight
                                + reclaimDetail.implicitHeight + 22
                            radius: 10
                            property bool isActive: fgSchedPage.snapshot.reclaimMode === modelData.id
                            color: isActive
                                ? theme.selectedContainer
                                : (reclaimMouse.containsMouse
                                    ? theme.searchField : theme.sidebar)
                            border.width: isActive ? 2 : 0
                            border.color: theme.accent

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 2

                                Text {
                                    id: reclaimLabel
                                    text: modelData.label
                                    color: parent.parent.isActive
                                        ? theme.selectedForeground : theme.primaryText
                                    font { pixelSize: 13; weight: Font.DemiBold }
                                }
                                Text {
                                    id: reclaimDetail
                                    Layout.fillWidth: true
                                    text: modelData.detail
                                    color: theme.secondaryText
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                id: reclaimMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.bridge.fgSchedSetReclaim(modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── 内存状态 ──
        Rectangle {
            visible: fgSchedPage.snapshot.resourceSchedulingAvailable === true
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: memColumn.implicitHeight + 32

            ColumnLayout {
                id: memColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: I18n.tr("Memory state")
                        color: theme.primaryText
                        font { pixelSize: 14; weight: Font.Medium }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: I18n.tr("Refresh")
                        color: fgSchedMemMouse.containsMouse
                            ? theme.accent : theme.secondaryText
                        font.pixelSize: 12

                        MouseArea {
                            id: fgSchedMemMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fgSchedPage.bridge.fgSchedMemStatus()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        const st = fgSchedPage.memStatus
                        if (st.memAvailableKb === undefined)
                            return I18n.tr("Reading…")
                        return I18n.tr("Available memory ") + fgSchedPage.gb(st.memAvailableKb)
                            + " / " + fgSchedPage.gb(st.memTotalKb)
                    }
                    color: theme.primaryText
                    font.pixelSize: 13
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        const st = fgSchedPage.memStatus
                        if (st.zramOrigKb === undefined)
                            return I18n.tr("zram compression pool is not readable")
                        const ratio = st.zramComprKb > 0
                            ? (st.zramOrigKb / st.zramComprKb).toFixed(1) : "—"
                        return I18n.tr("Compression pool (zram): compressed ") + fgSchedPage.gb(st.zramComprKb)
                            + I18n.tr(" (originally ") + fgSchedPage.gb(st.zramOrigKb)
                            + I18n.tr(", compression ratio ") + ratio + ":1）"
                    }
                    color: theme.secondaryText
                    font.pixelSize: 12
                }
                Text {
                    Layout.fillWidth: true
                    text: fgSchedPage.snapshot.reclaimMode === "kill"
                        ? I18n.tr("Extreme mode: background apps are compressed continuously, then killed after 10 minutes")
                          + I18n.tr(" (memory zeroed). Data safety relies on the app's own session restore; ")
                          + I18n.tr("Apps outside the exemption list are always killed — if it has unsaved work, add it to the ")
                          + I18n.tr("list below.")
                        : I18n.tr("Aggressive mode squeezes background apps' memory pages into the pool repeatedly: usage drops sharply, ")
                          + I18n.tr("The cost is a brief stall when switching back (pages are swapped in from the compression pool).")
                    color: fgSchedPage.snapshot.reclaimMode === "kill" ? "#ff9f0a" : theme.tertiaryText
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 后台全资源运行名单 ──
        Rectangle {
            visible: fgSchedPage.snapshot.resourceSchedulingAvailable === true
            Layout.fillWidth: true
            radius: 14
            color: theme.card
            implicitHeight: listColumn.implicitHeight + 32

            ColumnLayout {
                id: listColumn
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                Text {
                    text: I18n.tr("Full-resource background list")
                    color: theme.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Apps on the list keep full priority and cores in the background (for resident services, ")
                          + I18n.tr("for idle downloads or background agents). Fill in app class names")
                          + I18n.tr(" (e.g. org.kde.konsole), or pick from the apps seen below.")
                    color: theme.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                // 名单行
                Repeater {
                    model: fgSchedPage.snapshot.fullResources || []

                    delegate: RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            Layout.alignment: Qt.AlignVCenter
                            color: theme.accent
                        }
                        Text {
                            Layout.fillWidth: true
                            text: appNameFor(modelData)
                            color: theme.primaryText
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData
                            color: theme.tertiaryText
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 130
                        }
                        Text {
                            text: I18n.tr("Remove")
                            color: "#ff453a"
                            font.pixelSize: 12

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: fgSchedPage.bridge.fgSchedRemoveFull(parent.parent.modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: (fgSchedPage.snapshot.fullResources || []).length === 0
                    text: I18n.tr("List is empty: every app gets resource-limited in the background")
                    color: theme.tertiaryText
                    font.pixelSize: 12
                }

                // 分隔线
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: theme.separator
                }

                // 从当前运行的应用添加
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ComboBox {
                        id: knownAppsBox
                        Layout.fillWidth: true
                        model: fgSchedPage.runningApps
                        textRole: "name"
                        valueRole: "appId"
                        enabled: count > 0
                        displayText: count > 0
                            ? currentText : I18n.tr("Tap refresh on the right to scan currently running apps")
                        font.pixelSize: 12
                    }

                    Button {
                        text: fgSchedPage.runningApps.length > 0 ? I18n.tr("Add") : I18n.tr("Refresh")
                        enabled: fgSchedPage.runningApps.length === 0
                            || (knownAppsBox.count > 0
                                && knownAppsBox.currentValue !== undefined
                                && knownAppsBox.currentValue.length > 0)
                        onClicked: {
                            if (fgSchedPage.runningApps.length === 0) {
                                fgSchedPage.refresh()
                            } else if (knownAppsBox.currentValue) {
                                fgSchedPage.bridge.fgSchedAddFull(
                                            knownAppsBox.currentValue)
                            }
                        }
                    }
                }

                // 手动输入
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    TextField {
                        id: manualInput
                        Layout.fillWidth: true
                        placeholderText: I18n.tr("Type a class name manually, e.g. org.kde.konsole")
                        font.pixelSize: 12
                        onAccepted: {
                            if (text.trim().length > 0) {
                                fgSchedPage.bridge.fgSchedAddFull(text)
                                text = ""
                            }
                        }
                    }

                    Button {
                        text: I18n.tr("Add")
                        enabled: manualInput.text.trim().length > 0
                        onClicked: {
                            fgSchedPage.bridge.fgSchedAddFull(manualInput.text)
                            manualInput.text = ""
                        }
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 4 }
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
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            // The reply lands on integrationSnapshotChanged; the bridge does
            // its D-Bus and /proc probes off the UI thread now, so this page's
            // 5s poll no longer freezes anything.
            bridge.integrationSnapshot()
        }

        Connections {
            target: integrationPage.bridge
            enabled: integrationPage.bridge !== null
            function onIntegrationSnapshotChanged(state) {
                integrationPage.snapshot = state
                integrationPage.errorText = I18n.tr(integrationPage.bridge.lastError) || ""
            }
        }

        function notificationState() {
            const provider = snapshot.notificationProvider || "none"
            if (provider === "kos")
                return { label: I18n.tr("KOS has taken over"), color: "#30d158",
                    detail: I18n.tr("Notifications will appear in the KOS notification center") }
            if (provider === "plasma")
                return { label: I18n.tr("Plasma takeover"), color: "#ff9f0a",
                    detail: I18n.tr("KOS is waiting for the org.freedesktop.Notifications name") }
            if (provider === "other")
                return { label: I18n.tr("Another program has taken over"), color: "#ff9f0a",
                    detail: snapshot.notificationCommand || snapshot.notificationOwner || I18n.tr("Unknown notification service") }
            return { label: I18n.tr("Not registered"), color: "#ff453a",
                detail: I18n.tr("No desktop notification service available") }
        }

        function statusRow(icon, tint, title, ready, readyLabel, detail) {
            return { icon: icon, tint: tint, title: title,
                label: ready ? readyLabel : I18n.tr("Not connected"),
                color: ready ? "#30d158" : "#ff453a", detail: detail }
        }

        readonly property var notification: notificationState()
        readonly property var rows: [
            statusRow("K", "#0a84ff", "KOS Shell", !!snapshot.shellReady,
                I18n.tr("Running"), I18n.tr("Settings page and Quickshell IPC channel")),
            statusRow("↔", "#5ac8fa", I18n.tr("Platform bridge"), !!snapshot.platformConnected,
                I18n.tr("Connected"), I18n.tr("Windows, network, audio and system actions")),
            statusRow("D", "#34c759", I18n.tr("Data service"), !!snapshot.dataConnected,
                I18n.tr("Connected"), I18n.tr("System metrics, activity records and desktop files")),
            statusRow("▦", "#af52de", I18n.tr("Desktop widgets"), !!snapshot.desktopWidgetsVisible,
                I18n.tr("Shown"), snapshot.desktopFilesReady
                    ? I18n.tr("Clock, weather, resource cards and desktop files are ready")
                    : I18n.tr("Widget layer shown; desktop files still syncing")),
            { icon: "N", tint: "#ff9500", title: I18n.tr("Notification takeover"),
                label: notification.label, color: notification.color,
                detail: notification.detail },
            statusRow("G", "#64d2ff", I18n.tr("Glass effects"), !!snapshot.glassLoaded,
                I18n.tr("Loaded"), I18n.tr("KWin blur and liquid glass effects")),
            statusRow("A", "#ff375f", I18n.tr("Dock window animation"),
                !!snapshot.dockAnimationLoaded, I18n.tr("Loaded"), I18n.tr("KWin Dock zoom / genie animation")),
            statusRow("I", "#bf5af2", I18n.tr("Desktop input bridge"),
                !!snapshot.contextMenuInputLoaded, I18n.tr("Loaded"), I18n.tr("Global clicks and menu dismiss events"))
        ]

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13

            Text {
                Layout.fillWidth: true
                text: snapshot.updatedAt
                    ? I18n.tr("Last checked ") + snapshot.updatedAt : I18n.tr("Reading live state…")
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
                    text: I18n.tr("Refresh")
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
        property int dockContentStyleIndex: 0
        readonly property var dockContentStyles: ["compact", "relaxed"]
        property int dockStyleIndex: 0
        readonly property var dockStyles: ["floating", "taskbar", "transparent"]
        // One percentage controls magnification and its proportional lift.
        // 100% disables both; the shell clamps the peak to 300%.
        property real dockHoverScalePct: 119
        readonly property real minHoverScalePct: 100
        readonly property real maxHoverScalePct: 300
        property int visibilityModeIndex: 0
        readonly property var visibilityModes: ["always", "smart", "persistent"]
        property int windowGroupingIndex: 0
        readonly property var windowGroupings: ["grouped", "separate"]
        property bool showLauncher: true
        property bool showTrash: true
        property bool showRevealIndicator: true
        property bool revealIndicatorUpdatePending: false
        property bool stateReady: false
        property bool builtinUpdatePending: false
        property string errorText: ""
        property bool layoutDirty: false
        property bool hoverScaleDirty: false

        function positionIndexFromString(position) {
            const idx = dockPositions.indexOf(position)
            return idx >= 0 ? idx : 0
        }

        function dockContentStyleIndexFromString(style) {
            const idx = dockContentStyles.indexOf(style)
            return idx >= 0 ? idx : 0
        }

        function dockStyleIndexFromString(style) {
            const idx = dockStyles.indexOf(style)
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

        function applyState(state) {
            if (!state || state.baseHeight === undefined)
                return
            // Do not overwrite a slider preview with an unrelated IPC reply.
            if (!layoutDirty && !dockHeightSlider._pressed)
                dockHeight = Number(state.baseHeight)
            dockPositionIndex = positionIndexFromString(state.position)
            dockContentStyleIndex = dockContentStyleIndexFromString(state.contentStyle)
            dockStyleIndex = dockStyleIndexFromString(state.dockStyle)
            // The snapshot always carries the effective values, so an untouched
            // profile opens on exactly what the Dock is drawing right now.
            const hoverScale = Number(state.hoverScale)
            if (!hoverScaleDirty && !hoverScaleSlider._pressed) {
                dockHoverScalePct = Number.isFinite(hoverScale)
                    ? Math.max(minHoverScalePct, Math.min(maxHoverScalePct,
                        Math.round(hoverScale * 100)))
                    : 119
            }
            visibilityModeIndex = visibilityModeIndexFromString(state.visibilityMode)
            windowGroupingIndex = windowGroupingIndexFromString(state.windowGrouping)
            showLauncher = state.showLauncher !== false
            showTrash = state.showTrash !== false
            showRevealIndicator = state.showRevealIndicator !== false
            stateReady = true
            errorText = ""
        }

        function savePosition(index) {
            if (!bridge)
                return
            const position = dockPositions[index]
            bridge.updateDockPosition(position)
        }

        // Fire-and-forget: the shell answers with a full snapshot, which lands
        // on dockSnapshotChanged and is folded in by applyState there.
        function saveContentStyle(index) {
            if (!bridge)
                return
            bridge.updateDockContentStyle(dockContentStyles[index])
        }

        function saveDockStyle(index) {
            if (!bridge)
                return
            bridge.updateDockStyle(dockStyles[index])
        }

        // Hover magnification: preview while dragging, commit on release.
        function previewHoverScale(position) {
            const next = Math.round(minHoverScalePct
                + position * (maxHoverScalePct - minHoverScalePct))
            if (next === dockHoverScalePct)
                return
            dockHoverScalePct = next
            hoverScaleDirty = true
        }

        function commitHoverScale() {
            if (!hoverScaleDirty)
                return
            hoverScaleDirty = false
            if (bridge)
                bridge.updateDockHoverScale(dockHoverScalePct / 100)
        }

        function saveVisibilityMode(index) {
            if (!bridge)
                return
            const mode = visibilityModes[index]
            bridge.updateDockVisibilityMode(mode)
        }

        function saveWindowGrouping(index) {
            if (!bridge)
                return
            const mode = windowGroupings[index]
            bridge.updateDockWindowGrouping(mode)
        }

        function saveRevealIndicatorVisibility(visible) {
            if (!bridge || !stateReady || revealIndicatorUpdatePending)
                return
            revealIndicatorUpdatePending = true
            bridge.updateDockRevealIndicatorVisibility(visible)
        }

        function saveBuiltinVisibility(id, visible) {
            if (!bridge || !stateReady || builtinUpdatePending)
                return
            builtinUpdatePending = true
            bridge.updateDockBuiltinVisibility(id, visible)
        }
        function refresh() {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.dockSnapshot()
        }

        function saveLayout() {
            if (!bridge)
                return
            bridge.updateDockLayout(dockHeight)
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
        Connections {
            target: dockPage.bridge
            enabled: dockPage.bridge !== null
            function onDockSnapshotChanged(state) {
                dockPage.applyState(state)
                if (dockPage.bridge.lastError)
                    dockPage.errorText = I18n.tr(dockPage.bridge.lastError)
            }
            function onDockRevealIndicatorVisibilityChanged(state) {
                dockPage.revealIndicatorUpdatePending = false
                dockPage.applyState(state)
                if (dockPage.bridge.lastError)
                    dockPage.errorText = I18n.tr(dockPage.bridge.lastError)
            }
            function onDockBuiltinVisibilityChanged(state) {
                dockPage.builtinUpdatePending = false
                dockPage.applyState(state)
                if (dockPage.bridge.lastError)
                    dockPage.errorText = I18n.tr(dockPage.bridge.lastError)
            }
        }

        Component.onCompleted: refresh()

        Text {
            text: I18n.tr("Size and position").toUpperCase()
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
                            text: I18n.tr("Dock height")
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
                            id: dockHeightSlider
                            // The shared controls carry the host's palette, so the
                            // Material form has to hand them the Material accent: their own
                            // default is the iPadOS blue this window was designed with.
                            accentColor: theme.accent
                            Layout.preferredWidth: 190
                            // Ctrl+滚轮一档 = 1pt（下面的显示就是整数 pt）
                            wheelStep: 1 / 60
                            value: (dockPage.dockHeight - 40) / 60
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                dockPage.previewDockHeight(position)
                            }
                            onCanceled: { dockPage.layoutDirty = false; dockPage.refresh() }
                            onCommitRequested: dockPage.commitLayout()
                        }
                    }
                }
            }
        }

        Text {
            text: I18n.tr("Hover effects").toUpperCase()
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
            implicitHeight: hoverColumn.implicitHeight

            Column {
                id: hoverColumn
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 62
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◍"; tint: "#0a84ff" }
                        ColumnLayout {
                            spacing: 1
                            Text { text: I18n.tr("Hover to zoom"); color: theme.primaryText; font.pixelSize: 14 }
                            Text {
                                text: I18n.tr("Scales up and lifts together; 100% disables, up to 300%")
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: Math.round(dockPage.dockHoverScalePct) + "%"
                            color: theme.secondaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            id: hoverScaleSlider
                            accentColor: theme.accent
                            Layout.preferredWidth: 156
                            trackColor: theme.divider
                            // Ctrl+滚轮一档 = 1%（显示就是整数百分比）
                            wheelStep: 1 / (dockPage.maxHoverScalePct
                                            - dockPage.minHoverScalePct)
                            value: (dockPage.dockHoverScalePct
                                - dockPage.minHoverScalePct)
                                / (dockPage.maxHoverScalePct
                                    - dockPage.minHoverScalePct)
                            onPreviewChanged: function(position) {
                                dockPage.previewHoverScale(position)
                            }
                            onCanceled: { dockPage.hoverScaleDirty = false; dockPage.refresh() }
                            onCommitRequested: dockPage.commitHoverScale()
                        }
                    }
                }
            }
        }

        Text {
            text: I18n.tr("Built-in icons")
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
            implicitHeight: builtinRows.implicitHeight

            Column {
                id: builtinRows
                width: parent.width

                Repeater {
                    id: builtinRepeater
                    model: [
                        { id: "launcher", stateKey: "showLauncher", label: I18n.tr("Launcher"), symbol: "❖", tint: "#ff9500" },
                        { id: "trash", stateKey: "showTrash", label: I18n.tr("Trash"), symbol: "♲", tint: "#8e8e93" }
                    ]

                    delegate: Item {
                        id: builtinRow
                        required property var modelData
                        required property int index
                        readonly property bool confirmedVisible: dockPage[modelData.stateKey]
                        width: builtinRows.width
                        height: 54

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12
                            SettingIcon {
                                symbol: builtinRow.modelData.symbol
                                tint: builtinRow.modelData.tint
                            }
                            Text {
                                text: builtinRow.modelData.label
                                color: theme.primaryText
                                font.pixelSize: 14
                            }
                            Item { Layout.fillWidth: true }
                            CheckBox {
                                id: builtinCheck
                                objectName: "dock-" + builtinRow.modelData.id + "-checkbox"
                                checked: builtinRow.confirmedVisible
                                enabled: dockPage.stateReady && !dockPage.builtinUpdatePending
                                implicitWidth: 36
                                implicitHeight: 36
                                padding: 6
                                Accessible.name: builtinRow.modelData.label
                                indicator: Rectangle {
                                    width: 22
                                    height: 22
                                    x: (builtinCheck.width - width) / 2
                                    y: (builtinCheck.height - height) / 2
                                    radius: 5
                                    color: builtinCheck.checked ? theme.role("primary", "#0a84ff") : theme.card
                                    border.width: builtinCheck.checked ? 0 : 1.5
                                    border.color: builtinCheck.hovered ? theme.primaryText : theme.tertiaryText
                                    opacity: builtinCheck.enabled ? 1 : 0.45
                                    Text {
                                        anchors.centerIn: parent
                                        visible: builtinCheck.checked
                                        text: "✓"
                                        color: theme.role("on_primary", "#ffffff")
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                    }
                                }
                                contentItem: Item {}
                                background: Rectangle {
                                    color: "transparent"
                                    radius: 8
                                    border.width: builtinCheck.visualFocus ? 2 : 0
                                    border.color: theme.role("primary", "#0a84ff")
                                }
                                onToggled: {
                                    dockPage.saveBuiltinVisibility(builtinRow.modelData.id, checked)
                                    // The confirmed snapshot stays authoritative, including
                                    // when saving fails or another client changes the setting.
                                    builtinCheck.checked = Qt.binding(function() {
                                        return builtinRow.confirmedVisible
                                    })
                                }
                            }
                        }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            anchors.leftMargin: 54
                            height: 1
                            color: theme.separator
                            visible: builtinRow.index < builtinRepeater.count - 1
                        }
                    }
                }
            }
        }

        Text {
            text: I18n.tr("Window").toUpperCase()
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
                    text: I18n.tr("Merge windows by app")
                    color: theme.primaryText
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Item { Layout.fillWidth: true }
                LiquidControls.LiquidGlassSwitch {
                    id: windowGroupingSwitch
                    objectName: "window-grouping-switch"
                    checked: dockPage.windowGroupingIndex === 0
                    accentColor: theme.role("primary", "#0a84ff")
                    trackColor: theme.divider
                    onToggled: function(checked) {
                        const requestedIndex = checked ? 0 : 1
                        if (requestedIndex !== dockPage.windowGroupingIndex) {
                            dockPage.saveWindowGrouping(requestedIndex)
                        }
                    }
                }
            }
        }

        Text {
            text: I18n.tr("DOCK APP BAR").toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 14
        }

        Rectangle {
            Layout.fillWidth: true
            color: theme.card
            radius: window.materialForm ? 24 : 18
            implicitHeight: dockLayoutColumn.implicitHeight

            Column {
                id: dockLayoutColumn
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
                            text: I18n.tr("Dock position")
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

                Rectangle { width: parent.width; height: 1; color: theme.separator }

                Item {
                    width: parent.width
                    height: 62
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "↔"; tint: "#5ac8fa" }
                        ColumnLayout {
                            spacing: 1
                            Text { text: I18n.tr("Content style"); color: theme.primaryText; font.pixelSize: 14 }
                            Text {
                                text: dockPage.dockContentStyleIndex === 0
                                    ? I18n.tr("Apps, windows and widgets laid out compactly")
                                    : I18n.tr("Apps and windows come first, other components behind")
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            model: [
                                { id: "compact", label: I18n.tr("Compact") },
                                { id: "relaxed", label: I18n.tr("Comfortable") }
                            ]
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            itemWidthOverride: 62
                            currentIndex: dockPage.dockContentStyleIndex
                            onSelectionChanged: function(index) { dockPage.saveContentStyle(index) }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.separator }

                Item {
                    width: parent.width
                    height: 62
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "▭"; tint: "#af52de" }
                        ColumnLayout {
                            spacing: 1
                            Text { text: I18n.tr("Dock style"); color: theme.primaryText; font.pixelSize: 14 }
                            Text {
                                text: dockPage.dockStyleIndex === 0
                                    ? I18n.tr("Adapt to content and keep theme spacing")
                                    : (dockPage.dockStyleIndex === 1
                                        ? I18n.tr("Hugs the screen edge and extends into a taskbar")
                                        : I18n.tr("Hide the Dock background but keep the widget background"))
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            model: [
                                { id: "floating", label: I18n.tr("Floating") },
                                { id: "taskbar", label: I18n.tr("Taskbar") },
                                { id: "transparent", label: I18n.tr("Fully transparent") }
                            ]
                            itemWidthOverride: 62
                            currentIndex: dockPage.dockStyleIndex
                            onSelectionChanged: function(index) { dockPage.saveDockStyle(index) }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.separator }

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
                            text: I18n.tr("Dock display")
                            color: theme.primaryText
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: visibilityNavBar
                            model: [
                                { id: "always", label: I18n.tr("Always show") },
                                { id: "smart", label: I18n.tr("Smart hide") },
                                { id: "persistent", label: I18n.tr("Keep hidden") }
                            ]
                            itemWidthOverride: 76
                            currentIndex: dockPage.visibilityModeIndex
                            onSelectionChanged: function(index) {
                                dockPage.saveVisibilityMode(index)
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: theme.separator }

                Item {
                    width: parent.width
                    height: 64
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "━"; tint: "#8e8e93" }
                        ColumnLayout {
                            spacing: 1
                            Text { text: I18n.tr("Show the hide hint bar"); color: theme.primaryText; font.pixelSize: 14 }
                            Text {
                                text: I18n.tr("After turning it off, moving to the screen edge still summons the Dock")
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidGlassSwitch {
                            objectName: "dock-reveal-indicator-switch"
                            checked: dockPage.showRevealIndicator
                            enabled: dockPage.stateReady && !dockPage.revealIndicatorUpdatePending
                            accentColor: theme.role("primary", "#0a84ff")
                            trackColor: theme.divider
                            Accessible.name: I18n.tr("Show the hide hint bar")
                            onToggled: function(checked) {
                                dockPage.saveRevealIndicatorVisibility(checked)
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: dockPage.errorText.length > 0
            text: dockPage.errorText
            color: theme.role("error", "#ff453a")
            wrapMode: Text.Wrap
            font.pixelSize: 12
        }
    }

    component DisplaySettingsPage: ColumnLayout {
        id: displayPage

        Layout.fillWidth: true
        spacing: 7

        property bool showSystemAppearance: true
        property bool showGlassMaterial: true
        property bool showIconAppearance: true
        property bool showSpatialWallpaper: false

        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property real blurStrength: 0.42
        property real liquidStrength: 1.0
        property string glassStyle: "liquid"
        property string shellStyle: "macos"
        readonly property bool isMaterialDesign: shellStyle === "material"
        property bool glassFollowsAppearanceMode: false
        property bool spatialWallpaperEnabled: false
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
            const styleIndex = glassStyles.indexOf(state.glassStyle)
            glassStyle = styleIndex >= 0 ? String(state.glassStyle) : "liquid"
            shellStyle = String(state.shellStyle || "macos")
            LiquidControls.ControlForm.materialForm = isMaterialDesign
                        // The window palette follows the same style.
            window.shellStyle = shellStyle
            if (state.glassFollowsAppearanceMode !== undefined)
                glassFollowsAppearanceMode = !!state.glassFollowsAppearanceMode
            spatialWallpaperEnabled = !!state.spatialWallpaperEnabled
            blurDirty = false
            liquidDirty = false
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.appearanceSnapshot()
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
            bridge.updateGlobalBlurStrength(blurStrength)
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
            bridge.updateGlobalLiquidStrength(liquidStrength)
        }

        function setSystemAppearance(index) {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.applySystemAppearance(index === 1)
        }

        function setGlassStyle(index) {
            if (!bridge)
                return
            const option = glassStyles.options[index]
            if (!option)
                return
            bridge.updateGlassStyle(option.id)
        }

        function saveGlassFollowsAppearanceMode(checked) {
            if (!bridge)
                return
            bridge.updateGlassFollowsAppearanceMode(checked)
        }

        Connections {
            target: displayPage.bridge
            enabled: displayPage.bridge !== null
            function onAppearanceSnapshotChanged(state) {
                displayPage.applyState(state)
                if (displayPage.bridge.lastError)
                    displayPage.errorText = I18n.tr(displayPage.bridge.lastError)
            }
            function onSystemAppearanceApplied(accepted) {
                if (accepted)
                    displayPage.errorText = ""
                else if (displayPage.bridge.lastError)
                    displayPage.errorText = I18n.tr(displayPage.bridge.lastError)
            }
        }

        Component.onCompleted: refresh()

        Text {
            visible: displayPage.showSystemAppearance
            text: I18n.tr("System appearance").toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            visible: displayPage.showSystemAppearance
            Layout.fillWidth: true
            // The glass-follows-appearance row is a liquid-glass control and is
            // absent under Material, so the card collapses to just the
            // appearance-mode row instead of leaving a gap behind it.
            implicitHeight: displayPage.isMaterialDesign ? 54 : 109
            radius: 18
            color: theme.card

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

                        SettingIcon { symbol: "◐"; tint: "#5ac8fa" }
                        Text {
                            text: I18n.tr("Appearance mode")
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: systemAppearanceNavBar
                            model: [
                                { id: "light", label: I18n.tr("Light") },
                                { id: "dark", label: I18n.tr("Dark") }
                            ]
                            currentIndex: theme.dark ? 1 : 0
                            onSelectionChanged: function(index) {
                                displayPage.setSystemAppearance(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    // Hidden together with the row below it: a separator with
                    // no second row would draw a stray line under the mode
                    // switch once the card collapses under Material.
                    visible: !displayPage.isMaterialDesign
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 54
                    // Liquid glass only. Material has no liquid blur to follow
                    // the appearance mode with, so the row is dropped rather
                    // than shown disabled.
                    visible: !displayPage.isMaterialDesign

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        SettingIcon { symbol: "◈"; tint: "#64d2ff" }
                        Text {
                            text: I18n.tr("Liquid glass follows the appearance mode")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidGlassSwitch {
                            id: glassFollowsAppearanceModeSwitch
                            width: 64
                            height: 25
                            checked: displayPage.glassFollowsAppearanceMode
                            // The shared controls carry the host's palette, so the
                            // Material form hands them the Material accent: their
                            // own default is the iPadOS blue this window was
                            // designed with.
                            accentColor: theme.accent
                            trackColor: theme.divider
                            onToggled: function(checked) {
                                displayPage.saveGlassFollowsAppearanceMode(checked)
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: displayPage.showSpatialWallpaper
            text: I18n.tr("Spatial wallpaper")
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 10
        }

        Rectangle {
            visible: displayPage.showSpatialWallpaper
            Layout.fillWidth: true
            implicitHeight: spatialWallpaperRow.implicitHeight + 20
            radius: 18
            color: theme.card

            RowLayout {
                id: spatialWallpaperRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                SettingIcon { symbol: "◉"; tint: "#64d2ff" }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        text: I18n.tr("Enable spatial wallpaper parallax")
                        color: theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("The model runs locally only. First enablement downloads it and generates the depth cache on CPU; afterwards only wallpaper changes are reprocessed.")
                        color: theme.secondaryText
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    id: spatialWallpaperSwitch
                    width: 64
                    height: 25
                    checked: displayPage.spatialWallpaperEnabled
                    accentColor: theme.accent
                    trackColor: theme.divider
                    onToggled: function(checked) {
                        if (displayPage.bridge)
                            displayPage.bridge.updateSpatialWallpaperEnabled(checked)
                        spatialWallpaperSwitch.checked =
                            displayPage.spatialWallpaperEnabled
                    }
                }
            }
        }

        Text {
            visible: displayPage.showGlassMaterial
            text: (displayPage.isMaterialDesign ? I18n.tr("Background blur") : I18n.tr("Glass material")).toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            visible: displayPage.showGlassMaterial
            Layout.fillWidth: true
            implicitHeight: displayPage.isMaterialDesign ? 48 : 145
            radius: 18
            color: theme.card

            Column {
                anchors.fill: parent

                Item {
                    width: parent.width
                    height: 48
                    visible: !displayPage.isMaterialDesign

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◇"; tint: "#64d2ff" }
                        Text {
                            text: I18n.tr("Material style")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            Layout.preferredWidth: 264
                            itemWidthOverride: 88
                            model: glassStyles.options
                            currentIndex: Math.max(0,
                                glassStyles.indexOf(displayPage.glassStyle))
                            onSelectionChanged: function(index) {
                                displayPage.setGlassStyle(index)
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    visible: !displayPage.isMaterialDesign
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

                        SettingIcon { symbol: "◌"; tint: "#5ac8fa" }
                        Text {
                            text: I18n.tr("Blur strength")
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
                            // The shared controls carry the host's palette, so the
                            // Material form has to hand them the Material accent: their own
                            // default is the iPadOS blue this window was designed with.
                            accentColor: theme.accent
                            Layout.preferredWidth: 190
                            value: displayPage.blurStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                displayPage.previewBlur(position)
                            }
                            onCanceled: { liveBlurDebounce.stop(); displayPage.blurDirty = false; displayPage.refresh() }
                            onCommitRequested: displayPage.commitBlur()
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 53
                    height: 1
                    visible: !displayPage.isMaterialDesign
                    color: theme.separator
                }

                Item {
                    width: parent.width
                    height: 48
                    visible: !displayPage.isMaterialDesign

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        SettingIcon { symbol: "≈"; tint: "#af52de" }
                        Text {
                            text: I18n.tr("Liquid strength")
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
                            // The shared controls carry the host's palette, so the
                            // Material form has to hand them the Material accent: their own
                            // default is the iPadOS blue this window was designed with.
                            accentColor: theme.accent
                            Layout.preferredWidth: 190
                            value: displayPage.liquidStrength
                            trackColor: theme.divider
                            onPreviewChanged: function(position) {
                                displayPage.previewLiquid(position)
                            }
                            onCanceled: { liveLiquidDebounce.stop(); displayPage.liquidDirty = false; displayPage.refresh() }
                            onCommitRequested: displayPage.commitLiquid()
                        }
                    }
                }
            }
        }

        IconAppearanceSection {
            visible: displayPage.showIconAppearance
            bridge: displayPage.bridge
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

    component GlassDebugPage: ColumnLayout {
        id: glassDebugPage
        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property var controls: []
        property bool showAdvanced: false
        property string errorText: ""
        // Which glass style's preset the 材质 rows edit; the shell owns that preset
        // and rewrites kwinrc from it on every appearance sync. The label comes
        // from the same style list the 材质风格 row renders.
        property string presetStyle: "liquid"
        readonly property string presetStyleLabel: glassStyles.labelOf(presetStyle)
        readonly property var visibleControls: controls.filter(function(control) {
            if (showAdvanced)
                return true
            if (control.section === "Colour")
                return ["Brightness", "Saturation", "Contrast"]
                    .indexOf(control.key) >= 0
            if (control.section !== "Material")
                return false
            // Keep only controls that visibly contribute to the selected
            // material. Shader-development controls remain under 高级参数.
            const keys = presetStyle === "soft"
                ? ["RefractionStrength", "MaterialSoftness"]
                : presetStyle === "frosted"
                    ? ["MaterialSoftness", "MaterialReflectionStrength"]
                    : ["RefractionStrength", "RefractionEdgeSize",
                        "RefractionOffsetStrength"]
            return keys.indexOf(control.key) >= 0
        })
        function refresh() {
            if (!bridge) return
            bridge.glassDebugSnapshot()
        }
        function updateValue(key, value) {
            if (!bridge) {
                errorText = I18n.tr("Settings bridge unavailable")
                return
            }
            // Fire-and-forget: the reply re-reads what was actually stored
            // (a preset-backed value passes through the shell's own clamping)
            // and lands on glassDebugSnapshotChanged below.
            bridge.updateGlassDebugValue(key, value)
        }

        Connections {
            target: glassDebugPage.bridge
            enabled: glassDebugPage.bridge !== null
            function onGlassDebugSnapshotChanged(controls, presetStyle) {
                glassDebugPage.controls = controls
                glassDebugPage.presetStyle = presetStyle
                glassDebugPage.errorText = I18n.tr(glassDebugPage.bridge.lastError) || ""
            }
        }

        Component.onCompleted: refresh()
        onVisibleChanged: {
            if (visible)
                refresh()
        }

        Text {
            Layout.fillWidth: true
            text: I18n.tr("The Material group IS the current material style (") + glassDebugPage.presetStyleLabel
                + I18n.tr(" ) preset: changes are written to that preset, apply immediately, survive restarts, and switching material styles swaps in the other set.")
                + I18n.tr("Refraction strength is multiplied by Liquid strength above; effective value = liquid strength × this value.")
                + I18n.tr("Other groups write straight to kwinrc [Effect-blurplus]; the appearance theme does not manage them and the changes persist;")
                + I18n.tr("Rows marked Designed value come from the appearance theme and are read-only.")
            color: theme.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.leftMargin: 13
            Layout.rightMargin: 13
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            Text {
                Layout.fillWidth: true
                text: glassDebugPage.showAdvanced
                    ? I18n.tr("Showing all KWin parameters") : I18n.tr("Shows only the core parameters that affect the glass look")
                color: theme.secondaryText
                font.pixelSize: 12
            }
            Switch {
                checked: glassDebugPage.showAdvanced
                onToggled: glassDebugPage.showAdvanced = checked
            }
            Text {
                text: I18n.tr("Advanced parameters")
                color: theme.primaryText
                font.pixelSize: 12
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: debugRows.implicitHeight + 8
            radius: 18
            color: theme.card

            Column {
                id: debugRows
                width: parent.width
                Repeater {
                    model: glassDebugPage.visibleControls
                    delegate: Item {
                        required property var modelData
                        required property int index
                        // Outer modelData alias: the TintMode Repeater shadows
                        // `modelData` with its own {value,label} items, so the
                        // key-based write-back must reach the debug control's
                        // spec through this name instead.
                        readonly property var debugItem: modelData
                        property real currentNumber: Number(modelData.value)
                        property bool currentBool: modelData.value === true
                            || String(modelData.value) === "true"
                        property string currentText: String(modelData.value)
                        width: debugRows.width
                        height: 72
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.top: parent.top
                            anchors.topMargin: 4
                            text: I18n.tr(modelData.section)
                            visible: index === 0 || glassDebugPage.visibleControls[index - 1].section !== modelData.section
                            color: theme.secondaryText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 52
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12
                            Text { text: I18n.tr(modelData.label); color: theme.primaryText; font.pixelSize: 13 }
                            Text {
                                // The rows the shell owns: their value is stored in
                                // the active material preset, not in kwinrc.
                                visible: modelData.presetBacked === true
                                text: I18n.tr("Preset")
                                color: theme.secondaryText
                                font.pixelSize: 10
                            }
                            Text {
                                // Derived from a design value on every appearance
                                // sync, so it is shown for reference but offers no
                                // control: an edit here would silently revert.
                                visible: modelData.readOnly === true
                                text: I18n.tr("Designed value")
                                color: theme.secondaryText
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: modelData.type !== "bool" && modelData.type !== "string"
                                    && modelData.key !== "TintMode"
                                text: modelData.type === "int" ? String(Math.round(currentNumber))
                                    : currentNumber.toFixed(2)
                                color: theme.secondaryText
                                font.pixelSize: 12
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignRight
                            }
                            LiquidControls.LiquidSlider {
                                // The shared controls carry the host's palette, so the
                                // Material form has to hand them the Material accent: their own
                                // default is the iPadOS blue this window was designed with.
                                accentColor: theme.accent
                                Layout.preferredWidth: 220
                                visible: (modelData.type === "int" || modelData.type === "real")
                                    && modelData.key !== "TintMode"
                                    && modelData.readOnly !== true
                                // Ctrl+滚轮一档 = 这个参数自己的 step（整数参数就是 1）
                                wheelStep: (modelData.type === "int"
                                    ? 1 : Number(modelData.step))
                                    / Math.max(Number(modelData.max)
                                               - Number(modelData.min), 0.001)
                                value: (currentNumber - Number(modelData.min))
                                    / Math.max(Number(modelData.max) - Number(modelData.min), 0.001)
                                trackColor: theme.divider
                                onPreviewChanged: function(position) {
                                    const raw = Number(modelData.min) + position
                                        * (Number(modelData.max) - Number(modelData.min))
                                    currentNumber = modelData.type === "int" ? Math.round(raw)
                                        : Math.round(raw / Number(modelData.step)) * Number(modelData.step)
                                }
                                onCanceled: currentNumber = Qt.binding(function() { return Number(modelData.value) })
                                onCommitRequested: glassDebugPage.updateValue(modelData.key, currentNumber)
                            }
                            Row {
                                visible: modelData.key === "TintMode"
                                spacing: 6
                                property var modes: [
                                    { value: 0, label: I18n.tr("Off") },
                                    { value: 1, label: I18n.tr("Constant dark") },
                                    { value: 2, label: I18n.tr("Follow theme") }
                                ]
                                Repeater {
                                    model: parent.modes
                                    Rectangle {
                                        required property var modelData
                                        width: 74
                                        height: 30
                                        radius: 15
                                        color: modelData.value === Math.round(currentNumber)
                                            ? (theme.dark ? "#2a6fb0" : "#0066cc")
                                            : theme.divider
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: modelData.value === Math.round(currentNumber)
                                                ? "#ffffff" : theme.primaryText
                                            font.pixelSize: 12
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                currentNumber = modelData.value
                                                glassDebugPage.updateValue(debugItem.key, modelData.value)
                                            }
                                        }
                                    }
                                }
                            }
                            Switch {
                                visible: modelData.type === "bool"
                                checked: currentBool
                                onToggled: {
                                    currentBool = checked
                                    glassDebugPage.updateValue(modelData.key, checked)
                                }
                            }
                            TextField {
                                visible: modelData.type === "string"
                                Layout.preferredWidth: 220
                                text: currentText
                                color: theme.primaryText
                                onEditingFinished: {
                                    currentText = text
                                    glassDebugPage.updateValue(modelData.key, text)
                                }
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 53
                            anchors.bottom: parent.bottom
                            height: 1
                            color: theme.separator
                            visible: index < glassDebugPage.visibleControls.length - 1
                        }
                    }
                }
            }
        }

        Text {
            visible: glassDebugPage.errorText.length > 0
            text: glassDebugPage.errorText
            color: "#ff453a"
            font.pixelSize: 12
        }
    }

    component WidgetAppearanceSection: ColumnLayout {
        id: widgetAppearance
        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined") ? settingsBridge : null
        property string style: "color"
        property bool loaded: false

        Connections {
            target: widgetAppearance.bridge
            function onAppearanceSnapshotChanged(state) {
                if (!state || (state.widgetStyle !== "color" && state.widgetStyle !== "glass"))
                    return
                widgetAppearance.style = state.widgetStyle
                widgetAppearance.loaded = true
            }
        }
        Component.onCompleted: {
            if (bridge)
                bridge.appearanceSnapshot()
        }

        Text {
            text: I18n.tr("Widget appearance")
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 58
            radius: 18
            color: theme.card
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                SettingIcon { symbol: "▦"; tint: "#5ac8fa" }
                Text { text: I18n.tr("Card style"); color: theme.primaryText; font.pixelSize: 15; font.weight: Font.DemiBold }
                Item { Layout.fillWidth: true }
                SettingsNavBar {
                    objectName: "widget-style-picker"
                    model: [{ id: "color", label: I18n.tr("Colorful cards") }, { id: "glass", label: I18n.tr("Glass") }]
                    itemWidthOverride: 78
                    currentIndex: widgetAppearance.style === "glass" ? 1 : 0
                    disabled: !widgetAppearance.loaded || window.materialForm
                    onSelectionChanged: function(index) {
                        // LiquidNavBar.select() assigns currentIndex. Restore
                        // the binding so failures and later snapshots still
                        // show the confirmed Shell value.
                        currentIndex = Qt.binding(function() {
                            return widgetAppearance.style === "glass" ? 1 : 0
                        })
                        if (widgetAppearance.bridge)
                            widgetAppearance.bridge.updateWidgetStyle(index === 1 ? "glass" : "color")
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            text: window.materialForm
                ? I18n.tr("Material Design uses theme-colored cards; other themes can pick colorful cards or glass separately.")
                : I18n.tr("Glass effects follow the material settings in the theme. This option does not change app icon colors.")
            wrapMode: Text.Wrap
            color: theme.secondaryText
            font.pixelSize: 12
        }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            text: widgetAppearance.bridge ? widgetAppearance.bridge.lastError : ""
            visible: text.length > 0
            wrapMode: Text.Wrap
            color: "#ff453a"
            font.pixelSize: 12
        }
    }

    component IconAppearanceSection: ColumnLayout {
        id: iconAppearance

        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property int modeIndex: 0
        readonly property var modes: ["color", "grayscale", "tint"]
        property real iconOpacity: 0.5
        property string tintColor: "#a855f7"
        property real huePosition: 0.75
        property real tonePosition: 0.5
        property bool opacityDirty: false
        readonly property color pureHue: Qt.hsva(huePosition, 1, 1, 1)
        readonly property color selectedColor: toneColor(tonePosition)
        readonly property var presets: [
            { label: I18n.tr("Purple"), color: "#a855f7" },
            { label: I18n.tr("Red"), color: "#ef4444" },
            { label: I18n.tr("Blue"), color: "#3b82f6" },
            { label: I18n.tr("Orange"), color: "#f97316" }
        ]
        readonly property var hueRamp: [
            Qt.hsva(0 / 6, 1, 1, 1), Qt.hsva(1 / 6, 1, 1, 1),
            Qt.hsva(2 / 6, 1, 1, 1), Qt.hsva(3 / 6, 1, 1, 1),
            Qt.hsva(4 / 6, 1, 1, 1), Qt.hsva(5 / 6, 1, 1, 1),
            Qt.hsva(6 / 6, 1, 1, 1)
        ]
        readonly property var toneRamp: [
            Qt.rgba(1, 1, 1, 1), blend(Qt.rgba(1, 1, 1, 1), pureHue, 1 / 3),
            blend(Qt.rgba(1, 1, 1, 1), pureHue, 2 / 3), pureHue,
            blend(pureHue, Qt.rgba(0, 0, 0, 1), 1 / 3),
            blend(pureHue, Qt.rgba(0, 0, 0, 1), 2 / 3), Qt.rgba(0, 0, 0, 1)
        ]

        function blend(first, second, amount) {
            return Qt.rgba(first.r + (second.r - first.r) * amount,
                first.g + (second.g - first.g) * amount,
                first.b + (second.b - first.b) * amount, 1)
        }
        function toneColor(position) {
            return position <= 0.5
                ? blend(Qt.rgba(1, 1, 1, 1), pureHue, position * 2)
                : blend(pureHue, Qt.rgba(0, 0, 0, 1), (position - 0.5) * 2)
        }
        function colorHex(color) {
            function channel(value) { return Math.round(value * 255).toString(16).padStart(2, "0") }
            return "#" + channel(color.r) + channel(color.g) + channel(color.b)
        }
        function colorFromHex(value) {
            const hex = String(value).replace("#", "")
            return hex.length === 6 ? Qt.rgba(parseInt(hex.slice(0, 2), 16) / 255,
                parseInt(hex.slice(2, 4), 16) / 255, parseInt(hex.slice(4, 6), 16) / 255, 1)
                : Qt.rgba(0.66, 0.33, 0.97, 1)
        }
        function hueFor(color) {
            const max = Math.max(color.r, color.g, color.b)
            const min = Math.min(color.r, color.g, color.b)
            const delta = max - min
            if (delta < 0.0001) return huePosition
            let hue = max === color.r ? (color.g - color.b) / delta
                : (max === color.g ? (color.b - color.r) / delta + 2
                    : (color.r - color.g) / delta + 4)
            return ((hue / 6) + 1) % 1
        }
        function nearestTone(color) {
            let best = 0.5
            let distance = Number.MAX_VALUE
            for (let step = 0; step <= 100; ++step) {
                const candidate = toneColor(step / 100)
                const delta = Math.pow(candidate.r - color.r, 2)
                    + Math.pow(candidate.g - color.g, 2) + Math.pow(candidate.b - color.b, 2)
                if (delta < distance) { distance = delta; best = step / 100 }
            }
            return best
        }
        function applyState(state) {
            if (!state) return
            const index = modes.indexOf(state.iconMode)
            modeIndex = index >= 0 ? index : 0
            iconOpacity = Number.isFinite(Number(state.iconOpacity)) ? Number(state.iconOpacity) : 0.5
            tintColor = String(state.iconTintColor || "#a855f7").toLowerCase()
            const color = colorFromHex(tintColor)
            huePosition = hueFor(color)
            tonePosition = nearestTone(color)
            opacityDirty = false
        }
        function refresh() { if (bridge) bridge.appearanceSnapshot() }
        function saveMode(index) { if (bridge) bridge.updateGlobalIconMode(modes[index]) }
        function saveTint(color) { if (bridge) bridge.updateGlobalIconTintColor(color) }
        function commitOpacity() {
            if (!opacityDirty || !bridge) return
            opacityDirty = false
            bridge.updateGlobalIconOpacity(iconOpacity)
        }

        Connections {
            target: iconAppearance.bridge
            enabled: iconAppearance.bridge !== null
            function onAppearanceSnapshotChanged(state) {
                iconAppearance.applyState(state)
            }
        }

        Component.onCompleted: refresh()

        Text {
            text: I18n.tr("Icon appearance").toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 10
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: appearanceRows.implicitHeight
            radius: 18
            color: theme.card
            Column {
                id: appearanceRows
                anchors.left: parent.left
                anchors.right: parent.right
                Item {
                    width: parent.width; height: 52
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "◐"; tint: "#af52de" }
                        Text { text: I18n.tr("Icon color"); color: theme.primaryText; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            model: [{ id: "color", label: I18n.tr("Colorful") }, { id: "grayscale", label: I18n.tr("Black and white") }, { id: "tint", label: I18n.tr("Tinted") }]
                            currentIndex: iconAppearance.modeIndex
                            onSelectionChanged: function(index) { iconAppearance.saveMode(index) }
                        }
                    }
                }
                Rectangle { width: parent.width - 53; x: 53; height: 1; color: theme.separator; visible: iconAppearance.modeIndex > 0 }
                Item {
                    width: parent.width; height: iconAppearance.modeIndex > 0 ? 48 : 0; visible: height > 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "◔"; tint: "#5ac8fa" }
                        Text { text: I18n.tr("Opacity"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        Text { text: Math.round(iconAppearance.iconOpacity * 100) + "%"; color: theme.secondaryText; font.pixelSize: 12 }
                        LiquidControls.LiquidSlider {
                            // The shared controls carry the host's palette, so the
                            // Material form has to hand them the Material accent: their own
                            // default is the iPadOS blue this window was designed with.
                            accentColor: theme.accent
                            Layout.preferredWidth: 190; value: iconAppearance.iconOpacity; trackColor: theme.divider
                            onPreviewChanged: function(position) { iconAppearance.iconOpacity = Math.max(0.1, position); iconAppearance.opacityDirty = true }
                            onCanceled: { iconAppearance.opacityDirty = false; iconAppearance.refresh() }
                            onCommitRequested: iconAppearance.commitOpacity()
                        }
                    }
                }
                Rectangle { width: parent.width - 53; x: 53; height: 1; color: theme.separator; visible: iconAppearance.modeIndex === 2 }
                Item {
                    width: parent.width; height: iconAppearance.modeIndex === 2 ? 55 : 0; visible: height > 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 10
                        SettingIcon { symbol: "●"; tint: iconAppearance.tintColor }
                        Text { text: I18n.tr("Color"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            model: iconAppearance.presets
                            currentIndex: 0
                            onSelectionChanged: function(index) { iconAppearance.saveTint(iconAppearance.presets[index].color) }
                        }
                    }
                }
                Item {
                    width: parent.width; height: iconAppearance.modeIndex === 2 ? 48 : 0; visible: height > 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                        Text { text: I18n.tr("Custom"); color: theme.secondaryText; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        LiquidControls.ColorRampSlider {
                            Layout.preferredWidth: 190; value: iconAppearance.huePosition; rampColors: iconAppearance.hueRamp; thumbColor: iconAppearance.pureHue
                            onPreviewChanged: function(position) { iconAppearance.huePosition = position }
                            onCommitRequested: function(position) {
                                iconAppearance.huePosition = position
                                iconAppearance.saveTint(iconAppearance.colorHex(iconAppearance.selectedColor))
                            }
                        }
                    }
                }
                Item {
                    width: parent.width; height: iconAppearance.modeIndex === 2 ? 48 : 0; visible: height > 0
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                        Text { text: I18n.tr("Light and dark"); color: theme.secondaryText; font.pixelSize: 13 }
                        Item { Layout.fillWidth: true }
                        LiquidControls.ColorRampSlider {
                            Layout.preferredWidth: 190; value: iconAppearance.tonePosition; rampColors: iconAppearance.toneRamp; thumbColor: iconAppearance.selectedColor
                            onPreviewChanged: function(position) { iconAppearance.tonePosition = position }
                            onCommitRequested: function(position) {
                                iconAppearance.tonePosition = position
                                iconAppearance.saveTint(iconAppearance.colorHex(iconAppearance.selectedColor))
                            }
                        }
                    }
                }
            }
        }
    }

    component WindowAnimationSettingsPage: ColumnLayout {
        id: windowPage
        objectName: "windowAppearancePage"
        spacing: 10
        property var backend: typeof windowSettings !== "undefined" ? windowSettings : null
        readonly property var snapshot: backend ? backend.state : ({})
        readonly property var radiusStops: [0, 8, 12, 20, 28, 36]
        readonly property var radiusLabels: [I18n.tr("Square corner"), I18n.tr("Slight round"), I18n.tr("Small"), I18n.tr("Standard"), I18n.tr("Large"), I18n.tr("Larger")]
        property int previewRadius: -1
        readonly property int radiusIndex: {
            let best = 0
            for (let i = 1; i < radiusStops.length; ++i)
                if (Math.abs(radiusStops[i] - Number(snapshot.radius ?? 20))
                    < Math.abs(radiusStops[best] - Number(snapshot.radius ?? 20))) best = i
            return best
        }
        Component.onCompleted: { if (backend) backend.refresh() }

        Text {
            text: I18n.tr("Window appearance")
            color: theme.secondaryText; font.pixelSize: 12; font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: windowRows.implicitHeight
            radius: 18; color: theme.card
            Column {
                id: windowRows
                anchors.left: parent.left; anchors.right: parent.right
                Item {
                    width: parent.width; height: 54
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "▣"; tint: "#5856d6" }
                        Text { text: I18n.tr("KOS window appearance"); color: theme.primaryText; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidGlassSwitch {
                            width: 64; height: 25
                            enabled: windowPage.backend !== null
                            objectName: "windowTakeoverSwitch"
                            checked: windowPage.snapshot.enabled !== false
                            accentColor: theme.accent; trackColor: theme.divider
                            onToggled: function(checked) { windowPage.backend.setTakeover(checked) }
                        }
                    }
                }
                Rectangle { width: parent.width - 53; x: 53; height: 1; color: theme.separator }
                Item {
                    width: parent.width; height: 64
                    enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                    opacity: enabled ? 1 : 0.4
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "▢"; tint: "#5ac8fa" }
                        Text { text: I18n.tr("Corner radius"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: windowPage.radiusLabels[windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex]
                                + " · " + (windowPage.previewRadius >= 0 ? windowPage.radiusStops[windowPage.previewRadius] : Number(windowPage.snapshot.radius ?? 20)) + " px"
                            color: theme.secondaryText; font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            objectName: "windowRadiusSlider"
                            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                            Layout.preferredWidth: 190
                            accentColor: theme.accent; trackColor: theme.divider
                            wheelStep: 0.2
                            value: (windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex) / 5
                            onPreviewChanged: function(position) { windowPage.previewRadius = Math.round(position * 5) }
                            onCanceled: windowPage.previewRadius = -1
                            onCommitRequested: function(position) {
                                windowPage.backend.setRadius(windowPage.radiusStops[Math.round(position * 5)])
                                windowPage.previewRadius = -1
                            }
                        }
                    }
                }
                Rectangle { width: parent.width - 53; x: 53; height: 1; color: theme.separator }
                Item {
                    width: parent.width; height: 54
                    enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                    opacity: enabled ? 1 : 0.4
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "◧"; tint: "#8e8e93" }
                        Text { text: I18n.tr("Window shadow"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        LiquidControls.LiquidGlassSwitch {
                            width: 64; height: 25
                            objectName: "windowShadowSwitch"
                            checked: windowPage.snapshot.shadow !== false
                            accentColor: theme.accent; trackColor: theme.divider
                            onToggled: function(checked) { windowPage.backend.setShadow(checked) }
                        }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
            text: I18n.tr("Turning off KOS window appearance restores the original decorator. Radius and shadow apply immediately; decorator switches take effect on next login.")
            color: theme.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap
        }
        Text {
            text: I18n.tr("Window animations")
            color: theme.secondaryText; font.pixelSize: 12; font.weight: Font.DemiBold
            Layout.leftMargin: 13; Layout.topMargin: 10
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: animationRows.implicitHeight
            radius: 18; color: theme.card
            Column {
                id: animationRows
                anchors.left: parent.left; anchors.right: parent.right
                Item {
                    width: parent.width; height: 54
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "↓"; tint: "#ff9500" }
                        Text { text: I18n.tr("Hide and restore"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            objectName: "windowHideAnimation"
                            disabled: windowPage.backend === null
                            model: [{ id: "none", label: I18n.tr("None") }, { id: "scale", label: I18n.tr("Scale") }, { id: "genie", label: I18n.tr("Genie") }]
                            currentIndex: ["none", "scale", "genie"].indexOf(windowPage.snapshot.hideAnimation ?? "scale")
                            onSelectionChanged: function(index) { windowPage.backend.setAnimation("hide", model[index].id) }
                        }
                    }
                }
                Rectangle { width: parent.width - 53; x: 53; height: 1; color: theme.separator }
                Item {
                    width: parent.width; height: 54
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 12
                        SettingIcon { symbol: "×"; tint: "#ff3b30" }
                        Text { text: I18n.tr("Close window"); color: theme.primaryText; font.pixelSize: 14 }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            objectName: "windowCloseAnimation"
                            disabled: windowPage.backend === null
                            itemWidthOverride: 80
                            model: [{ id: "none", label: I18n.tr("None") }, { id: "fade", label: I18n.tr("Fade out") }, { id: "scale", label: I18n.tr("Shrink and fade") }]
                            currentIndex: ["none", "fade", "scale"].indexOf(windowPage.snapshot.closeAnimation ?? "scale")
                            onSelectionChanged: function(index) { windowPage.backend.setAnimation("close", model[index].id) }
                        }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
            text: I18n.tr("Hide means minimizing to the Dock. Choosing “None” makes KOS drop the animation and leave it to other enabled KWin effects.")
            color: theme.secondaryText; font.pixelSize: 11; wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true; Layout.leftMargin: 13; Layout.rightMargin: 13
            visible: !windowPage.backend || windowPage.backend.error.length > 0
            text: windowPage.backend ? I18n.tr(windowPage.backend.error) : I18n.tr("Window settings backend unavailable")
            color: "#ff453a"; font.pixelSize: 12; wrapMode: Text.Wrap
        }
    }

    component ThemeSettingsPage: ColumnLayout {
        id: themePage

        Layout.fillWidth: true
        spacing: 10

        property var bridge: (typeof settingsBridge !== "undefined")
            ? settingsBridge : null
        property string shellStyle: "macos"
        // Material's colour source, mirrored from the Shell so the segmented
        // control reflects what is actually applied.
        property string materialColorScheme: "monet"
        // Name of the traditional swatch the accent resolved to, shown as
        // feedback so "中国传统色" is legible rather than abstract.
        property string materialAccentName: ""
        // Representative swatches per colour source, straight from the Shell
        // (materialColorSwatches on the snapshot). Each entry is
        // {id, colors: [#rrggbb, ...]}; empty until a wallpaper seed exists.
        property var colorSchemes: []
        property string errorText: ""
        // 界面语言（zh-CN / en），经 i18n-settings IPC 由 Shell 持有与落盘。
        property string language: "zh-CN"
        readonly property var styles: [
            {
                id: "macos",
                name: "macOS",
                feature: "LIQUID GLASS",
                description: I18n.tr("Floating Dock, translucent top bar and softer large-radius components"),
                accent: "#0a84ff"
            },
            {
                id: "material",
                name: "Material Design",
                feature: "MONET TONAL",
                description: I18n.tr("Tonal surfaces, state indicators and standardized hierarchy with motion"),
                accent: "#6750a4"
            }
        ]

        function isValidStyle(style) {
            return style === "windows12" || style === "macos"
                || style === "material"
        }

        function isValidMaterialColorScheme(scheme) {
            return scheme === "monet" || scheme === "chinese"
                || scheme === "japanese"
        }

        function schemeName(id) {
            return id === "chinese" ? I18n.tr("Chinese traditional colors")
                : (id === "japanese" ? I18n.tr("Japanese palettes") : I18n.tr("Monet colors"))
        }

        // One accent per source, so the selected card reads at a glance the way
        // the style gallery's cards do.
        function schemeAccent(id) {
            return id === "chinese" ? "#c3272b"
                : (id === "japanese" ? "#bc64a4" : "#6750a4")
        }

        function applyState(state) {
            if (!state || !isValidStyle(state.shellStyle))
                return
            shellStyle = state.shellStyle
            // The window palette follows the same style. ControlForm is NOT
            // assigned here: reading window.materialForm before this line would
            // hand the shared controls the previous style. Both
            // DisplaySettingsPage instances re-apply the form from their own
            // fresh isMaterialDesign, and selectStyle() calls them right after.
            window.shellStyle = shellStyle
            if (isValidMaterialColorScheme(state.materialColorScheme))
                materialColorScheme = state.materialColorScheme
            materialAccentName = String(state.materialAccentName ?? "")
            // The Shell owns the scheme and sends previews; the page never
            // evaluates colours itself. The swatches cross the C++ bridge as a
            // JSON string (see the Shell side for why); parsing here keeps the
            // bridge free of nested-type conversion.
            let parsed = []
            try {
                parsed = JSON.parse(state.materialColorSwatches || "[]")
            } catch (error) {
                parsed = []
                console.warn("[Settings] colour swatches unreadable: " + error)
            }
            colorSchemes = parsed
            // The accent the shell derived from the wallpaper is enough to
            // rebuild the same Material 3 roles in this window.
            window.materialSeed = parsed.length > 0 && parsed[0].colors
                && parsed[0].colors.length > 0 ? String(parsed[0].colors[0]) : ""
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.appearanceSnapshot()
        }

        function selectStyle(style) {
            if (!bridge || !isValidStyle(style)) {
                errorText = bridge ? I18n.tr("Unknown theme shape") : I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.updateShellStyle(style)
        }

        // Only the Material shell style reads the colour source; switching it
        // is still sent for every style so the stored preference survives a
        // detour through macOS or Windows 12.
        function selectMaterialColorScheme(scheme) {
            if (!bridge || !isValidMaterialColorScheme(scheme)) {
                errorText = bridge ? I18n.tr("Unknown palette source") : I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.updateMaterialColorScheme(scheme)
        }

        function isValidLanguage(lang) {
            return lang === "zh-CN" || lang === "en" || lang === "auto"
        }

        function setLanguage(lang) {
            if (!bridge || !isValidLanguage(lang)) {
                errorText = bridge ? I18n.tr("Unknown language") : I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.updateLanguage(lang)
        }

        Connections {
            target: themePage.bridge
            enabled: themePage.bridge !== null
            function onAppearanceSnapshotChanged(state) {
                themePage.applyState(state)
                themeMaterialSettings.applyState(state)
                globalAppearanceSettings.applyState(state)
                if (themePage.bridge.lastError)
                    themePage.errorText = I18n.tr(themePage.bridge.lastError)
            }
        }

        Connections {
            target: themePage.bridge
            enabled: themePage.bridge !== null
            function onI18nSnapshotChanged(state) {
                if (state && state.language !== undefined
                        && state.language !== "") {
                    themePage.language = String(state.language)
                    // "auto" 只作为持久值：生效语言由 shell 解析后同步回来时
                    // 已经是具体值；这里在本地也解析一份，保证立即生效。
                    I18n.language = themePage.language === "auto"
                        ? (Qt.locale().uiLanguages.some(function(tag) {
                              return /^zh/i.test(String(tag)) }) ? "zh-CN" : "en")
                        : themePage.language
                }
            }
        }

        Component.onCompleted: {
            refresh()
            if (bridge)
                bridge.i18nSnapshot()
        }

        Text {
            text: I18n.tr("Interface shape").toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
        }

        Rectangle {
            Layout.fillWidth: true
            // The card is as tall as its contents: the style gallery, the
            // divider, the Material colour-source control (only present while
            // Material is selected) and the embedded appearance controls. Under
            // Material that controls block is much shorter, so a fixed 550
            // would leave a dead band below it.
            implicitHeight: 16 + styleGallery.height + 13 + 1 + 10
                + (themeColorSchemeCard.visible
                    ? themeColorSchemeCard.implicitHeight + 10 : 0)
                + themeMaterialSettings.implicitHeight + 16
            Layout.preferredHeight: implicitHeight
            radius: 26
            color: theme.dark ? "#000000" : "#ffffff"
            border.width: 1
            border.color: theme.floatingBorder
            clip: true

            Flickable {
                id: styleGallery
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                height: 310
                contentWidth: styleGalleryRow.width
                contentHeight: styleGalleryRow.height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Row {
                    id: styleGalleryRow
                    width: childrenRect.width
                    height: 310
                    spacing: 14

                    Repeater {
                        model: themePage.styles

                        delegate: Rectangle {
                            id: styleCard
                            required property var modelData

                            // Only implemented styles are shown for now, so
                            // both cards should be complete rather than look
                            // accidentally clipped.
                            width: Math.max(300,
                                (styleGallery.width - styleGalleryRow.spacing) / 2)
                            height: styleGalleryRow.height
                            radius: 22
                            color: theme.dark
                                ? (themePage.shellStyle === modelData.id
                                    ? "#34343a" : "#262629")
                                : Qt.rgba(0, 0, 0, themePage.shellStyle === modelData.id ? 0.085 : 0.045)
                            border.width: themePage.shellStyle === modelData.id ? 2 : 1
                            border.color: themePage.shellStyle === modelData.id
                                ? modelData.accent : theme.floatingBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 10

                                Rectangle {
                                    id: stylePreview
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 166
                                    radius: 16
                                    clip: true
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop {
                                            position: 0
                                            color: styleCard.modelData.id === "material"
                                                ? "#d8c8f0" : (styleCard.modelData.id === "macos" ? "#789cc6" : "#b9d8ef")
                                        }
                                        GradientStop {
                                            position: 1
                                            color: styleCard.modelData.id === "material"
                                                ? "#a8d5c6" : (styleCard.modelData.id === "macos" ? "#b786bd" : "#9ba9c3")
                                        }
                                    }

                                    Rectangle {
                                        x: 18; y: 32
                                        width: parent.width * 0.46
                                        height: 76
                                        radius: styleCard.modelData.id === "material" ? 22 : 10
                                        color: styleCard.modelData.id === "material"
                                            ? Qt.rgba(0.96, 0.91, 1, 0.70) : Qt.rgba(1, 1, 1, 0.44)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.48)

                                        Rectangle {
                                            x: 12; y: 13; width: parent.width * 0.58; height: 7
                                            radius: 4; color: Qt.rgba(0.18, 0.20, 0.28, 0.35)
                                        }
                                        Rectangle {
                                            x: 12; y: 28; width: parent.width * 0.76; height: 5
                                            radius: 3; color: Qt.rgba(0.18, 0.20, 0.28, 0.18)
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        height: 22
                                        color: Qt.rgba(1, 1, 1,
                                            styleCard.modelData.id === "macos" ? 0.34 : 0.16)
                                        visible: styleCard.modelData.id !== "windows12"

                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 9
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4
                                            Repeater {
                                                model: 3
                                                Rectangle {
                                                    width: 6; height: 6; radius: 3
                                                    color: index === 0 ? "#ff665d"
                                                        : (index === 1 ? "#ffbd45" : "#28c941")
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 18
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 45
                                        width: 42; height: 42; radius: 21
                                        visible: styleCard.modelData.id === "material"
                                        color: "#72558f"
                                        Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 25 }
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: styleCard.modelData.id === "macos" ? 10 : 0
                                        width: styleCard.modelData.id === "windows12"
                                            ? parent.width : (styleCard.modelData.id === "macos" ? 206 : 222)
                                        height: styleCard.modelData.id === "windows12" ? 34 : 42
                                        radius: styleCard.modelData.id === "windows12"
                                            ? 0 : (styleCard.modelData.id === "macos" ? 16 : 21)
                                        color: styleCard.modelData.id === "material"
                                            ? Qt.rgba(0.92, 0.84, 1, 0.88)
                                            : Qt.rgba(0.92, 0.96, 1, styleCard.modelData.id === "macos" ? 0.47 : 0.76)
                                        border.width: styleCard.modelData.id === "macos" ? 1 : 0
                                        border.color: Qt.rgba(1, 1, 1, 0.80)

                                        Rectangle {
                                            visible: styleCard.modelData.id === "macos"
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 2
                                            height: 8
                                            radius: 7
                                            color: Qt.rgba(1, 1, 1, 0.32)
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: styleCard.modelData.id === "material" ? 21 : 9
                                            Repeater {
                                                model: styleCard.modelData.id === "macos" ? 6 : 5
                                                Rectangle {
                                                    width: styleCard.modelData.id === "macos" ? 24 : 16
                                                    height: width
                                                    radius: styleCard.modelData.id === "macos" ? 7 : width / 2
                                                    color: index === 0 ? styleCard.modelData.accent
                                                        : (index % 3 === 1 ? "#f49e5c"
                                                        : (index % 3 === 2 ? "#70b98c" : "#8b83ca"))
                                                    border.width: styleCard.modelData.id === "macos" ? 1 : 0
                                                    border.color: Qt.rgba(1, 1, 1, 0.55)
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: styleCard.modelData.feature
                                            color: styleCard.modelData.accent
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.8
                                        }
                                        Text {
                                            text: styleCard.modelData.name
                                            color: theme.primaryText
                                            font.pixelSize: 18
                                            font.weight: Font.Bold
                                        }
                                    }

                                    Rectangle {
                                        visible: themePage.shellStyle === styleCard.modelData.id
                                        Layout.preferredWidth: 46
                                        Layout.preferredHeight: 22
                                        radius: 11
                                        color: Qt.rgba(0.04, 0.52, 1, 0.16)
                                        Text {
                                            anchors.centerIn: parent
                                            text: I18n.tr("Now")
                                            color: styleCard.modelData.accent
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: styleCard.modelData.description
                                    color: theme.secondaryText
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
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
                }

                // 横向画廊：滚轮顺着惯性滑动（竖向滚轮在没有可竖向滚动的内容时
                // 会落到唯一可滚的轴上）。
                Foundation.KosKineticScroll { flickable: styleGallery }
            }

            Rectangle {
                id: themeMaterialDivider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: styleGallery.bottom
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.topMargin: 13
                height: 1
                color: theme.dark ? Qt.rgba(1, 1, 1, 0.18)
                                  : Qt.rgba(0, 0, 0, 0.12)
            }

            // Material's colour source. Only shown while the Material card is
            // selected: the choice has no effect on the glass styles, and a
            // control that does nothing is worse than an absent one.
            Rectangle {
                id: themeColorSchemeCard
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: themeMaterialDivider.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 10
                // Tall enough for the tile row below: the header column (39),
                // the 10px gap and the 74px tiles, plus the 14px margins.
                // The old 136 cut 3px off that and squeezed the tiles.
                implicitHeight: 152
                visible: themePage.shellStyle === "material"
                radius: 18
                color: theme.card

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 11

                        SettingIcon { symbol: "◐"; tint: "#8d6e63" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: I18n.tr("Theme palette")
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: {
                                    if (themePage.materialColorScheme === "monet")
                                        return I18n.tr("Material You: derive the whole palette from the wallpaper hue")
                                    if (themePage.materialAccentName)
                                        return I18n.tr("Current seed color: ") + themePage.materialAccentName
                                    return I18n.tr("No traditional color close enough to the wallpaper seed; fell back to Monet")
                                }
                                color: theme.secondaryText
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Each source is drawn from the Shell's own preview colours,
                    // so the cards show what this wallpaper actually becomes
                    // rather than three labels. The big top swatch is the
                    // accent — the colour a user recognises as theirs — and the
                    // strip below it carries the companions and both surfaces.
                    // Never leave the block blank: an empty swatch list means the
                    // Shell has no wallpaper seed yet, which is a state worth
                    // naming rather than rendering as nothing.
                    Text {
                        Layout.fillWidth: true
                        visible: themePage.colorSchemes.length === 0
                        text: I18n.tr("Waiting for wallpaper color extraction; three swatches will appear here")
                        color: theme.secondaryText
                        font.pixelSize: 11
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        // 7 + accent 24 + 5 + strip 10 + 5 + label 16 + 7. At 62
                        // the label had no room and hung 8px out of the tile.
                        Layout.preferredHeight: 74
                        visible: themePage.colorSchemes.length > 0
                        spacing: 10

                        Repeater {
                            model: themePage.colorSchemes

                            delegate: Rectangle {
                                id: schemeTile
                                required property var modelData
                                readonly property bool chosen:
                                    themePage.materialColorScheme === modelData.id
                                readonly property var swatches: modelData.colors

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                // A selected tile is a filled container in the
                                // tonal form, not an outlined one; the iPadOS form
                                // keeps the wash and the scheme's own accent rim.
                                radius: window.materialForm ? 16 : 12
                                color: schemeTile.chosen
                                    ? theme.selectedContainer
                                    : (theme.dark ? Qt.rgba(1, 1, 1, 0.05)
                                                  : Qt.rgba(0, 0, 0, 0.025))
                                border.width: window.materialForm
                                    ? 0 : (schemeTile.chosen ? 2 : 1)
                                border.color: schemeTile.chosen
                                    ? themePage.schemeAccent(schemeTile.modelData.id)
                                    : theme.floatingBorder

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 5

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        radius: window.materialForm ? 8 : 6
                                        color: schemeTile.swatches.length > 0
                                            ? schemeTile.swatches[0] : "transparent"
                                    }

                                    Row {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 10
                                        spacing: 2

                                        Repeater {
                                            model: schemeTile.swatches.slice(1)

                                            delegate: Rectangle {
                                                required property var modelData
                                                width: Math.max(2,
                                                    (parent.width - 8) / 5)
                                                height: parent.height
                                                radius: 3
                                                color: modelData
                                            }
                                        }
                                    }

                                    // A leading radio is the loudest cue the tile
                                    // has: the container tint alone read as noise
                                    // next to three coloured swatches. Kept at
                                    // 14px so it stays inside the label's own
                                    // 16px line box -- the card height above is
                                    // sized around that line and cannot grow.
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 6

                                        Rectangle {
                                            id: schemeRadio
                                            implicitWidth: 14
                                            implicitHeight: 14
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 1.5
                                            border.color: schemeTile.chosen
                                                ? theme.accent : theme.secondaryText

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 6
                                                height: 6
                                                radius: 3
                                                visible: schemeTile.chosen
                                                color: schemeRadio.border.color
                                            }
                                        }

                                        Text {
                                            text: themePage.schemeName(
                                                schemeTile.modelData.id)
                                            color: schemeTile.chosen
                                                ? theme.primaryText : theme.secondaryText
                                            font.pixelSize: 11
                                            font.weight: schemeTile.chosen
                                                ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: themePage.selectMaterialColorScheme(
                                        schemeTile.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            DisplaySettingsPage {
                id: themeMaterialSettings
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: themeColorSchemeCard.visible
                    ? themeColorSchemeCard.bottom : themeMaterialDivider.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 10
                showSystemAppearance: false
                showGlassMaterial: true
                showIconAppearance: false
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 12
        }

        // Appearance controls belong to the selected theme. Keep the global
        // blur control available for every shell style, including Material.
        DisplaySettingsPage {
            id: globalAppearanceSettings
            Layout.fillWidth: true
            showSystemAppearance: true
            showGlassMaterial: false
            showIconAppearance: true
            showSpatialWallpaper: false
        }

        WidgetAppearanceSection {
            Layout.topMargin: 12
            Layout.bottomMargin: 12
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            Layout.preferredHeight: implicitHeight
            radius: 26
            color: theme.dark ? "#000000" : "#ffffff"
            border.width: 1
            border.color: theme.floatingBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                SettingIcon { symbol: "文"; tint: "#0a84ff" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: I18n.tr("Language")
                        color: theme.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: I18n.tr("Switch the interface language; applies live.")
                        color: theme.secondaryText
                        font.pixelSize: 11
                    }
                }
                SettingsNavBar {
                    Layout.preferredWidth: 216
                    Layout.preferredHeight: 30
                    size: "tiny"
                    barHeight: 30
                    itemWidthOverride: 72
                    // 语言选项固定显示各自语言的写法，不参与翻译；
                    // 「跟随系统」是模式名，随界面语言翻译。
                    model: [
                        { id: "auto", label: I18n.tr("Follow system") },
                        { id: "zh-CN", label: "简体中文" },
                        { id: "en", label: "English" }
                    ]
                    currentIndex: themePage.language === "auto" ? 0
                        : themePage.language === "en" ? 2 : 1
                    onSelectionChanged: function(index) {
                        themePage.setLanguage(index === 0 ? "auto"
                            : index === 2 ? "en" : "zh-CN")
                    }
                }
            }
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
        property int barLayoutModeIndex: 2
        readonly property var barLayoutModes: ["full", "floating", "transparent"]
        // The mac style is a style choice with one intensity knob: the
        // selector turns it on and off, and the tint slider only applies while
        // it is on. Off is the default Bar, outlines and all.
        property bool barMacStyle: false
        // The tint opacity. The shell clamps it to 0..1 (AppearanceConfigService);
        // the slider only ever produces values inside this narrower range, which
        // runs from "barely there" to "nearly opaque plate".
        property real barMacTint: 0.30
        readonly property real minBarMacTint: 0.05
        readonly property real maxBarMacTint: 0.85
        property bool tintDirty: false
        property string errorText: ""

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
            barMacStyle = state.barMacStyle === true
            const macTint = Number(state.barMacTint)
            barMacTint = Number.isFinite(macTint)
                ? Math.max(minBarMacTint, Math.min(maxBarMacTint, macTint))
                : 0.30
            tintDirty = false
            errorText = ""
        }

        function refresh() {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.appearanceSnapshot()
        }

        function setBarMacStyle(enabled) {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.updateBarMacStyle(enabled)
        }

        // The tint slider previews while dragging and commits on release, like
        // the Dock curvature slider: the shell writes the config once, and the
        // snapshot that comes back is authoritative. It is gated by the style
        // selector, so it only ever runs while the mac style is on.
        function previewBarMacTint(position) {
            const next = Math.round((minBarMacTint
                + position * (maxBarMacTint - minBarMacTint)) * 100) / 100
            if (Math.abs(next - barMacTint) <= 0.001)
                return
            barMacTint = next
            tintDirty = true
        }

        function commitBarMacTint() {
            if (!tintDirty)
                return
            tintDirty = false
            if (bridge)
                bridge.updateBarMacTint(barMacTint)
        }

        function setBarIntegratedWithDock(enabled) {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.updateBarIntegratedWithDock(enabled)
        }

        function saveBarVisibilityMode(index) {
            if (!bridge)
                return
            const mode = barVisibilityModes[index]
            bridge.updateBarVisibilityMode(mode)
        }

        function saveBarLayoutMode(index) {
            if (!bridge)
                return
            const mode = barLayoutModes[index]
            bridge.updateBarLayoutMode(mode)
        }
        Connections {
            target: barPage.bridge
            enabled: barPage.bridge !== null
            function onAppearanceSnapshotChanged(state) {
                barPage.applyState(state)
                if (barPage.bridge.lastError)
                    barPage.errorText = I18n.tr(barPage.bridge.lastError)
            }
        }

        Component.onCompleted: refresh()

        Text {
            text: I18n.tr("Display and layout").toUpperCase()
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
                            text: I18n.tr("Top bar shape")
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: barLayoutNavBar
                            model: [
                                { id: "full", label: I18n.tr("Full-width edge to edge") },
                                { id: "floating", label: I18n.tr("Floating capsule") },
                                { id: "transparent", label: I18n.tr("Fully transparent") }
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
                            text: I18n.tr("Bar display")
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: barVisibilityNavBar
                            model: [
                                { id: "always", label: I18n.tr("Always show") },
                                { id: "smart", label: I18n.tr("Smart hide") },
                                { id: "persistent", label: I18n.tr("Keep hidden") }
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
                                text: I18n.tr("Bar merges into Dock")
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: I18n.tr("Only applies when the Dock sits at the bottom; side Docks keep the top Bar automatically")
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }
                        LiquidControls.LiquidGlassSwitch {
                            checked: barPage.barIntegratedWithDock
                            accentColor: theme.role("primary", "#0a84ff")
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
            text: I18n.tr("Bar style").toUpperCase()
            color: theme.secondaryText
            font.pixelSize: 12
            font.weight: Font.DemiBold
            Layout.leftMargin: 13
            Layout.topMargin: 8
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: macStyleCol.implicitHeight
            radius: 18
            color: theme.card

            Column {
                id: macStyleCol
                anchors.left: parent.left
                anchors.right: parent.right

                Item {
                    width: parent.width
                    height: 64
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◍"; tint: "#64d2ff" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: I18n.tr("mac style")
                                color: theme.primaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                // The style and the ink are one decision: the
                                // selector is where the user learns that the
                                // outlines go away with the style.
                                text: barPage.barMacStyle
                                    ? I18n.tr("Frosted tint layer, outlines removed, ink follows the background")
                                    : I18n.tr("Keeps the default style when off (outline and shadow unchanged)")
                                color: theme.secondaryText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                            }
                        }
                        SettingsNavBar {
                            id: barMacStyleNavBar
                            model: [
                                { id: "default", label: I18n.tr("Default") },
                                { id: "mac", label: I18n.tr("mac style") }
                            ]
                            itemWidthOverride: 76
                            currentIndex: barPage.barMacStyle ? 1 : 0
                            onSelectionChanged: function(index) {
                                barPage.setBarMacStyle(index === 1)
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
                    height: 62
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        SettingIcon { symbol: "◐"; tint: "#5e5ce6" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: I18n.tr("Tint strength")
                                color: barPage.barMacStyle
                                    ? theme.primaryText : theme.secondaryText
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                // The tint only draws while the style is on, so
                                // the row says so instead of silently doing
                                // nothing.
                                text: barPage.barMacStyle
                                    ? I18n.tr("Dark gray over light wallpapers, light gray over dark ones; higher is more opaque")
                                    : I18n.tr("Only takes effect while “mac style” is on")
                                color: barPage.barMacStyle
                                    ? theme.secondaryText : theme.tertiaryText
                                font.pixelSize: 11
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            // Fixed width so the slider does not jog as the
                            // readout grows 9% -> 10% mid-drag.
                            Layout.preferredWidth: 34
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(barPage.barMacTint * 100) + "%"
                            color: barPage.barMacStyle
                                ? theme.secondaryText : theme.tertiaryText
                            font.pixelSize: 12
                        }
                        LiquidControls.LiquidSlider {
                            id: barMacTintSlider
                            accentColor: theme.accent
                            trackColor: theme.divider
                            Layout.preferredWidth: 156
                            // The slider dims itself to 45% while disabled, so
                            // the gate is one binding and no extra styling.
                            enabled: barPage.barMacStyle
                            value: (barPage.barMacTint - barPage.minBarMacTint)
                                / (barPage.maxBarMacTint - barPage.minBarMacTint)
                            onPreviewChanged: function(position) {
                                barPage.previewBarMacTint(position)
                            }
                            onCanceled: { barPage.tintDirty = false; barPage.refresh() }
                            onCommitRequested: barPage.commitBarMacTint()
                        }
                    }
                }
            }
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

    component ShortcutsSettingsPage: ColumnLayout {
        id: shortcutsPage

        Layout.fillWidth: true
        spacing: 7
        property var bridge: (typeof settingsBridge !== "undefined") ? settingsBridge : null
        property var shortcuts: []
        property string errorText: ""
        readonly property var rowIcons: ({
            "net.local.kos-launcher": { symbol: "❖", tint: "#ff9500" },
            "net.local.kos-window-switcher": { symbol: "⌕", tint: "#0a84ff" },
            "net.local.kos-control-center": { symbol: "≋", tint: "#5ac8fa" },
            "net.local.kos-overview": { symbol: "▦", tint: "#af52de" },
            "net.local.kos-clipboard": { symbol: "⧉", tint: "#34c759" },
            "net.local.kos-show-desktop": { symbol: "⌂", tint: "#ff375f" },
        })

        function applyState(state) {
            if (!state) return
            // A QVariantList nested in the bridge's QVariantMap arrives as an
            // array-LIKE object (has .length) but Array.isArray() is false,
            // so the list must be copied into a real JS array here or the
            // Repeater silently renders nothing.
            const raw = state.shortcuts
            shortcuts = Array.isArray(raw) ? raw
                : (raw && raw.length !== undefined
                    ? Array.prototype.slice.call(raw) : [])
            errorText = state.error || ""
        }

        function refresh() {
            if (!bridge) {
                errorText = I18n.tr("The Settings bridge has not been built")
                return
            }
            bridge.shortcutsSnapshot()
        }

        function saveBinding(id, combo) {
            if (!bridge)
                return
            bridge.updateShortcut(id, combo)
        }

        function resetBinding(id) {
            if (!bridge)
                return
            bridge.resetShortcut(id)
        }

        Connections {
            target: shortcutsPage.bridge
            enabled: shortcutsPage.bridge !== null
            function onShortcutsSnapshotChanged(state) {
                shortcutsPage.applyState(state)
                if (shortcutsPage.bridge.lastError)
                    shortcutsPage.errorText = I18n.tr(shortcutsPage.bridge.lastError)
            }
        }

        // Maps a raw key event to its kglobalaccel PortableText name.
        // Returns "" for lone modifier presses so recording keeps waiting.
        function keyDisplayName(event) {
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
                return String.fromCharCode(event.key)
            if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
                return String.fromCharCode(event.key)
            if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24)
                return "F" + (event.key - Qt.Key_F1 + 1)
            switch (event.key) {
                case Qt.Key_Space: return "Space"
                case Qt.Key_Tab: return "Tab"
                case Qt.Key_Backspace: return "Backspace"
                case Qt.Key_Return: return "Return"
                case Qt.Key_Enter: return "Enter"
                case Qt.Key_Insert: return "Ins"
                case Qt.Key_Delete: return "Del"
                case Qt.Key_Home: return "Home"
                case Qt.Key_End: return "End"
                case Qt.Key_Left: return "Left"
                case Qt.Key_Up: return "Up"
                case Qt.Key_Right: return "Right"
                case Qt.Key_Down: return "Down"
                case Qt.Key_PageUp: return "PgUp"
                case Qt.Key_PageDown: return "PgDown"
                case Qt.Key_Print: return "Print"
                case Qt.Key_Pause: return "Pause"
            }
            const text = String(event.text || "")
            if (text.length === 1) {
                const upper = text.toUpperCase()
                const code = upper.charCodeAt(0)
                if (code >= 0x21 && code <= 0x7e)
                    return upper
            }
            return ""
        }

        Component.onCompleted: refresh()

        Text {
            text: I18n.tr("Click a key capsule then press the new combination to rebind; Esc cancels.")
            color: theme.secondaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
        }

        Rectangle {
            id: shortcutsCard
            Layout.fillWidth: true
            color: theme.card
            radius: 18
            implicitHeight: shortcutsColumn.implicitHeight

            Column {
                id: shortcutsColumn
                anchors.left: parent.left
                anchors.right: parent.right

                Repeater {
                    model: shortcutsPage.shortcuts

                    delegate: Item {
                        id: shortcutRow

                        required property var modelData
                        required property int index
                        readonly property var iconInfo:
                            shortcutsPage.rowIcons[modelData.id]
                            || { symbol: "⌘", tint: "#8e8e93" }
                        readonly property string rowCombo: modelData.combo || ""

                        width: shortcutsColumn.width
                        height: 54

                        // Explicit anchoring: icon + title group left-aligned,
                        // combo pill right-aligned, everything vertically
                        // centered — no layout-engine ambiguity between rows.
                        SettingIcon {
                            id: rowIcon
                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            symbol: shortcutRow.iconInfo.symbol
                            tint: shortcutRow.iconInfo.tint
                        }

                        ColumnLayout {
                            id: rowText
                            anchors.left: rowIcon.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: shortcutRow.modelData.description
                                color: theme.primaryText
                                font.pixelSize: 14
                            }
                            Text {
                                text: shortcutRow.modelData.custom
                                    ? I18n.tr("Custom shortcut") : I18n.tr("Default shortcut")
                                color: theme.secondaryText
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            id: resetLabel
                            anchors.right: comboPill.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            visible: shortcutRow.modelData.custom
                            text: I18n.tr("Reset to default")
                            color: theme.dark ? "#64b5ff" : "#0066cc"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shortcutsPage.resetBinding(shortcutRow.modelData.id)
                            }
                        }

                        // Click to record: the pill grabs keyboard focus
                        // and shows a hint; the next full combo commits.
                        Rectangle {
                            id: comboPill

                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            width: 158
                            height: 30
                            radius: 15
                            property bool recording: false
                            color: recording
                                ? Qt.rgba(0.04, 0.52, 1.0, 0.18)
                                : (theme.dark
                                    ? Qt.rgba(1, 1, 1, 0.09)
                                    : Qt.rgba(0, 0, 0, 0.055))
                            border.width: recording ? 2 : 1
                            border.color: recording
                                ? "#0a84ff" : theme.floatingBorder

                            Text {
                                anchors.centerIn: parent
                                text: comboPill.recording
                                    ? I18n.tr("Press a new key combination…")
                                    : (shortcutRow.rowCombo || I18n.tr("Tap to configure"))
                                color: comboPill.recording
                                    ? (theme.dark ? "#64b5ff" : "#0066cc")
                                    : theme.primaryText
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    comboPill.forceActiveFocus()
                                    comboPill.recording = true
                                }
                            }

                            Keys.onPressed: function(event) {
                                if (!comboPill.recording)
                                    return
                                event.accepted = true
                                if (event.key === Qt.Key_Escape) {
                                    comboPill.recording = false
                                    comboPill.focus = false
                                    return
                                }
                                const name = shortcutsPage.keyDisplayName(event)
                                if (name === "")
                                    return
                                const parts = []
                                if (event.modifiers & Qt.MetaModifier)
                                    parts.push("Meta")
                                if (event.modifiers & Qt.ControlModifier)
                                    parts.push("Ctrl")
                                if (event.modifiers & Qt.AltModifier)
                                    parts.push("Alt")
                                if (event.modifiers & Qt.ShiftModifier)
                                    parts.push("Shift")
                                parts.push(name)
                                comboPill.recording = false
                                comboPill.focus = false
                                shortcutsPage.saveBinding(
                                    shortcutRow.modelData.id, parts.join("+"))
                            }

                            onActiveFocusChanged: if (!activeFocus) recording = false
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 53
                            anchors.bottom: parent.bottom
                            height: 1
                            color: theme.separator
                            visible: index < shortcutsPage.shortcuts.length - 1
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 13
            Layout.rightMargin: 13
            visible: shortcutsPage.errorText.length > 0
            text: shortcutsPage.errorText
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
        readonly property var displayModes: ["bottom", "bottomWide", "center", "fullscreen"]
        property int displayModeIndex: 0
        property string iconSize: "medium"
        property string density: "balanced"
        property string fontWeight: "normal"
        readonly property var iconSizes: ["small", "medium", "large"]
        readonly property var densities: ["compact", "balanced", "spacious"]
        property int iconSizeIndex: 1
        property int densityIndex: 1
        readonly property var fontWeights: ["normal", "medium", "bold"]
        property int fontWeightIndex: 0
        property string errorText: ""

        function applySnapshot(snapshot) {
            if (!snapshot) return
            if (snapshot.displayMode !== undefined) {
                displayMode = snapshot.displayMode
                const idx = displayModes.indexOf(displayMode)
                displayModeIndex = idx >= 0 ? idx : 0
            }
            const profiles = snapshot.layoutProfiles
            const profile = profiles && profiles[displayMode] ? profiles[displayMode] : null
            if (!profile)
                return
            iconSize = iconSizes.indexOf(profile.iconSize) >= 0 ? profile.iconSize : "medium"
            density = densities.indexOf(profile.density) >= 0 ? profile.density : "balanced"
            fontWeight = fontWeights.indexOf(profile.fontWeight) >= 0 ? profile.fontWeight : "normal"
            iconSizeIndex = iconSizes.indexOf(iconSize)
            densityIndex = densities.indexOf(density)
            fontWeightIndex = fontWeights.indexOf(fontWeight)
        }

        function reloadFromBridge() {
            if (!bridge) return
            bridge.launcherSnapshot()
        }

        // The picker rows keep the optimistic local update they had; the
        // authoritative snapshot arrives on launcherSnapshotChanged below.
        function saveDisplayMode(index) {
            displayModeIndex = index
            displayMode = displayModes[index] || "bottom"
            if (bridge)
                bridge.updateLauncherDisplayMode(displayMode)
        }

        function saveFontWeight(index) {
            fontWeightIndex = index
            fontWeight = fontWeights[index] || "normal"
            if (bridge)
                bridge.updateLauncherProfileFontWeight(displayMode, fontWeight)
        }

        function saveIconSize(index) {
            iconSizeIndex = index
            iconSize = iconSizes[index] || "medium"
            if (bridge)
                bridge.updateLauncherProfileIconSize(displayMode, iconSize)
        }

        function saveDensity(index) {
            densityIndex = index
            density = densities[index] || "balanced"
            if (bridge)
                bridge.updateLauncherProfileDensity(displayMode, density)
        }

        function resetCurrentProfile() {
            if (!bridge)
                return
            bridge.resetLauncherLayoutProfile(displayMode)
        }

        Connections {
            target: launcherPage.bridge
            enabled: launcherPage.bridge !== null
            function onLauncherSnapshotChanged(snap) {
                launcherPage.applySnapshot(snap)
                if (launcherPage.bridge.lastError)
                    launcherPage.errorText = I18n.tr(launcherPage.bridge.lastError)
            }
        }

        Component.onCompleted: reloadFromBridge()

        Text {
            text: I18n.tr("Display shape").toUpperCase()
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
                        text: I18n.tr("Launcher shape")
                        color: theme.primaryText
                        font.pixelSize: 14
                    }
                    Item { Layout.fillWidth: true }
                    SettingsNavBar {
                        id: launcherModeNavBar
                        model: [
                            { id: "bottom",     label: I18n.tr("Dock to bottom") },
                            { id: "bottomWide", label: I18n.tr("Compact bottom") },
                            { id: "center",     label: I18n.tr("Center on screen") },
                            { id: "fullscreen", label: I18n.tr("Fullscreen") }
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
            text: I18n.tr("Grid, icons and text").toUpperCase()
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
                            text: I18n.tr("Icon Size")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            model: [
                                { id: "small", label: I18n.tr("Small") },
                                { id: "medium", label: I18n.tr("Medium") },
                                { id: "large", label: I18n.tr("Large") }
                            ]
                            itemWidthOverride: 56
                            currentIndex: launcherPage.iconSizeIndex
                            onSelectionChanged: function(index) {
                                launcherPage.saveIconSize(index)
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
                        SettingIcon { symbol: "↔"; tint: "#5ac8fa" }
                        Text {
                            text: I18n.tr("Grid density")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            model: [
                                { id: "compact", label: I18n.tr("Compact") },
                                { id: "balanced", label: I18n.tr("Standard") },
                                { id: "spacious", label: I18n.tr("Comfortable") }
                            ]
                            itemWidthOverride: 56
                            currentIndex: launcherPage.densityIndex
                            onSelectionChanged: function(index) {
                                launcherPage.saveDensity(index)
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
                        SettingIcon { symbol: "B"; tint: "#ff9500" }
                        Text {
                            text: I18n.tr("Font weight")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        SettingsNavBar {
                            id: launcherFontWeightNavBar
                            model: [
                                { id: "normal", label: I18n.tr("General") },
                                { id: "medium", label: I18n.tr("Medium black") },
                                { id: "bold",   label: I18n.tr("Bold") }
                            ]
                            itemWidthOverride: 56
                            currentIndex: launcherPage.fontWeightIndex
                            onSelectionChanged: function(index) {
                                launcherPage.saveFontWeight(index)
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
                        SettingIcon { symbol: "↺"; tint: "#8e8e93" }
                        Text {
                            text: I18n.tr("Restore recommended layout")
                            color: theme.primaryText
                            font.pixelSize: 14
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: I18n.tr("Current shape only")
                            color: theme.secondaryText
                            font.pixelSize: 11
                        }
                        Rectangle {
                            width: 52
                            height: 26
                            radius: 13
                            color: resetProfileMouse.containsMouse
                                ? Qt.rgba(0.04, 0.52, 1.0, 0.20)
                                : Qt.rgba(0.04, 0.52, 1.0, 0.12)
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Restore")
                                color: theme.dark ? "#64b5ff" : "#0066cc"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: resetProfileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcherPage.resetCurrentProfile()
                            }
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
            // 302 → 211（缩到 70%，用户要求窄 30%）→ 230（用户要求加宽一点点）。
            // 条目最长的标签是 4 个汉字（"接入状态"／"玻璃调试"），14px 字号约
            // 56px；一条 ItemDelegate 占 10(左内) + 18(图标) + 10(间隔) + 文本 +
            // 10(右内)，再加 ColumnLayout 两侧各 14 的边距 ⇒ 230 下文本仍有约
            // 150px 可用，不会触发 ElideRight。
            width: 230
            height: parent.height
            radius: 0
            color: theme.sidebar

            ColumnLayout {
                anchors.fill: parent
                // 左 24 / 右 4 是有意不对称的：右侧要再叠加内容面板的 inset(20)，
                // 4+20=24 才和左侧的 24 相等，session 卡片于是落在「窗口左缘 ↔
                // 内容面板」这段视觉空间的正中；标题和搜索框跟卡片同列对齐。
                anchors.leftMargin: 24
                anchors.rightMargin: 4
                anchors.topMargin: 22
                anchors.bottomMargin: 16
                spacing: 0

                Text {
                    text: I18n.tr("Settings")
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
                        placeholderText: I18n.tr("Search")
                        glassColor: theme.searchField
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

                // 侧栏条目也按 session 分组卡片呈现：背景和圆角对齐右侧内容区
                // 的卡片（theme.card / radius 18），组间 15px。搜索过滤掉条目时
                // ColumnLayout 只按可见项撑高，卡片会跟着收缩。
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 15
                    color: theme.card
                    radius: 18
                    implicitHeight: navGroup1.implicitHeight + 8

                    ColumnLayout {
                        id: navGroup1
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 0

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 1
                            label: I18n.tr("Theme")
                            navSymbol: "◈"
                            navTint: "#af52de"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 11
                            label: I18n.tr("Windows and animations")
                            navSymbol: "▣"
                            navTint: "#af52de"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 8
                            label: I18n.tr("Wallpaper")
                            navSymbol: "▧"
                            navTint: "#64d2ff"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 2
                            label: I18n.tr("Top bar")
                            navSymbol: "⎍"
                            navTint: "#5ac8fa"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 3
                            label: I18n.tr("Dock")
                            navSymbol: "▰"
                            navTint: "#0a84ff"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 12
                            label: I18n.tr("Notifications")
                            navSymbol: "●"
                            navTint: "#ff3b30"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 4
                            label: I18n.tr("Launcher")
                            navSymbol: "❖"
                            navTint: "#ff9500"
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    color: theme.card
                    radius: 18
                    implicitHeight: navGroup2.implicitHeight + 8

                    ColumnLayout {
                        id: navGroup2
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        spacing: 0

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 5
                            label: I18n.tr("Shortcuts")
                            navSymbol: "⌘"
                            navTint: "#5856d6"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 6
                            label: I18n.tr("Integration status")
                            navSymbol: "✓"
                            navTint: "#30d158"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 9
                            label: I18n.tr("Services and components")
                            navSymbol: "◇"
                            navTint: "#5ac8fa"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 7
                            label: I18n.tr("Glass debugging")
                            navSymbol: "⚙"
                            navTint: "#64d2ff"
                        }

                        SidebarEntry {
                            Layout.fillWidth: true
                            pageIndex: 10
                            label: I18n.tr("Stage scheduling")
                            navSymbol: "⏵"
                            navTint: "#ff9f0a"
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        Rectangle {
            id: contentSurface
            // 右侧内容面板四周让开 inset（呼吸空间），否则贴边时圆角会被窗口
            // 边缘切掉，只在左下露出一点圆弧。圆角之外露出的就是 theme.background
            // （#eff0f1），也就是侧栏那块平面，看上去像分栏而不是割裂。
            // 10 → 20：用户要求边距大一点、圆角区域小一点。面板自身的内边距
            // （下面 Flickable 的 30/24）保持不变，所以变大的是面板外的留白。
            readonly property real inset: 20
            x: sidebar.width + inset
            y: inset
            width: parent.width - x - inset
            height: parent.height - inset * 2
            radius: 18
            color: theme.contentSurface

            Flickable {
                id: pageScroll
                opacity: pageMotion.progress
                enabled: pageMotion.interactive
                transform: Translate { x: Foundation.AppTheme.reduceMotion ? 0 : 12 * (1 - pageMotion.progress) }
                objectName: "settings-page-scroll"
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
                    // 固定宽度:窗口缩放只改变两侧留白,内容列(含图片网格)
                    // 尺寸恒定,不触发网格重排/缩略图重生成。窗口窄于 700 时
                    // 由外层 Flickable 的横向滚动兜底(contentWidth 已取 max)。
                    width: 700
                    x: Math.max(0, Math.round((pageScroll.width - width) / 2))
                    spacing: 0

                    // Invisible rows are left out of a Layout, so an installed
                    // session shows no gap where this sits, and neither does a
                    // development one once the banner has been closed.
                    DevelopmentBanner {
                        visible: window.developmentBannerVisible
                    }

                    Text {
                        text: window.contentByPage[window.displayedPage].subtitle
                        color: theme.primaryText
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        Layout.bottomMargin: 18
                    }
                    Repeater {
                        model: (window.displayedPage >= 0 && window.displayedPage <= 9)
                            ? [] : window.contentByPage[window.displayedPage].groups
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
                        sourceComponent: WindowAnimationSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 4
                        visible: active
                        sourceComponent: LauncherSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 5
                        visible: active
                        sourceComponent: ShortcutsSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 6
                        visible: active
                        sourceComponent: IntegrationStatusPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 7
                        visible: active
                        sourceComponent: GlassDebugPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 9
                        visible: active
                        sourceComponent: ServicesSettingsPage {
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
                        Layout.fillWidth: true
                        active: window.displayedPage === 10
                        visible: active
                        sourceComponent: FgSchedSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 3
                        visible: active
                        sourceComponent: DockSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 2
                        visible: active
                        sourceComponent: BarSettingsPage {}
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: window.displayedPage === 1
                        visible: active
                        sourceComponent: ThemeSettingsPage {}
                    }

                }

                // 设置页正文：浏览器式惯性滚动。禁用态（页面切换动画期间
                // enabled: pageMotion.interactive）会连同 wheel 一起失效。
                Foundation.KosKineticScroll { flickable: pageScroll }
            }
        }
    }
}
