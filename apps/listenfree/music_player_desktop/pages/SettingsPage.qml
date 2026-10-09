pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import "../components"

Item {
    id: page
    objectName: "settingsPage"

    property int refreshRateLimit: 60
    property int selectedCategory: 0
    property string filterText: ""
    readonly property var matchingCategories: {
        const result = []
        for (let category = 0; category < categories.length; ++category) {
            for (let child of body.children) {
                if (child.categoryIndex === category && child.hasMatches) {
                    result.push(category)
                    break
                }
            }
        }
        return result
    }
    function matches(text, category) {
        const haystack = (categories[category] + " " + text).toLocaleLowerCase()
        return filterText.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
            .every(function(word) { return haystack.indexOf(word) >= 0 })
    }
    function selectMatchingCategory() {
        if (matchingCategories.indexOf(selectedCategory) < 0)
            selectedCategory = matchingCategories.length ? matchingCategories[0] : -1
        scroll.contentY = 0
    }
    onFilterTextChanged: Qt.callLater(selectMatchingCategory)
    onMatchingCategoriesChanged: Qt.callLater(selectMatchingCategory)
    onSelectedCategoryChanged: { scroll.contentY = 0; if (shortcutService) shortcutService.cancelCapture() }
    onVisibleChanged: if (!visible && shortcutService) shortcutService.cancelCapture()
    Component.onDestruction: if (shortcutService) shortcutService.cancelCapture()
    property var shortcutService: typeof backendShortcuts !== "undefined" ? backendShortcuts : null
    property bool darkMode: false
    property var sourceController: null
    property var libraryController: null
    property var settingsStore: null
    property var downloadController: null
    property var playerController: null
    function setting(key, fallback) {
        if (!settingsStore) return fallback
        const revision = settingsStore.revision
        return settingsStore.value(key, fallback)
    }
    property string noticeText: ""
    readonly property bool translationEnabled: setting("lyrics.showTranslation", true)
    readonly property bool romanizationEnabled: setting("lyrics.showRomanization", false)
    property bool systemTrayEnabled: setting("tray.enabled", true)
    readonly property var fontOptions: [{ label: qsTr("系统默认"), value: "SystemDefault" }].concat(
        Qt.fontFamilies().map(function(family) { return { label: family, value: family } }))
    property string selectedFont: "SystemDefault"
    property bool dynamicArtworkEnabled: true
    property bool animationsEnabled: true
    property string animationStyle: "Elegant"
    property bool sourceManagerOpen: false
    property bool accountCookieOpen: false
    property string accountCookieProvider: ""
    property string neteaseAccountName: ""
    property string bilibiliAccountName: ""
    property string currentSourceId: sourceController ? sourceController.activeId : ""
    property var sourceEntries: sourceController ? sourceController.sources : []

    readonly property var categories: [
        qsTr("基本"), qsTr("资料库"), qsTr("播放"), qsTr("外观"), qsTr("下载"), qsTr("音源"),
        qsTr("账号"), qsTr("快捷键"), qsTr("备份与恢复"), qsTr("其他"), qsTr("关于")
    ]
    readonly property var categoryDescriptions: [
        qsTr("语言、字体、启动、应用动画和界面刷新率。"),
        qsTr("管理本地音乐目录、索引和重复歌曲。"),
        qsTr("设置启动队列、音频输出与切歌行为。"),
        qsTr("调整界面动效、播放详情和歌词显示。"),
        qsTr("管理下载文件、并发任务与歌词。"),
        qsTr("导入洛雪音源"),
        qsTr("管理网易云音乐与哔哩哔哩的 Cookie 登录状态。"),
        qsTr("管理应用内和全局快捷键。"),
        qsTr("导出、导入或恢复公开设置。"),
        qsTr("管理窗口、列表、缓存和危险操作。"),
        qsTr("查看版本、诊断信息和开源许可。")
    ]

    // Stable keys are independent of the active UI language.
    readonly property var settingKeys: ({
        language: "ui.language",
        fontFamily: "ui.fontFamily",
        launchAtLogin: "app.launchAtLogin",
        startInFullScreen: "window.startInFullScreen",
        refreshRateLimit: "ui.refreshRateLimit",
        libraryFolders: "library.folders",
        addLibraryFolder: "library.addFolder",
        removeLibraryFolder: "library.removeFolder",
        rescanLibrary: "library.rescan",
        analyzeDuplicates: "library.analyzeDuplicates",
        autoPlayOnLaunch: "playback.autoPlayOnLaunch",
        restorePosition: "playback.restorePosition",
        defaultPlaybackMode: "playback.defaultMode",
        playActionBehavior: "playback.playActionBehavior",
        clearShuffleHistory: "playback.clearShuffleHistory",
        outputDeviceId: "audio.outputDeviceId",
        pauseOnDeviceRemoval: "audio.pauseOnDeviceRemoval",
        preventSystemSleep: "playback.preventSystemSleep",
        showTaskbarProgress: "window.showTaskbarProgress",
        skipOnError: "playback.skipOnError",
        motionEnabled: "ui.motionEnabled",
        motionStyle: "ui.motionStyle",
        backgroundStyle: "nowPlaying.backgroundStyle",
        backgroundBlur: "nowPlaying.backgroundBlur",
        lyricTextSize: "lyrics.textSize",
        lyricAlignment: "lyrics.alignment",
        lyricCurrentLineAnchor: "lyrics.currentLineAnchor",
        lyricCurrentLineScale: "lyrics.currentLineScaleEnabled",
        lyricInactiveBlur: "lyrics.inactiveBlurEnabled",
        lyricSpringScrolling: "lyrics.springScrollingEnabled",
        lyricTranslation: "lyrics.showTranslation",
        lyricRomanization: "lyrics.showRomanization",
        lyricSecondaryOrder: "lyrics.secondaryLineOrder",
        lyricChineseConversion: "lyrics.chineseConversion",
        lyricWordTiming: "lyrics.wordTimingEnabled",
        lyricKaraoke: "lyrics.karaokeEnabled",
        shortcutPlayPause: "shortcuts.application.playPause",
        shortcutPrevious: "shortcuts.application.previous",
        shortcutNext: "shortcuts.application.next",
        shortcutFocusSearch: "shortcuts.application.focusSearch",
        shortcutReset: "shortcuts.resetDefaults",
        globalShortcutsEnabled: "shortcuts.global.enabled",
        globalShortcutPlayPause: "shortcuts.global.playPause",
        globalShortcutPrevious: "shortcuts.global.previous",
        globalShortcutNext: "shortcuts.global.next",
        globalShortcutVolumeUp: "shortcuts.global.volumeUp",
        globalShortcutVolumeDown: "shortcuts.global.volumeDown",
        globalShortcutReset: "shortcuts.global.resetDefaults",
        accountNeteaseCookie: "account.netease.inputCookie",
        accountBilibiliCookie: "account.bilibili.inputCookie",
        accountBilibiliSource: "account.bilibili.sourceEnabled",
        settingsExport: "settingsBackup.export",
        includeDevicePaths: "settingsBackup.includeDevicePaths",
        settingsImport: "settingsBackup.import",
        devicePathHandling: "settingsBackup.devicePathHandling",
        settingsReset: "settings.resetDefaults",
        downloadEnabled: "download.enabled",
        downloadFolder: "download.folder",
        downloadFileNameTemplate: "download.fileNameTemplate",
        downloadMaxConcurrent: "download.maxConcurrent",
        downloadExistingFilePolicy: "download.existingFilePolicy",
        downloadExternalLyrics: "download.lyrics.externalFile",
        downloadLyricEncoding: "download.lyrics.encoding",
        downloadLyricContent: "download.lyrics.content",
        downloadEmbedContent: "download.embedContent",
        downloadAlternateSource: "download.tryAlternateSource",
        sourceActiveId: "source.activeId",
        sourceNameStyle: "source.nameStyle",
        sourceImportFile: "source.importFile",
        sourceImportUrl: "source.importUrl",
        sourceUpdateNotifications: "source.updateNotificationsEnabled",
        appearanceMode: "appearance.mode",
        windowTransparency: "window.transparencyEnabled",
        closeAction: "window.closeAction",
        askBeforeClosing: "window.askBeforeClosing",
        systemTray: "tray.enabled",
        trayIconStyle: "tray.iconStyle",
        focusSearchOnLaunch: "search.focusOnLaunch",
        rememberListPosition: "list.rememberScrollPosition",
        clearResourceCache: "cache.resources.clear",
        clearLibraryIndex: "library.clearIndex",
        clearMyLists: "playlist.clearSavedLists",
        copyDiagnostics: "diagnostics.copy",
        checkUpdates: "updates.checkManually",
        openReleasePage: "updates.openReleasePage",
        openLicenses: "about.licenses"
    })

    signal closeRequested
    signal refreshRateChanged(int value)
    signal themeToggleRequested
    signal settingChanged(string key, var value)
    signal scanRequested
    signal mergeRequested
    signal sourceSelectionRequested(string sourceId)
    signal sourceUpdatePromptChanged(string sourceId, bool enabled)
    signal sourceRemoveRequested(string sourceId)
    signal sourceImportLocalRequested
    signal sourceImportOnlineRequested(string url)
    signal accountCookieSaveRequested(string provider, string cookie)
    signal accountLogoutRequested(string provider)

    readonly property color surfaceColor: darkMode ? "#202a33" : "#f5f5f7"
    readonly property color sidebarColor: "transparent"
    readonly property color panelColor: darkMode ? "#98242c35" : "#adffffff"
    readonly property color primaryText: darkMode ? "#f2f5f7" : "#25272a"
    readonly property color secondaryText: darkMode ? "#d0d8e2" : "#465463"
    readonly property color accentColor: AppTheme.accent

    function showNotice(text) {
        noticeText = text
        noticeTimer.restart()
    }

    function currentSourceName() {
        for (let i = 0; i < sourceEntries.length; ++i) {
            if (sourceEntries[i].id === currentSourceId)
                return sourceEntries[i].name
        }
        return qsTr("无")
    }

    function selectSource(sourceId) {
        if (sourceController) { sourceController.selectSource(sourceId); return }
        currentSourceId = sourceId
        settingChanged(settingKeys.sourceActiveId, sourceId)
        sourceSelectionRequested(sourceId)
    }

    function setSourceUpdatePrompt(sourceId, enabled) {
        if (sourceController) { sourceController.setUpdatePrompt(sourceId, enabled); return }
        const next = sourceEntries.slice()
        for (let i = 0; i < next.length; ++i) {
            if (next[i].id !== sourceId)
                continue
            next[i] = Object.assign({}, next[i], { updatePrompt: enabled })
            break
        }
        sourceEntries = next
        settingChanged("source.updatePrompt." + sourceId, enabled)
        sourceUpdatePromptChanged(sourceId, enabled)
    }

    function removeSource(sourceId) {
        if (sourceController) { sourceController.removeSource(sourceId); return }
        const next = []
        for (let i = 0; i < sourceEntries.length; ++i) {
            if (sourceEntries[i].id !== sourceId)
                next.push(sourceEntries[i])
        }
        sourceEntries = next
        if (currentSourceId === sourceId)
            selectSource(next.length ? next[0].id : "")
        sourceRemoveRequested(sourceId)
    }

    function openAccountCookie(provider) {
        accountCookieProvider = provider
        accountCookieOpen = true
    }

    function accountLoggedIn(provider) {
        const accountName = provider === "netease" ? neteaseAccountName : bilibiliAccountName
        return accountName.length > 0 && accountName !== qsTr("失败")
    }

    function handleAccountAction(provider) {
        if (accountLoggedIn(provider))
            accountLogoutRequested(provider)
        else
            openAccountCookie(provider)
    }

    // Backend callback after it has tested the cookie.  Account names and
    // secrets are deliberately not persisted inside this QML page.
    function setAccountTestResult(provider, success, accountName) {
        const result = success ? String(accountName || "") : qsTr("失败")
        if (provider === "netease")
            neteaseAccountName = result
        else if (provider === "bilibili")
            bilibiliAccountName = result
    }

    function handleSettingChanged(key, value) {
        if (key === "shortcuts.global.enabled" || key === "shortcuts.application.enabled") {
            if (shortcutService) shortcutService.setEnabled(key.split(".")[1], Boolean(value))
            return
        }
        if (key === settingKeys.fontFamily)
            selectedFont = String(value)
        else if (key === settingKeys.motionEnabled)
            animationsEnabled = Boolean(value)
        else if (key === settingKeys.motionStyle)
            animationStyle = String(value)
        else if (key === settingKeys.systemTray)
            systemTrayEnabled = value
        else if (key === settingKeys.appearanceMode) {
            if ((value === "Dark" && !darkMode) || (value === "Light" && darkMode))
                themeToggleRequested()
        }

        settingChanged(key, value)
    }

    function selectedFontIndex() {
        for (let i = 0; i < fontOptions.length; ++i) {
            const option = fontOptions[i]
            const value = option && typeof option === "object" && option.value !== undefined ? option.value : option
            if (String(value) === selectedFont)
                return i
        }
        return 0
    }

    FileDialog {
        id: backgroundImagePicker
        title: qsTr("选择背景图片"); nameFilters: [qsTr("图片 (*.jpg *.jpeg *.png *.webp *.bmp)")]
        onAccepted: { page.handleSettingChanged("background.image",String(selectedFile));page.handleSettingChanged("background.type","Image") }
    }
    function backgroundPathDetail(key, description) {
        const source = setting(key, "")
        return source && settingsStore ? settingsStore.localFilePath(source) || source : description
    }
    function acceptBackgroundFile(file, wallpaper) {
        if (!settingsStore) return
        const result = settingsStore.resolveBackground(file, wallpaper)
        if (result.error) { showNotice(result.error); return }
        page.handleSettingChanged(wallpaper ? "background.wallpaper" : "background.video", String(file))
    }
    FileDialog {
        id: backgroundVideoPicker
        objectName: "backgroundVideoPicker"
        title: qsTr("选择背景视频")
        nameFilters: [qsTr("视频 (*.mp4 *.m4v *.mov *.mkv *.webm *.avi *.wmv)")]
        onAccepted: page.acceptBackgroundFile(selectedFile, false)
    }
    WallpaperPickerPopup {
        id: backgroundWallpaperPicker
        settingsStore: page.settingsStore
        selectedProject: page.setting("background.wallpaper", "")
        extraFolder: page.setting("background.wallpaperFolder", "")
        onWallpaperSelected: project => page.acceptBackgroundFile(project, true)
        onFolderSelected: folder => page.handleSettingChanged("background.wallpaperFolder", String(folder))
    }
    ColorPickerPopup {
        id: backgroundColorPicker
        onColorEdited: value => page.handleSettingChanged("background.color",String(value))
    }
    function handleAction(key) {
        if(key === settingKeys.settingsExport || key === settingKeys.settingsImport || key === settingKeys.settingsReset) {
            transferDialog.begin(key === settingKeys.settingsExport ? "export" : key === settingKeys.settingsImport ? "import" : "reset")
            return
        }
        if([settingKeys.copyDiagnostics,settingKeys.checkUpdates,settingKeys.openReleasePage,settingKeys.openLicenses].indexOf(key)>=0) { backendPlatform.action(key);return }
        if (key === settingKeys.shortcutReset || key === settingKeys.globalShortcutReset) {
            if (shortcutService) shortcutService.cancelCapture()
            shortcutResetDialog.group = key === settingKeys.shortcutReset ? "application" : "global"
            shortcutResetDialog.open = true
            shortcutResetDialog.forceActiveFocus()
            return
        }
        if(key==="background.chooseImage"){backgroundImagePicker.open();return}
        if(key==="background.chooseVideo"){backgroundVideoPicker.open();return}
        if(key==="background.chooseWallpaper"){backgroundWallpaperPicker.open();return}
        if(key==="background.chooseColor"){backgroundColorPicker.selectedColor=setting("background.color","#c8bad9");backgroundColorPicker.open();return}
        if ([settingKeys.clearResourceCache, settingKeys.clearLibraryIndex, settingKeys.clearMyLists, settingKeys.clearShuffleHistory].indexOf(key) >= 0) { backendPlatform.action(key); return }
        if (key === settingKeys.downloadFolder && downloadController) { downloadController.chooseFolder(); return }
        if (key === settingKeys.rescanLibrary) {
            if (page.libraryController && page.libraryController.scanning) {
                page.libraryController.cancel()
                page.showNotice(qsTr("正在取消扫描…"))
            } else {
                scanRequested()
                page.showNotice(qsTr("正在扫描音乐目录…"))
            }
        } else if (key === settingKeys.analyzeDuplicates) {
            noticeText = ""
            mergeRequested()
        } else if (key === settingKeys.addLibraryFolder) {
            libraryFolderDialog.open()
        } else if (key.startsWith(settingKeys.removeLibraryFolder + ":")) {
            const path = key.substring(settingKeys.removeLibraryFolder.length + 1)
            if (page.libraryController && page.libraryController.removeRoot(path))
                page.showNotice(qsTr("已移除目录及其索引"))
            else
                page.showNotice(qsTr("目录不存在或删除失败"))
        } else if (key === settingKeys.accountNeteaseCookie) {
            handleAccountAction("netease")
        } else if (key === settingKeys.accountBilibiliCookie) {
            handleAccountAction("bilibili")
        } else {
            page.showNotice(qsTr("操作接口已预留"))
        }
    }

    function localPath(url) {
        let path = url.toString()
        if (path.startsWith("file:///"))
            path = path.substring(8)
        else if (path.startsWith("file://"))
            path = path.substring(7)
        return decodeURIComponent(path)
    }

    SettingsTransferDialog {
        id: transferDialog; anchors.fill: parent; z: 310
        service: typeof backendSettingsTransfer !== "undefined" ? backendSettingsTransfer : null
    }

    Connections {
        target: page.shortcutService
        function onChanged() {
            if (!page.visible || !page.shortcutService.error.length) return
            page.showNotice(page.shortcutService.error)
            function findRow(item, key) {
                if (item.objectName === "settingRow/" + key) return item
                for (let child of item.children || []) {
                    const found = findRow(child, key)
                    if (found) return found
                }
                return null
            }
            const row = findRow(body, page.shortcutService.conflictKey)
            if (row && row.visible) scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, row.mapToItem(body, 0, 0).y - 24))
        }
    }
    AlertDialog {
        id: shortcutResetDialog
        objectName: "shortcutResetDialog"
        anchors.fill: parent
        z: 300
        property string group: "application"
        title: qsTr("恢复默认快捷键")
        message: qsTr("恢复") + (group === "global" ? qsTr("全局") : qsTr("应用内")) + qsTr("分组的默认绑定？另一分组不受影响。")
        primaryLabel: qsTr("恢复默认")
        onAccepted: { open = false; if (page.shortcutService) page.shortcutService.resetGroup(group) }
        onRejected: open = false
    }

    Connections {
        target: page.libraryController
        ignoreUnknownSignals: true

        function onScanningChanged() {
            if (!page.libraryController)
                return
            if (page.libraryController.scanning)
                page.showNotice(qsTr("正在扫描音乐目录…"))
            else if (page.libraryController.lastError && page.libraryController.lastError.length)
                page.showNotice(qsTr("扫描失败：") + page.libraryController.lastError)
            else if (page.libraryController.importedCount > 0)
                page.showNotice(qsTr("已导入 ") + page.libraryController.importedCount + qsTr(" 首歌曲"))
        }
    }

    FolderDialog {
        id: libraryFolderDialog
        title: qsTr("选择音乐目录")
        onAccepted: {
            const path = page.localPath(libraryFolderDialog.selectedFolder)
            if (!page.libraryController || !page.libraryController.addRoot(path))
                page.showNotice(qsTr("目录无效、重复或与现有目录重叠"))
            else
                page.showNotice(qsTr("已加入并开始扫描"))
        }
    }

    Rectangle { anchors.fill: parent; color: "transparent" }

    Rectangle {
        id: categoryPane
        width: 223
        height: parent.height
        color: page.sidebarColor


        Column {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 22
            spacing: 3

            Text {
                text: qsTr("设置")
                color: AppTheme.canvasText
                font.family: AppTheme.fontFamily
                font.pixelSize: 27
                font.weight: Font.DemiBold
                bottomPadding: 12
            }

            Repeater {
                model: page.categories
                delegate: Rectangle {
                    id: categoryDelegate
                    objectName: "settingsCategory" + index
                    visible: page.matchingCategories.indexOf(index) >= 0
                    required property int index
                    required property string modelData
                    width: parent.width
                    height: 34
                    radius: 9
                    color: categoryDelegate.index === page.selectedCategory ? AppTheme.canvasSelected : categoryHover.hovered ? AppTheme.canvasHover : "transparent"
                    Behavior on color { ColorAnimation { duration: AppTheme.duration(90) } }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: categoryDelegate.modelData
                        color: AppTheme.canvasText
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 13
                        font.weight: categoryDelegate.index === page.selectedCategory ? Font.DemiBold : Font.Normal
                    }
                    HoverHandler { id: categoryHover }
                    TapHandler { onTapped: page.selectedCategory = categoryDelegate.index }
                }
            }

            Item { width: 1; height: 7 }
            Rectangle {
                width: 144
                height: 34
                radius: 17
                color: returnHover.hovered ? (page.darkMode ? "#28ffffff" : "#ffffff") : AppTheme.canvasSelected
                border.width: 1
                border.color: page.darkMode ? "#52606b" : "#d2d6da"
                Text { anchors.centerIn: parent; text: qsTr("‹  返回播放器"); color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
                HoverHandler { id: returnHover }
                TapHandler { onTapped: page.closeRequested() }
            }
        }
    }

    Flickable {
        id: scroll
        x: categoryPane.width
        width: parent.width - categoryPane.width
        height: parent.height
        contentWidth: width
        contentHeight: body.height + 36
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2500

        Column {
            id: body
            x: 29
            y: 23
            width: scroll.width - 58
            spacing: 13

            Text {
                text: page.selectedCategory < 0 ? qsTr("没有匹配的设置") : page.categories[page.selectedCategory]
                color: AppTheme.canvasText
                font.family: AppTheme.fontFamily
                font.pixelSize: 28
                font.weight: Font.Medium
                font.letterSpacing: -0.4
            }
            Text {
                width: parent.width
                text: page.selectedCategory < 0 ? qsTr("试试其他关键词，或清空搜索以显示全部设置。") : page.categoryDescriptions[page.selectedCategory]
                color: AppTheme.canvasSecondary
                font.family: AppTheme.fontFamily
                font.pixelSize: 12
                bottomPadding: 4
            }

            SettingsGroup {
                categoryIndex: 0
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("语言与启动")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("语言"), detail: qsTr("立即切换界面文字，不改变技术键。"), key: page.settingKeys.language, type: "select", options: [{label: qsTr("简体中文"), value: "ZhCn"}, {label: "English", value: "EnUs"}], currentIndex: 0 },
                    { title: qsTr("字体"), detail: qsTr("选择本机安装的字体，立即应用。"), key: page.settingKeys.fontFamily, type: "select", options: page.fontOptions, currentIndex: page.selectedFontIndex() },
                    { title: qsTr("登录时启动"), detail: qsTr("登录 Windows 后启动 ListenFree。"), key: page.settingKeys.launchAtLogin, type: "toggle", checked: false },
                    { title: qsTr("启动时全屏"), detail: qsTr("仅影响下次启动。"), key: page.settingKeys.startInFullScreen, type: "toggle", checked: false }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }

            Text {
                visible: page.selectedCategory === 0 && (animationSettings.hasMatches || refreshSettings.hasMatches)
                text: qsTr("显示设置")
                color: AppTheme.canvasSecondary
                font.family: AppTheme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 0.3
            }

            Rectangle {
                id: animationSettings
                property int categoryIndex: 0
                readonly property bool animationMatches: page.matches(qsTr("显示设置 应用动画 关闭后组件立即切换 开启动效"), 0)
                readonly property bool styleMatches: page.matches(qsTr("显示设置 动效节奏 动画风格 优雅 明快"), 0)
                readonly property bool hasMatches: animationMatches || styleMatches
                visible: page.selectedCategory === 0 && hasMatches
                width: parent.width
                height: (animationMatches ? 86 : 0) + (styleMatches && (page.animationsEnabled || page.filterText.length) ? 50 : 0)
                radius: 14
                color: page.panelColor
                border.width: 1
                border.color: page.darkMode ? "#46515b" : "#e1e1e3"
                Behavior on height {
                    NumberAnimation {
                        duration: page.animationsEnabled ? AppTheme.duration(180) : 0
                        easing.type: Easing.OutCubic
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 15
                    visible: animationSettings.animationMatches
                    text: qsTr("应用动画")
                    color: page.primaryText
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: animationSwitch.left
                    anchors.rightMargin: 18
                    anchors.top: parent.top
                    anchors.topMargin: 39
                    visible: animationSettings.animationMatches
                    text: qsTr("关闭后组件立即切换；开启后可选择动效节奏。")
                    color: page.secondaryText
                    elide: Text.ElideRight
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 11
                }
                SettingsSwitch {
                    id: animationSwitch
                    visible: animationSettings.animationMatches
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 15
                    checked: page.animationsEnabled
                    darkMode: page.darkMode
                    onToggled: checked => page.handleSettingChanged(page.settingKeys.motionEnabled, checked)
                }
                SegmentedTabBar {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    visible: animationSettings.styleMatches && (page.animationsEnabled || page.filterText.length > 0)
                    enabled: page.animationsEnabled
                    model: [{ label: qsTr("优雅"), value: "Elegant" }, { label: qsTr("明快"), value: "Bright" }]
                    currentIndex: page.animationStyle === "Bright" ? 1 : 0
                    cellWidth: 88
                    cellHeight: 30
                    cellRadius: 15
                    outerPadding: 1
                    textColor: page.primaryText
                    hoverBackground: page.darkMode ? "#22ffffff" : "#0a000000"
                    darkMode: page.darkMode
                    reduceMotion: !page.animationsEnabled
                    onSelected: (index, value) => page.handleSettingChanged(page.settingKeys.motionStyle,
                                                                            value && value.value ? value.value : (index === 0 ? "Elegant" : "Bright"))
                }
            }

            Rectangle {
                id: refreshSettings
                property int categoryIndex: 0
                readonly property bool hasMatches: page.matches(qsTr("显示设置 界面刷新率上限 限制界面动画和歌词滚动的最高刷新率 不修改显示器设置 60 90 120 Hz"), 0)
                visible: page.selectedCategory === 0 && hasMatches
                width: parent.width
                height: 108
                radius: 14
                color: page.panelColor
                border.width: 1
                border.color: page.darkMode ? "#46515b" : "#e1e1e3"
                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 7
                    Text { text: qsTr("界面刷新率上限"); color: page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { text: qsTr("限制界面动画和歌词滚动的最高刷新率，不修改显示器设置。"); color: page.secondaryText; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                    Row {
                        spacing: 9
                        Repeater {
                            model: [60, 90, 120]
                            delegate: Rectangle {
                                id: rateDelegate
                                required property int modelData
                                width: 88
                                height: 30
                                radius: 15
                                color: page.refreshRateLimit === rateDelegate.modelData ? AppTheme.selected : rateHover.hovered ? (page.darkMode ? "#45515b" : "#ffffff") : (page.darkMode ? "#36424c" : "#edf1f3")
                                border.width: 1
                                border.color: page.refreshRateLimit === rateDelegate.modelData ? page.accentColor : (page.darkMode ? "#55616b" : "#d5dde2")
                                Text { anchors.centerIn: parent; text: rateDelegate.modelData + " Hz"; color: page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
                                HoverHandler { id: rateHover }
                                TapHandler {
                                    onTapped: {
                                        page.refreshRateLimit = rateDelegate.modelData
                                        page.refreshRateChanged(rateDelegate.modelData)
                                        page.settingChanged(page.settingKeys.refreshRateLimit, rateDelegate.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SettingsGroup {
                categoryIndex: 1
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("资料库概览")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("歌曲"), detail: qsTr("当前资料库中的可搜索歌曲。"), type: "info", readOnlyValue: page.libraryController ? String(page.libraryController.totalCount || 0) : "0" },
                    { title: qsTr("音乐目录"), detail: qsTr("已经加入监控和扫描的文件夹。"), type: "info",
                      readOnlyValue: page.libraryController ? String(page.libraryController.roots.length) : "0" },
                    { title: qsTr("索引状态"), detail: qsTr("最近一次资料库任务状态。"), type: "info", readOnlyValue: page.libraryController && page.libraryController.scanning ? qsTr("扫描中") : qsTr("已就绪") }
                ]
            }
            SettingsGroup {
                categoryIndex: 1
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("音乐目录")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("添加音乐目录"), detail: qsTr("选择一个文件夹并递归扫描子目录。"), key: page.settingKeys.addLibraryFolder, type: "action", actionLabel: qsTr("添加") },
                    { title: qsTr("自动监听音乐目录"), detail: qsTr("下载或复制完成后，自动将已添加目录中的新音乐加入资料库。"), key: "library.autoWatch", type: "toggle", checked: true },
                    ...((page.libraryController && page.libraryController.roots ? page.libraryController.roots : []).map(path => ({
                        title: path,
                        detail: qsTr("移除后停止监控此目录，并从资料库索引中删除其歌曲。"),
                        key: page.settingKeys.removeLibraryFolder + ":" + path,
                        type: "action",
                        actionLabel: qsTr("移除")
                    }))),
                    { title: qsTr("重新扫描资料库"), detail: qsTr("扫描所有已配置目录，也会重新加入仅从资料库移除的歌曲。"), key: page.settingKeys.rescanLibrary, type: "action", actionLabel: page.libraryController && page.libraryController.scanning ? qsTr("取消") : qsTr("扫描") },
                    { title: qsTr("合并重复歌曲"), detail: qsTr("先按大小和完整哈希执行只读分析。"), key: page.settingKeys.analyzeDuplicates, type: "action", actionLabel: qsTr("检查") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            SettingsGroup {
                categoryIndex: 2
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("启动与队列")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("启动后自动播放"), detail: qsTr("仅在恢复的队列中存在可播放歌曲时生效。"), key: page.settingKeys.autoPlayOnLaunch, type: "toggle", checked: false },
                    { title: qsTr("恢复播放位置"), detail: qsTr("恢复队列、当前歌曲和进度。"), key: page.settingKeys.restorePosition, type: "toggle", checked: true },
                    { title: qsTr("默认播放模式"), detail: qsTr("浮岛运行时选择会同步覆盖此值。"), key: page.settingKeys.defaultPlaybackMode, type: "select", options: [{label:qsTr("列表循环"),value:"LoopAll"},{label:qsTr("随机播放"),value:"Shuffle"},{label:qsTr("单曲循环"),value:"LoopOne"},{label:qsTr("无尽模式"),value:"Endless"},{label:qsTr("播完停止"),value:"StopAfterCurrent"}], currentIndex: 0 },
                    { title: qsTr("歌曲播放行为"), detail: qsTr("双击歌曲或点击播放时，决定如何使用所在列表。"), key: page.settingKeys.playActionBehavior, type: "select", options: [{label:qsTr("加入到队列"),value:"AppendToQueue"},{label:qsTr("切换到当前列表"),value:"ReplaceCurrentList"}], currentIndex: 0 },
                    { title: qsTr("随机播放后清理历史"), detail: qsTr("一轮播放后重新随机；关闭则保留本轮随机顺序。"), key: page.settingKeys.clearShuffleHistory, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }
            SettingsGroup {
                categoryIndex: 2
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("音频输出")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("输出设备"), detail: qsTr("设备消失时回退到系统默认。"), key: page.settingKeys.outputDeviceId, type: "select", options: page.playerController ? page.playerController.outputDevices : [{label:qsTr("系统默认"),value:"default"}], currentIndex: 0 },
                    { title: qsTr("设备断开时暂停"), detail: qsTr("仅作用于选定的非默认设备。"), key: page.settingKeys.pauseOnDeviceRemoval, type: "toggle", checked: true },
                    { title: qsTr("播放时防止系统休眠"), detail: qsTr("暂停和停止时释放系统请求。"), key: page.settingKeys.preventSystemSleep, type: "toggle", checked: true },
                    { title: qsTr("任务栏显示播放进度"), detail: qsTr("不影响浮岛进度条。"), key: page.settingKeys.showTaskbarProgress, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }
            SettingsGroup {
                categoryIndex: 2
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("音质与播放错误")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("智能过渡"), detail: qsTr("分析近静音尾部并平滑衔接；连续专辑、直播及不兼容格式保留普通播放。"), key: "playback.transition.smart", type: "toggle", checked: false },
                    { title: qsTr("在线播放音质"), detail: qsTr("优先请求所选音质；当前音源不支持时使用可用音质。"), key: "playback.quality", type: "select", options: [{label:qsTr("无损 FLAC"),value:"flac"},{label:qsTr("高品质 320k"),value:"320k"},{label:qsTr("标准 128k"),value:"128k"}], currentIndex: 0 },
                    { title: qsTr("播放错误时自动跳过"), detail: qsTr("连续五首失败后停止并汇总错误。"), key: page.settingKeys.skipOnError, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }

            SettingsGroup {
                categoryIndex: 3
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("播放详情与应用背景")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("播放器样式"), detail: qsTr("经典保留方形封面；满溢将封面铺满左侧，底边悬停显示控件。"), key: "nowPlaying.playerStyle", type: "select", options: [{label:qsTr("经典"),value:"Classic"},{label:qsTr("满溢"),value:"Overflow"}], currentIndex: 0 },
                    { title: qsTr("动态封面"), detail: qsTr("播放详情使用动态封面；不可用时显示静态封面。"), key: "appearance.dynamicArtworkEnabled", type: "toggle", checked: page.dynamicArtworkEnabled },
                    { title: qsTr("专辑页样式"), detail: qsTr("轮转、网格或可拖拽的拼窗；搜索专辑默认使用网格。"), key: "appearance.albumLayout", type: "select", options: [{label:qsTr("轮转"),value:"Flow"},{label:qsTr("网格"),value:"Grid"},{label:qsTr("拼窗"),value:"Mosaic"}], currentIndex: 0 },
                    { title: qsTr("播放详情背景样式"), detail: qsTr("适用于经典播放器；满溢自动使用封面模糊背景。"), enabled: page.setting("nowPlaying.playerStyle", "Classic") === "Classic", key: page.settingKeys.backgroundStyle, type: "select", options: [{label:qsTr("纯色"),value:"SolidMaterial"},{label:qsTr("模糊背景"),value:"BlurredArtwork"},{label:qsTr("动态流转"),value:"DynamicFlow"}], currentIndex: 0 },
                    { title: qsTr("背景类型"), detail: qsTr("应用于主界面，不影响播放详情背景。"), key: "background.type", type: "select", options: [{label:qsTr("自动封面"),value:"AutoCover"},{label:qsTr("自选图片"),value:"Image"},{label:qsTr("自选颜色"),value:"Color"},{label:qsTr("本地视频"),value:"Video"},{label:qsTr("Wallpaper Engine"),value:"Wallpaper"}], currentIndex: 0 },
                    { title: qsTr("背景图片"), detail: page.backgroundPathDetail("background.image", qsTr("默认使用细颗粒渐变，也可选择本地图片。")), key: "background.chooseImage", type: "action", actionLabel: qsTr("选择图片"), visible: page.setting("background.type","AutoCover")==="Image" },
                    { title: qsTr("背景颜色"), detail: page.setting("background.color", "") || qsTr("选择喜欢的颜色。"), key: "background.chooseColor", type: "action", actionLabel: qsTr("选择颜色"), visible: page.setting("background.type","AutoCover")==="Color" },
                    { title: qsTr("背景视频"), detail: page.backgroundPathDetail("background.video", qsTr("选择本地视频，静音循环播放。")), key: "background.chooseVideo", type: "action", actionLabel: qsTr("选择视频"), visible: page.setting("background.type","AutoCover")==="Video" },
                    { title: qsTr("Wallpaper 壁纸"), detail: page.backgroundPathDetail("background.wallpaper", qsTr("自动查找已下载的视频壁纸，点击预览即可选择。")), key: "background.chooseWallpaper", type: "action", actionLabel: qsTr("选择壁纸"), visible: page.setting("background.type","AutoCover")==="Wallpaper" },
                    { title: qsTr("背景模糊度"), detail: qsTr("0 px 为清晰；自动封面默认随窗口大小适配。"), key: page.setting("background.type","AutoCover") === "AutoCover" ? "background.autoBlurPx" : "background.blur", type: "slider", numericValue: page.setting("background.type","AutoCover") === "AutoCover" ? Math.round((page.Window.window ? page.Window.window.width : 1066)*.03) : 56, minimumValue: 0, maximumValue: 192, stepSize: 1, valueSuffix: " px", enabled: page.setting("background.type","AutoCover")!=="Color" },
                    { title: qsTr("遮罩透明度"), detail: qsTr("黑色遮罩的不透明度，0% 完全透明。"), key: "background.mask", type: "slider", numericValue: 0, minimumValue: 0, maximumValue: 100, stepSize: 1, valueSuffix: "%" }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }
            SettingsGroup {
                categoryIndex: 3
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("歌词")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("歌词字号"), detail: qsTr("主歌词 16–48 px，翻译按比例缩放。"), key: page.settingKeys.lyricTextSize, type: "slider", numericValue: 28, minimumValue: 16, maximumValue: 48, stepSize: 1, valueSuffix: " px" },
                    { title: qsTr("歌词对齐"), detail: qsTr("设置 Now Playing 中的歌词行对齐。"), key: page.settingKeys.lyricAlignment, type: "select", options: [{label:qsTr("左对齐"),value:"Left"},{label:qsTr("居中"),value:"Center"},{label:qsTr("右对齐"),value:"Right"}], currentIndex: 1 },
                    { title: qsTr("当前歌词位置"), detail: qsTr("当前行在歌词视口中的锚点。"), key: page.settingKeys.lyricCurrentLineAnchor, type: "select", options: [{label:qsTr("居中"),value:"Center"},{label:qsTr("偏上"),value:"Upper"},{label:qsTr("偏下"),value:"Lower"}], currentIndex: 0 },
                    { title: qsTr("强调当前歌词"), detail: qsTr("只调整缩放和字重。"), key: page.settingKeys.lyricCurrentLineScale, type: "toggle", checked: true },
                    { title: qsTr("模糊非当前歌词"), detail: qsTr("性能降级时使用透明度替代。"), key: page.settingKeys.lyricInactiveBlur, type: "toggle", checked: true },
                    { title: qsTr("弹性滚动"), detail: qsTr("关闭界面动画后自动禁用。"), key: page.settingKeys.lyricSpringScrolling, type: "toggle", checked: true },
                    { title: qsTr("显示翻译"), detail: qsTr("无翻译时不显示空行。"), key: page.settingKeys.lyricTranslation, type: "check", checked: page.translationEnabled },
                    { title: qsTr("显示罗马音"), detail: qsTr("无罗马音时不显示空行。"), key: page.settingKeys.lyricRomanization, type: "check", checked: page.romanizationEnabled },
                    { title: qsTr("辅助歌词顺序"), detail: qsTr("翻译和罗马音都开启时可选。"), key: page.settingKeys.lyricSecondaryOrder, type: "select", options: [{label:qsTr("翻译优先"),value:"TranslationFirst"},{label:qsTr("罗马音优先"),value:"RomanizationFirst"}], currentIndex: 0, enabled: page.translationEnabled && page.romanizationEnabled },
                    { title: qsTr("中文转换"), detail: qsTr("只转换显示文本，不改写标签。"), key: page.settingKeys.lyricChineseConversion, type: "select", options: [{label:qsTr("关闭"),value:"Off"},{label:qsTr("转简体"),value:"Simplified"},{label:qsTr("转繁体"),value:"Traditional"}], currentIndex: 0 },
                    { title: qsTr("逐字歌词"), detail: qsTr("无逐字数据时自动回退逐行显示。"), key: page.settingKeys.lyricWordTiming, type: "toggle", checked: true },
                    { title: qsTr("卡拉 OK 高亮"), detail: qsTr("逐字时间存在时生效。"), key: page.settingKeys.lyricKaraoke, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }

            SettingsGroup {
                categoryIndex: 4
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("文件保存")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("启用下载"), detail: qsTr("关闭时不接受新任务，现有任务继续完成。"), key: page.settingKeys.downloadEnabled, type: "toggle", checked: true },
                    { title: qsTr("下载目录"), detail: page.setting("download.folder", qsTr("选择用于保存在线歌曲的文件夹。")), key: page.settingKeys.downloadFolder, type: "action", actionLabel: qsTr("选择") },
                    { title: qsTr("文件命名"), detail: qsTr("非法文件名字符将自动替换。"), key: page.settingKeys.downloadFileNameTemplate, type: "select", options: [{label:qsTr("歌曲名 - 艺术家"),value:"TitleArtist"},{label:qsTr("艺术家 - 歌曲名"),value:"ArtistTitle"},{label:qsTr("仅歌曲名"),value:"TitleOnly"}], currentIndex: 0 },
                    { title: qsTr("同时下载数"), detail: qsTr("修改只影响后续调度。"), key: page.settingKeys.downloadMaxConcurrent, type: "select", options: [{label:"1",value:1},{label:"2",value:2},{label:"3",value:3},{label:"4",value:4},{label:"5",value:5},{label:"6",value:6}], currentIndex: 0 },
                    { title: qsTr("同名文件处理"), detail: qsTr("覆盖前仍会验证目标是普通文件。"), key: page.settingKeys.downloadExistingFilePolicy, type: "select", options: [{label:qsTr("跳过"),value:"Skip"},{label:qsTr("自动重命名"),value:"AutoRename"},{label:qsTr("覆盖"),value:"Overwrite"}], currentIndex: 0 }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }
            SettingsGroup {
                categoryIndex: 4
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("歌词文件")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("保存独立歌词文件"), detail: qsTr("额外生成 LRC，内嵌歌词仍会写入。"), key: page.settingKeys.downloadExternalLyrics, type: "toggle", checked: false },
                    { title: qsTr("歌词编码"), detail: qsTr("只影响独立歌词文件。"), key: page.settingKeys.downloadLyricEncoding, type: "select", options: [{label:"UTF-8",value:"Utf8"},{label:"GBK",value:"Gbk"}], currentIndex: 0 },
                    { title: qsTr("原文"), detail: qsTr("写入可用的原文歌词。"), key: page.settingKeys.downloadLyricContent, type: "check", optionValue: "Original", checked: true },
                    { title: qsTr("翻译"), detail: qsTr("无翻译数据时自动跳过。"), key: page.settingKeys.downloadLyricContent, type: "check", optionValue: "Translation", checked: true },
                    { title: qsTr("罗马音"), detail: qsTr("无罗马音数据时自动跳过。"), key: page.settingKeys.downloadLyricContent, type: "check", optionValue: "Romanization", checked: false },
                    { title: qsTr("逐字信息"), detail: qsTr("保留可用的逐字时间数据。"), key: page.settingKeys.downloadLyricContent, type: "check", optionValue: "WordTiming", checked: false }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }
            SettingsGroup {
                categoryIndex: 4
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("嵌入音频文件")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("封面"), detail: qsTr("格式不支持时自动跳过。"), key: page.settingKeys.downloadEmbedContent, type: "check", optionValue: "Artwork", checked: true },
                    { title: qsTr("歌词"), detail: qsTr("内容受上方歌词内容选项控制。"), key: page.settingKeys.downloadEmbedContent, type: "check", optionValue: "Lyrics", checked: true },
                    { title: qsTr("艺术家"), detail: qsTr("写入可用的艺术家标签。"), key: page.settingKeys.downloadEmbedContent, type: "check", optionValue: "Artist", checked: true },
                    { title: qsTr("专辑"), detail: qsTr("写入可用的专辑标签。"), key: page.settingKeys.downloadEmbedContent, type: "check", optionValue: "Album", checked: false },
                    { title: qsTr("尝试其他音源"), detail: qsTr("解析失败时依次尝试已导入的其他音源，不切换当前播放音源。"), key: page.settingKeys.downloadAlternateSource, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }

            Column {
                property int categoryIndex: 5
                readonly property bool hasMatches: page.matches(qsTr("音源选择与管理 当前音源 同一时间最多选择一个音源 切换请进入音源管理 ") + page.currentSourceName(), 5)
                visible: page.selectedCategory === 5 && hasMatches
                width: parent.width
                spacing: 7

                Text {
                    text: qsTr("音源选择与管理")
                    color: page.secondaryText
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 10
                    font.letterSpacing: 0.3
                }

                Rectangle {
                    width: parent.width
                    height: 64
                    radius: 14
                    color: page.panelColor
                    border.width: 1
                    border.color: page.darkMode ? "#46515b" : "#e1e1e3"

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.right: manageSourceButton.left
                        anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: qsTr("当前音源  ·  ") + page.currentSourceName()
                            color: page.primaryText
                            elide: Text.ElideRight
                            font.family: AppTheme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: qsTr("同一时间最多选择一个音源，切换请进入音源管理。")
                            color: page.secondaryText
                            elide: Text.ElideRight
                            font.family: AppTheme.fontFamily
                            font.pixelSize: 10
                        }
                    }

                    Rectangle {
                        id: manageSourceButton
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 94
                        height: 32
                        radius: 16
                        color: manageSourceHover.hovered ? page.accentColor : (page.darkMode ? "#3b4751" : "#f8fafb")
                        border.width: 1
                        border.color: manageSourceHover.hovered ? page.accentColor : (page.darkMode ? "#59656e" : "#d5dde2")
                        Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("音源管理")
                            color: manageSourceHover.hovered ? "white" : page.primaryText
                            font.family: AppTheme.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        HoverHandler { id: manageSourceHover }
                        TapHandler { onTapped: page.sourceManagerOpen = true }
                    }
                }
            }
            SettingsGroup {
                categoryIndex: 5
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("来源显示")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("来源名称"), detail: qsTr("只改变网易云、酷我等来源显示文字。"), key: page.settingKeys.sourceNameStyle, type: "select", options: [{label:qsTr("原名"),value:"Original"},{label:qsTr("别名"),value:"Alias"}], currentIndex: 1 }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }
            SettingsGroup {
                categoryIndex: 6
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("网易云音乐")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("当前账号：") + page.neteaseAccountName,
                      detail: qsTr("Cookie 只交给后端凭据服务验证与保存。"),
                      key: page.settingKeys.accountNeteaseCookie,
                      type: "action", actionLabel: page.accountLoggedIn("netease") ? qsTr("登出") : qsTr("登录") }
                ]
                onActionTriggered: key => page.handleAction(key)
            }
            SettingsGroup {
                categoryIndex: 6
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("哔哩哔哩")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("当前账号：") + page.bilibiliAccountName,
                      detail: qsTr("Cookie 只交给后端凭据服务验证与保存。"),
                      key: page.settingKeys.accountBilibiliCookie,
                      type: "action", actionLabel: page.accountLoggedIn("bilibili") ? qsTr("登出") : qsTr("登录") },
                    { title: qsTr("将哔哩哔哩纳入音源"),
                      detail: qsTr("发现页可搜索 B 站歌曲与歌单，多 P 视频作为歌单，不提供专辑。"),
                      key: page.settingKeys.accountBilibiliSource, type: "toggle", checked: false }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            SettingsGroup {
                categoryIndex: 7
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("应用内快捷键")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("启用应用内快捷键"), detail: qsTr("仅 ListenFree 获得焦点时生效。"), key: "shortcuts.application.enabled", type: "toggle", checked: true },
                    { title: qsTr("播放/暂停"), detail: qsTr("单击录入组合键，可清空。"), key: page.settingKeys.shortcutPlayPause, type: "shortcut", actionLabel: "Ctrl+F5" },
                    { title: qsTr("上一首"), detail: qsTr("单击录入组合键，可清空。"), key: page.settingKeys.shortcutPrevious, type: "shortcut", actionLabel: "Ctrl+Left" },
                    { title: qsTr("下一首"), detail: qsTr("单击录入组合键，可清空。"), key: page.settingKeys.shortcutNext, type: "shortcut", actionLabel: "Ctrl+Right" },
                    { title: qsTr("聚焦搜索"), detail: qsTr("单击录入组合键，可清空。"), key: page.settingKeys.shortcutFocusSearch, type: "shortcut", actionLabel: "F1" },
                    { title: qsTr("返回"), detail: qsTr("关闭弹窗、退出沉浸式，或将正在播放缩回迷你播放器。"), key: "shortcuts.application.back", type: "shortcut", actionLabel: "Esc" },
                    { title: qsTr("恢复默认快捷键"), detail: qsTr("重置前将使用统一确认弹窗。"), key: page.settingKeys.shortcutReset, type: "action", actionLabel: qsTr("重置") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }
            SettingsGroup {
                categoryIndex: 7
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("全局快捷键")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("启用全局快捷键"), detail: qsTr("关闭后不会向 Windows 注册组合键。"), key: page.settingKeys.globalShortcutsEnabled, type: "toggle", checked: false },
                    { title: qsTr("播放/暂停"), detail: qsTr("默认 Ctrl+Alt+F5，可清空。"), key: page.settingKeys.globalShortcutPlayPause, type: "shortcut", actionLabel: "Ctrl+Alt+F5" },
                    { title: qsTr("上一首"), detail: qsTr("默认 Ctrl+Alt+Left，可清空。"), key: page.settingKeys.globalShortcutPrevious, type: "shortcut", actionLabel: "Ctrl+Alt+Left" },
                    { title: qsTr("下一首"), detail: qsTr("默认 Ctrl+Alt+Right，可清空。"), key: page.settingKeys.globalShortcutNext, type: "shortcut", actionLabel: "Ctrl+Alt+Right" },
                    { title: qsTr("提高音量"), detail: qsTr("默认 Ctrl+Alt+Up，可清空。"), key: page.settingKeys.globalShortcutVolumeUp, type: "shortcut", actionLabel: "Ctrl+Alt+Up" },
                    { title: qsTr("降低音量"), detail: qsTr("默认 Ctrl+Alt+Down，可清空。"), key: page.settingKeys.globalShortcutVolumeDown, type: "shortcut", actionLabel: "Ctrl+Alt+Down" },
                    { title: qsTr("恢复默认快捷键"), detail: qsTr("只重置全局快捷键分组。"), key: page.settingKeys.globalShortcutReset, type: "action", actionLabel: qsTr("重置") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            SettingsGroup {
                categoryIndex: 8
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("导出与导入")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("导出设置"), detail: qsTr("不包含账号凭据、缓存、队列和播放位置。"), key: page.settingKeys.settingsExport, type: "action", actionLabel: qsTr("导出") },
                    { title: qsTr("包含本机路径"), detail: qsTr("包含音乐目录和下载目录。"), key: page.settingKeys.includeDevicePaths, type: "toggle", checked: false },
                    { title: qsTr("导入设置"), detail: qsTr("预览后再应用有效设置。"), key: page.settingKeys.settingsImport, type: "action", actionLabel: qsTr("导入") },
                    { title: qsTr("本机路径处理"), detail: qsTr("导入时忽略或创建缺失目录。"), key: page.settingKeys.devicePathHandling, type: "select", options: [{label:qsTr("忽略"),value:"Ignore"},{label:qsTr("创建路径"),value:"Create"}], currentIndex: 0 },
                    { title: qsTr("恢复默认设置"), detail: qsTr("只重置所选分类，不影响音乐文件。"), key: page.settingKeys.settingsReset, type: "action", actionLabel: qsTr("选择分类") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            SettingsGroup {
                categoryIndex: 9
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("外观模式与窗口")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("外观模式"), detail: qsTr("跟随系统、浅色或深色。"), key: page.settingKeys.appearanceMode, type: "select", options: [{label:qsTr("跟随系统"),value:"System"},{label:qsTr("浅色"),value:"Light"},{label:qsTr("深色"),value:"Dark"}], currentIndex: page.darkMode ? 2 : 0 },
                    { title: qsTr("窗口透明效果"), detail: qsTr("仅侧栏背景透出桌面，其余区域保持不透明。"), key: page.settingKeys.windowTransparency, type: "toggle", checked: true },
                    { title: qsTr("关闭按钮行为"), detail: qsTr("托盘关闭时只能退出应用。"), key: page.settingKeys.closeAction, type: "select", options: [{label:qsTr("退出应用"),value:"Quit"},{label:qsTr("最小化到托盘"),value:"MinimizeToTray"}], currentIndex: 0, enabled: page.systemTrayEnabled },
                    { title: qsTr("关闭时询问"), detail: qsTr("仅退出应用时生效。"), key: page.settingKeys.askBeforeClosing, type: "toggle", checked: true },
                    { title: qsTr("系统托盘"), detail: qsTr("关闭后隐藏托盘图标。"), key: page.settingKeys.systemTray, type: "toggle", checked: page.systemTrayEnabled },
                    { title: qsTr("托盘图标样式"), detail: qsTr("托盘关闭时不可用。"), key: page.settingKeys.trayIconStyle, type: "select", options: [{label:qsTr("自动"),value:"Auto"},{label:qsTr("浅色"),value:"Light"},{label:qsTr("深色"),value:"Dark"}], currentIndex: 0, enabled: page.systemTrayEnabled }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }
            SettingsGroup {
                categoryIndex: 9
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("搜索与列表")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("启动时聚焦搜索"), detail: qsTr("只影响主窗口首次获得焦点时。"), key: page.settingKeys.focusSearchOnLaunch, type: "toggle", checked: false },
                    { title: qsTr("记住列表位置"), detail: qsTr("只记住浏览位置，不记住查询。"), key: page.settingKeys.rememberListPosition, type: "toggle", checked: true }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
            }
            SettingsGroup {
                categoryIndex: 9
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("缓存与索引")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: qsTr("封面与界面资源缓存"), detail: qsTr("不会删除内嵌封面。"), key: page.settingKeys.clearResourceCache, type: "action", actionLabel: qsTr("清理") },
                    { title: qsTr("清空资料库索引"), detail: qsTr("不删除音乐文件和监控目录。"), key: page.settingKeys.clearLibraryIndex, type: "action", actionLabel: qsTr("清空") },
                    { title: qsTr("清空歌单收藏"), detail: qsTr("不删除电台收藏、Queue、音乐文件或远端歌单。"), key: page.settingKeys.clearMyLists, type: "action", actionLabel: qsTr("清空") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            SettingsGroup {
                categoryIndex: 10
                settingsStore: page.settingsStore
                categoryTitle: page.categories[categoryIndex]
                filterText: page.filterText
                visible: page.selectedCategory === categoryIndex && hasMatches
                width: parent.width
                section: qsTr("应用信息")
                darkMode: page.darkMode
                panelColor: page.panelColor
                sectionColor: AppTheme.canvasSecondary
                primaryText: page.primaryText
                secondaryText: page.secondaryText
                rows: [
                    { title: "ListenFree", detail: qsTr("构建于 Qt 6.11.2。"), type: "info", readOnlyValue: "0.3.7" },
                    { title: qsTr("复制诊断信息"), detail: qsTr("不会包含账号凭据和完整日志。"), key: page.settingKeys.copyDiagnostics, type: "action", actionLabel: qsTr("复制") },
                    { title: qsTr("检查软件更新"), detail: qsTr("检查 GitHub 新版本，可查看说明、下载并安装更新。"), key: page.settingKeys.checkUpdates, type: "action", actionLabel: qsTr("检查") },
                    { title: qsTr("打开下载页面"), detail: qsTr("使用系统浏览器打开 GitHub Releases。"), key: page.settingKeys.openReleasePage, type: "action", actionLabel: qsTr("打开") },
                    { title: qsTr("开源许可"), detail: qsTr("查看项目与第三方依赖许可证。"), key: page.settingKeys.openLicenses, type: "action", actionLabel: qsTr("查看") }
                ]
                onSettingChanged: (key, value) => page.handleSettingChanged(key, value)
                onActionTriggered: key => page.handleAction(key)
            }

            Item { width: 1; height: 78 }
        }


    }

    Rectangle {
        visible: page.noticeText.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: Math.min(parent.width - 40, 420)
        height: 42
        radius: 14
        color: page.darkMode ? "#ec35424c" : "#f4ffffff"
        border.width: 1
        border.color: page.darkMode ? "#59656f" : "#d6e0e5"
        z: 20
        Text { anchors.centerIn: parent; text: page.noticeText; color: page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
    }

    AlertDialog {
        id: accountCookieDialog
        objectName: "accountCookieDialog"
        anchors.fill: parent
        z: 160
        open: page.accountCookieOpen
        title: qsTr("请输入 Cookie")
        message: (page.accountCookieProvider === "netease" ? qsTr("登录网易云音乐。") : qsTr("登录哔哩哔哩。"))
                 + qsTr("粘贴已登录网页请求头中的完整 Cookie，也支持带 Cookie: 前缀。验证成功后会安全保存。")
        primaryLabel: qsTr("保存")
        secondaryLabel: qsTr("取消")
        cancelable: true
        contentComponent: Component {
            Column {
                spacing: 12
                property alias cookieText: accountCookieInput.text
                function focusInput() { accountCookieInput.forceActiveFocus() }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 12
                    color: page.darkMode ? "#35414b" : "#f7f9fa"
                    border.width: accountCookieInput.activeFocus ? 2 : 1
                    border.color: accountCookieInput.activeFocus
                                  ? page.accentColor
                                  : (page.darkMode ? "#59656e" : "#d5d9dd")

                    TextInput {
                        id: accountCookieInput
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: page.primaryText
                        selectionColor: "#586b747d"
                        selectedTextColor: page.darkMode ? "white" : "#16232d"
                        echoMode: TextInput.Password
                        passwordCharacter: "\u2022"
                        clip: true
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 12
                        Keys.onReturnPressed: accountCookieDialog.accepted(accountCookieDialog.selectedOption)
                    }

                    Text {
                        visible: accountCookieInput.text.length === 0 && !accountCookieInput.activeFocus
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("粘贴 Cookie")
                        color: page.secondaryText
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 12
                    }
                }
                UiButton {
                    objectName: "accountCookiePasteButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: qsTr("粘贴")
                    enabled: accountCookieInput.canPaste
                    opacity: enabled ? 1 : 0.45
                    onClicked: {
                        accountCookieInput.forceActiveFocus()
                        accountCookieInput.selectAll()
                        accountCookieInput.paste()
                    }
                }
            }
        }
        onRejected: {
            page.accountCookieOpen = false
            if (contentItem)
                contentItem.cookieText = ""
        }
        onAccepted: {
            const cookie = contentItem ? String(contentItem.cookieText).trim() : ""
            if (!cookie.length) {
                page.showNotice(qsTr("请输入 Cookie"))
                return
            }
            page.accountCookieOpen = false
            page.accountCookieSaveRequested(page.accountCookieProvider, cookie)
            if (contentItem)
                contentItem.cookieText = ""
        }
        onOpenChanged: {
            if (open && contentItem)
                contentItem.focusInput()
        }
    }

    Item {
        id: sourceManager
        objectName: "sourceManagerDialog"
        anchors.fill: parent
        visible: page.sourceManagerOpen
        z: 120
        focus: visible
        opacity: visible ? 1 : 0
        Keys.onEscapePressed: page.sourceManagerOpen = false
        onVisibleChanged: if (visible) forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: page.darkMode ? "#96080d12" : "#650f1b24"
            // Deliberately consume backdrop clicks.  Managing a source may
            // involve several edits, so only the close button or Escape exits.
            TapHandler { onTapped: {} }
        }

        Rectangle {
            id: sourceDialogCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 660)
            height: Math.min(parent.height - 60, 450)
            radius: 22
            color: page.darkMode ? "#f52b353e" : "#f7ffffff"
            border.width: 1
            border.color: page.darkMode ? "#63717c" : "#d8dde1"
            scale: page.sourceManagerOpen ? 1 : 0.97
            Behavior on scale { NumberAnimation { duration: AppTheme.duration(180); easing.type: Easing.OutCubic } }
            TapHandler { onTapped: {} }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.top: parent.top
                anchors.topMargin: 21
                text: qsTr("音源管理")
                color: page.primaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.top: parent.top
                anchors.topMargin: 53
                text: qsTr("当前一次只能启用一个音源；导入、移除与更新检测由后端接口完成。")
                color: page.secondaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 11
            }

            Rectangle {
                id: closeSourceManager
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.top: parent.top
                anchors.topMargin: 18
                width: 34
                height: 34
                radius: 17
                color: closeSourceHover.hovered ? (page.darkMode ? "#22ffffff" : "#0d000000") : "transparent"
                Text { anchors.centerIn: parent; text: "×"; color: page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 22 }
                HoverHandler { id: closeSourceHover }
                TapHandler { onTapped: page.sourceManagerOpen = false }
            }

            UiButton {
                objectName: "sourceReconnectButton"
                anchors.right: closeSourceManager.left
                anchors.rightMargin: 12
                anchors.verticalCenter: closeSourceManager.verticalCenter
                label: qsTr("重新连接")
                visible: page.sourceController && page.sourceController.hostAvailable
                onClicked: page.sourceController.restartHost()
            }

            Rectangle {
                id: sourceListSurface
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                anchors.top: parent.top
                anchors.topMargin: 84
                height: 250
                radius: 15
                color: page.darkMode ? "#b4212a32" : "#c8f5f6f7"
                border.width: 1
                border.color: page.darkMode ? "#47545f" : "#dde1e4"
                clip: true

                ListView {
                    id: sourceList
                    anchors.fill: parent
                    anchors.margins: 6
                    model: page.sourceEntries
                    spacing: 2
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: sourceDelegate
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 74
                        radius: 12
                        color: modelData.id === page.currentSourceId
                               ? AppTheme.selected
                               : sourceRowHover.hovered
                                 ? (page.darkMode ? "#16ffffff" : "#0b000000")
                                 : "transparent"
                        border.width: modelData.id === page.currentSourceId ? 1 : 0
                        border.color: page.accentColor
                        Behavior on color { ColorAnimation { duration: AppTheme.duration(90) } }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            anchors.right: removeSourceButton.left
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            spacing: 1
                            Text {
                                width: parent.width
                                text: sourceDelegate.modelData.name
                                color: page.primaryText
                                elide: Text.ElideRight
                                font.family: AppTheme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                text: sourceDelegate.modelData.version + "  ·  " + sourceDelegate.modelData.status
                                color: page.secondaryText
                                elide: Text.ElideRight
                                font.family: AppTheme.fontFamily
                                font.pixelSize: 10
                            }
                        }

                        SettingsCheckBox {
                            id: updatePromptCheck
                            anchors.left: parent.left
                            anchors.leftMargin: 13
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            darkMode: page.darkMode
                            checked: sourceDelegate.modelData.updatePrompt
                            onToggled: value => page.setSourceUpdatePrompt(sourceDelegate.modelData.id, value)
                        }
                        Text {
                            anchors.left: updatePromptCheck.right
                            anchors.leftMargin: 7
                            anchors.verticalCenter: updatePromptCheck.verticalCenter
                            text: qsTr("允许更新弹窗")
                            color: page.secondaryText
                            font.family: AppTheme.fontFamily
                            font.pixelSize: 10
                        }

                        Rectangle {
                            id: removeSourceButton
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: 17
                            enabled: sourceDelegate.modelData.removable
                            opacity: enabled ? 1 : 0.3
                            color: removeSourceHover.hovered && enabled ? "#24ff5f57" : "transparent"

                            Item {
                                anchors.centerIn: parent
                                width: 15
                                height: 17
                                Rectangle { x: 3; y: 4; width: 9; height: 11; radius: 2; color: "transparent"; border.width: 1.5; border.color: page.darkMode ? "#ff9a96" : "#c74452" }
                                Rectangle { x: 2; y: 2; width: 11; height: 1.5; radius: 1; color: page.darkMode ? "#ff9a96" : "#c74452" }
                                Rectangle { x: 5; y: 0; width: 5; height: 1.5; radius: 1; color: page.darkMode ? "#ff9a96" : "#c74452" }
                            }
                            HoverHandler { id: removeSourceHover }
                            TapHandler {
                                enabled: removeSourceButton.enabled
                                onTapped: page.removeSource(sourceDelegate.modelData.id)
                            }
                        }
                        HoverHandler { id: sourceRowHover }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: page.selectSource(sourceDelegate.modelData.id)
                        }
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 25
                anchors.top: sourceListSurface.bottom
                anchors.topMargin: 18
                text: qsTr("导入音源")
                color: page.secondaryText
                font.family: AppTheme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 0.3
            }

            Rectangle {
                id: sourceUrlField
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.right: onlineImportButton.left
                anchors.rightMargin: 9
                anchors.top: sourceListSurface.bottom
                anchors.topMargin: 39
                height: 36
                radius: 10
                color: page.darkMode ? "#35414b" : "#f8fafb"
                border.width: sourceUrlInput.activeFocus ? 2 : 1
                border.color: sourceUrlInput.activeFocus ? page.accentColor : (page.darkMode ? "#59656e" : "#d5d9dd")
                TextInput {
                    id: sourceUrlInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: page.primaryText
                    selectionColor: "#586b747d"
                    selectedTextColor: page.darkMode ? "white" : "#16232d"
                    clip: true
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 11
                }
                Text {
                    visible: sourceUrlInput.text.length === 0 && !sourceUrlInput.activeFocus
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "https://example.com/source.js"
                    color: page.secondaryText
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 11
                }
            }

            Rectangle {
                id: onlineImportButton
                anchors.right: localImportButton.left
                anchors.rightMargin: 9
                anchors.top: sourceListSurface.bottom
                anchors.topMargin: 39
                width: 86
                height: 36
                radius: 18
                enabled: sourceUrlInput.text.trim().length > 0
                opacity: enabled ? 1 : 0.45
                color: onlineImportHover.hovered && enabled ? page.accentColor : (page.darkMode ? "#3b4751" : "#f8fafb")
                border.width: 1
                border.color: onlineImportHover.hovered && enabled ? page.accentColor : (page.darkMode ? "#59656e" : "#d5dde2")
                Text { anchors.centerIn: parent; text: qsTr("在线导入"); color: onlineImportHover.hovered && onlineImportButton.enabled ? "white" : page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                HoverHandler { id: onlineImportHover }
                TapHandler {
                    enabled: onlineImportButton.enabled
                    onTapped: {
                        const url = sourceUrlInput.text.trim()
                        page.sourceImportOnlineRequested(url)
                        sourceUrlInput.text = ""
                    }
                }
            }

            Rectangle {
                id: localImportButton
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.top: sourceListSurface.bottom
                anchors.topMargin: 39
                width: 86
                height: 36
                radius: 18
                color: localImportHover.hovered ? page.accentColor : (page.darkMode ? "#3b4751" : "#f8fafb")
                border.width: 1
                border.color: localImportHover.hovered ? page.accentColor : (page.darkMode ? "#59656e" : "#d5dde2")
                Text { anchors.centerIn: parent; text: qsTr("本地导入"); color: localImportHover.hovered ? "white" : page.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
                HoverHandler { id: localImportHover }
                TapHandler { onTapped: page.sourceImportLocalRequested() }
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(page.selectMatchingCategory)
        const args = Qt.application.arguments
        if (args.indexOf("--wallpaper-picker-preview") >= 0)
            Qt.callLater(function() { page.selectedCategory = 3; backgroundWallpaperPicker.open() })
        const categoryArg = args.indexOf("--settings-category")
        if (categoryArg >= 0 && categoryArg + 1 < args.length) {
            const routeName = args[categoryArg + 1]
            const routeIndex = ({ general: 0, library: 1, playback: 2, appearance: 3,
                                  downloads: 4, sources: 5, accounts: 6, shortcuts: 7,
                                  backup: 8, other: 9, about: 10 })[routeName]
            if (routeIndex !== undefined)
                page.selectedCategory = routeIndex
        }
        if (args.indexOf("--dark-preview") >= 0 && !page.darkMode)
            Qt.callLater(page.themeToggleRequested)
        if (args.indexOf("--source-manager-preview") >= 0)
            page.sourceManagerOpen = true
    }

    Timer { id: noticeTimer; interval: 2400; repeat: false; onTriggered: page.noticeText = "" }

    component UnavailableCard: Rectangle {
        id: unavailableCard
        required property string title
        required property string description
        width: body.width
        height: 132
        radius: 14
        color: page.panelColor
        border.width: 1
        border.color: page.darkMode ? "#63484d" : "#efd0d4"
        Column {
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 8
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: unavailableCard.title; color: page.darkMode ? "#ff9ca6" : "#c74452"; font.family: AppTheme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: unavailableCard.description; color: page.secondaryText; wrapMode: Text.WordWrap; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
        }
    }
}
