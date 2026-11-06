import "../../shared/qml/i18n"
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "components" as Controls

Flow {
    id: page
    property var bridge: null
    property var store: null
    readonly property var music: store ? store.music : ({})
    property var colors
    property var resources: ({})
    property string errorText: ""
    property string requestedApp: ""
    property string planAppId: ""
    property string planId: ""
    property var planData: ({})
    property var dismissedPlanIds: ({})
    signal revealRequested(var card)
    property bool revealPending: true
    function requestReveal() {
        revealPending = true
        Qt.callLater(page.revealApp)
    }
    function revealApp() {
        if (!requestedApp || !revealPending) return
        forceLayout()
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
    spacing: 12
    readonly property int columns: 1
    readonly property real entryWidth: (width - spacing * (columns - 1)) / columns
    readonly property real rowHeight: Math.max(spatialEntry.implicitHeight, musicEntry.implicitHeight)

    function refresh() {
        if (compatible)
            bridge.wallpaperSnapshot();
    }
    Component.onCompleted: {
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

    Controls.ExtensionEntry {
        id: spatialEntry
        width: page.entryWidth
        height: page.columns === 2 ? page.rowHeight : implicitHeight
        category: I18n.tr("Service")
        colors: page.colors
        title: I18n.tr("Spatial wallpaper")
        description: I18n.tr("Add depth and motion to your wallpaper")
        iconSource: Qt.resolvedUrl("icons/spatial-wallpaper.svg")
        actionObjectName: "spatialServiceAction"
        actionText: !page.available ? I18n.tr("Unavailable") : page.resources.busy ? I18n.tr("Preparing…") : page.checking ? I18n.tr("Checking…") : page.resources.enabled ? I18n.tr("Disable") : page.resources.ready ? I18n.tr("Enable") : I18n.tr("Get")
        actionEnabled: page.available && !page.resources.busy && !page.checking
        onActivated: {
            if (page.resources.enabled)
                page.bridge.disableSpatialService();
            else
                page.bridge.initializeSpatialService();
        }

        Text {
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
            objectName: "spatialServiceError"
            Layout.fillWidth: true
            visible: page.errorText.length > 0
            text: page.errorText
            wrapMode: Text.Wrap
            color: page.colors.primaryText
            font.pixelSize: 12
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: page.visible && !!page.store
        onTriggered: page.store.refresh()
    }
    Connections {
        target: page.store
        ignoreUnknownSignals: true
        function onChanged() {
            if (!page.store || planDialog.visible) return;
            const apps = page.store.apps || [];
            for (let i = 0; i < apps.length; ++i) {
                const app = apps[i];
                const plan = app.flatpak ? app.flatpak.plan || ({}) : ({});
                const id = plan.planId || "";
                if (!id || page.dismissedPlanIds[id]) continue;
                page.planAppId = app.id;
                page.planId = id;
                page.planData = plan;
                planDialog.open();
                return;
            }
        }
    }

    Controls.ExtensionEntry {
        id: musicEntry
        objectName: "kmusicEntry"
        width: page.entryWidth
        height: page.columns === 2 ? page.rowHeight : implicitHeight
        category: I18n.tr("App")
        colors: page.colors
        title: "KMusic"
        description: I18n.tr("Your music, all in one place")
        iconSource: Qt.resolvedUrl("icons/kmusic.svg")
        actionObjectName: "kmusicAction"
        actionText: page.music.busy ? I18n.tr("Working…") : page.music.installed ? I18n.tr("Open") : I18n.tr("Install")
        actionEnabled: !!page.store && !page.store.anyBusy && !page.music.busy && (!!page.music.installed || !!page.music.available)
        secondaryText: page.music.busy ? I18n.tr("Cancel") : page.music.installed ? I18n.tr("Uninstall") : ""
        secondaryEnabled: page.music.stage !== "cancelling" && (!!page.music.busy || (!!page.music.available && !page.store.anyBusy))
        onActivated: {
            if (page.music.installed)
                page.store.open();
            else
                page.store.install();
        }
        onSecondaryActivated: {
            if (page.music.busy)
                page.store.cancel();
            else
                uninstallDialog.open();
        }
        Text {
            objectName: "kmusicStatus"
            Layout.fillWidth: true
            visible: !!page.music.busy || !page.music.available || (!page.music.installed && !page.music.code)
            text: page.music.busy ? page.musicStage(page.music.stage) : !page.store ? I18n.tr("Rebuild and reopen Settings to enable app installation") : !page.music.available ? I18n.tr("The installation release has not been published yet") : I18n.tr("Builds from source; development dependencies are required")
            color: page.colors.secondaryText
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "kmusicElapsed"
            Layout.fillWidth: true
            visible: !!page.music.busy
            text: I18n.tr("Elapsed: %1").arg(Math.floor((page.music.elapsedSeconds || 0) / 60) + ":" + ("0" + ((page.music.elapsedSeconds || 0) % 60)).slice(-2))
            color: page.colors.secondaryText
            font.pixelSize: 11
        }
        Text {
            objectName: "kmusicBuildHint"
            Layout.fillWidth: true
            visible: !!page.music.busy && page.music.stage === "build"
            text: I18n.tr("Compiling from source. This may take several minutes; the download has finished.")
            color: page.colors.secondaryText
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: !!page.music.busy
            indeterminate: true
        }
        Text {
            objectName: "kmusicError"
            Layout.fillWidth: true
            visible: !!page.music.code
            text: page.musicError(page.music.code)
            color: page.colors.primaryText
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        Text {
            Layout.fillWidth: true
            visible: !!page.music.busy
            text: I18n.tr("Tasks continue in the background after closing this window. Return anytime to view progress or cancel.")
            color: page.colors.secondaryText
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        Repeater {
            model: page.music.dependencies || []
            delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.id + " · " + modelData.required + (modelData.installed ? " (" + modelData.installed + ")" : "")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !!page.store && (!!page.music.code || !page.music.available)
            WallpaperTextButton {
                label: I18n.tr("Repository")
                colors: page.colors
                onClicked: page.store.openRepository()
            }
            WallpaperTextButton {
                visible: !!page.music.logPath
                label: I18n.tr("View log")
                colors: page.colors
                onClicked: page.store.openLog()
            }
        }
    }

    // One card implementation for each independently released application.
    Repeater {
        id: appEntries
        onItemAdded: Qt.callLater(page.revealApp)
        model: page.store && page.store.apps ? page.store.apps.filter(function(app) { return app.id !== "kmusic"; }) : []
        delegate: Controls.ExtensionEntry {
            id: appCard
            required property var modelData
            readonly property var app: modelData
            readonly property bool blocked: !!page.store.anyBusy
            objectName: app.id + "Entry"
            width: page.entryWidth
            colors: page.colors
            title: app.name + (page.requestedApp === app.id ? " · " + I18n.tr("Selected") : "")
            category: I18n.tr("App")
            description: I18n.tr(app.description || "")
            iconName: app.iconName || "grid"
            actionObjectName: app.id + "Action"
            actionText: app.busy ? I18n.tr("Working…") : app.installed ? I18n.tr("Open") : I18n.tr("Install")
            actionEnabled: !blocked && !!app.statusKnown && (!!app.installed || app.available !== false)
            secondaryText: app.busy ? I18n.tr("Cancel") : app.installed && app.managed ? I18n.tr("Uninstall") : ""
            secondaryEnabled: app.stage !== "cancelling" && (!!app.busy || !blocked)
            onActivated: {
                if (app.installed) page.store.open(app.id);
                else page.store.install(app.id);
            }
            onSecondaryActivated: {
                if (app.busy) page.store.cancel(app.id);
                else { appUninstallDialog.appId = app.id; appUninstallDialog.appName = app.name; appUninstallDialog.open(); }
            }
            Text {
                objectName: appCard.app.id + "Status"
                Layout.fillWidth: true
                text: appCard.app.busy ? page.appStage(appCard.app.stage) : !appCard.app.statusKnown ? I18n.tr("Checking installation status…") : appCard.app.backend === "flatpak-unavailable" ? (appCard.app.flatpak && appCard.app.flatpak.error ? appCard.app.flatpak.error : I18n.tr("Flatpak bundles are unavailable: no reviewed publisher key is included in this core version.")) : appCard.app.backend === "flatpak-ready" ? I18n.tr("Check GitHub for a signed Flatpak bundle before installing.") : appCard.app.backend === "flatpak" ? I18n.tr("Managed by Flatpak. Settings checks GitHub for bundle updates; external Flatpak tools can remove the same installation.") : appCard.app.installed && !appCard.app.managed ? I18n.tr("Installed outside Settings. Open is available; updates and removal stay with its installer.") : appCard.app.available === false ? I18n.tr("No stable release is available yet") : I18n.tr("Builds from source; development dependencies are required")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: appCard.app.backend === "flatpak"
                text: "Flatpak · " + (appCard.app.scope || "") + " · " + (appCard.app.origin || "")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: appCard.app.backend === "flatpak"
                text: appCard.app.bundleManaged ? I18n.tr("Verified standalone bundle; no hosted app source is required.") : I18n.tr("Publisher or local bundle origin could not be verified. Settings will not update this installation.")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                objectName: appCard.app.id + "Version"
                Layout.fillWidth: true
                visible: !!appCard.app.version || !!appCard.app.latestVersion
                text: I18n.tr("Installed: %1 · Latest: %2").arg(appCard.app.version || I18n.tr("Not installed")).arg(appCard.app.latestVersion || I18n.tr("Not checked"))
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: appCard.app.backend === "flatpak" && !!appCard.app.flatpakUpdate && !!appCard.app.flatpakUpdate.commit
                text: appCard.app.flatpakUpdate && appCard.app.flatpakUpdate.available
                    ? I18n.tr("A signed bundle update is available. Use Update to download and deploy it.")
                    : I18n.tr("The installed Flatpak commit matches the signed GitHub release.")
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Basic.ProgressBar {
                Layout.fillWidth: true
                visible: !!appCard.app.busy
                indeterminate: !(appCard.app.progress >= 0)
                value: Math.max(0, Math.min(1, appCard.app.progress || 0))
            }
            Text {
                Layout.fillWidth: true
                visible: !!appCard.app.busy
                text: I18n.tr("Tasks continue in the background after closing this window. Return anytime to view progress or cancel.") + " · " + I18n.tr("Elapsed: %1").arg(Math.floor((appCard.app.elapsedSeconds || 0) / 60) + ":" + ("0" + ((appCard.app.elapsedSeconds || 0) % 60)).slice(-2))
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                Layout.fillWidth: true
                visible: !!appCard.app.busy && !!appCard.app.transactionStatus
                text: appCard.app.transactionStatus || ""
                color: page.colors.secondaryText
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            Text {
                objectName: appCard.app.id + "Error"
                Layout.fillWidth: true
                visible: !!appCard.app.code && appCard.app.code !== "EXTERNALLY_MANAGED"
                text: page.appError(appCard.app.code) + (appCard.app.message ? "\n" + appCard.app.message : "")
                color: page.colors.primaryText
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
            Repeater {
                model: appCard.app.dependencies || []
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    text: typeof modelData === "string" ? modelData : (modelData.id || modelData.name || "") + " " + (modelData.required || "")
                    color: page.colors.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                WallpaperTextButton {
                    objectName: appCard.app.id + "CheckUpdates"
                    label: I18n.tr("Check for updates")
                    colors: page.colors
                    enabled: !appCard.blocked && appCard.app.backend !== "flatpak-unavailable" && (appCard.app.backend !== "flatpak" && appCard.app.backend !== "flatpak-ready" || !!appCard.app.canCheckUpdates)
                    onClicked: page.store.checkUpdates(appCard.app.id)
                }
                WallpaperTextButton {
                    objectName: appCard.app.id + "Update"
                    visible: !!appCard.app.installed && !!appCard.app.managed && !!appCard.app.updateAvailable
                    enabled: !appCard.blocked
                    label: I18n.tr("Update")
                    colors: page.colors
                    onClicked: page.store.update(appCard.app.id)
                }
                WallpaperTextButton {
                    visible: !!appCard.app.installed && !!appCard.app.managed && appCard.app.backend !== "flatpak"
                    enabled: !appCard.blocked
                    label: I18n.tr("Preview old program versions")
                    colors: page.colors
                    onClicked: page.store.cleanupProgram(appCard.app.id, "cleanup-plan")
                }
                WallpaperTextButton {
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
                    label: I18n.tr("Repository")
                    colors: page.colors
                    onClicked: page.store.openRepository(appCard.app.id)
                }
                WallpaperTextButton {
                    visible: !!appCard.app.logPath
                    label: I18n.tr("View log")
                    colors: page.colors
                    onClicked: page.store.openLog(appCard.app.id)
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
            text: programActionDialog.detail
            color: page.colors.primaryText
            wrapMode: Text.WrapAnywhere
        }
        background: Rectangle { radius: 10; color: page.colors.card; border.color: page.colors.secondaryText }
    }
    Dialog {
        id: planDialog
        objectName: "flatpakPlanDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(560, parent ? parent.width - 32 : 560)
        height: Math.min(620, parent ? parent.height - 32 : 620)
        modal: true
        title: I18n.tr("Review Flatpak plan")
        property var app: {
            const list = page.store ? page.store.apps || [] : [];
            for (let i = 0; i < list.length; ++i)
                if (list[i].id === page.planAppId) return list[i];
            return ({});
        }
        property var plan: page.planData
        onClosed: {
            if (page.planId) {
                const dismissed = Object.assign({}, page.dismissedPlanIds);
                dismissed[page.planId] = true;
                page.dismissedPlanIds = dismissed;
            }
            page.planId = "";
            page.planAppId = "";
            page.planData = ({});
        }
        contentItem: Flickable {
            contentWidth: width
            contentHeight: planContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: planContent
                width: parent.width
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: (planDialog.app.name || page.planAppId) + " · " + (planDialog.plan.operation || "")
                        + " · " + (planDialog.plan.version || I18n.tr("Unknown version"))
                    color: page.colors.primaryText
                    font.bold: true
                    wrapMode: Text.WrapAnywhere
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Branch: %1 · Architecture: %2 · Scope: user").arg(planDialog.plan.branch || I18n.tr("Unknown")).arg(planDialog.plan.arch || I18n.tr("Unknown"))
                        + "\n" + I18n.tr("Trusted publisher: %1").arg((planDialog.plan.sourceTrust || []).join(", ") || I18n.tr("Unknown"))
                    color: page.colors.secondaryText
                    wrapMode: Text.WrapAnywhere
                }
                Repeater {
                    model: planDialog.plan.operationSet || []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: (modelData.role || I18n.tr("Dependency")) + " · " + (modelData.ref || I18n.tr("Unknown reference"))
                            color: page.colors.primaryText
                            wrapMode: Text.WrapAnywhere
                        }
                        Text {
                            Layout.fillWidth: true
                            text: (modelData.action || "") + " · " + (modelData.remote || I18n.tr("Signed bundle"))
                                + " · " + (modelData.sizeKnown === false ? I18n.tr("Download size unknown") : page.formatBytes(modelData.downloadBytes))
                                + " · " + (modelData.installedBytes === undefined ? I18n.tr("Installed size unknown") : page.formatBytes(modelData.installedBytes))
                            color: page.colors.secondaryText
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Estimated download: %1").arg(page.formatBytes(page.planDownloadBytes(planDialog.plan)))
                        + "\n" + I18n.tr("Reference installed size: %1").arg(page.formatBytes(page.planInstalledBytes(planDialog.plan)))
                    color: page.colors.primaryText
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Installed sizes are reference values; actual additional disk use can be lower when OSTree objects are shared. Unknown sizes are not included in totals. Reused runtimes show zero download in this plan, but shared objects may still affect disk use.")
                        + " " + I18n.tr("KDE on the host does not count as a Flatpak sandbox runtime.")
                    color: page.colors.secondaryText
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }
        footer: DialogButtonBox {
            standardButtons: DialogButtonBox.Cancel
            Button {
                objectName: "flatpakPlanConfirm"
                text: planDialog.plan.operation === "update" ? I18n.tr("Download and update") : I18n.tr("Download and install")
                enabled: !!page.store && !!page.planId && !page.store.anyBusy
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    const id = page.planAppId;
                    const planId = page.planId;
                    planDialog.close();
                    if (page.store && !page.store.anyBusy) page.store.confirmPlan(id, planId);
                }
            }
            onRejected: planDialog.close()
        }
        background: Rectangle { radius: 8; color: page.colors.card; border.color: page.colors.secondaryText }
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
            text: I18n.tr("Your personal data and preferences will be kept.")
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
    function planInstalledBytes(plan) {
        const operations = plan && plan.operationSet ? plan.operationSet : [];
        let total = 0;
        for (let i = 0; i < operations.length; ++i) {
            const value = operations[i].installedBytes;
            if (value === undefined || value === null || value === "" || Number(value) < 0 || !isFinite(Number(value)))
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
        case "uninstall": return I18n.tr("Uninstalling…");
        case "cleanup-plan": return I18n.tr("Inspecting old program versions…");
        case "prune": return I18n.tr("Cleaning installer-owned old versions…");
        case "cancelling": return I18n.tr("Cancelling…");
        default: return I18n.tr("Preparing…");
        }
    }
    function appError(code) {
        switch (code) {
        case "RELEASE_UNAVAILABLE": case "NO_RELEASE": return I18n.tr("No stable release is available yet");
        case "NETWORK_ERROR": case "TLS_ERROR": case "DOWNLOAD_FAILED": return I18n.tr("Network request failed. Check your connection and try again.");
        case "RATE_LIMITED": case "RATE_LIMIT": return I18n.tr("GitHub request limit reached. Try again later.");
        case "DEPENDENCY_UNSATISFIED": return I18n.tr("Install or update the dependencies listed below, then try again.");
        case "OPERATION_TIMEOUT": case "DOWNLOAD_TIMEOUT": case "NETWORK_TIMEOUT": case "TIMED_OUT": return I18n.tr("The operation timed out and was stopped. View the log before trying again.");
        case "CANCELLED": return I18n.tr("Operation cancelled");
        case "OPEN_FAILED": return I18n.tr("The app could not be opened. Check the installation and try again.");
        case "BUNDLE_KEY_MISSING": return I18n.tr("Flatpak bundles are unavailable: no reviewed publisher key is included in this core version.");
        case "ARCH_UNAVAILABLE": return I18n.tr("No Flatpak bundle has been published for this architecture.");
        case "VERSION_CONFLICT": return I18n.tr("The signed release would downgrade or replace an existing version. Deployment was refused.");
        case "INVALID_RELEASE": case "INTEGRITY_FAILED": case "UNTRUSTED_URL": case "RESPONSE_TOO_LARGE": return I18n.tr("The release metadata or bundle failed validation. Nothing was deployed.");
        case "FLATPAK_UNAVAILABLE": return I18n.tr("No approved signed bundle is available. Check publisher trust and installation conflicts, then check for updates.");
        case "PLAN_REQUIRED": return I18n.tr("Review and confirm the Flatpak dependency plan before downloading.");
        case "PLAN_UNAVAILABLE": return I18n.tr("A complete Flatpak installation plan could not be prepared. Check the approved sources and try again.");
        case "PLAN_CHANGED": return I18n.tr("The Flatpak installation plan changed or expired. Prepare a fresh plan before continuing.");
        case "WORKER_UNAVAILABLE": return I18n.tr("The optional Flatpak backend is unavailable. Install it and its distribution dependencies, then recheck.");
        case "WORKER_TIMEOUT": return I18n.tr("The optional Flatpak backend timed out. Installed state is unknown; recheck before retrying.");
        case "FLATPAK_TIMEOUT": return I18n.tr("The Flatpak operation exceeded its time limit. Cancellation was requested; the displayed installation state was queried again.");
        case "FLATPAK_UNTRUSTED": return I18n.tr("The app or runtime source does not match the approved publisher policy. No unapproved deployment was authorized.");
        case "FLATPAK_RUNTIME_MISSING": return I18n.tr("A required Flatpak runtime is unavailable. Configure its approved software source first.");
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

    Dialog {
        id: uninstallDialog
        objectName: "kmusicUninstallDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(360, parent ? parent.width - 32 : 360)
        modal: true
        title: I18n.tr("Uninstall KMusic?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: if (page.store)
            page.store.uninstall()
        contentItem: Text {
            text: I18n.tr("Your music library, preferences and account data will be kept.")
            color: page.colors.primaryText
            wrapMode: Text.Wrap
        }
    }

    function musicStage(stage) {
        switch (stage) {
        case "bootstrap":
            return I18n.tr("Downloading installer… Attempt %1/%2").arg(page.music.attempt || 1).arg(page.music.maxAttempts || 3);
        case "retry-bootstrap":
            return I18n.tr("Installer download failed. Retrying… Attempt %1/%2").arg(page.music.attempt).arg(page.music.maxAttempts);
        case "retry-download":
            return I18n.tr("Source download failed. Retrying… Attempt %1/%2").arg(page.music.attempt).arg(page.music.maxAttempts);
        case "check":
            return I18n.tr("Checking dependencies…");
        case "download":
            return I18n.tr("Downloading KMusic… Attempt %1/%2 (up to 5 minutes each)").arg(page.music.attempt || 1).arg(page.music.maxAttempts || 5);
        case "build":
            return I18n.tr("Building KMusic…");
        case "install":
            return I18n.tr("Installing KMusic…");
        case "uninstall":
            return I18n.tr("Uninstalling KMusic…");
        case "status":
            return I18n.tr("Refreshing installation status…");
        case "cancelling":
            return I18n.tr("Cancelling…");
        default:
            return I18n.tr("Preparing…");
        }
    }

    function musicError(code) {
        switch (code) {
        case "DEPENDENCY_UNSATISFIED":
            return I18n.tr("Install or update the dependencies listed below, then try again.");
        case "UNSUPPORTED_PLATFORM":
            return I18n.tr("KMusic source installation supports Arch, Ubuntu and Debian on x86_64 and aarch64.");
        case "RELEASE_UNAVAILABLE":
            return I18n.tr("The installation release has not been published yet");
        case "DOWNLOAD_FAILED":
            return I18n.tr("Download failed after %1 attempt(s). Check your connection and try again.").arg(page.music.attempt || 1);
        case "DOWNLOAD_TIMEOUT":
            return I18n.tr("Download timed out after %1 attempt(s). Check your connection and try again.").arg(page.music.attempt || 1);
        case "OPERATION_TIMEOUT":
            return I18n.tr("The operation timed out and was stopped. View the log before trying again.");
        case "INTEGRITY_FAILED":
            return I18n.tr("Installer verification failed. The operation was stopped.");
        case "INSTALL_BUSY":
            return I18n.tr("Another KMusic installation is already running.");
        case "CANCELLED":
            return I18n.tr("Operation cancelled");
        case "RESULT_UNKNOWN":
            return I18n.tr("Installation was interrupted or its result could not be confirmed. Check the log before retrying.");
        case "OPEN_FAILED":
            return I18n.tr("KMusic could not be opened. Check the installation and try again.");
        case "PERMISSION_DENIED":
            return I18n.tr("The installation location is not writable. Run Settings as your normal desktop user.");
        case "BUILD_FAILED":
            return I18n.tr("KMusic could not be built. View the log for details.");
        case "UNINSTALL_FAILED":
            return I18n.tr("KMusic could not be uninstalled. View the log for details.");
        case "START_FAILED":
            return I18n.tr("The installer could not be started. Check that Python 3.9 or newer is installed.");
        default:
            return I18n.tr("The operation failed. View the log for details.");
        }
    }
}
