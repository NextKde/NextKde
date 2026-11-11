import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Dialogs as NativeDialogs
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: page
    objectName: "PluginSettingsPage"
    property var colors
    property var store: null
    property string selectedKey: ""
    property int category: 0
    property var selectedPermissions: []
    property var permissionDraft: []
    property bool waitingForPlan: false
    signal manageSourcesRequested()
    spacing: 14

    // Normalize nested QVariant sequences once at the boundary; QML consumers
    // use real JS arrays without assuming Array.isArray(QVariantList).
    readonly property var snapshot: store ? JSON.parse(JSON.stringify(store.snapshot)) : ({})
    readonly property var plan: store ? JSON.parse(JSON.stringify(store.plan)) : ({})
    readonly property bool busy: !!store && store.busy
    readonly property bool ready: !!store && store.connected && snapshot.revision !== undefined
    readonly property bool canAct: ready && !busy
    readonly property var entries: buildEntries()
    readonly property var filteredEntries: entries.filter(function(entry) {
        const query = search.text.trim().toLowerCase()
        if (query && (entry.name + " " + entry.description + " " + entry.id + " " + entry.author).toLowerCase().indexOf(query) < 0) return false
        if (category === 1) return entry.installed
        if (category === 2) return entry.updateAvailable
        if (category === 3) return entry.sourceKind === "catalog"
        if (category === 4) return entry.sourceKind === "example"
        if (category === 5) return entry.sourceKind === "local"
        return true
    })
    readonly property var selected: entries.find(entry => entry.key === selectedKey) || ({})

    function localText(value) {
        if (typeof value === "string") return value
        return value ? (value[I18n.language] || value.en || "") : ""
    }
    function buildEntries() {
        const installed = snapshot.plugins || []
        const rows = (snapshot.catalog || []).map(function(candidate) {
            const record = installed.find(plugin => plugin.id === candidate.id && plugin.sourceId === candidate.sourceId)
            return makeEntry(candidate, record)
        })
        for (const record of installed) {
            if (!rows.some(row => row.id === record.id && row.sourceId === record.sourceId))
                rows.push(makeEntry(null, record))
        }
        return rows
    }
    function makeEntry(candidate, record) {
        const data = Object.assign({}, candidate || {}, record || {})
        data.key = data.sourceId + ":" + data.id
        data.name = localText(data.name) || data.id
        data.description = localText(data.description)
        data.author = localText(data.author)
        data.installed = !!record
        data.candidateVersion = candidate ? candidate.version : ""
        data.installedVersion = record ? record.version : ""
        data.available = !!candidate && candidate.available !== false
        data.updateAvailable = !!record && !!candidate && data.available && newerVersion(candidate.version, record.version)
        data.candidateError = candidate ? candidate.error || "" : ""
        data.permissions = record ? record.permissions || [] : []
        data.grantedPermissions = record ? record.grantedPermissions || [] : []
        data.widgets = record ? record.widgets || [] : []
        return data
    }
    function newerVersion(candidate, installed) {
        const a = String(candidate || "").split(".").map(Number)
        const b = String(installed || "").split(".").map(Number)
        for (let i = 0; i < 3; ++i) {
            if (a[i] > b[i]) return true
            if (a[i] < b[i]) return false
        }
        return false
    }
    function sourceLabel(kind) {
        if (kind === "catalog") return I18n.tr("Signed catalog")
        if (kind === "example") return I18n.tr("SDK example")
        return I18n.tr("Local development import")
    }
    function permissionLabel(permission) {
        if (permission === "system.summary") return I18n.tr("Memory and uptime summary")
        return permission
    }
    function statusLabel(entry) {
        if (!entry.installed) return entry.available ? I18n.tr("Available") : I18n.tr("Unavailable")
        if (!entry.enabled) return I18n.tr("Disabled")
        if (entry.status === "ready" || entry.status === "enabled" || !entry.status) return I18n.tr("Enabled")
        if (entry.status === "permission-required") return I18n.tr("Permission required")
        if (entry.status === "unavailable") return I18n.tr("Unavailable")
        if (entry.status === "revoked") return I18n.tr("Revoked")
        return I18n.tr(entry.status)
    }
    function operationLabel(operation) {
        if (operation === "plugin.prepare-install") return I18n.tr("Preparing installation plan…")
        if (operation === "plugin.confirm-install") return I18n.tr("Installing plugin…")
        if (operation === "plugin.refresh-catalog") return I18n.tr("Refreshing signed catalog…")
        if (operation === "plugin.uninstall") return I18n.tr("Uninstalling plugin…")
        if (operation === "plugin.instance-add") return I18n.tr("Adding widget…")
        if (operation === "plugin.snapshot") return I18n.tr("Loading plugins…")
        return I18n.tr("Saving plugin settings…")
    }
    function togglePermission(values, permission, granted) {
        const next = values.filter(value => value !== permission)
        if (granted) next.push(permission)
        return next
    }
    function openDetails(entry) {
        selectedKey = entry.key
        detailsDialog.open()
    }
    function prepare(entry) {
        if (!canAct || !entry.available) return
        waitingForPlan = true
        detailsDialog.close()
        store.prepareInstall(entry.sourceId, entry.id)
    }
    function showPermissionEditor() {
        permissionDraft = selected.grantedPermissions.slice()
        permissionDialog.open()
    }
    Component.onCompleted: { if (store) store.observing = visible }
    Component.onDestruction: { if (store) store.observing = false }
    onVisibleChanged: {
        if (store) store.observing = visible
        if (!visible) {
            waitingForPlan = false
            detailsDialog.close()
            planDialog.close()
            permissionDialog.close()
            uninstallDialog.close()
            filePicker.close()
        }
    }
    Connections {
        target: page.store
        function onPlanReady() {
            if (!page.waitingForPlan || !page.visible) { page.store.discardPlan(); return }
            page.waitingForPlan = false
            const installed = (page.snapshot.plugins || []).find(plugin => plugin.id === page.plan.pluginId && plugin.sourceId === page.plan.sourceId)
            const previous = installed ? installed.grantedPermissions || [] : []
            page.selectedPermissions = previous.filter(permission => (page.plan.permissions || []).indexOf(permission) >= 0)
            localTrust.checked = false
            planDialog.open()
        }
        function onPlanChanged() {
            if (!page.store.plan.id) planDialog.close()
        }
        function onOperationFinished(operation, success) {
            if (operation === "plugin.prepare-install" && !success) page.waitingForPlan = false
        }
    }

    component BodyText: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        color: page.colors.secondaryText
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
    component SectionTitle: BodyText {
        color: page.colors.primaryText
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: page.colors.separator
    }
    component Metadata: ColumnLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 3
        BodyText { text: label; font.pixelSize: 11 }
        BodyText { text: value || "—"; color: page.colors.primaryText; wrapMode: Text.WrapAnywhere }
    }
    component PluginDialog: Dialog {
        id: dialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(550, parent ? parent.width - 32 : 550)
        height: Math.min(600, parent ? parent.height - 32 : 600)
        modal: true
        padding: 22
        closePolicy: Popup.CloseOnEscape
        background: Rectangle {
            radius: 22
            color: page.colors.contentSurface
            border.width: 1
            border.color: page.colors.separator
        }
        header: Text {
            text: dialog.title
            textFormat: Text.PlainText
            color: page.colors.primaryText
            font.pixelSize: 17
            font.weight: Font.DemiBold
            padding: 22
            bottomPadding: 8
            wrapMode: Text.Wrap
        }
    }

    BodyText {
        text: I18n.tr("Discover data-only desktop widgets. Plugins use built-in components; they cannot execute QML, JavaScript or native code, or access the network.")
    }
    Basic.TextField {
        id: search
        objectName: "pluginSearch"
        Layout.fillWidth: true
        placeholderText: I18n.tr("Search plugins")
        color: page.colors.primaryText
        placeholderTextColor: page.colors.secondaryText
        selectByMouse: true
        leftPadding: 12
        implicitHeight: 34
        background: Rectangle { radius: 8; color: page.colors.searchField }
        Accessible.name: placeholderText
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Controls.SettingsSelect {
            objectName: "pluginCategory"
            colors: page.colors
            Layout.fillWidth: true
            model: [I18n.tr("All plugins"), I18n.tr("Installed"), I18n.tr("Updates"), I18n.tr("Signed catalog"), I18n.tr("SDK examples"), I18n.tr("Development")]
            currentIndex: page.category
            onSelectionChanged: index => page.category = index
            Accessible.name: I18n.tr("Plugin category")
        }
        Controls.SettingsTextButton {
            label: I18n.tr("Refresh")
            colors: page.colors
            enabled: !!page.store && !page.busy
            onClicked: page.store.refresh(true)
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 10
        Controls.SettingsTextButton {
            objectName: "pluginImport"
            label: I18n.tr("Import development plugin…")
            colors: page.colors
            enabled: page.canAct
            onClicked: filePicker.open()
        }
        Controls.SettingsTextButton {
            label: I18n.tr("Manage app sources")
            colors: page.colors
            onClicked: page.manageSourcesRequested()
        }
    }
    BodyText {
        text: I18n.tr("Signed catalog packages are verified before installation. SDK examples ship with KOS. Development imports are unsigned local JSON files and require your explicit trust.")
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: page.busy
        spacing: 6
        BodyText { text: page.store ? page.operationLabel(page.store.operation) : "" }
        Basic.ProgressBar { Layout.fillWidth: true; indeterminate: true }
    }
    BodyText {
        objectName: "pluginError"
        visible: text.length > 0
        text: page.store ? I18n.tr(page.store.error || page.snapshot.error || "") : I18n.tr("Plugin service unavailable. Refresh to reconnect.")
        color: page.colors.primaryText
    }
    BodyText {
        objectName: "pluginOperationResult"
        visible: text.length > 0
        text: page.store ? I18n.tr(page.store.lastMessage || "") : ""
        color: page.colors.accent
    }
    Rule {}
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 560 ? 2 : 1
        columnSpacing: 24
        rowSpacing: 20
        Repeater {
            model: page.filteredEntries
            delegate: ColumnLayout {
                id: card
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                spacing: 5
                Controls.ExtensionEntry {
                    Layout.fillWidth: true
                    colors: page.colors
                    title: card.modelData.name
                    description: card.modelData.description
                    iconName: "grid"
                    iconColor: card.modelData.sourceKind === "catalog" ? "#5b7cfa" : card.modelData.sourceKind === "example" ? "#39a885" : "#a775cf"
                    actionObjectName: "pluginAction_" + card.modelData.id
                    actionText: card.modelData.updateAvailable ? I18n.tr("Update") : card.modelData.installed ? I18n.tr("Manage") : I18n.tr("Install")
                    actionEnabled: page.canAct && (card.modelData.installed || card.modelData.available)
                    actionAvailable: card.modelData.installed || card.modelData.available
                    onDetailsRequested: page.openDetails(card.modelData)
                    onActivated: {
                        if (card.modelData.installed && !card.modelData.updateAvailable) page.openDetails(card.modelData)
                        else page.prepare(card.modelData)
                    }
                }
                BodyText {
                    text: page.sourceLabel(card.modelData.sourceKind) + " · " + I18n.tr("Version %1").arg(card.modelData.version || "—")
                    font.pixelSize: 11
                }
                BodyText {
                    text: page.statusLabel(card.modelData) + (card.modelData.updateAvailable ? " · " + I18n.tr("Update available: %1").arg(card.modelData.candidateVersion) : "")
                    font.pixelSize: 11
                    color: card.modelData.updateAvailable ? page.colors.accent : page.colors.secondaryText
                }
            }
        }
    }
    BodyText {
        visible: page.filteredEntries.length === 0 && !page.busy
        text: search.text || page.category !== 0 ? I18n.tr("No plugins match this search.") : I18n.tr("No plugins available. Refresh the catalog or import a development plugin.")
    }

    NativeDialogs.FileDialog {
        id: filePicker
        title: I18n.tr("Import development plugin")
        nameFilters: [I18n.tr("Plugin manifests (*.json)")]
        fileMode: NativeDialogs.FileDialog.OpenFile
        onAccepted: {
            if (!page.canAct) return
            page.waitingForPlan = true
            page.store.importFile(selectedFile)
        }
    }

    PluginDialog {
        id: detailsDialog
        objectName: "pluginDetailsDialog"
        title: page.selected.name || I18n.tr("Plugin details")
        contentItem: Flickable {
            contentWidth: width
            contentHeight: detailsContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: detailsContent
                width: parent.width
                spacing: 14
                BodyText { text: page.selected.description || "" }
                Metadata { label: I18n.tr("Plugin ID"); value: page.selected.id || "" }
                Metadata { label: I18n.tr("Author"); value: page.selected.author || "" }
                Metadata { label: I18n.tr("Source"); value: page.sourceLabel(page.selected.sourceKind) + " · " + (page.selected.sourceId || "") }
                Metadata {
                    label: I18n.tr("Version")
                    value: page.selected.installed
                        ? I18n.tr("Installed: %1").arg(page.selected.installedVersion) + (page.selected.candidateVersion ? "\n" + I18n.tr("Catalog: %1").arg(page.selected.candidateVersion) : "")
                        : page.selected.candidateVersion || ""
                }
                Metadata { label: I18n.tr("Status"); value: page.statusLabel(page.selected) }
                BodyText { visible: text.length > 0; text: I18n.tr(page.selected.message || page.selected.candidateError || "") }
                Rule {}
                SectionTitle { text: I18n.tr("Allowed permissions") }
                BodyText {
                    text: !page.selected.installed ? I18n.tr("Package permissions are verified when preparing an installation plan. Nothing is granted before confirmation.")
                        : (page.selected.grantedPermissions || []).length === 0 ? I18n.tr("None. All permissions are denied by default.")
                        : page.selected.grantedPermissions.map(page.permissionLabel).join("\n")
                }
                BodyText {
                    visible: page.selected.installed === true && (page.selected.permissions || []).some(permission => page.selected.grantedPermissions.indexOf(permission) < 0)
                    text: I18n.tr("Denied: %1").arg((page.selected.permissions || []).filter(permission => page.selected.grantedPermissions.indexOf(permission) < 0).map(page.permissionLabel).join(", "))
                }
                Controls.SettingsTextButton {
                    visible: page.selected.installed === true
                    label: I18n.tr("Review permissions…")
                    colors: page.colors
                    enabled: page.canAct
                    onClicked: page.showPermissionEditor()
                }
                Rule { visible: page.selected.installed === true }
                SectionTitle { visible: page.selected.installed === true; text: I18n.tr("Widgets") }
                Repeater {
                    model: page.selected.widgets || []
                    delegate: ColumnLayout {
                        id: widgetRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        SectionTitle { text: page.localText(widgetRow.modelData.name) || widgetRow.modelData.id }
                        BodyText { text: page.localText(widgetRow.modelData.description) }
                        RowLayout {
                            Layout.fillWidth: true
                            Controls.SettingsSelect {
                                id: sizeSelector
                                colors: page.colors
                                Layout.fillWidth: true
                                model: (widgetRow.modelData.sizes || []).map(size => size === "small" ? I18n.tr("Small") : size === "large" ? I18n.tr("Large") : I18n.tr("Medium"))
                                currentIndex: Math.max(0, (widgetRow.modelData.sizes || []).indexOf("medium"))
                                Accessible.name: I18n.tr("Widget size")
                            }
                            Controls.SettingsTextButton {
                                label: I18n.tr("Add to desktop")
                                colors: page.colors
                                enabled: page.canAct && page.selected.enabled === true && page.selected.status !== "unavailable"
                                    && (widgetRow.modelData.sizes || []).length > 0
                                    && (widgetRow.modelData.multiInstance === true || !(page.snapshot.instances || []).some(instance => instance.pluginId === page.selected.id && instance.widgetId === widgetRow.modelData.id))
                                onClicked: page.store.addInstance(page.selected.id, widgetRow.modelData.id, widgetRow.modelData.sizes[sizeSelector.currentIndex])
                            }
                        }
                    }
                }
                BodyText {
                    visible: page.selected.installed === true
                    text: I18n.tr("Installing a plugin does not place widgets automatically. Disabling preserves widget positions and settings.")
                }
                BodyText {
                    visible: page.busy
                    text: page.store ? page.operationLabel(page.store.operation) : ""
                }
                BodyText {
                    text: page.store ? I18n.tr(page.store.error || page.store.lastMessage || "") : ""
                    visible: text.length > 0
                    color: page.colors.primaryText
                }
            }
        }
        footer: Flow {
            padding: 18
            spacing: 8
            Controls.SettingsTextButton {
                visible: !page.selected.installed || page.selected.updateAvailable === true
                label: page.selected.installed ? I18n.tr("Review update…") : I18n.tr("Review installation…")
                colors: page.colors
                emphasized: true
                enabled: page.canAct && page.selected.available === true
                onClicked: page.prepare(page.selected)
            }
            Controls.SettingsTextButton {
                visible: page.selected.installed === true
                label: page.selected.enabled ? I18n.tr("Disable") : I18n.tr("Enable")
                colors: page.colors
                enabled: page.canAct
                onClicked: page.store.setEnabled(page.selected.id, !page.selected.enabled)
            }
            Controls.SettingsTextButton {
                visible: page.selected.installed === true
                label: I18n.tr("Uninstall…")
                colors: page.colors
                enabled: page.canAct
                onClicked: { removeData.checked = false; uninstallDialog.open() }
            }
            Controls.SettingsTextButton { label: I18n.tr("Close"); colors: page.colors; onClicked: detailsDialog.close() }
        }
    }

    PluginDialog {
        id: planDialog
        objectName: "pluginPlanDialog"
        title: page.plan.previousVersion ? I18n.tr("Review plugin update") : I18n.tr("Review plugin installation")
        onClosed: { if (page.store) page.store.discardPlan() }
        contentItem: Flickable {
            contentWidth: width
            contentHeight: planContent.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ColumnLayout {
                id: planContent
                width: parent.width
                spacing: 12
                SectionTitle { text: page.localText(page.plan.name) || page.plan.pluginId || "" }
                Metadata {
                    label: I18n.tr("Version")
                    value: page.plan.previousVersion ? page.plan.previousVersion + " → " + page.plan.version : page.plan.version || ""
                }
                Metadata { label: I18n.tr("Source"); value: page.sourceLabel(page.plan.sourceKind) + " · " + (page.plan.sourceId || "") }
                BodyText { visible: !!page.plan.previousVersion; text: I18n.tr("This update replaces the installed package and preserves compatible widget settings. Review any newly requested permissions below.") }
                BodyText { visible: page.plan.requiresTrust === true; text: I18n.tr("Unsigned development file. Its publisher has not been verified by a signed catalog. Import only a file you trust."); color: page.colors.primaryText }
                Rule {}
                SectionTitle { text: I18n.tr("Choose allowed permissions") }
                BodyText { text: I18n.tr("Permissions are optional and denied by default. Existing grants are preserved for updates; new permissions remain denied unless you select them. Restricted values stay unavailable without permission.") }
                BodyText { visible: (page.plan.permissions || []).length === 0; text: I18n.tr("This plugin requests no permissions.") }
                Repeater {
                    model: page.plan.permissions || []
                    delegate: Basic.CheckBox {
                        required property string modelData
                        Layout.fillWidth: true
                        checked: page.selectedPermissions.indexOf(modelData) >= 0
                        text: page.permissionLabel(modelData) + ((page.plan.addedPermissions || []).indexOf(modelData) >= 0 && page.plan.previousVersion ? " · " + I18n.tr("New permission") : "")
                        contentItem: BodyText { leftPadding: 28; text: parent.text; color: page.colors.primaryText }
                        onToggled: page.selectedPermissions = page.togglePermission(page.selectedPermissions, modelData, checked)
                    }
                }
                BodyText { visible: (page.plan.permissions || []).indexOf("system.summary") >= 0; text: I18n.tr("Memory and uptime only. No files, process lists, personal data or network access.") }
                Rule {}
                SectionTitle { text: I18n.tr("Included widgets") }
                Repeater {
                    model: page.plan.widgets || []
                    delegate: BodyText {
                        required property var modelData
                        text: page.localText(modelData.name) || modelData.id || String(modelData)
                    }
                }
                Repeater {
                    model: page.plan.warnings || []
                    delegate: BodyText { required property string modelData; text: I18n.tr(modelData) }
                }
                Metadata { label: I18n.tr("Package SHA-256"); value: page.plan.digest || "" }
                Basic.CheckBox {
                    id: localTrust
                    objectName: "pluginTrustLocal"
                    Layout.fillWidth: true
                    visible: page.plan.requiresTrust === true
                    text: I18n.tr("I trust this unsigned local development file.")
                    contentItem: BodyText { leftPadding: 28; text: localTrust.text; color: page.colors.primaryText }
                }
            }
        }
        footer: DialogButtonBox {
            Button { text: I18n.tr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                objectName: "pluginConfirmInstall"
                text: page.plan.previousVersion ? I18n.tr("Update plugin") : I18n.tr("Install plugin")
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                enabled: page.canAct && !!page.plan.id && (!page.plan.requiresTrust || localTrust.checked)
                onClicked: page.store.confirmInstall(page.selectedPermissions, localTrust.checked)
            }
            onRejected: planDialog.close()
        }
    }

    PluginDialog {
        id: permissionDialog
        objectName: "pluginPermissionsDialog"
        title: I18n.tr("Allowed permissions")
        height: Math.min(380, parent ? parent.height - 32 : 380)
        contentItem: ColumnLayout {
            BodyText { text: I18n.tr("Only the selected permissions will be granted. Changes apply to all widgets from this plugin.") }
            Repeater {
                model: page.selected.permissions || []
                delegate: Basic.CheckBox {
                    required property string modelData
                    Layout.fillWidth: true
                    checked: page.permissionDraft.indexOf(modelData) >= 0
                    text: page.permissionLabel(modelData)
                    contentItem: BodyText { leftPadding: 28; text: parent.text; color: page.colors.primaryText }
                    onToggled: page.permissionDraft = page.togglePermission(page.permissionDraft, modelData, checked)
                }
            }
            BodyText { visible: (page.selected.permissions || []).length === 0; text: I18n.tr("This plugin requests no permissions.") }
            Item { Layout.fillHeight: true }
        }
        footer: DialogButtonBox {
            Button { text: I18n.tr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: I18n.tr("Apply")
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                enabled: page.canAct && page.selected.installed === true
                onClicked: { page.store.setPermissions(page.selected.id, page.permissionDraft); permissionDialog.close() }
            }
            onRejected: permissionDialog.close()
        }
    }

    PluginDialog {
        id: uninstallDialog
        objectName: "pluginUninstallDialog"
        title: I18n.tr("Uninstall %1?").arg(page.selected.name || "")
        height: Math.min(380, parent ? parent.height - 32 : 380)
        contentItem: ColumnLayout {
            BodyText { text: I18n.tr("Uninstalling removes this plugin and its desktop widgets. Keep widget settings to restore them on a compatible reinstall, or delete them permanently below. Application data is not affected.") }
            Basic.CheckBox {
                id: removeData
                objectName: "pluginRemoveData"
                Layout.fillWidth: true
                text: I18n.tr("Also delete saved widget settings")
                contentItem: BodyText { leftPadding: 28; text: removeData.text; color: page.colors.primaryText }
            }
            Item { Layout.fillHeight: true }
        }
        footer: DialogButtonBox {
            Button { text: I18n.tr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole }
            Button {
                text: I18n.tr("Uninstall")
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                enabled: page.canAct && page.selected.installed === true
                onClicked: {
                    page.store.uninstall(page.selected.id, removeData.checked)
                    uninstallDialog.close()
                    detailsDialog.close()
                }
            }
            onRejected: uninstallDialog.close()
        }
    }
}
