import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Kos.Demo as Demo
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: page
    required property var colors
    readonly property string repositoryUrl: "https://github.com/NextKde/NextKde"
    readonly property string websiteUrl: "https://nextkde.github.io/.github/"
    readonly property string submissionUrl: "https://github.com/NextKde/appCatalog"
        + (I18n.language === "zh-CN" ? "/blob/main/README.zh-CN.md"
           : I18n.language === "pt-BR" ? "/blob/main/README.pt-BR.md" : "#submit-an-application")
    property var contributors: []
    // Injected by the main window; a null backend keeps the page loadable alone.
    property var updateBackend: null
    readonly property bool updateKnown: !!updateBackend
    readonly property bool updateBusy: updateKnown && !!updateBackend.busy
    readonly property bool updateAvailable: updateKnown && !!updateBackend.available
    readonly property bool updateUpToDate: updateKnown && !!updateBackend.upToDate
    readonly property bool updateBlocked: updateKnown && !!updateBackend.blocked
    readonly property bool updateFailed: updateKnown && !!updateBackend.failed
    readonly property bool updateUpdated: updateKnown && !!updateBackend.updated
    readonly property bool updateNeedsRestart: updateKnown && !!updateBackend.needsRestart
    readonly property bool updateRecorded: updateKnown && !!updateBackend.sourceRoot
    readonly property bool updateHasLog: updateKnown && !!updateBackend.logPath
    readonly property bool updateCanCheck: updateKnown && !!updateBackend.canCheck && !updateBusy
    readonly property bool updateCanUpdate: updateKnown && !!updateBackend.canUpdate && !updateBusy
    readonly property string updateInstalledLabel: {
        if (!updateKnown) return ""
        const version = updateBackend.currentVersion ? String(updateBackend.currentVersion) : ""
        const revision = updateBackend.currentRevision ? String(updateBackend.currentRevision) : ""
        const tag = updateBackend.currentTag ? String(updateBackend.currentTag) : ""
        // A tagged install has a meaningful release version; a development
        // checkout is identified by its commit, not by the VERSION suffix.
        if (tag.length > 0) return version || tag
        if (revision.length > 0 && revision !== "unknown") return revision.slice(0, 7)
        return version || I18n.tr("Unknown version")
    }
    readonly property string updateBranchName: updateKnown && updateBackend.branch
        ? String(updateBackend.branch) : ""
    readonly property string updateTrackedName: updateKnown && updateBackend.upstream
        ? String(updateBackend.upstream) : updateBranchName
    // Stable tracks the tagged release the controller reports in upstream;
    // main is the canary channel and reports origin/main there. The fallback
    // matches the controller's own default before its release record is read.
    readonly property string updateChannel: updateKnown && updateBackend.channel
        ? String(updateBackend.channel) : "main"
    readonly property bool updateStableChannel: updateChannel !== "main"
    readonly property int updateChannelIndex: updateStableChannel ? 0 : 1
    readonly property string updateTargetName: updateTrackedName || I18n.tr("the tracked branch")
    // Long git output belongs in the log; the row keeps the first screens only.
    readonly property string updateError: {
        if (!updateKnown || !updateBackend.error) return ""
        const text = String(updateBackend.error).trim()
        return text.length > 300 ? text.slice(0, 300) + "…" : text
    }
    readonly property string updateStageLabel: {
        if (!updateKnown) return ""
        if (String(updateBackend.state || "") === "checking") return I18n.tr("Checking for updates…")
        switch (String(updateBackend.stage || "")) {
        case "fetch": return I18n.tr("Fetching changes…")
        case "merge": return I18n.tr("Applying changes…")
        case "install": return I18n.tr("Building and installing…")
        case "done": return I18n.tr("Finishing up…")
        }
        return updateBusy ? I18n.tr("Working…") : ""
    }
    readonly property string updateStatusTitle: {
        if (!updateKnown) return I18n.tr("Updates unavailable")
        if (!updateRecorded) return I18n.tr("Update source not recorded")
        if (updateFailed) return I18n.tr("Update failed")
        if (updateBlocked) return I18n.tr("Update paused")
        if (updateBusy) return updateStageLabel
        if (updateNeedsRestart) return I18n.tr("Restart required")
        if (updateUpdated) return I18n.tr("Updated")
        if (updateAvailable) return I18n.tr("Update available")
        if (updateUpToDate) return I18n.tr("Up to date")
        return ""
    }
    readonly property string updateStatusDetail: {
        if (!updateKnown) return I18n.tr("This build of Settings cannot check for KOS updates.")
        if (!updateRecorded) return I18n.tr("Run ./tools/kosctl install once from the KOS source folder, then reopen Settings.")
        if (updateBusy) return I18n.tr("You can close Settings; the update continues in the background.")
        if (updateFailed) return updateError || I18n.tr("The update stopped before it finished. Open the log for details.")
        if (updateBlocked) return updateError || I18n.tr("The update did not start. Open the log for details.")
        if (updateUpdated || updateNeedsRestart) {
            const version = updateInstalledLabel
            if (updateNeedsRestart) return version
                ? I18n.tr("KOS %1 is installed. Restart KOS to load it, and log out or restart the compositor to load updated KWin plugins.").arg(version)
                : I18n.tr("The new version is installed. Restart KOS to load it, and log out or restart the compositor to load updated KWin plugins.")
            return version ? I18n.tr("KOS %1 is installed.").arg(version) : I18n.tr("The new version is installed.")
        }
        if (updateAvailable) {
            if (updateBackend.sourceAhead && !Number(updateBackend.commitsBehind))
                return I18n.tr("The source checkout is newer than the installed version.")
            if (updateStableChannel)
                return I18n.tr("Stable release %1 is available.").arg(updateTargetName)
            const behind = Math.max(1, Number(updateBackend.commitsBehind) || 0)
            return behind === 1 ? I18n.tr("1 commit behind %1").arg(updateTargetName)
                : I18n.tr("%1 commits behind %2").arg(behind).arg(updateTargetName)
        }
        if (updateUpToDate) return I18n.tr("Installed version matches %1.").arg(updateTargetName)
        return ""
    }
    // One row, one action: the state decides which action is offered.
    readonly property string updateAction: {
        if (!updateKnown) return ""
        if (updateBusy) return updateHasLog ? "log" : ""
        if (updateFailed || updateBlocked) return updateHasLog ? "log" : ""
        if (updateNeedsRestart) return "restart"
        if (updateAvailable && updateCanUpdate) return "update"
        return ""
    }
    readonly property string updateActionText: updateAction === "log" ? I18n.tr("Open log")
        : updateAction === "restart" ? I18n.tr("Restart KOS")
        : updateAction === "update" ? I18n.tr("Update now") : ""
    property double updateStartedAt: 0
    property int updateElapsed: 0
    readonly property string updateElapsedLabel: Math.floor(updateElapsed / 60) + ":"
        + ("0" + (updateElapsed % 60)).slice(-2)
    onUpdateBusyChanged: {
        updateElapsed = 0
        updateStartedAt = updateBusy ? Date.now() : 0
    }
    // A busy backend can already be running when the page opens; the clock then
    // counts from that moment, which is close enough for a "still working" cue.
    function runUpdateAction() {
        if (!updateBackend) return
        if (updateAction === "update") updateBackend.update()
        else if (updateAction === "restart") updateBackend.restart()
        else if (updateAction === "log") updateBackend.openLog()
    }
    property var cache: null
    property var request: null
    property int nextPage: 1
    property bool hasMore: true
    property bool loading: false
    property bool loadFailed: false
    property bool backgroundLoading: false
    property bool openFailed: false
    // Allows isolated page consumers to opt out of network access.
    property bool loadContributors: true
    spacing: 12
    Layout.fillWidth: true

    function openLink(url) {
        openFailed = !Qt.openUrlExternally(url)
    }

    function applyContributors(json, requestedPage, previousContributors) {
        const entries = JSON.parse(json)
        if (!Array.isArray(entries)) throw new Error("Invalid contributors")
        const previous = requestedPage === 1 ? [] : previousContributors
        const known = new Set(previous.map(item => item.login))
        const added = []
        for (const entry of entries) {
            if (!entry || typeof entry.login !== "string" || !/^[a-zA-Z0-9-]+(?:\[bot\])?$/.test(entry.login)
                || known.has(entry.login)) continue
            known.add(entry.login)
            added.push({login: entry.login,
                avatar: typeof entry.avatar_url === "string"
                    && entry.avatar_url.startsWith("https://avatars.githubusercontent.com/")
                    ? entry.avatar_url : ""})
        }
        contributors = previous.concat(added)
        hasMore = entries.length === 100
        nextPage = requestedPage + 1
    }

    function fetchContributors() {
        if (loading || !hasMore) return
        const requestedPage = nextPage
        const previousContributors = contributors
        let background = false
        loadFailed = false
        if (cache) {
            const saved = cache.readPage(requestedPage)
            if (saved) {
                try {
                    applyContributors(saved, requestedPage, previousContributors)
                    if (!cache.pageNeedsRefresh(requestedPage)) return
                    background = true
                } catch (error) { /* Fetch a replacement for an invalid cache. */ }
            }
        }
        backgroundLoading = background
        loading = true
        const xhr = new XMLHttpRequest()
        request = xhr
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || page.request !== xhr) return
            requestTimeout.stop()
            page.request = null
            page.loading = false
            if (xhr.status !== 200) {
                page.loadFailed = !background
                return
            }
            try {
                page.applyContributors(xhr.responseText, requestedPage, previousContributors)
                if (page.cache) page.cache.savePage(requestedPage, xhr.responseText)
            } catch (error) {
                page.loadFailed = !background
            }
        }
        xhr.open("GET", "https://api.github.com/repos/NextKde/NextKde/contributors?per_page=100&page=" + requestedPage)
        xhr.setRequestHeader("Accept", "application/vnd.github+json")
        requestTimeout.start()
        xhr.send()
    }

    Component.onCompleted: {
        if (loadContributors) fetchContributors()
        if (updateBusy) updateStartedAt = Date.now()
    }
    Component.onDestruction: {
        const xhr = request
        request = null
        if (xhr) xhr.abort()
    }

    Timer {
        id: requestTimeout
        interval: 15000
        onTriggered: {
            const xhr = page.request
            page.request = null
            page.loading = false
            page.loadFailed = !page.backgroundLoading
            if (xhr) xhr.abort()
        }
    }

    component Section: Demo.SettingsGroup {
        backgroundColor: page.colors.card
        titleColor: page.colors.primaryText
    }

    component LinkRow: Demo.SettingsItem {
        id: linkRow
        required property string url
        titleColor: page.colors.primaryText
        descriptionColor: page.colors.secondaryText
        separatorColor: page.colors.separator
        minimumRowHeight: 36
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Link
        Accessible.onPressAction: page.openLink(url)
        Keys.onReturnPressed: page.openLink(url)
        Keys.onEnterPressed: page.openLink(url)
        Keys.onSpacePressed: page.openLink(url)
        property Item pointer: MouseArea {
            parent: linkRow
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: page.openLink(linkRow.url)
        }
        Demo.VectorIcon {
            name: "arrow_up_right_square"
            size: 14
            color: linkRow.activeFocus ? page.colors.accent : page.colors.secondaryText
        }
    }

    // Brand header: the mark, the product name, and the README tagline. The
    // sections below keep their own titles.
    ColumnLayout {
        Layout.fillWidth: true
        // A nested layout takes its maximum width from the text children, so
        // fillWidth alone leaves the capped block at the page's left edge.
        Layout.maximumWidth: 420
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 12
        Layout.bottomMargin: 4
        spacing: 4
        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            source: page.colors.dark ? Qt.resolvedUrl("../icons/nextkde-logo-dark.svg")
                : Qt.resolvedUrl("../icons/nextkde-logo.svg")
            sourceSize: Qt.size(144, 144)
            fillMode: Image.PreserveAspectFit
            Accessible.ignored: true
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "NextKDE"
            color: page.colors.primaryText
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            Layout.topMargin: 4
            text: I18n.tr("A Quickshell desktop for KDE Plasma.")
            color: page.colors.primaryText
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 420
            text: I18n.tr("Liquid glass, a floating dock, and a workspace you can make your own.")
            color: page.colors.secondaryText
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }

    Section {
        LinkRow {
            objectName: "about-website"
            title: I18n.tr("Official website")
            description: page.websiteUrl
            url: page.websiteUrl
            enabled: url.length > 0
        }
        LinkRow {
            objectName: "about-repository"
            title: I18n.tr("GitHub repository")
            description: "NextKde/NextKde"
            url: page.repositoryUrl
        }
    }

    Section {
        title: I18n.tr("Updates")
        Demo.SettingsItem {
            objectName: "about-update-channel"
            title: I18n.tr("Update channel")
            description: page.updateStableChannel ? I18n.tr("Latest official release")
                : I18n.tr("Main branch (development)")
            titleColor: page.colors.primaryText
            descriptionColor: page.colors.secondaryText
            // Two choices stay segmented (settings control contract).
            Controls.SettingsNavBar {
                objectName: "about-update-channel-select"
                colors: page.colors
                // Persistence and the resulting status belong to the controller.
                disabled: !page.updateCanCheck
                model: [
                    {
                        id: "stable",
                        label: I18n.tr("Stable")
                    },
                    {
                        id: "main",
                        label: I18n.tr("Canary")
                    }
                ]
                currentIndex: page.updateChannelIndex
                onSelectionChanged: function (index) {
                    if (page.updateBackend)
                        page.updateBackend.channel = index === 0 ? "stable" : "main"
                }
            }
        }
        Demo.SettingsItem {
            objectName: "about-installed-version"
            title: I18n.tr("Installed version")
            description: page.updateInstalledLabel
            titleColor: page.colors.primaryText
            descriptionColor: page.colors.secondaryText
            Demo.LiquidActionButton {
                objectName: "about-check-updates"
                text: page.updateFailed || page.updateBlocked ? I18n.tr("Check again") : I18n.tr("Check for updates")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                enabled: page.updateCanCheck
                activeFocusOnTab: enabled
                onClicked: page.updateBackend.check()
            }
        }
        Demo.SettingsItem {
            objectName: "about-update-status"
            visible: page.updateStatusTitle.length > 0
            title: page.updateStatusTitle
            description: page.updateStatusDetail
            // An available update is the only state that asks for attention.
            titleColor: page.updateAvailable ? page.colors.accent : page.colors.primaryText
            descriptionColor: page.colors.secondaryText
            Demo.LiquidActionButton {
                objectName: "about-update-action"
                visible: page.updateActionText.length > 0
                text: page.updateActionText
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                activeFocusOnTab: enabled
                onClicked: page.runUpdateAction()
            }
        }
        ColumnLayout {
            visible: page.updateBusy
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 4
            Layout.bottomMargin: 8
            spacing: 6
            ProgressBar {
                objectName: "about-update-progress"
                Layout.fillWidth: true
                // No progress protocol exists, so the bar never claims a percentage.
                indeterminate: true
                implicitHeight: 4
                background: Rectangle {
                    radius: 2
                    color: Qt.rgba(page.colors.accent.r, page.colors.accent.g, page.colors.accent.b, 0.1)
                }
                contentItem: Item {
                    Rectangle {
                        width: parent.width * 0.3
                        height: parent.height
                        radius: 2
                        color: page.colors.accent
                        SequentialAnimation on opacity {
                            running: page.updateBusy
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.4; to: 1; duration: 650 }
                            NumberAnimation { from: 1; to: 0.4; duration: 650 }
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: I18n.tr("Elapsed: %1").arg(page.updateElapsedLabel)
                color: page.colors.secondaryText
                font.pixelSize: 10
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: page.updateBusy && page.visible
        onTriggered: page.updateElapsed = page.updateStartedAt > 0
            ? Math.max(0, Math.floor((Date.now() - page.updateStartedAt) / 1000)) : 0
    }

    Section {
        title: I18n.tr("Get involved")
        LinkRow {
            objectName: "about-issue"
            title: I18n.tr("Submit an Issue")
            description: I18n.tr("Report a bug or suggest an improvement on GitHub.")
            url: page.repositoryUrl + "/issues/new/choose"
        }
        LinkRow {
            objectName: "about-pr"
            title: I18n.tr("Submit a Pull Request")
            description: I18n.tr("Compare your changes and open a pull request.")
            url: page.repositoryUrl + "/compare"
        }
        LinkRow {
            objectName: "about-submit-app"
            title: I18n.tr("Submit an application")
            description: I18n.tr("Follow the appCatalog guide to publish your app in Applications and services.")
            url: page.submissionUrl
        }
    }

    Section {
        title: I18n.tr("Contributors")
        Demo.SettingsItem {
            description: I18n.tr("Thank you to everyone who contributes to NextKDE.")
            descriptionColor: page.colors.secondaryText
        }
        Flow {
            id: contributorsFlow
            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (68 + spacing)))
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: visible ? 4 : 0
            Layout.bottomMargin: visible ? 4 : 0
            visible: page.contributors.length > 0
            spacing: 4
            Repeater {
                model: page.contributors
                delegate: ItemDelegate {
                    id: contributor
                    required property var modelData
                    // Share one column width so the final row stays left-aligned
                    // with the avatars above it.
                    width: Math.floor((contributorsFlow.width - (contributorsFlow.columns - 1)
                        * contributorsFlow.spacing) / contributorsFlow.columns)
                    height: 62
                    padding: 4
                    Accessible.name: modelData.login
                    Accessible.role: Accessible.Link
                    onClicked: page.openLink("https://github.com/" + encodeURIComponent(modelData.login))
                    background: Rectangle {
                        radius: 8
                        color: contributor.hovered ? page.colors.sidebarHover : "transparent"
                        border.width: contributor.activeFocus ? 1 : 0
                        border.color: page.colors.accent
                    }
                    contentItem: ColumnLayout {
                        spacing: 4
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 36
                            implicitHeight: 36
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: page.colors.separator
                                visible: avatar.status !== Image.Ready
                                Text {
                                    anchors.centerIn: parent
                                    text: contributor.modelData.login.charAt(0).toUpperCase()
                                    color: page.colors.primaryText
                                    font.pixelSize: 18
                                }
                            }
                            Image {
                                id: avatar
                                anchors.fill: parent
                                source: {
                                    if (!page.cache) return contributor.modelData.avatar
                                    const revision = page.cache.avatarRevision
                                    return page.cache.avatar(contributor.modelData.avatar)
                                }
                                sourceSize: Qt.size(72, 72)
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: avatarMask
                                }
                            }
                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: 8
                                color: "white"
                                visible: false
                                layer.enabled: true
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: contributor.modelData.login
                            textFormat: Text.PlainText
                            color: page.colors.primaryText
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.pixelSize: 10
                        }
                    }
                    Demo.KosToolTip { target: contributor; text: contributor.modelData.login }
                }
            }
        }
        Demo.SettingsItem {
            visible: (page.loading && !page.backgroundLoading) || page.loadFailed
                || page.hasMore || page.contributors.length === 0
            description: page.loading && !page.backgroundLoading ? I18n.tr("Loading contributors…")
                : page.loadFailed ? I18n.tr("Could not load contributors. Try again or view the full list on GitHub.")
                : page.contributors.length === 0 ? I18n.tr("No contributors to display yet.") : ""
            descriptionColor: page.colors.secondaryText
            Demo.LiquidActionButton {
                visible: !page.loading && (page.loadFailed || page.hasMore)
                text: page.loadFailed ? I18n.tr("Retry") : I18n.tr("Load more")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: page.fetchContributors()
            }
        }
        LinkRow {
            title: I18n.tr("View all contributors on GitHub")
            url: page.repositoryUrl + "/graphs/contributors"
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.openFailed
        text: I18n.tr("Could not open the browser. Check your default browser settings and try again.")
        color: page.colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
}
