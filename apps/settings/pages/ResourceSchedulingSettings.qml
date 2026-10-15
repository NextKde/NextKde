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
    spacing: 8
    required property var colors
    property var bridge: null
    property var snapshot: ({})
    property var memStatus: ({})
    property var runningApps: []
    signal refreshRequested()
    function gb(kb) { return (kb / 1048576).toFixed(1) + " GB" }
    function appNameFor(cls) {
        for (let i = 0; i < runningApps.length; ++i)
            if (runningApps[i].appId === cls) return runningApps[i].name
        return cls
    }

    Rectangle {
        visible: section.snapshot.resourceSchedulingAvailable === true
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: freezeRow.implicitHeight + 32

        RowLayout {
            id: freezeRow
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: I18n.tr("Freeze minimized windows")
                    color: colors.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Suspends the whole tree after 3 minutes in the sidebar (saves CPU; restore may occasionally glitch).")
                        + I18n.tr("Off by default: the background is only resource-limited; processes are never frozen.")
                    color: colors.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            LiquidControls.LiquidGlassSwitch {
                Layout.alignment: Qt.AlignVCenter
                accentColor: colors.accent
                checked: section.snapshot.freezeEnabled === true
                onToggled: function(checked) {
                    section.bridge.fgSchedSetFreeze(checked)
                }
            }
        }
    }

    Rectangle {
        visible: section.snapshot.resourceSchedulingAvailable === true
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: reclaimColumn.implicitHeight + 32

        ColumnLayout {
            id: reclaimColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: I18n.tr("Background memory saving")
                color: colors.primaryText
                font { pixelSize: 14; weight: Font.Medium }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // 三档选择：关 / 标准 / 激进 / 极限
                Repeater {
                    model: [
                        { id: "off", label: I18n.tr("Off"),
                          detail: I18n.tr("Leave background memory alone") },
                        { id: "once", label: I18n.tr("Standard"),
                          detail: I18n.tr("Compresses once after 60 seconds in the background (cold pages squeezed into zram; switching back is slightly slower)") },
                        { id: "aggressive", label: I18n.tr("Aggressive compression"),
                          detail: I18n.tr("Compresses continuously in the background (recompressed every 5 minutes), minimizing memory use") },
                        { id: "kill", label: I18n.tr("Extreme"),
                          detail: I18n.tr("Compresses continuously, then kills the app after 10 minutes in the background — memory goes to zero. Unsaved work is lost (browsers can restore sessions); add apps you want spared to the list below") }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: reclaimLabel.implicitHeight
                            + reclaimDetail.implicitHeight + 22
                        radius: 10
                        property bool isActive: section.snapshot.reclaimMode === modelData.id
                        color: isActive
                            ? colors.selectedContainer
                            : (reclaimMouse.containsMouse
                                ? colors.searchField : colors.sidebar)
                        border.width: isActive ? 2 : 0
                        border.color: colors.accent

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2

                            Text {
                                id: reclaimLabel
                                text: modelData.label
                                color: parent.parent.isActive
                                    ? colors.selectedForeground : colors.primaryText
                                font { pixelSize: 13; weight: Font.DemiBold }
                            }
                            Text {
                                id: reclaimDetail
                                Layout.fillWidth: true
                                text: modelData.detail
                                color: colors.secondaryText
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }
                        }

                        MouseArea {
                            id: reclaimMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: section.bridge.fgSchedSetReclaim(modelData.id)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: section.snapshot.resourceSchedulingAvailable === true
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: memColumn.implicitHeight + 32

        ColumnLayout {
            id: memColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: I18n.tr("Memory state")
                    color: colors.primaryText
                    font { pixelSize: 14; weight: Font.Medium }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: I18n.tr("Refresh")
                    color: fgSchedMemMouse.containsMouse
                        ? colors.accent : colors.secondaryText
                    font.pixelSize: 12

                    MouseArea {
                        id: fgSchedMemMouse
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: section.bridge.fgSchedMemStatus()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: {
                    const st = section.memStatus
                    if (st.memAvailableKb === undefined)
                        return I18n.tr("Reading…")
                    return I18n.tr("Available memory ") + section.gb(st.memAvailableKb)
                        + " / " + section.gb(st.memTotalKb)
                }
                color: colors.primaryText
                font.pixelSize: 13
            }
            Text {
                Layout.fillWidth: true
                text: {
                    const st = section.memStatus
                    if (st.zramOrigKb === undefined)
                        return I18n.tr("zram compression pool is not readable")
                    const ratio = st.zramComprKb > 0
                        ? (st.zramOrigKb / st.zramComprKb).toFixed(1) : "—"
                    return I18n.tr("Compression pool (zram): compressed ") + section.gb(st.zramComprKb)
                        + I18n.tr(" (originally ") + section.gb(st.zramOrigKb)
                        + I18n.tr(", compression ratio ") + ratio + ":1）"
                }
                color: colors.secondaryText
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                text: section.snapshot.reclaimMode === "kill"
                    ? I18n.tr("Extreme mode: background apps are compressed continuously, then killed after 10 minutes")
                      + I18n.tr(" (memory zeroed). Data safety relies on the app's own session restore; ")
                      + I18n.tr("Apps outside the exemption list are always killed — if it has unsaved work, add it to the ")
                      + I18n.tr("list below.")
                    : I18n.tr("Aggressive mode squeezes background apps' memory pages into the pool repeatedly: usage drops sharply, ")
                      + I18n.tr("The cost is a brief stall when switching back (pages are swapped in from the compression pool).")
                color: section.snapshot.reclaimMode === "kill" ? "#ff9f0a" : colors.tertiaryText
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    Rectangle {
        visible: section.snapshot.resourceSchedulingAvailable === true
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: listColumn.implicitHeight + 32

        ColumnLayout {
            id: listColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: I18n.tr("Full-resource background list")
                color: colors.primaryText
                font { pixelSize: 14; weight: Font.Medium }
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Apps on the list keep full priority and cores in the background (for resident services, ")
                      + I18n.tr("for idle downloads or background agents). Fill in app class names")
                      + I18n.tr(" (e.g. org.kde.konsole), or pick from the apps seen below.")
                color: colors.secondaryText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // 名单行
            Repeater {
                model: section.snapshot.fullResources || []

                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        Layout.alignment: Qt.AlignVCenter
                        color: colors.accent
                    }
                    Text {
                        Layout.fillWidth: true
                        text: appNameFor(modelData)
                        color: colors.primaryText
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    Text {
                        text: modelData
                        color: colors.tertiaryText
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: 130
                    }
                    Text {
                        text: I18n.tr("Remove")
                        color: "#ff453a"
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: section.bridge.fgSchedRemoveFull(parent.parent.modelData)
                        }
                    }
                }
            }

            Text {
                visible: (section.snapshot.fullResources || []).length === 0
                text: I18n.tr("List is empty: every app gets resource-limited in the background")
                color: colors.tertiaryText
                font.pixelSize: 12
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: colors.separator
            }

            // 从当前运行的应用添加
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ComboBox {
                    id: knownAppsBox
                    Layout.fillWidth: true
                    model: section.runningApps
                    textRole: "name"
                    valueRole: "appId"
                    enabled: count > 0
                    displayText: count > 0
                        ? currentText : I18n.tr("Tap refresh on the right to scan currently running apps")
                    font.pixelSize: 12
                }

                Button {
                    text: section.runningApps.length > 0 ? I18n.tr("Add") : I18n.tr("Refresh")
                    enabled: section.runningApps.length === 0
                        || (knownAppsBox.count > 0
                            && knownAppsBox.currentValue !== undefined
                            && knownAppsBox.currentValue.length > 0)
                    onClicked: {
                        if (section.runningApps.length === 0) {
                            section.refreshRequested()
                        } else if (knownAppsBox.currentValue) {
                            section.bridge.fgSchedAddFull(
                                        knownAppsBox.currentValue)
                        }
                    }
                }
            }

            // 手动输入
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: manualInput
                    Layout.fillWidth: true
                    placeholderText: I18n.tr("Type a class name manually, e.g. org.kde.konsole")
                    font.pixelSize: 12
                    onAccepted: {
                        if (text.trim().length > 0) {
                            section.bridge.fgSchedAddFull(text)
                            text = ""
                        }
                    }
                }

                Button {
                    text: I18n.tr("Add")
                    enabled: manualInput.text.trim().length > 0
                    onClicked: {
                        section.bridge.fgSchedAddFull(manualInput.text)
                        manualInput.text = ""
                    }
                }
            }
        }
    }
}
