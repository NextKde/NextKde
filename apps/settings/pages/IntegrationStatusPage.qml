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
    id: integrationPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property var snapshot: ({})
    property string errorText: ""
    property bool inputMethodExpanded: false
    readonly property var candidatePreferences: snapshot.inputMethodPresentation || ({})
    readonly property bool candidatePreferencesReady: bridge !== null && candidatePreferences.ready === true

    function setCandidatePreference(key, value) {
        if (!candidatePreferencesReady) return
        const patch = ({})
        patch[key] = value
        bridge.setInputMethodPresentation(patch)
    }

    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        // The reply lands on integrationSnapshotChanged; the bridge does
        // its D-Bus and /proc probes off the UI thread now, so this page's
        // 5s poll no longer freezes anything.
        bridge.integrationSnapshot();
    }

    function setInputMethodEnabled(checked) {
        if (!bridge) return;
        bridge.setInputMethodEnabled(checked);
    }

    Connections {
        target: integrationPage.bridge
        enabled: integrationPage.bridge !== null
        function onIntegrationSnapshotChanged(state) {
            integrationPage.snapshot = state;
            integrationPage.errorText = I18n.tr(integrationPage.bridge.lastError) || "";
        }
    }

    function notificationState() {
        const provider = snapshot.notificationProvider || "none";
        if (provider === "kos")
            return {
                label: I18n.tr("KOS has taken over"),
                color: "#30d158",
                detail: I18n.tr("Notifications will appear in the KOS notification center")
            };
        if (provider === "plasma")
            return {
                label: I18n.tr("Plasma takeover"),
                color: "#ff9f0a",
                detail: I18n.tr("KOS is waiting for the org.freedesktop.Notifications name")
            };
        if (provider === "other")
            return {
                label: I18n.tr("Another program has taken over"),
                color: "#ff9f0a",
                detail: snapshot.notificationCommand || snapshot.notificationOwner || I18n.tr("Unknown notification service")
            };
        return {
            label: I18n.tr("Not registered"),
            color: "#ff453a",
            detail: I18n.tr("No desktop notification service available")
        };
    }

    function statusRow(icon, tint, title, ready, readyLabel, detail) {
        return {
            icon: icon,
            tint: tint,
            title: title,
            label: ready ? readyLabel : I18n.tr("Not connected"),
            color: ready ? "#30d158" : "#ff453a",
            detail: detail
        };
    }

    readonly property var notification: notificationState()
    readonly property var rows: [statusRow("K", "#0a84ff", "KOS Shell", !!snapshot.shellReady, I18n.tr("Running"), I18n.tr("Settings page and Quickshell IPC channel")), statusRow("↔", "#5ac8fa", I18n.tr("Platform bridge"), !!snapshot.platformConnected, I18n.tr("Connected"), I18n.tr("Windows, network, audio and system actions")), statusRow("D", "#34c759", I18n.tr("Data service"), !!snapshot.dataConnected, I18n.tr("Connected"), I18n.tr("System metrics, activity records and desktop files")), statusRow("▦", "#af52de", I18n.tr("Desktop widgets"), !!snapshot.desktopWidgetsVisible, I18n.tr("Shown"), snapshot.desktopFilesReady ? I18n.tr("Clock, weather, resource cards and desktop files are ready") : I18n.tr("Widget layer shown; desktop files still syncing")),
        {
            icon: "N",
            tint: "#ff9500",
            title: I18n.tr("Notification takeover"),
            label: notification.label,
            color: notification.color,
            detail: notification.detail
        },
        statusRow("G", "#64d2ff", I18n.tr("Glass effects"), !!snapshot.glassLoaded, I18n.tr("Loaded"), I18n.tr("KWin blur and liquid glass effects")), statusRow("A", "#ff375f", I18n.tr("Dock window animation"), !!snapshot.dockAnimationLoaded, I18n.tr("Loaded"), I18n.tr("KWin Dock opening / scaling animation")), statusRow("I", "#bf5af2", I18n.tr("Desktop input bridge"), !!snapshot.contextMenuInputLoaded, I18n.tr("Loaded"), I18n.tr("Global clicks and menu dismiss events"))]

    Demo.SettingsGroup {
        title: I18n.tr("System Services & Bridges")
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: snapshot.updatedAt ? I18n.tr("Last checked ") + snapshot.updatedAt : I18n.tr("Reading live state…")
            Demo.LiquidActionButton {
                text: I18n.tr("Refresh")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: integrationPage.refresh()
            }
        }
        Repeater {
            model: integrationPage.rows
            delegate: Demo.SettingsItem {
                required property var modelData
                title: modelData.title
                description: modelData.detail
                Text {
                    text: modelData.label
                    color: modelData.color
                    font.pixelSize: 11
                }
            }
        }
    }

    Demo.SettingsGroup {
        title: I18n.tr("Application Compatibility & Troubleshooting")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Enable NextKde Input Method Popups")
            description: integrationPage.snapshot.inputMethodError
                ? I18n.tr("Input method activation failed") + ": " + integrationPage.snapshot.inputMethodError
                : integrationPage.snapshot.inputMethodChanging ? I18n.tr("Reloading input method…")
                : integrationPage.snapshot.inputMethodActive ? I18n.tr("Enabled")
                : I18n.tr("Render candidates and tips with liquid glass. When disabled, Fcitx5 native candidate windows are preserved.")

            Controls.SettingsSwitch {
                objectName: "inputMethodTakeoverSwitch"
                checked: !!integrationPage.snapshot.inputMethodEnabled
                enabled: !integrationPage.snapshot.inputMethodChanging
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function(checked) {
                    integrationPage.setInputMethodEnabled(checked);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Candidate Styling & App Compatibility")
            description: I18n.tr("NextKde renders liquid glass popups via Wayland text-input-v3. Expand to view per-app adaptation flags and environment settings.")
            Demo.LiquidActionButton {
                text: integrationPage.inputMethodExpanded ? I18n.tr("Hide Solutions ▴") : I18n.tr("App Solutions ▾")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: integrationPage.inputMethodExpanded = !integrationPage.inputMethodExpanded
            }
            Demo.LiquidActionButton {
                text: I18n.tr("View Guide")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: Qt.openUrlExternally("https://github.com/NextKde/NextKde/blob/main/docs/InputMethodIntegration"
                    + (I18n.language === "zh-CN" ? ".zh-CN.md" : ".md"))
            }
        }

        Demo.SettingsItem {
            visible: integrationPage.inputMethodExpanded
            title: "↳ " + I18n.tr("Chromium & Electron (Chrome, VS Code)")
            description: I18n.tr("Add startup flags: --enable-wayland-ime --wayland-text-input-version=3")
        }

        Demo.SettingsItem {
            visible: integrationPage.inputMethodExpanded
            title: "↳ " + I18n.tr("Bundled Qt Applications (WeChat RPM, WPS)")
            description: I18n.tr("Launch with environment variable: QT_IM_MODULE=text-input-unstable-v3")
        }

        Demo.SettingsItem {
            visible: integrationPage.inputMethodExpanded
            title: "↳ " + I18n.tr("Firefox & Native Desktop Apps")
            description: I18n.tr("Leave GTK_IM_MODULE and QT_IM_MODULE empty to enable compositor takeover.")
        }
    }
    Demo.SettingsGroup {
        title: I18n.tr("Candidate appearance")
        backgroundColor: colors.card
        Demo.SettingsItem {
            description: I18n.tr("Applies to NextKde candidate popups only. Your Fcitx configuration stays unchanged.")
        }
        Demo.SettingsItem {
            title: I18n.tr("Candidate material")
            description: I18n.tr("Choose liquid glass or a soft frosted blur for candidate popups.")
            Controls.SettingsSelect {
                objectName: "candidateMaterialSelect"
                colors: integrationPage.colors
                disabled: !integrationPage.candidatePreferencesReady
                textRole: "label"
                model: [
                    {value: "liquid", label: I18n.tr("Liquid glass")},
                    {value: "frosted", label: I18n.tr("Frosted glass")}
                ]
                currentIndex: Math.max(0, ["liquid", "frosted"].indexOf(integrationPage.candidatePreferences.material))
                onSelectionChanged: index => integrationPage.setCandidatePreference("material", model[index].value)
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Candidate font size")
            Controls.SettingsSelect {
                objectName: "candidateFontSizeSelect"
                colors: integrationPage.colors
                disabled: !integrationPage.candidatePreferencesReady
                textRole: "label"
                model: Array.from({length: 13}, (_, index) => ({size: index + 12, label: String(index + 12)}))
                currentIndex: (integrationPage.candidatePreferences.fontSize || 15) - 12
                onSelectionChanged: index => integrationPage.setCandidatePreference("fontSize", index + 12)
            }
        }
        Demo.SettingsItem {
            title: I18n.tr("Candidate layout")
            Controls.SettingsSelect {
                objectName: "candidateLayoutSelect"
                colors: integrationPage.colors
                disabled: !integrationPage.candidatePreferencesReady
                textRole: "label"
                model: [
                    {value: "engine", label: I18n.tr("Follow input method")},
                    {value: "adaptive", label: I18n.tr("Automatic layout")},
                    {value: "horizontal", label: I18n.tr("Horizontal")},
                    {value: "vertical", label: I18n.tr("Vertical")}
                ]
                currentIndex: Math.max(0, ["engine", "adaptive", "horizontal", "vertical"].indexOf(integrationPage.candidatePreferences.layout))
                onSelectionChanged: index => integrationPage.setCandidatePreference("layout", model[index].value)
            }
        }
        Repeater {
            model: [
                {key: "showAnnotations", title: I18n.tr("Show candidate annotations"), detail: I18n.tr("Show readings and auxiliary codes supplied by the input method.")},
                {key: "highContrast", title: I18n.tr("High contrast candidates"), detail: I18n.tr("Use an opaque background and stronger selection contrast.")},
                {key: "reduceMotion", title: I18n.tr("Reduce candidate motion"), detail: I18n.tr("Show candidates without scaling or size transitions.")}
            ]
            delegate: Demo.SettingsItem {
                required property var modelData
                title: modelData.title
                description: modelData.detail
                Controls.SettingsSwitch {
                    objectName: "candidate-" + modelData.key + "-switch"
                    checked: integrationPage.candidatePreferences[modelData.key] === true
                    enabled: integrationPage.candidatePreferencesReady
                    accentColor: integrationPage.colors.accent
                    trackColor: integrationPage.colors.divider
                    Accessible.name: modelData.title
                    onToggled: checked => integrationPage.setCandidatePreference(modelData.key, checked)
                }
            }
        }
        Demo.SettingsItem {
            visible: !!integrationPage.candidatePreferences.saveError
            description: I18n.tr(integrationPage.candidatePreferences.saveError || "")
        }
    }
    Text {
        Layout.fillWidth: true
        visible: errorText.length > 0
        text: errorText
        color: "#ff453a"
        font.pixelSize: 10
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
