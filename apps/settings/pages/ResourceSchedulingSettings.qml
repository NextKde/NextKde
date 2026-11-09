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
    id: section
    Layout.fillWidth: true
    spacing: 12
    required property var colors
    property var bridge: null
    property var snapshot: ({})
    property var memStatus: ({})
    property var runningApps: []
    signal refreshRequested
    function gb(kb) {
        return (kb / 1048576).toFixed(1) + " GB";
    }
    function appNameFor(cls) {
        for (let i = 0; i < runningApps.length; ++i)
            if (runningApps[i].appId === cls)
                return runningApps[i].name;
        return cls;
    }

    visible: snapshot.resourceSchedulingAvailable === true
    Demo.SettingsGroup {
        visible: section.snapshot.resourceSchedulingAvailable === true
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: I18n.tr("Freeze minimized windows")
            description: I18n.tr("Suspends the whole tree after 3 minutes in the sidebar (saves CPU; restore may occasionally glitch).") + I18n.tr("Off by default: the background is only resource-limited; processes are never frozen.")
            Controls.SettingsSwitch {
                accentColor: colors.accent
                checked: section.snapshot.freezeEnabled === true
                onToggled: function (checked) {
                    section.bridge.fgSchedSetFreeze(checked);
                }
            }
        }
    }
    Demo.SettingsGroup {
        visible: section.snapshot.resourceSchedulingAvailable === true
        title: I18n.tr("Background memory saving")
        backgroundColor: colors.card
        Repeater {
            model: [
                {
                    id: "off",
                    label: I18n.tr("Off"),
                    detail: I18n.tr("Leave background memory alone")
                },
                {
                    id: "once",
                    label: I18n.tr("Standard"),
                    detail: I18n.tr("Compresses once after 60 seconds in the background (cold pages squeezed into zram; switching back is slightly slower)")
                },
                {
                    id: "aggressive",
                    label: I18n.tr("Aggressive compression"),
                    detail: I18n.tr("Compresses continuously in the background (recompressed every 5 minutes), minimizing memory use")
                },
                {
                    id: "kill",
                    label: I18n.tr("Extreme"),
                    detail: I18n.tr("Compresses continuously, then kills the app after 10 minutes in the background — memory goes to zero. Unsaved work is lost (browsers can restore sessions); add apps you want spared to the list below")
                }
            ]
            delegate: Demo.SettingsItem {
                id: reclaimRow
                required property var modelData
                readonly property bool selected: section.snapshot.reclaimMode === modelData.id
                title: modelData.label
                description: modelData.detail
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                Accessible.onPressAction: section.bridge.fgSchedSetReclaim(modelData.id)
                Text {
                    text: reclaimRow.selected ? "✓" : ""
                    color: colors.accent
                    font.pixelSize: 16
                }
                property Item activationArea: MouseArea {
                    parent: reclaimRow
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: section.bridge.fgSchedSetReclaim(reclaimRow.modelData.id)
                }
            }
        }
    }
    Demo.SettingsGroup {
        visible: section.snapshot.resourceSchedulingAvailable === true
        title: I18n.tr("Memory state")
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: {
                const st = section.memStatus;
                if (st.memAvailableKb === undefined)
                    return I18n.tr("Reading…");
                return I18n.tr("Available memory ") + section.gb(st.memAvailableKb) + " / " + section.gb(st.memTotalKb);
            }
            description: {
                const st = section.memStatus;
                if (st.zramOrigKb === undefined)
                    return I18n.tr("zram compression pool is not readable");
                const ratio = st.zramComprKb > 0 ? (st.zramOrigKb / st.zramComprKb).toFixed(1) : "—";
                return I18n.tr("Compression pool (zram): compressed ") + section.gb(st.zramComprKb) + I18n.tr(" (originally ") + section.gb(st.zramOrigKb) + I18n.tr(", compression ratio ") + ratio + ":1）";
            }
            Demo.LiquidActionButton {
                text: I18n.tr("Refresh")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                onClicked: section.bridge.fgSchedMemStatus()
            }
        }
        Demo.SettingsItem {
            description: section.snapshot.reclaimMode === "kill" ? I18n.tr("Extreme mode: background apps are compressed continuously, then killed after 10 minutes") + I18n.tr(" (memory zeroed). Data safety relies on the app's own session restore; ") + I18n.tr("Apps outside the exemption list are always killed — if it has unsaved work, add it to the ") + I18n.tr("list below.") : I18n.tr("Aggressive mode squeezes background apps' memory pages into the pool repeatedly: usage drops sharply, ") + I18n.tr("The cost is a brief stall when switching back (pages are swapped in from the compression pool).")
        }
    }
    Demo.SettingsGroup {
        visible: section.snapshot.resourceSchedulingAvailable === true
        title: I18n.tr("Full-resource background list")
        backgroundColor: colors.card
        Demo.SettingsItem {
            description: I18n.tr("Apps on the list keep full priority and cores in the background (for resident services, ") + I18n.tr("for idle downloads or background agents). Fill in app class names") + I18n.tr(" (e.g. org.kde.konsole), or pick from the apps seen below.")
        }
        Repeater {
            model: section.snapshot.fullResources || []
            delegate: Demo.SettingsItem {
                id: appRow
                required property string modelData
                title: section.appNameFor(modelData)
                description: modelData
                Demo.LiquidActionButton {
                    text: I18n.tr("Remove")
                    materialForm: true
                    implicitHeight: 24
                    cornerRadius: 6
                    onClicked: section.bridge.fgSchedRemoveFull(appRow.modelData)
                }
            }
        }
        Demo.SettingsItem {
            visible: (section.snapshot.fullResources || []).length === 0
            description: I18n.tr("List is empty: every app gets resource-limited in the background")
        }
        Demo.SettingsItem {
            description: section.runningApps.length === 0 ? I18n.tr("Tap refresh on the right to scan currently running apps") : ""
            Controls.SettingsSelect {
                id: knownAppsBox
                colors: section.colors
                implicitWidth: 180
                implicitHeight: 24
                Layout.minimumWidth: 80
                Layout.preferredWidth: 180
                model: section.runningApps
                textRole: "name"
                enabled: model.length > 0
                property int selectedIndex: 0
                currentIndex: selectedIndex
                onActivated: function (index) {
                    selectedIndex = index;
                }
            }
            Demo.LiquidActionButton {
                text: section.runningApps.length > 0 ? I18n.tr("Add") : I18n.tr("Refresh")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                enabled: section.runningApps.length === 0 || !!section.runningApps[knownAppsBox.currentIndex]?.appId
                onClicked: {
                    if (section.runningApps.length === 0)
                        section.refreshRequested();
                    else {
                        const app = section.runningApps[knownAppsBox.currentIndex];
                        if (app && app.appId)
                            section.bridge.fgSchedAddFull(app.appId);
                    }
                }
            }
        }
        Demo.SettingsItem {
            Demo.LiquidTextField {
                id: manualInput
                implicitWidth: 180
                implicitHeight: 24
                Layout.minimumWidth: 80
                Layout.preferredWidth: 180
                placeholderText: I18n.tr("Type a class name manually, e.g. org.kde.konsole")
                onAccepted: {
                    if (text.trim().length > 0) {
                        section.bridge.fgSchedAddFull(text);
                        text = "";
                    }
                }
            }
            Demo.LiquidActionButton {
                text: I18n.tr("Add")
                materialForm: true
                implicitHeight: 24
                cornerRadius: 6
                enabled: manualInput.text.trim().length > 0
                onClicked: {
                    section.bridge.fgSchedAddFull(manualInput.text);
                    manualInput.text = "";
                }
            }
        }
    }
}
