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
    id: dockPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property real dockHeight: 60
    property int dockPositionIndex: 0
    readonly property var dockPositions: ["bottom", "left", "right"]
    property int dockContentStyleIndex: 0
    readonly property var dockContentStyles: ["compact", "relaxed"]
    property int dockStyleIndex: 0
    readonly property var dockStyles: ["floating", "taskbar", "transparent"]
    // One percentage controls magnification and its proportional lift.
    // 100% disables both; the shell clamps the peak to 300%.
    property real dockHoverScalePct: 119
    readonly property real minHoverScalePct: 100
    readonly property real maxHoverScalePct: 300
    property int visibilityModeIndex: 0
    readonly property var visibilityModes: ["always", "smart", "persistent"]
    property int windowGroupingIndex: 0
    readonly property var windowGroupings: ["grouped", "separate"]
    property bool showLauncher: true
    property bool showTrash: true
    property bool showRevealIndicator: true
    property bool revealIndicatorUpdatePending: false
    property bool stateReady: false
    property bool builtinUpdatePending: false
    property string errorText: ""
    property bool layoutDirty: false
    property bool hoverScaleDirty: false

    function positionIndexFromString(position) {
        const idx = dockPositions.indexOf(position);
        return idx >= 0 ? idx : 0;
    }

    function dockContentStyleIndexFromString(style) {
        const idx = dockContentStyles.indexOf(style);
        return idx >= 0 ? idx : 0;
    }

    function dockStyleIndexFromString(style) {
        const idx = dockStyles.indexOf(style);
        return idx >= 0 ? idx : 0;
    }

    function visibilityModeIndexFromString(mode) {
        const idx = visibilityModes.indexOf(mode);
        return idx >= 0 ? idx : 0;
    }

    function windowGroupingIndexFromString(mode) {
        const idx = windowGroupings.indexOf(mode);
        return idx >= 0 ? idx : 0;
    }

    function applyState(state) {
        if (!state || state.baseHeight === undefined)
            return;
        // Do not overwrite a slider preview with an unrelated IPC reply.
        if (!layoutDirty && !dockHeightSlider._pressed)
            dockHeight = Number(state.baseHeight);
        dockPositionIndex = positionIndexFromString(state.position);
        dockContentStyleIndex = dockContentStyleIndexFromString(state.contentStyle);
        dockStyleIndex = dockStyleIndexFromString(state.dockStyle);
        // The snapshot always carries the effective values, so an untouched
        // profile opens on exactly what the Dock is drawing right now.
        const hoverScale = Number(state.hoverScale);
        if (!hoverScaleDirty && !hoverScaleSlider._pressed) {
            dockHoverScalePct = Number.isFinite(hoverScale) ? Math.max(minHoverScalePct, Math.min(maxHoverScalePct, Math.round(hoverScale * 100))) : 119;
        }
        visibilityModeIndex = visibilityModeIndexFromString(state.visibilityMode);
        windowGroupingIndex = windowGroupingIndexFromString(state.windowGrouping);
        showLauncher = state.showLauncher !== false;
        showTrash = state.showTrash !== false;
        showRevealIndicator = state.showRevealIndicator !== false;
        stateReady = true;
        errorText = "";
    }

    function savePosition(index) {
        if (!bridge)
            return;
        const position = dockPositions[index];
        bridge.updateDockPosition(position);
    }

    // Fire-and-forget: the shell answers with a full snapshot, which lands
    // on dockSnapshotChanged and is folded in by applyState there.
    function saveContentStyle(index) {
        if (!bridge)
            return;
        bridge.updateDockContentStyle(dockContentStyles[index]);
    }

    function saveDockStyle(index) {
        if (!bridge)
            return;
        bridge.updateDockStyle(dockStyles[index]);
    }

    // Hover magnification: preview while dragging, commit on release.
    function previewHoverScale(position) {
        const next = Math.round(minHoverScalePct + position * (maxHoverScalePct - minHoverScalePct));
        if (next === dockHoverScalePct)
            return;
        dockHoverScalePct = next;
        hoverScaleDirty = true;
    }

    function commitHoverScale() {
        if (!hoverScaleDirty)
            return;
        hoverScaleDirty = false;
        if (bridge)
            bridge.updateDockHoverScale(dockHoverScalePct / 100);
    }

    function saveVisibilityMode(index) {
        if (!bridge)
            return;
        const mode = visibilityModes[index];
        bridge.updateDockVisibilityMode(mode);
    }

    function saveWindowGrouping(index) {
        if (!bridge)
            return;
        const mode = windowGroupings[index];
        bridge.updateDockWindowGrouping(mode);
    }

    function saveRevealIndicatorVisibility(visible) {
        if (!bridge || !stateReady || revealIndicatorUpdatePending)
            return;
        revealIndicatorUpdatePending = true;
        bridge.updateDockRevealIndicatorVisibility(visible);
    }

    function saveBuiltinVisibility(id, visible) {
        if (!bridge || !stateReady || builtinUpdatePending)
            return;
        builtinUpdatePending = true;
        bridge.updateDockBuiltinVisibility(id, visible);
    }
    function refresh() {
        if (!bridge) {
            errorText = I18n.tr("The Settings bridge has not been built");
            return;
        }
        bridge.dockSnapshot();
    }

    function saveLayout() {
        if (!bridge)
            return;
        bridge.updateDockLayout(dockHeight);
    }

    function previewDockHeight(position) {
        const nextHeight = Math.round(40 + position * 60);
        if (nextHeight === dockHeight)
            return;
        dockHeight = nextHeight;
        layoutDirty = true;
    }

    function commitLayout() {
        if (!layoutDirty)
            return;
        layoutDirty = false;
        saveLayout();
    }
    Connections {
        target: dockPage.bridge
        enabled: dockPage.bridge !== null
        function onDockSnapshotChanged(state) {
            dockPage.applyState(state);
            if (dockPage.bridge.lastError)
                dockPage.errorText = I18n.tr(dockPage.bridge.lastError);
        }
        function onDockRevealIndicatorVisibilityChanged(state) {
            dockPage.revealIndicatorUpdatePending = false;
            dockPage.applyState(state);
            if (dockPage.bridge.lastError)
                dockPage.errorText = I18n.tr(dockPage.bridge.lastError);
        }
        function onDockBuiltinVisibilityChanged(state) {
            dockPage.builtinUpdatePending = false;
            dockPage.applyState(state);
            if (dockPage.bridge.lastError)
                dockPage.errorText = I18n.tr(dockPage.bridge.lastError);
        }
    }

    Component.onCompleted: refresh()

    Demo.SettingsGroup {
        title: I18n.tr("Size and position")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Dock height")

            Text {
                text: Math.round(dockPage.dockHeight) + " pt"
                color: colors.secondaryText
                font.pixelSize: 12
            }
            Controls.SettingsSlider {
                id: dockHeightSlider
                // The shared controls carry the host's palette, so the
                // Material form has to hand them the Material accent: their own
                // default is the iPadOS blue this window was designed with.
                accentColor: colors.accent
                // Ctrl+滚轮一档 = 1pt（下面的显示就是整数 pt）
                wheelStep: 1 / 60
                value: (dockPage.dockHeight - 40) / 60
                trackColor: colors.divider
                onPreviewChanged: function (position) {
                    dockPage.previewDockHeight(position);
                }
                onCanceled: {
                    dockPage.layoutDirty = false;
                    dockPage.refresh();
                }
                onCommitRequested: dockPage.commitLayout()
            }
        }
    }

    Demo.SettingsGroup {
        id: hoverColumn
        title: I18n.tr("Hover effects")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Hover to zoom")
            description: I18n.tr("Scales up and lifts together; 100% disables, up to 300%")

            Text {
                text: Math.round(dockPage.dockHoverScalePct) + "%"
                color: colors.secondaryText
                font.pixelSize: 12
            }
            Controls.SettingsSlider {
                id: hoverScaleSlider
                accentColor: colors.accent
                trackColor: colors.divider
                // Ctrl+滚轮一档 = 1%（显示就是整数百分比）
                wheelStep: 1 / (dockPage.maxHoverScalePct - dockPage.minHoverScalePct)
                value: (dockPage.dockHoverScalePct - dockPage.minHoverScalePct) / (dockPage.maxHoverScalePct - dockPage.minHoverScalePct)
                onPreviewChanged: function (position) {
                    dockPage.previewHoverScale(position);
                }
                onCanceled: {
                    dockPage.hoverScaleDirty = false;
                    dockPage.refresh();
                }
                onCommitRequested: dockPage.commitHoverScale()
            }
        }
    }

    Demo.SettingsGroup {
        id: builtinRows
        title: I18n.tr("Built-in icons")
        backgroundColor: colors.card

        Repeater {
            id: builtinRepeater
            model: [
                {
                    id: "launcher",
                    stateKey: "showLauncher",
                    label: I18n.tr("Launcher"),
                    symbol: "❖",
                    tint: "#ff9500"
                },
                {
                    id: "trash",
                    stateKey: "showTrash",
                    label: I18n.tr("Trash"),
                    symbol: "♲",
                    tint: "#8e8e93"
                }
            ]

            delegate: Demo.SettingsItem {
                id: builtinRow
                required property var modelData
                required property int index
                readonly property bool confirmedVisible: dockPage[modelData.stateKey]
                title: modelData.label
                CheckBox {
                    id: builtinCheck
                    objectName: "dock-" + builtinRow.modelData.id + "-checkbox"
                    checked: builtinRow.confirmedVisible
                    enabled: dockPage.stateReady && !dockPage.builtinUpdatePending
                    implicitWidth: 24
                    implicitHeight: 24
                    padding: 0
                    Accessible.name: builtinRow.modelData.label
                    indicator: Rectangle {
                        width: 22
                        height: 22
                        x: (builtinCheck.width - width) / 2
                        y: (builtinCheck.height - height) / 2
                        radius: 5
                        color: builtinCheck.checked ? colors.role("primary", "#0a84ff") : colors.card
                        border.width: builtinCheck.checked ? 0 : 1.5
                        border.color: builtinCheck.hovered ? colors.primaryText : colors.tertiaryText
                        opacity: builtinCheck.enabled ? 1 : 0.45
                        Text {
                            anchors.centerIn: parent
                            visible: builtinCheck.checked
                            text: "✓"
                            color: colors.role("on_primary", "#ffffff")
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }
                    }
                    contentItem: Item {}
                    background: Rectangle {
                        color: "transparent"
                        radius: 8
                        border.width: builtinCheck.visualFocus ? 2 : 0
                        border.color: colors.role("primary", "#0a84ff")
                    }
                    onToggled: {
                        dockPage.saveBuiltinVisibility(builtinRow.modelData.id, checked);
                        // The confirmed snapshot stays authoritative, including
                        // when saving fails or another client changes the setting.
                        builtinCheck.checked = Qt.binding(function () {
                            return builtinRow.confirmedVisible;
                        });
                    }
                }
            }
        }
    }

    Demo.SettingsGroup {
        title: I18n.tr("Window")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Merge windows by app")

            Controls.SettingsSwitch {
                id: windowGroupingSwitch
                objectName: "window-grouping-switch"
                checked: dockPage.windowGroupingIndex === 0
                accentColor: colors.role("primary", "#0a84ff")
                trackColor: colors.divider
                onToggled: function (checked) {
                    const requestedIndex = checked ? 0 : 1;
                    if (requestedIndex !== dockPage.windowGroupingIndex) {
                        dockPage.saveWindowGrouping(requestedIndex);
                    }
                }
            }
        }
    }

    Demo.SettingsGroup {
        id: dockLayoutColumn
        title: I18n.tr("DOCK APP BAR")
        backgroundColor: colors.card

        Demo.SettingsItem {
            title: I18n.tr("Dock position")

            Controls.SettingsSelect {
                id: positionNavBar
                textRole: "label"
                colors: dockPage.colors
                materialForm: dockPage.materialForm
                model: [
                    {
                        id: "bottom",
                        label: I18n.tr("Bottom"),
                        icon: "↓"
                    },
                    {
                        id: "left",
                        label: I18n.tr("Left"),
                        icon: "←"
                    },
                    {
                        id: "right",
                        label: I18n.tr("Right"),
                        icon: "→"
                    }
                ]
                currentIndex: dockPage.dockPositionIndex
                onSelectionChanged: function (index) {
                    dockPage.savePosition(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Content style")
            description: dockPage.dockContentStyleIndex === 0 ? I18n.tr("Apps, windows and widgets laid out compactly") : I18n.tr("Apps and windows come first, other components behind")

            Controls.SettingsNavBar {
                colors: dockPage.colors
                materialForm: dockPage.materialForm
                model: [
                    {
                        id: "compact",
                        label: I18n.tr("Compact")
                    },
                    {
                        id: "relaxed",
                        label: I18n.tr("Comfortable")
                    }
                ]
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                itemWidthOverride: 62
                currentIndex: dockPage.dockContentStyleIndex
                onSelectionChanged: function (index) {
                    dockPage.saveContentStyle(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Dock style")
            description: dockPage.dockStyleIndex === 0 ? I18n.tr("Adapt to content and keep theme spacing") : (dockPage.dockStyleIndex === 1 ? I18n.tr("Hugs the screen edge and extends into a taskbar") : I18n.tr("Hide the Dock background but keep the widget background"))

            Controls.SettingsSelect {
                textRole: "label"
                colors: dockPage.colors
                materialForm: dockPage.materialForm
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                model: [
                    {
                        id: "floating",
                        label: I18n.tr("Floating")
                    },
                    {
                        id: "taskbar",
                        label: I18n.tr("Taskbar")
                    },
                    {
                        id: "transparent",
                        label: I18n.tr("Fully transparent")
                    }
                ]

                currentIndex: dockPage.dockStyleIndex
                onSelectionChanged: function (index) {
                    dockPage.saveDockStyle(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Dock display")

            Controls.SettingsSelect {
                id: visibilityNavBar
                textRole: "label"
                colors: dockPage.colors
                materialForm: dockPage.materialForm
                model: [
                    {
                        id: "always",
                        label: I18n.tr("Always show")
                    },
                    {
                        id: "smart",
                        label: I18n.tr("Smart hide")
                    },
                    {
                        id: "persistent",
                        label: I18n.tr("Keep hidden")
                    }
                ]

                currentIndex: dockPage.visibilityModeIndex
                onSelectionChanged: function (index) {
                    dockPage.saveVisibilityMode(index);
                }
            }
        }

        Demo.SettingsItem {
            title: I18n.tr("Show the hide hint bar")
            description: I18n.tr("After turning it off, moving to the screen edge still summons the Dock")

            Controls.SettingsSwitch {
                objectName: "dock-reveal-indicator-switch"
                checked: dockPage.showRevealIndicator
                enabled: dockPage.stateReady && !dockPage.revealIndicatorUpdatePending
                accentColor: colors.role("primary", "#0a84ff")
                trackColor: colors.divider
                Accessible.name: I18n.tr("Show the hide hint bar")
                onToggled: function (checked) {
                    dockPage.saveRevealIndicatorVisibility(checked);
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: dockPage.errorText.length > 0
        text: dockPage.errorText
        color: colors.role("error", "#ff453a")
        wrapMode: Text.Wrap
        font.pixelSize: 12
    }
}
