import Kos.Demo as Demo
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    id: windowPage
    required property var colors
    property bool materialForm: false
    objectName: "windowAppearancePage"
    spacing: 12
    property var backend: null
    property var bridge: null
    property var runningApps: []
    property var appIcons: ({})
    function appIcon(appId) {
        if (Object.prototype.hasOwnProperty.call(appIcons, appId))
            return appIcons[appId];
        const source = bridge && typeof bridge.applicationIcon === "function" ? bridge.applicationIcon(appId) : "";
        appIcons[appId] = source;
        return source;
    }
    readonly property var snapshot: backend ? backend.state : ({})
    readonly property var availableRunningApps: {
        const excluded = snapshot.buttonExclusions ?? [];
        const apps = [];
        for (const app of runningApps) {
            if (app.appId && excluded.indexOf(app.appId) < 0)
                apps.push({appId: app.appId, label: app.name && app.name !== app.appId ? app.name + " · " + app.appId : app.appId});
        }
        return apps;
    }
    readonly property var radiusStops: [0, 8, 12, 20, 28, 36]
    readonly property var radiusLabels: [I18n.tr("Square corner"), I18n.tr("Slight round"), I18n.tr("Small"), I18n.tr("Standard"), I18n.tr("Large"), I18n.tr("Larger")]
    property int previewRadius: -1
    readonly property int radiusIndex: {
        let best = 0;
        for (let i = 1; i < radiusStops.length; ++i)
            if (Math.abs(radiusStops[i] - Number(snapshot.radius ?? 20)) < Math.abs(radiusStops[best] - Number(snapshot.radius ?? 20)))
                best = i;
        return best;
    }
    function addManualExclusion() {
        if (!backend || manualExclusionInput.text.trim().length === 0)
            return;
        if (backend.setButtonExclusion(manualExclusionInput.text, true))
            manualExclusionInput.text = "";
    }
    Connections {
        target: windowPage.bridge
        enabled: windowPage.bridge !== null
        function onFgSchedRunningAppsChanged(apps) {
            windowPage.runningApps = apps || [];
        }
    }
    Component.onCompleted: {
        if (backend)
            backend.refresh();
        if (bridge)
            bridge.fgSchedRunningApps();
    }

    Demo.SettingsGroup {
        id: windowRows
        title: I18n.tr("Window appearance")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("KOS window appearance")
            separator: false
            verticalPadding: 4
            description: I18n.tr("Radius and shadow apply now; turning KOS off restores the original decorator on next login.")

            Controls.SettingsSwitch {
                enabled: windowPage.backend !== null
                objectName: "windowTakeoverSwitch"
                checked: windowPage.snapshot.enabled !== false
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    windowPage.backend.setTakeover(checked);
                }
            }
        }

        Demo.SettingsItem {
            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
            title: I18n.tr("Corner radius")

            Text {
                text: windowPage.radiusLabels[windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex] + " · " + (windowPage.previewRadius >= 0 ? windowPage.radiusStops[windowPage.previewRadius] : Number(windowPage.snapshot.radius ?? 20)) + " px"
                color: colors.secondaryText
                font.pixelSize: 12
            }
            Controls.SettingsSlider {
                objectName: "windowRadiusSlider"
                enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                accentColor: colors.accent
                trackColor: colors.divider
                wheelStep: 0.2
                value: (windowPage.previewRadius >= 0 ? windowPage.previewRadius : windowPage.radiusIndex) / 5
                onPreviewChanged: function (position) {
                    windowPage.previewRadius = Math.round(position * 5);
                }
                onCanceled: windowPage.previewRadius = -1
                onCommitRequested: function (position) {
                    windowPage.backend.setRadius(windowPage.radiusStops[Math.round(position * 5)]);
                    windowPage.previewRadius = -1;
                }
            }
        }

        Demo.SettingsItem {
            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
            title: I18n.tr("Square corners when maximized")
            separator: false
            verticalPadding: 4
            description: I18n.tr("Fullscreen uses square corners; restoring brings back the radius.")

            Controls.SettingsSwitch {
                objectName: "windowSquareMaximizedSwitch"
                enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                checked: windowPage.snapshot.squareMaximized === true
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    windowPage.backend.setSquareMaximized(checked);
                }
            }
        }

        Demo.SettingsItem {
            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
            title: I18n.tr("Window shadow")

            Controls.SettingsSwitch {
                objectName: "windowShadowSwitch"
                checked: windowPage.snapshot.shadow !== false
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    windowPage.backend.setShadow(checked);
                }
            }
        }
    }
    Demo.SettingsGroup {
        id: windowButtonRows
        objectName: "windowButtonsGroup"
        title: I18n.tr("Window buttons")
        backgroundColor: colors.card

        Controls.WindowButtonPreview {
            objectName: "windowButtonsPreview"
            colors: windowPage.colors
            materialForm: windowPage.materialForm
        }

        Demo.SettingsItem {
            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
            title: I18n.tr("Window button icons")

            Controls.SettingsNavBar {
                colors: windowPage.colors
                materialForm: windowPage.materialForm
                objectName: "windowButtonGlyphMode"
                disabled: windowPage.backend === null || windowPage.snapshot.enabled === false
                model: [
                    {
                        id: "always",
                        label: I18n.tr("Always show")
                    },
                    {
                        id: "hover",
                        label: I18n.tr("macOS (on hover)")
                    }
                ]
                currentIndex: ["always", "hover"].indexOf(windowPage.snapshot.buttonGlyphMode ?? "always")
                onSelectionChanged: function (index) {
                    windowPage.backend.setButtonGlyphMode(model[index].id);
                }
            }
        }

        Demo.SettingsItem {
            enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
            title: I18n.tr("Resize button background separately")
            verticalPadding: 4
            description: I18n.tr("Right-click and drag the background edges; buttons stay fixed.")

            Controls.SettingsSwitch {
                objectName: "windowIndependentButtonBackground"
                enabled: windowPage.backend !== null && windowPage.snapshot.enabled !== false
                checked: windowPage.snapshot.independentButtonBackground === true
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    windowPage.backend.setIndependentButtonBackground(checked);
                }
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Hide KOS window buttons for selected apps")
            separator: false
            verticalPadding: 4
            description: I18n.tr("Hide KOS buttons for listed apps; keep their original buttons.")
        }
        Repeater {
            model: windowPage.snapshot.buttonExclusions ?? []
            delegate: Demo.SettingsItem {
                id: exclusionRow
                required property string modelData
                objectName: "windowButtonExclusionRow_" + modelData
                allowStacking: false
                minimumLabelWidth: 0
                controlSpacing: 0
                Accessible.name: modelData
                RowLayout {
                    implicitWidth: exclusionRow.availableWidth
                    Layout.fillWidth: true
                    spacing: 8
                    Controls.ApplicationIcon {
                        objectName: "windowButtonExclusionIcon_" + exclusionRow.modelData
                        source: windowPage.appIcon(exclusionRow.modelData)
                        fallbackColor: windowPage.colors.secondaryText
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: exclusionRow.modelData
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        color: windowPage.colors.primaryText
                        elide: Text.ElideRight
                    }
                    Controls.WindowButtonAction {
                        objectName: "removeWindowButtonExclusion"
                        text: I18n.tr("Remove")
                        iconName: "close"
                        enabled: windowPage.backend !== null
                        onClicked: windowPage.backend.setButtonExclusion(exclusionRow.modelData, false)
                    }
                }
            }
        }
        Demo.SettingsItem {
            separator: false
            verticalPadding: 4
            description: windowPage.availableRunningApps.length === 0 ? I18n.tr("No apps available. Refresh or enter an app class below.") : ""
            Controls.ApplicationIcon {
                objectName: "windowButtonSelectedAppIcon"
                source: windowPage.appIcon(windowPage.availableRunningApps[runningAppsBox.currentIndex]?.appId || "")
                fallbackColor: windowPage.colors.secondaryText
            }
            Controls.SettingsSelect {
                id: runningAppsBox
                objectName: "windowButtonRunningApps"
                colors: windowPage.colors
                materialForm: windowPage.materialForm
                implicitWidth: 180
                implicitHeight: 24
                Layout.minimumWidth: 80
                Layout.preferredWidth: 180
                model: windowPage.availableRunningApps
                textRole: "label"
                enabled: windowPage.bridge !== null && model.length > 0
                property string selectedAppId: ""
                currentIndex: Math.max(0, model.findIndex(app => app.appId === selectedAppId))
                onActivated: function (index) {
                    selectedAppId = model[index].appId;
                }
            }
            Controls.WindowButtonAction {
                objectName: "refreshWindowButtonRunningApps"
                text: I18n.tr("Refresh")
                iconName: "refreshRounded"
                enabled: windowPage.bridge !== null
                onClicked: {
                    windowPage.appIcons = ({});
                    windowPage.bridge.fgSchedRunningApps();
                }
            }
            Controls.WindowButtonAction {
                objectName: "addRunningWindowButtonExclusion"
                text: I18n.tr("Add")
                iconName: "plus"
                enabled: windowPage.backend !== null && !!windowPage.availableRunningApps[runningAppsBox.currentIndex]?.appId
                onClicked: {
                    const app = windowPage.availableRunningApps[runningAppsBox.currentIndex];
                    if (app && app.appId)
                        windowPage.backend.setButtonExclusion(app.appId, true);
                }
            }
        }
        Demo.SettingsItem {
            Demo.LiquidTextField {
                id: manualExclusionInput
                objectName: "windowButtonExclusionInput"
                implicitWidth: 180
                implicitHeight: 24
                Layout.minimumWidth: 80
                Layout.preferredWidth: 180
                placeholderText: I18n.tr("Application class, e.g. md.obsidian.Obsidian")
                onAccepted: windowPage.addManualExclusion()
            }
            Controls.WindowButtonAction {
                objectName: "addManualWindowButtonExclusion"
                text: I18n.tr("Add")
                iconName: "plus"
                enabled: windowPage.backend !== null && manualExclusionInput.text.trim().length > 0
                onClicked: windowPage.addManualExclusion()
            }
        }
    }

    Demo.SettingsGroup {
        id: animationRows
        title: I18n.tr("Window animations")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Hide and restore")

            Controls.SettingsSelect {
                textRole: "label"
                colors: windowPage.colors
                materialForm: windowPage.materialForm
                objectName: "windowHideAnimation"
                disabled: windowPage.backend === null
                model: [
                    {
                        id: "none",
                        label: I18n.tr("None")
                    },
                    {
                        id: "scale",
                        label: I18n.tr("Scale")
                    },
                    {
                        id: "genie",
                        label: I18n.tr("Genie")
                    }
                ]
                enabled: windowPage.backend && !windowPage.backend.animationBusy
                currentIndex: ["none", "scale", "genie"].indexOf(windowPage.snapshot.hideAnimation ?? "scale")
                onSelectionChanged: function (index) {
                    windowPage.backend.requestAnimation("hide", model[index].id);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Close window")

            Controls.SettingsSelect {
                textRole: "label"
                colors: windowPage.colors
                materialForm: windowPage.materialForm
                objectName: "windowCloseAnimation"
                disabled: windowPage.backend === null

                model: [
                    {
                        id: "none",
                        label: I18n.tr("None")
                    },
                    {
                        id: "fade",
                        label: I18n.tr("Fade out")
                    },
                    {
                        id: "scale",
                        label: I18n.tr("Shrink and fade")
                    }
                ]
                enabled: windowPage.backend && !windowPage.backend.animationBusy
                currentIndex: ["none", "fade", "scale"].indexOf(windowPage.snapshot.closeAnimation ?? "scale")
                onSelectionChanged: function (index) {
                    windowPage.backend.requestAnimation("close", model[index].id);
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: (windowPage.snapshot.nativeGenieFallback ?? "").length > 0
        text: I18n.tr("Temporarily using Scale. Your Genie preference is saved.")
        color: colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: !windowPage.backend || windowPage.backend.error.length > 0
        text: windowPage.backend ? I18n.tr(windowPage.backend.error) : I18n.tr("Window settings backend unavailable")
        color: "#ff453a"
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
}
