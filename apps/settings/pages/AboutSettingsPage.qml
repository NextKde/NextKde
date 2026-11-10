import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Kos.Demo as Demo
import "../../../shared/qml/i18n"

ColumnLayout {
    id: page
    required property var colors
    readonly property string repositoryUrl: "https://github.com/NextKde/NextKde"
    readonly property string websiteUrl: "https://nextkde.github.io/.github/"
    readonly property string submissionUrl: "https://github.com/NextKde/appCatalog"
        + (I18n.language === "zh-CN" ? "/blob/main/README.zh-CN.md"
           : I18n.language === "pt-BR" ? "/blob/main/README.pt-BR.md" : "#submit-an-application")
    property var contributors: []
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

    Component.onCompleted: if (loadContributors) fetchContributors()
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
            name: "chevron"
            rotation: -90
            size: 14
            color: linkRow.activeFocus ? page.colors.accent : page.colors.secondaryText
        }
    }

    Section {
        Demo.SettingsItem {
            title: "KOS Desktop Shell"
            description: I18n.tr("A Quickshell desktop for KDE Plasma, built together with our community.")
            titleColor: page.colors.primaryText
            descriptionColor: page.colors.secondaryText
        }
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
            description: "github.com/NextKde/NextKde"
            url: page.repositoryUrl
        }
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
