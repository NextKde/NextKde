import "../../shared/qml/i18n"
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "components" as Controls

GridLayout {
    id: page
    property var bridge: null
    property var store: null
    // Keep delegate identity stable while per-app status queries finish.
    property var appIds: []
    function syncAppIds() {
        const ids = store && store.apps
            ? store.apps.map(app => app.id) : []
        if (JSON.stringify(ids) !== JSON.stringify(appIds)) appIds = ids
    }
    onStoreChanged: syncAppIds()
    property var colors
    property var resources: ({})
    property string errorText: ""
    property string requestedApp: ""
    property alias selectedCategory: categoryTabs.currentIndex
    property string planAppId: ""
    property string planId: ""
    property var planData: ({})
    // A cached plan is data, not a request to show a dialog. Only a click in
    // this page can wait for a fresh plan; navigation destroys that intent.
    property var pendingPlanRequest: null
    function requestPlan(app, updating) {
        if (!store || store.anyBusy) return;
        const previous = app.flatpak ? app.flatpak.plan || ({}) : ({});
        pendingPlanRequest = { appId: app.id, previousPlanId: previous.planId || "" };
        if (updating) store.update(app.id);
        else store.install(app.id);
    }
    onVisibleChanged: {
        if (!visible) {
            pendingPlanRequest = null;
            planDialog.close();
        }
    }
    signal revealRequested(var card)
    property bool revealPending: true
    function requestReveal() {
        if (requestedApp) selectedCategory = 0
        revealPending = true
        Qt.callLater(page.revealApp)
    }
    function revealApp() {
        if (!requestedApp || !revealPending) return
        for (let index = 0; index < appEntries.count; ++index) {
            const card = appEntries.itemAt(index)
            if (card && card.app.id === requestedApp) {
                revealPending = false
                revealRequested(card)
                return
            }
        }
    }
    onRequestedAppChanged: requestReveal()
    property bool snapshotReceived: false
    readonly property bool compatible: !!bridge && typeof bridge.initializeSpatialService === "function"
    readonly property bool checking: !snapshotReceived || !!resources.checking
    readonly property bool available: compatible && resources.available !== false
    columns: 2
    columnSpacing: 24
    rowSpacing: 8
    readonly property real entryWidth: Math.max(0, (width - columnSpacing) / columns)

    Basic.TabBar {
        id: categoryTabs
        objectName: "extensionsCategoryTabs"
        Layout.columnSpan: 2
        Layout.fillWidth: true
        Layout.bottomMargin: 12
        implicitHeight: 38
        spacing: 16
        currentIndex: 0
        background: Rectangle {
            color: "transparent"
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Qt.rgba(page.colors.secondaryText.r, page.colors.secondaryText.g,
                    page.colors.secondaryText.b, 0.15)
            }
        }
        Repeater {
            model: [I18n.tr("Apps"), I18n.tr("Services")]
            delegate: Basic.TabButton {
                id: categoryTab
                required property string modelData
                text: modelData
                width: 72
                height: 38
                Accessible.name: text
                contentItem: Text {
                    textFormat: Text.PlainText
                    text: categoryTab.text
                    color: categoryTab.checked ? page.colors.accent : page.colors.secondaryText
                    font.pixelSize: 12
                    font.weight: categoryTab.checked ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: "transparent"
                    radius: 5
                    border.width: categoryTab.visualFocus ? 1 : 0
                    border.color: page.colors.accent
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 2
                        radius: 1
                        color: page.colors.accent
                        visible: categoryTab.checked
                    }
                }
            }
        }
    }

    function catalogMessage(message) {
        return String(message || "").split("\n").map(function(line) {
            const separator = line.indexOf(": ");
            if (separator > 0)
                return line.slice(0, separator + 2) + I18n.tr(line.slice(separator + 2));
            return I18n.tr(line);
        }).join("\n");
    }

    function localText(values, fallback) {
        return values ? (values[I18n.language] || values.en || fallback || "") : (fallback || "");
    }

    RowLayout {
        visible: page.selectedCategory === 0
        Layout.columnSpan: 2
        Layout.fillWidth: true
        Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: page.store && page.store.updateCount ? I18n.tr("%1 apps have updates").arg(page.store.updateCount) : I18n.tr("Applications")
            color: page.colors.primaryText
            font.pixelSize: 13
        }
        WallpaperTextButton {
            label: page.store && page.store.updateStatus && page.store.updateStatus.running ? I18n.tr("Checking for updates…") : I18n.tr("Check all updates")
            colors: page.colors
            enabled: !!page.store && !(page.store.updateStatus && page.store.updateStatus.running)
            onClicked: page.store.checkAllUpdates()
        }
        WallpaperTextButton {
            label: I18n.tr("Manage app sources")
            colors: page.colors
            onClicked: sourceDialog.open()
        }
    }
    Text {
        textFormat: Text.PlainText
        visible: page.selectedCategory === 0 && text.length > 0
        Layout.columnSpan: 2
        Layout.fillWidth: true
        text: page.catalogMessage(page.store ? (page.store.catalogError || (page.store.updateStatus || {}).error || "") : "")
        color: page.colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Dialog {
        id: sourceDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(640, parent ? parent.width - 32 : 640)
        height: Math.min(700, parent ? parent.height - 32 : 700)
        modal: true
        title: I18n.tr("Manage app sources")
        standardButtons: Dialog.Close
        contentItem: Flickable {
            clip: true
            contentWidth: width
            contentHeight: sourceContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            ColumnLayout {
                id: sourceContent
                width: parent.width
                spacing: 12
                Basic.CheckBox {
                    text: I18n.tr("Automatically check for updates")
                    checked: page.store ? !!page.store.automaticUpdates : true
                    onToggled: if (page.store) page.store.automaticUpdates = checked
                }
                Basic.CheckBox {
                    text: I18n.tr("Show update notifications")
                    checked: page.store ? !!page.store.updateNotifications : true
                    onToggled: if (page.store) page.store.updateNotifications = checked
                }
                Repeater {
                    model: page.store && page.store.sources ? page.store.sources : []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: modelData.id + " · " + modelData.repository + "\n" + modelData.fingerprint
                            color: page.colors.primaryText
                            wrapMode: Text.WrapAnywhere
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: page.catalogMessage(modelData.error)
                            visible: text.length > 0
                            color: page.colors.secondaryText
                            wrapMode: Text.Wrap
                        }
                        WallpaperTextButton {
                            label: I18n.tr("Remove source")
                            colors: page.colors
                            enabled: !!page.store && !page.store.catalogBusy && !page.store.hasActiveMutation
                            onClicked: { removeSourceDialog.sourceId = modelData.id; removeSourceDialog.open(); }
                        }
                    }
                }
                WallpaperTextButton {
                    label: page.store && page.store.catalogBusy ? I18n.tr("Checking…") : I18n.tr("Refresh app sources")
                    colors: page.colors
                    enabled: !!page.store && !page.store.catalogBusy && !page.store.hasActiveMutation
                    onClicked: page.store.refreshCatalog()
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: I18n.tr("Add a signed GitHub Release catalog. Verify the full key fingerprint with the source maintainer before trusting it.")
                    color: page.colors.primaryText
                    wrapMode: Text.Wrap
                }
                Basic.TextField { id: sourceIdField; Layout.fillWidth: true; placeholderText: I18n.tr("Source ID (lowercase letters and hyphens)") }
                Basic.TextField { id: sourceRepoField; Layout.fillWidth: true; placeholderText: I18n.tr("GitHub owner/repository") }
                Basic.TextField { id: sourceFingerprintField; Layout.fillWidth: true; placeholderText: I18n.tr("Full signing key fingerprint") }
                Basic.TextField { id: sourceKeyField; Layout.fillWidth: true; placeholderText: I18n.tr("Local path to exported public key (.gpg)") }
                Basic.CheckBox {
                    id: sourceTrust
                    text: I18n.tr("I trust this source to choose applications and release repositories")
                }
                Text {
                    textFormat: Text.PlainText
                    id: sourceError
                    property string message: ""
                    text: page.catalogMessage(message)
                    Layout.fillWidth: true
                    color: page.colors.primaryText
                    wrapMode: Text.Wrap
                }
                WallpaperTextButton {
                    label: I18n.tr("Add source")
                    colors: page.colors
                    enabled: !!page.store && sourceTrust.checked && !page.store.catalogBusy && !page.store.hasActiveMutation
                        && !!sourceIdField.text && !!sourceRepoField.text && !!sourceFingerprintField.text && !!sourceKeyField.text
                    onClicked: {
                        sourceError.message = page.store.addSource(sourceIdField.text, sourceRepoField.text, sourceFingerprintField.text, sourceKeyField.text);
                        if (!sourceError.message) { sourceTrust.checked = false; sourceIdField.clear(); sourceRepoField.clear(); sourceFingerprintField.clear(); sourceKeyField.clear(); }
                    }
                }
            }
        }
    }
    Dialog {
        id: removeSourceDialog
        property string sourceId: ""
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(400, parent ? parent.width - 32 : 400)
        modal: true
        title: I18n.tr("Remove source")
        standardButtons: Dialog.Ok | Dialog.Cancel
        contentItem: Text {
            textFormat: Text.PlainText
            text: I18n.tr("Installed applications are kept. Updates from this source will stop.")
            color: page.colors.primaryText
            wrapMode: Text.Wrap
        }
        onAccepted: sourceError.message = page.store.removeSource(sourceId)
    }

    function refresh() {
        if (compatible)
            bridge.wallpaperSnapshot();
    }
    Component.onCompleted: {
        syncAppIds()
        if (compatible)
            bridge.inspectSpatialService();
        refresh();
        if (store) {
            if (typeof store.refreshApps === "function") store.refreshApps();
            else store.refresh();
        }
    }
    Connections {
        target: page.bridge
        ignoreUnknownSignals: true
        function onWallpaperSnapshotChanged(state) {
            page.resources = state.spatialResources || ({});
            page.snapshotReceived = !!state.spatialResources;
            page.errorText = page.resources.error || "";
        }
    }
    Timer {
        interval: 1000
        running: page.visible && page.compatible
        repeat: true
        onTriggered: page.refresh()
    }

    ColumnLayout {
        id: spatialCard
        property bool detailsExpanded: false
        visible: page.selectedCategory === 1
        Layout.fillWidth: true
        Layout.preferredWidth: page.entryWidth
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: 12
        Controls.ExtensionEntry {
            id: spatialEntry
            Layout.fillWidth: true
            category: I18n.tr("Service")
            colors: page.colors
            title: I18n.tr("Spatial wallpaper")
            description: I18n.tr("Add depth and motion to your wallpaper")
            iconSource: Qt.resolvedUrl("icons/spatial-wallpaper.svg")
            actionObjectName: "spatialServiceAction"
            actionText: !page.available ? I18n.tr("Unavailable") : page.resources.busy ? I18n.tr("Preparing…") : page.checking ? I18n.tr("Checking…") : page.resources.enabled ? I18n.tr("Disable") : page.resources.ready ? I18n.tr("Enable") : I18n.tr("Get")
            actionEnabled: page.available && !page.resources.busy && !page.checking
            onDetailsRequested: spatialCard.detailsExpanded = !spatialCard.detailsExpanded
            onActivated: {
                if (page.resources.enabled)
                    page.bridge.disableSpatialService();
                else
                    page.bridge.initializeSpatialService();
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: spatialCard.detailsExpanded || !!page.resources.busy || page.errorText.length > 0
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.rgba(page.colors.secondaryText.r, page.colors.secondaryText.g,
                    page.colors.secondaryText.b, 0.15)
            }
            Text {
                textFormat: Text.PlainText
                objectName: "spatialServiceStatus"
                visible: !page.available || page.checking || !!page.resources.busy
                Layout.fillWidth: true
                text: !page.compatible ? I18n.tr("The Settings bridge has not been built") : page.resources.available === false ? I18n.tr("This build does not include the spatial wallpaper component") : page.resources.busy ? (page.resources.stage || I18n.tr("Preparing…")) + (Number(page.resources.progress) >= 0 ? " · " + Math.round(Number(page.resources.progress) * 100) + "%" : "") : page.checking ? I18n.tr("Checking resources…") : page.resources.enabled ? I18n.tr("Enabled") : page.resources.ready ? I18n.tr("Ready to enable") : I18n.tr("Required resources are downloaded on first enablement")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            ProgressBar {
                id: downloadProgress
                objectName: "spatialServiceProgress"
                Layout.fillWidth: true
                visible: !!page.resources.busy
                indeterminate: !(Number(page.resources.progress) >= 0)
                value: Math.max(0, Math.min(1, Number(page.resources.progress) || 0))
                implicitHeight: 4
                background: Rectangle {
                    radius: 2
                    color: Qt.rgba(page.colors.accent.r, page.colors.accent.g, page.colors.accent.b, 0.1)
                }
                contentItem: Item {
                    Rectangle {
                        width: parent.width * (page.resources.progress >= 0 ? downloadProgress.position : 0.3)
                        height: parent.height
                        radius: 2
                        color: page.colors.accent
                        SequentialAnimation on opacity {
                            running: !!page.resources.busy && !(Number(page.resources.progress) >= 0)
                            loops: Animation.Infinite
                            NumberAnimation {
                                from: 0.4
                                to: 1
                                duration: 650
                            }
                            NumberAnimation {
                                from: 1
                                to: 0.4
                                duration: 650
                            }
                        }
                    }
                }
            }
            Text {
                textFormat: Text.PlainText
                objectName: "spatialServiceError"
                Layout.fillWidth: true
                visible: page.errorText.length > 0
                text: page.errorText
                wrapMode: Text.Wrap
                color: page.colors.primaryText
                font.pixelSize: 12
            }
        }
    }
    Connections {
        target: page.store
        ignoreUnknownSignals: true
        function onChanged() {
            page.syncAppIds()
            if (!page.store || planDialog.visible || !page.pendingPlanRequest || !page.visible) return;
            const apps = page.store.apps || [];
            for (let i = 0; i < apps.length; ++i) {
                const app = apps[i];
                if (app.id !== page.pendingPlanRequest.appId) continue;
                if (app.busy || (app.flatpak && app.flatpak.busy)) return;
                if (app.code || (app.flatpak && app.flatpak.error)) {
                    page.pendingPlanRequest = null;
                    return;
                }
                const plan = app.flatpak ? app.flatpak.plan || ({}) : ({});
                const id = plan.planId || "";
                if (!id || id === page.pendingPlanRequest.previousPlanId) return;
                page.pendingPlanRequest = null;
                page.planAppId = app.id;
                page.planId = id;
                page.planData = plan;
                planDialog.open();
                return;
            }
        }
    }

    // Catalog cards use the installed backend state. Native installations may coexist
    // and never change Install/Open/Uninstall availability.
    Repeater {
        id: appEntries
        onItemAdded: Qt.callLater(page.revealApp)
        model: page.appIds
        delegate: Controls.ExtensionEntry {
            id: appCard
            visible: page.selectedCategory === 0
            required property var modelData
            readonly property var app: {
                const apps = page.store && page.store.apps ? page.store.apps : []
                return apps.find(item => item.id === modelData) || ({ id: modelData, name: "" })
            }
            readonly property bool blocked: !!page.store.anyBusy
            objectName: app.id + "Entry"
            Layout.fillWidth: true
            Layout.preferredWidth: page.entryWidth
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            colors: page.colors
            title: page.localText(app.nameLocales, I18n.tr(app.name))
            category: I18n.tr("App")
            description: (app.updateAvailable ? I18n.tr("Update available") + " · " : "") + page.localText(app.descriptionLocales, I18n.tr(app.description || ""))
            iconName: app.iconName || "grid"
            iconSource: app.iconFile ? Qt.resolvedUrl("icons/" + app.iconFile) : ""
            iconInset: app.id === "calendar" ? 8 / 128 : app.id === "listenfree" ? 0 : 10 / 128
            actionObjectName: app.id + "Action"
            actionText: app.busy && app.stage !== "status" ? I18n.tr("Working…") : app.installed ? I18n.tr("Open") : I18n.tr("Install")
            actionEnabled: !blocked && !!app.statusKnown && (!!app.installed || app.available !== false)
            actionAvailable: !!page.store && !page.store.hasActiveMutation
                && !!app.statusKnown && (!!app.installed || app.available !== false)
            onActivated: {
                if (app.installed) page.store.open(app.id);
                else page.requestPlan(app, false);
            }
            onDetailsRequested: appDetailsDialog.open()
            property Dialog detailsDialog: Dialog {
                id: appDetailsDialog
                objectName: appCard.app.id + "DetailsDialog"
                parent: Overlay.overlay
                anchors.centerIn: parent
                width: Math.min(520, parent ? parent.width - 32 : 520)
                implicitHeight: header.implicitHeight + topPadding + appDetailsContent.childrenRect.height + 40
                    + bottomPadding + footer.implicitHeight + spacing * 2
                height: Math.min(implicitHeight, parent ? parent.height - 32 : implicitHeight)
                modal: true
                title: I18n.tr("%1: %2").arg(appCard.title).arg(I18n.tr("Details"))
                closePolicy: Popup.CloseOnEscape
                // Reuse background discovery; check GitHub if no candidate is cached.
                onOpened: {
                    const target = appCard.app;
                    const canCheck = !appCard.blocked && target.backend !== "flatpak-unavailable"
                        && (target.backend !== "flatpak" && target.backend !== "flatpak-ready" || !!target.canCheckUpdates);
                    if (page.store && canCheck && !target.latestVersion && !target.busy)
                        page.store.checkUpdates(appCard.app.id);
                }
                Connections {
                    target: page
                    function onVisibleChanged() {
                        if (!page.visible) appDetailsDialog.close();
                    }
                }
                header: Item {}
                background: Rectangle {
                    radius: 22
                    color: page.colors.dark ? "#ed25282e" : "#f8f9fbfd"
                    border.width: 1
                    border.color: page.colors.dark ? "#62ffffff" : "#aaffffff"
                }
                footer: Item {
                    implicitHeight: 58
                    WallpaperTextButton {
                        objectName: appCard.app.id + "DetailsClose"
                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                            rightMargin: 24
                            bottomMargin: 20
                        }
                        label: I18n.tr("Close")
                        colors: page.colors
                        implicitHeight: 30
                        cornerRadius: 15
                        onClicked: appDetailsDialog.close()
                    }
                }
                contentItem: Flickable {
                    implicitHeight: appDetailsContent.childrenRect.height + 40
                    contentWidth: width
                    contentHeight: appDetailsContent.childrenRect.height + 40
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ColumnLayout {
                        id: appDetailsContent
                        readonly property color divider: Qt.rgba(page.colors.secondaryText.r,
                            page.colors.secondaryText.g, page.colors.secondaryText.b, 0.16)
                        x: 20
                        y: 18
                        width: parent.width - 40
                        spacing: 0

                        // Header: artwork, identity, subtitle.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 16
                            spacing: 14
                            Item {
                                Layout.preferredWidth: 60
                                Layout.preferredHeight: 60
                                Image {
                                    anchors.centerIn: parent
                                    width: parent.width / (1 - 2 * appCard.iconInset)
                                    height: width
                                    source: appCard.iconSource
                                    sourceSize: Qt.size(132, 132)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }
                                Rectangle {
                                    visible: !appCard.iconSource.toString().length
                                    anchors.fill: parent
                                    radius: 14
                                    color: appCard.iconColor
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 3
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: appCard.title
                                    color: page.colors.primaryText
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: appCard.description
                                    color: page.colors.secondaryText
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            // Same capsule action as the list row, so the dialog offers the
                            // identical Install / Open entry point at the same spot.
                            Basic.Button {
                                id: detailsAction
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 12
                                Layout.preferredWidth: Math.max(50, detailsActionLabel.implicitWidth + 20)
                                implicitHeight: 24
                                padding: 0
                                objectName: appCard.app.id + "DetailsAction"
                                text: appCard.actionText
                                enabled: appCard.actionEnabled
                                hoverEnabled: true
                                Accessible.name: appCard.title + ": " + text
                                onClicked: {
                                    if (appCard.app.installed) page.store.open(appCard.app.id);
                                    else page.requestPlan(appCard.app, false);
                                }
                                contentItem: Text {
                                    textFormat: Text.PlainText
                                    id: detailsActionLabel
                                    text: detailsAction.text
                                    color: appCard.actionAvailable ? "#0085ff" : page.colors.secondaryText
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: height / 2
                                    color: detailsAction.down ? "#d4e3f5" : "#e6edf7"
                                    border.width: detailsAction.visualFocus ? 2 : 0
                                    border.color: "#0085ff"
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: appDetailsContent.divider
                        }

                        // Status paragraph.
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            text: I18n.tr("STATUS")
                            color: page.colors.secondaryText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            objectName: appCard.app.id + "Status"
                            Layout.fillWidth: true
                            Layout.topMargin: 5
                            text: (appCard.app.catalogActive === false ? I18n.tr("This app is unavailable from its source. Installed copies are kept.") : appCard.app.format && appCard.app.format !== "flatpak" ? I18n.tr("This package format is not supported yet") : "") || page.appEnvironmentError(appCard.app) || (appCard.app.busy ? page.appStage(appCard.app.stage) : !appCard.app.statusKnown ? I18n.tr("Checking installation status…") : appCard.app.backend === "flatpak-unavailable" ? (appCard.app.flatpak && appCard.app.flatpak.error ? appCard.app.flatpak.error : I18n.tr("The application is unavailable in the current trusted catalog. Refresh app sources.")) : appCard.app.backend === "flatpak-ready" ? I18n.tr("Install a Flatpak bundle from the catalogued GitHub Release.") : appCard.app.backend === "flatpak" ? I18n.tr("Managed by Flatpak. Settings checks GitHub for bundle updates; external Flatpak tools can remove the same installation.") : appCard.app.installed && !appCard.app.managed ? I18n.tr("Installed outside Settings. Open is available; updates and removal stay with its installer.") : appCard.app.available === false ? I18n.tr("No stable release is available yet") : I18n.tr("Builds from source; development dependencies are required"))
                            color: page.colors.secondaryText
                            font.pixelSize: 12
                            lineHeight: 1.15
                            wrapMode: Text.Wrap
                        }
                        Text {
                            textFormat: Text.PlainText
                            objectName: appCard.app.id + "Version"
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            visible: !!appCard.app.version || !!appCard.app.latestVersion
                            text: I18n.tr("Installed: %1 · Latest: %2").arg(appCard.app.version || I18n.tr("Not installed")).arg(appCard.app.latestVersion || I18n.tr("Not checked"))
                            color: page.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }

                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: !!appCard.app.lastChecked
                            text: I18n.tr("Last checked: %1").arg(appCard.app.lastChecked || "")
                            color: page.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }

                        // Flatpak provenance block.
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            visible: appCard.app.backend === "flatpak"
                            text: I18n.tr("SOURCE")
                            color: page.colors.secondaryText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 5
                            visible: appCard.app.backend === "flatpak"
                            text: I18n.tr("Flatpak · %1 · %2").arg(appCard.app.scope || "").arg(appCard.app.origin || "")
                            color: page.colors.primaryText
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            visible: appCard.app.backend === "flatpak"
                            text: appCard.app.bundleManaged ? (appCard.app.developerSignature ? I18n.tr("Developer signature and SHA-256 verification") : I18n.tr("Trusted GitHub repository and SHA-256 verification")) : I18n.tr("This installation could not be associated with its application source. Settings will not update it.")
                            color: page.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }

                        // Update note.
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            visible: appCard.app.backend === "flatpak" && !!appCard.app.flatpakUpdate && !!appCard.app.flatpakUpdate.commit
                            text: I18n.tr("WHAT'S NEW")
                            color: page.colors.secondaryText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 5
                            visible: appCard.app.backend === "flatpak" && !!appCard.app.flatpakUpdate && !!appCard.app.flatpakUpdate.commit
                            text: appCard.app.flatpakUpdate && appCard.app.flatpakUpdate.available
                                ? I18n.tr("An update is available. Review and confirm to install it.")
                                : I18n.tr("The installed version matches the GitHub release.")
                            color: page.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }

                        // Live progress while a task runs.
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            visible: !!appCard.app.busy
                            spacing: 6
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: I18n.tr("PROGRESS")
                                color: page.colors.secondaryText
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.6
                            }
                            Basic.ProgressBar {
                                Layout.fillWidth: true
                                indeterminate: !(appCard.app.progress >= 0)
                                value: Math.max(0, Math.min(1, appCard.app.progress || 0))
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: I18n.tr("Elapsed: %1").arg(Math.floor((appCard.app.elapsedSeconds || 0) / 60) + ":" + ("0" + ((appCard.app.elapsedSeconds || 0) % 60)).slice(-2))
                                    + " · " + I18n.tr("Tasks continue in the background after closing this window.")
                                color: page.colors.secondaryText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: !!appCard.app.transactionStatus
                                text: I18n.tr(appCard.app.transactionStatus || "")
                                color: page.colors.secondaryText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }

                        // Error.
                        Text {
                            textFormat: Text.PlainText
                            objectName: appCard.app.id + "Error"
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            visible: !!appCard.app.code && appCard.app.code !== "EXTERNALLY_MANAGED"
                            text: page.appFailureText(appCard.app)
                            color: page.colors.primaryText
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }

                        // Dependencies.
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            visible: (appCard.app.dependencies || []).length > 0
                            text: I18n.tr("REQUIRES")
                            color: page.colors.secondaryText
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.6
                        }
                        Repeater {
                            model: appCard.app.dependencies || []
                            delegate: Text {
                                textFormat: Text.PlainText
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                text: typeof modelData === "string" ? modelData : (modelData.id || modelData.name || "") + " " + (modelData.required || "")
                                color: page.colors.secondaryText
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            implicitHeight: 1
                            color: appDetailsContent.divider
                        }

                        // Actions.
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            spacing: 8
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                objectName: appCard.app.id + "RecheckEnvironment"
                                visible: !!page.appEnvironmentError(appCard.app)
                                enabled: !appCard.blocked && !(appCard.app.flatpak || {}).querying
                                label: I18n.tr("Check again")
                                colors: page.colors
                                onClicked: page.store.refresh()
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                objectName: appCard.app.id + "CheckUpdates"
                                label: I18n.tr("Check for updates")
                                colors: page.colors
                                enabled: !appCard.blocked && appCard.app.backend !== "flatpak-unavailable" && (appCard.app.backend !== "flatpak" && appCard.app.backend !== "flatpak-ready" || !!appCard.app.canCheckUpdates)
                                onClicked: page.store.checkUpdates(appCard.app.id)
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                objectName: appCard.app.id + "Update"
                                visible: !!appCard.app.installed && !!appCard.app.managed && !!appCard.app.updateAvailable
                                enabled: !appCard.blocked
                                label: I18n.tr("Update")
                                colors: page.colors
                                onClicked: page.requestPlan(appCard.app, true)
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                visible: !!appCard.app.installed && !!appCard.app.managed && appCard.app.backend !== "flatpak"
                                enabled: !appCard.blocked
                                label: I18n.tr("Preview old program versions")
                                colors: page.colors
                                onClicked: page.store.cleanupProgram(appCard.app.id, "cleanup-plan")
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                visible: !!appCard.app.cleanupPlan && !!appCard.app.cleanupPlan.removedRevisions && appCard.app.cleanupPlan.removedRevisions.length > 0
                                enabled: !appCard.blocked
                                label: I18n.tr("Clean old program versions…")
                                colors: page.colors
                                onClicked: {
                                    programActionDialog.appId = appCard.app.id;
                                    programActionDialog.action = "prune";
                                    programActionDialog.detail = I18n.tr("Keep the current program and one rollback version. Remove only these installer-owned revisions; personal data and backups are kept.")
                                        + "\n" + appCard.app.cleanupPlan.removedRevisions.join("\n");
                                    programActionDialog.open();
                                }
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                label: I18n.tr("Repository")
                                colors: page.colors
                                onClicked: page.store.openRepository(appCard.app.id)
                            }
                            WallpaperTextButton {
                                implicitHeight: 28
                                cornerRadius: 14
                                visible: !!appCard.app.logPath
                                label: I18n.tr("View log")
                                colors: page.colors
                                onClicked: page.store.openLog(appCard.app.id)
                            }
                        }

                        // Destructive / cancel action, kept apart from the rest.
                        WallpaperTextButton {
                            implicitHeight: 28
                            cornerRadius: 14
                            objectName: appCard.app.id + "ActionSecondary"
                            Layout.topMargin: 10
                            visible: appCard.app.busy || (!!appCard.app.installed && !!appCard.app.managed)
                            enabled: appCard.app.stage !== "cancelling" && (!!appCard.app.busy || !appCard.blocked)
                            label: appCard.app.busy ? I18n.tr("Cancel") : I18n.tr("Uninstall")
                            colors: page.colors
                            onClicked: {
                                if (appCard.app.busy) page.store.cancel(appCard.app.id);
                                else {
                                    appUninstallDialog.appId = appCard.app.id;
                                    appUninstallDialog.appName = appCard.app.name;
                                    appUninstallDialog.open();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: programActionDialog
        property string appId: ""
        property string action: ""
        property string detail: ""
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, parent ? parent.width - 32 : 460)
        modal: true
        title: I18n.tr("Remove old program files?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (!page.store || page.store.anyBusy) return;
            page.store.cleanupProgram(appId, action);
        }
        contentItem: Text {
            textFormat: Text.PlainText
            text: programActionDialog.detail
            color: page.colors.primaryText
            wrapMode: Text.WrapAnywhere
        }
        background: Rectangle { radius: 10; color: page.colors.card; border.color: page.colors.secondaryText }
    }
    Basic.Dialog {
        id: planDialog
        objectName: "flatpakPlanDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(440, parent ? parent.width - 32 : 440)
        implicitHeight: header.implicitHeight + topPadding + planContent.implicitHeight
            + bottomPadding + footer.implicitHeight + spacing * 2
        height: Math.min(implicitHeight, parent ? parent.height - 32 : implicitHeight)
        padding: 24
        topPadding: 8
        bottomPadding: 0
        spacing: 16
        modal: true
        closePolicy: Popup.CloseOnEscape
        title: plan.operation === "update" ? I18n.tr("Confirm update") : I18n.tr("Confirm installation")
        property var app: {
            const list = page.store ? page.store.apps || [] : [];
            for (let i = 0; i < list.length; ++i)
                if (list[i].id === page.planAppId) return list[i];
            return ({});
        }
        property var plan: page.planData
        readonly property color secondaryColor: page.colors.secondaryText
        readonly property color accentColor: page.colors.accent
        readonly property color ruleColor: Qt.rgba(secondaryColor.r,
            secondaryColor.g, secondaryColor.b, 0.15)
        onAboutToHide: page.pendingPlanRequest = null
        onClosed: {
            page.planId = "";
            page.planAppId = "";
            page.planData = ({});
        }
        header: Item {
            implicitHeight: 48
            Text {
                textFormat: Text.PlainText
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 24; rightMargin: 24; topMargin: 22 }
                text: planDialog.title
                color: page.colors.primaryText
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
        contentItem: Flickable {
            implicitHeight: planContent.implicitHeight
            contentWidth: width
            contentHeight: planContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: planContent
                width: parent.width
                spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Image {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        source: planDialog.app.iconFile ? Qt.resolvedUrl("icons/" + planDialog.app.iconFile) : ""
                        sourceSize: Qt.size(88, 88)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: I18n.tr(planDialog.app.name || page.planAppId)
                            color: page.colors.primaryText
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                        }
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: I18n.tr("Version %1").arg(planDialog.plan.version || I18n.tr("Unknown version"))
                            color: page.colors.secondaryText
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: planDialog.ruleColor
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: planDialog.plan.operationSet || []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: modelData.role === "application" ? I18n.tr("App download")
                                    : modelData.role === "runtime" ? I18n.tr("Shared app components") : I18n.tr("Additional app components")
                                color: page.colors.secondaryText
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                            Text {
                                textFormat: Text.PlainText
                                Layout.maximumWidth: planContent.width * 0.5
                                text: modelData.action === "reuse" ? I18n.tr("Already installed")
                                    : modelData.sizeKnown === false ? I18n.tr("Unknown") : page.formatBytes(modelData.downloadBytes)
                                color: page.colors.primaryText
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 8
                    color: Qt.rgba(planDialog.accentColor.r, planDialog.accentColor.g, planDialog.accentColor.b, 0.08)
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        Text {
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            text: I18n.tr("Total download")
                            color: page.colors.primaryText
                            font.pixelSize: 12
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: page.formatBytes(page.planDownloadBytes(planDialog.plan))
                            color: page.colors.primaryText
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: I18n.tr("Installed components are reused. Only missing components are downloaded.")
                    color: page.colors.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }
        footer: Item {
            implicitHeight: 58
            RowLayout {
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 24; bottomMargin: 20 }
                spacing: 8
                WallpaperTextButton {
                    objectName: "flatpakPlanCancel"
                    label: I18n.tr("Cancel")
                    colors: page.colors
                    implicitHeight: 30
                    cornerRadius: 15
                    onClicked: planDialog.close()
                }
                WallpaperTextButton {
                    objectName: "flatpakPlanConfirm"
                    label: planDialog.plan.operation === "update" ? I18n.tr("Download and update") : I18n.tr("Download and install")
                    colors: page.colors
                    implicitHeight: 30
                    cornerRadius: 15
                    emphasized: true
                    enabled: !!page.store && !!page.planId && !page.store.anyBusy
                    onClicked: {
                        const id = page.planAppId;
                        const planId = page.planId;
                        planDialog.close();
                        if (page.store && !page.store.anyBusy) page.store.confirmPlan(id, planId);
                    }
                }
            }
        }
        background: Rectangle {
            radius: 14
            color: page.colors.card
            border.color: planDialog.ruleColor
        }
    }
    Dialog {
        id: appUninstallDialog
        objectName: "appUninstallDialog"
        property string appId: ""
        property string appName: ""
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(360, parent ? parent.width - 32 : 360)
        modal: true
        title: I18n.tr("Uninstall %1?").arg(appName)
        header: Text {
            textFormat: Text.PlainText
            text: appUninstallDialog.title
            color: page.colors.primaryText
            font.pixelSize: 16
            font.bold: true
            padding: 16
            wrapMode: Text.Wrap
        }
        background: Rectangle {
            radius: 10
            color: page.colors.card
            border.color: page.colors.secondaryText
            border.width: 1
        }
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: if (page.store) page.store.uninstall(appId)
        contentItem: Text {
            textFormat: Text.PlainText
            text: I18n.tr("Only the Flatpak version will be uninstalled. Your personal data, preferences and any native version will be kept.")
            color: page.colors.primaryText
            wrapMode: Text.Wrap
        }
    }

    function formatBytes(value) {
        if (value === undefined || value === null || value === "" || Number(value) < 0 || !isFinite(Number(value)))
            return I18n.tr("Unknown");
        const bytes = Number(value);
        if (bytes < 1024) return Math.round(bytes) + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KiB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MiB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GiB";
    }
    function planDownloadBytes(plan) {
        const operations = plan && plan.operationSet ? plan.operationSet : [];
        let total = 0;
        for (let i = 0; i < operations.length; ++i) {
            const value = operations[i].downloadBytes;
            if (operations[i].sizeKnown === false || value === undefined || value === null || value === "" || Number(value) < 0 || !isFinite(Number(value)))
                return undefined;
            total += Number(value);
        }
        return operations.length ? total : undefined;
    }
    function appStage(stage) {
        switch (stage) {
        case "check-update": return I18n.tr("Checking for updates…");
        case "status": return I18n.tr("Checking installation status…");
        case "check": case "configure": return I18n.tr("Checking dependencies…");
        case "release": return I18n.tr("Checking for updates…");
        case "download": return I18n.tr("Downloading source…");
        case "build": return I18n.tr("Building from source…");
        case "install": return I18n.tr("Installing…");
        case "update": return I18n.tr("Updating…");
        case "prepare-install": case "prepare-update": return I18n.tr("Preparing installation…");
        case "uninstall": return I18n.tr("Uninstalling…");
        case "cleanup-plan": return I18n.tr("Inspecting old program versions…");
        case "prune": return I18n.tr("Cleaning installer-owned old versions…");
        case "cancelling": return I18n.tr("Cancelling…");
        default: return I18n.tr("Preparing…");
        }
    }
    function appEnvironmentError(app) {
        const environment = app.flatpak || ({});
        if (environment.known || !environment.error) return "";
        if (environment.errorCode === "FLATPAK_NOT_INSTALLED" || environment.errorCode === "WORKER_UNAVAILABLE")
            return appError(environment.errorCode);
        return I18n.tr("Could not check the Flatpak environment. Check again; if the problem persists, repair Flatpak and the KOS installation backend.");
    }
    function appFailureText(app) {
        const space = app.diskSpace || ({});
        if (app.code === "DISK_FULL" && Number(space.missingBytes) > 0) {
            const location = space.location === "download" ? I18n.tr("the download disk")
                : space.location === "installation" ? I18n.tr("the app installation disk") : I18n.tr("the disk");
            const missing = Number(space.missingBytes);
            const amount = missing < 1024 * 1024 * 1024
                ? Math.ceil(missing / (1024 * 1024)) + " MiB"
                : (Math.ceil(missing / (1024 * 1024 * 1024) * 10) / 10).toFixed(1) + " GiB";
            return I18n.tr("Not enough space. Free at least %1 on %2, then try again.").arg(amount).arg(location);
        }
        const internal = String(app.code).startsWith("RUNTIME_") || app.code === "DISK_FULL" || app.code === "SPACE_CHECK_FAILED"
            || app.code === "FLATPAK_NOT_INSTALLED" || app.code === "WORKER_UNAVAILABLE"
            || app.code === "BUNDLE_METADATA_MISMATCH" || app.code === "BUNDLE_INSTALLED_SIZE_MISMATCH";
        return appError(app.code) + (app.message && !internal ? "\n" + app.message : "");
    }
    function appError(code) {
        switch (code) {
        case "CATALOG_CHANGED": return I18n.tr("The app source changed. Refresh and prepare a new installation plan.");
        case "RECEIPT_WRITE_FAILED": return I18n.tr("The app was deployed but its source record could not be saved. Check the log before retrying.");
        case "RELEASE_UNAVAILABLE": case "NO_RELEASE": return I18n.tr("No stable release is available yet");
        case "NETWORK_ERROR": case "TLS_ERROR": case "DOWNLOAD_FAILED": return I18n.tr("Network request failed. Check your connection and try again.");
        case "RATE_LIMITED": case "RATE_LIMIT": return I18n.tr("GitHub request limit reached. Try again later.");
        case "DEPENDENCY_UNSATISFIED": return I18n.tr("Install or update the dependencies listed below, then try again.");
        case "OPERATION_TIMEOUT": case "DOWNLOAD_TIMEOUT": case "NETWORK_TIMEOUT": case "TIMED_OUT": return I18n.tr("The operation timed out and was stopped. View the log before trying again.");
        case "CANCELLED": return I18n.tr("Operation cancelled");
        case "OPEN_FAILED": return I18n.tr("The app could not be opened. Check the installation and try again.");
        case "BUNDLE_KEY_MISSING": return I18n.tr("The application is unavailable in the current trusted catalog. Refresh app sources.");
        case "ARCH_UNAVAILABLE": return I18n.tr("No Flatpak bundle has been published for this architecture.");
        case "VERSION_CONFLICT": return I18n.tr("The signed release would downgrade or replace an existing version. Deployment was refused.");
        case "BUNDLE_METADATA_MISMATCH": return I18n.tr("The app package metadata does not match its signed release information. Installation stopped. Please wait for a corrected release.");
        case "BUNDLE_INSTALLED_SIZE_MISMATCH": return I18n.tr("The app package size does not match its signed release information. Installation stopped. Please wait for a corrected release.");
        case "INVALID_RELEASE": case "INTEGRITY_FAILED": case "UNTRUSTED_URL": case "RESPONSE_TOO_LARGE": return I18n.tr("The release metadata or bundle failed validation. Nothing was deployed.");
        case "FLATPAK_UNAVAILABLE": return I18n.tr("No eligible release is available. Refresh app sources and check the installation status.");
        case "PLAN_REQUIRED": return I18n.tr("Review and confirm the Flatpak dependency plan before downloading.");
        case "RUNTIME_SOURCE_MISSING": return I18n.tr("Could not prepare the components needed for installation. Please try installing again.");
        case "RUNTIME_SETUP_FAILED": return I18n.tr("Could not prepare the components needed for installation. Please try installing again.");
        case "RUNTIME_SETUP_CONFLICT": return I18n.tr("An existing software source prevents automatic setup. Your source settings have not been changed. Contact support and include the log.");
        case "RUNTIME_PLAN_UNAVAILABLE": return I18n.tr("Installation has not started. The required runtime could not be resolved from the configured sources. Check the source and network connection, then try again.");
        case "PLAN_UNAVAILABLE": return I18n.tr("A complete Flatpak installation plan could not be prepared. Check the approved sources and try again.");
        case "PLAN_CHANGED": return I18n.tr("The Flatpak installation plan changed or expired. Prepare a fresh plan before continuing.");
        case "FLATPAK_NOT_INSTALLED": return I18n.tr("Flatpak is not installed or its command is not available. Install Flatpak using your system software manager, then check again.");
        case "WORKER_UNAVAILABLE": return I18n.tr("The app installation backend is missing or could not start. Install or repair the KOS Flatpak backend and its system dependencies, then check again.");
        case "WORKER_TIMEOUT": return I18n.tr("The optional Flatpak backend timed out. Installed state is unknown; recheck before retrying.");
        case "FLATPAK_TIMEOUT": return I18n.tr("The Flatpak operation exceeded its time limit. Cancellation was requested; the displayed installation state was queried again.");
        case "FLATPAK_UNTRUSTED": return I18n.tr("The app or runtime source does not match the approved publisher policy. No unapproved deployment was authorized.");
        case "FLATPAK_RUNTIME_MISSING": return I18n.tr("Could not download the required app components. Check your connection and try again.");
        case "SPACE_CHECK_FAILED": return I18n.tr("Available disk space could not be checked. Check that your storage is connected and writable, then try again.");
        case "DISK_FULL": return I18n.tr("There is not enough disk space. Free space and retry.");
        case "FLATPAK_FAILED": return I18n.tr("Flatpak could not complete the operation. See the details below.");
        case "FLATPAK_INCOMPATIBLE": return I18n.tr("The installed Flatpak library cannot safely handle signed bundles. Update Flatpak and libflatpak before retrying. Nothing was deployed.");
        case "FLATPAK_EXTERNAL":
        case "EXTERNAL_INSTALL": case "EXTERNALLY_MANAGED": case "NOT_MANAGED": case "OWNERSHIP_CONFLICT": return I18n.tr("Installed outside Settings. Open is available; updates and removal stay with its installer.");
        case "APP_RUNNING": return I18n.tr("Close the app and its background helpers, then retry.");
        case "RECOVERY_REQUIRED": return I18n.tr("An interrupted program operation needs attention. Keep its ownership records and see the details.");
        case "BUSY": return I18n.tr("Another app installation is already running.");
        case "UNSUPPORTED_PLATFORM": return I18n.tr("Source installation is not supported on this platform.");
        case "RESULT_UNKNOWN": case "OUTPUT_LIMIT": return I18n.tr("Installation was interrupted or its result could not be confirmed. Check the log before retrying.");
        case "START_FAILED": return I18n.tr("The installer could not be started. Check that Python 3.9 or newer is installed.");
        case "PERMISSION_DENIED": return I18n.tr("The installation location is not writable. Run Settings as your normal desktop user.");
        default: return I18n.tr("The operation failed. View the log for details.");
        }
    }

}
