import "../../shared/qml/i18n"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components" as Controls

Flow {
    id: page
    property var bridge: null
    property var store: null
    property var notes: null
    readonly property var music: store ? store.music : ({})
    property var colors
    property var resources: ({})
    property string errorText: ""
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
        if (store)
            store.refresh();
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
        actionEnabled: !!page.store && !page.music.busy && (!!page.music.installed || !!page.music.available)
        secondaryText: page.music.busy ? I18n.tr("Cancel") : page.music.installed ? I18n.tr("Uninstall") : ""
        secondaryEnabled: page.music.stage !== "cancelling" && (!!page.music.busy || !!page.music.available)
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
            text: I18n.tr("Keep Settings open until the operation finishes, or cancel it here.")
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

    // 便签 + Markdown 笔记 + 记忆系统。安装后点「开启」才会启动；启动后常驻
    // 状态栏（StatusNotifierItem）并出现桌面悬浮球。运行状态由 D-Bus 上的
    // org.nextkde.Notes 判断：从悬浮球/托盘退出后，这里会自动回到「开启」。
    Controls.ExtensionEntry {
        id: notesEntry
        objectName: "myNotesEntry"
        width: page.entryWidth
        height: page.columns === 2 ? page.rowHeight : implicitHeight
        category: I18n.tr("Extension")
        colors: page.colors
        title: I18n.tr("My notes")
        description: I18n.tr("Sticky notes, Markdown notes and the memory system — with a floating ball and a status bar entry")
        iconSource: Qt.resolvedUrl("icons/my-notes.svg")
        actionObjectName: "myNotesAction"
        readonly property var nt: page.notes ? page.notes.state : ({})
        actionText: !page.notes || !notesEntry.nt.available ? I18n.tr("Unavailable")
            : notesEntry.nt.busy ? I18n.tr("Working…")
            : notesEntry.nt.installed && notesEntry.nt.running ? I18n.tr("Turned on")
            : notesEntry.nt.installed ? I18n.tr("Turn on")
            : I18n.tr("Install")
        actionEnabled: !!page.notes && !!notesEntry.nt.available && !notesEntry.nt.busy
            && !(notesEntry.nt.installed && notesEntry.nt.running)
        secondaryText: !page.notes || !notesEntry.nt.available ? ""
            : notesEntry.nt.running ? I18n.tr("Quit")
            : notesEntry.nt.installed ? I18n.tr("Uninstall")
            : ""
        secondaryEnabled: !!page.notes && !notesEntry.nt.busy
            && (!!notesEntry.nt.running || !!notesEntry.nt.installed)
        onActivated: {
            if (!page.notes) return
            if (notesEntry.nt.installed && !notesEntry.nt.running) page.notes.launch()
            else if (!notesEntry.nt.installed) page.notes.install()
        }
        onSecondaryActivated: {
            if (!page.notes) return
            if (notesEntry.nt.running) page.notes.quit()
            else if (notesEntry.nt.installed) notesUninstallDialog.open()
        }
        Text {
            objectName: "myNotesStatus"
            Layout.fillWidth: true
            text: !page.notes ? I18n.tr("Rebuild Settings to manage this extension")
                : !notesEntry.nt.available ? I18n.tr("The NextKde/Notes source directory was not found")
                : notesEntry.nt.busy ? I18n.tr("Building My notes…")
                : notesEntry.nt.code === "BUILD_FAILED" ? I18n.tr("Build failed — open the install log")
                : notesEntry.nt.code === "SOURCE_MISSING" ? I18n.tr("The NextKde/Notes source directory was not found")
                : notesEntry.nt.code === "LAUNCH_FAILED" ? I18n.tr("My notes could not be started")
                : notesEntry.nt.running ? I18n.tr("Turned on · the status bar icon and floating ball are ready")
                : notesEntry.nt.installed ? I18n.tr("Installed · press “Turn on” to start notes and the floating ball")
                : I18n.tr("The first launch builds locally and takes about 1–2 minutes")
            color: page.colors.secondaryText
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        Text {
            objectName: "myNotesStorage"
            Layout.fillWidth: true
            visible: !!page.notes && !!notesEntry.nt.storageRoot && notesEntry.nt.storageRoot.length > 0
            text: I18n.tr("Notes folder: %1").arg(notesEntry.nt.storageRoot || "")
            color: page.colors.secondaryText
            font.pixelSize: 11
            elide: Text.ElideMiddle
            wrapMode: Text.NoWrap
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !!page.notes && !!notesEntry.nt.installed
            WallpaperTextButton {
                label: I18n.tr("Open notes")
                colors: page.colors
                onClicked: page.notes.openMainWindow()
            }
            WallpaperTextButton {
                label: I18n.tr("View install log")
                colors: page.colors
                visible: !!(notesEntry.nt.logPath && notesEntry.nt.logPath.length > 0)
                onClicked: Qt.openUrlExternally("file://" + notesEntry.nt.logPath)
            }
        }
    }

    Dialog {
        id: notesUninstallDialog
        objectName: "myNotesUninstallDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(380, parent ? parent.width - 32 : 380)
        modal: true
        title: I18n.tr("Uninstall My notes?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: if (page.notes)
            page.notes.uninstall()
        contentItem: Text {
            text: I18n.tr("Only the program is removed; your Markdown notes stay untouched.")
            color: page.colors.primaryText
            wrapMode: Text.Wrap
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
