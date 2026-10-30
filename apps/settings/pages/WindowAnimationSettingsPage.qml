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
    readonly property var snapshot: backend ? backend.state : ({})
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
    Component.onCompleted: {
        if (backend)
            backend.refresh();
    }

    Demo.SettingsGroup {
        id: windowRows
        title: I18n.tr("Window appearance")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("KOS window appearance")

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
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: I18n.tr("Turning off KOS window appearance restores the original decorator. Radius and shadow apply immediately; decorator switches take effect on next login.")
        color: colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
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
                currentIndex: ["none", "scale", "genie"].indexOf(windowPage.snapshot.hideAnimation ?? "scale")
                onSelectionChanged: function (index) {
                    windowPage.backend.setAnimation("hide", model[index].id);
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
                currentIndex: ["none", "fade", "scale"].indexOf(windowPage.snapshot.closeAnimation ?? "scale")
                onSelectionChanged: function (index) {
                    windowPage.backend.setAnimation("close", model[index].id);
                }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: (windowPage.snapshot.nativeGenieFallback ?? "").length > 0
        text: I18n.tr(windowPage.snapshot.nativeGenieFallback ?? "")
        color: colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        text: I18n.tr("Genie uses KWin Magic Lamp and follows the Dock icon, with Scale as a fallback. None restores your previous KWin minimize effects.")
        color: colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 13
        Layout.rightMargin: 13
        visible: (windowPage.snapshot.nativeGenieFallback ?? "").length > 0
        text: I18n.tr("Magic Lamp comes with standard KDE Plasma installations and is enabled by this setting. If it is missing, repair the KWin package using your distribution’s software manager. In KDE System Settings → Desktop Effects, search for Magic Lamp to configure it.")
        color: colors.secondaryText
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Demo.LiquidActionButton {
        Layout.leftMargin: 13
        visible: (windowPage.snapshot.nativeGenieFallback ?? "").length > 0
        text: I18n.tr("Open KDE System Settings")
        enabled: typeof settingsBridge !== "undefined"
            && typeof settingsBridge.launchSystemSettings === "function"
        onClicked: settingsBridge.launchSystemSettings()
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
