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
    id: fgSchedPage
    required property var colors
    property bool materialForm: false

    Layout.fillWidth: true
    spacing: 12
    property var bridge: null
    property var snapshot: ({})
    property var stageSnapshot: ({})
    property var runningApps: []

    function stageSet(key, value) {
        if (bridge)
            bridge.stageConfigSet(key, String(value));
    }

    // ── 台前侧栏简单面：总开关 + 3 档风格预设，其余细节全下线 ──
    // 预设是**完整手感包**：卡面几何 / 玻璃质感 / 动效节拍 / 扇叠与图标排
    // 全在包内，套用后观感完全确定——不留"预设之外的残留值"（历史
    // config.json 里手调过的 fanSpacing / stripIconSize / glassOpacity
    // 等若不进包，会在每次套用预设后继续污染画面）。
    // 行为模式（layoutMode / side / autoMinimize / reserveStrip /
    // thumbLiveEffect / showCardTitle / centerCards 及收编节拍）**不属于
    // 风格**，不进预设、也不在 UI 暴露：值仍存于 config.json 与
    // StageConfigService，需要时用 `stage-config set <key> <value>` 调。
    readonly property var stagePresets: [
        {
            id: "lite",
            name: I18n.tr("Lithe"),
            detail: I18n.tr("Compact cards · crisp motion"),
            values: {
                cardHeight: 149,
                cardWidth: 112,
                cardGapPercent: 3.5,
                stripMargin: 12,
                deckSidePeek: 16,
                focusDim: false,
                fanSpacing: 6,
                fanHoverSpread: 1.4,
                stripIconSize: 40,
                maxIconSlots: 1,
                deckRestTilt: 2,
                tiltAngle: 0,
                hoverScale: 1.0,
                hoverDwellDelay: 200,
                engageDelay: 170,
                cardEnterDuration: 190,
                tiltAnimDuration: 220,
                cardRadius: 8,
                cardTint: 0.35,
                cardOpacity: 1.0,
                cardTopLight: 0.07,
                cardBorder: 0.05,
                cardGlow: 0.08,
                cardDepth: 0.28,
                thumbSize: 560,
                animDuration: 340,
                glassOpacity: 0.65,
                animEasing: "OutCubic"
            }
        },
        {
            id: "standard",
            name: I18n.tr("Standard"),
            detail: I18n.tr("Medium cards · balanced motion"),
            values: {
                cardHeight: 170,
                cardWidth: 128,
                cardGapPercent: 4.5,
                stripMargin: 12,
                deckSidePeek: 20,
                focusDim: false,
                fanSpacing: 8,
                fanHoverSpread: 1.4,
                stripIconSize: 46,
                maxIconSlots: 1,
                deckRestTilt: 2,
                tiltAngle: 0,
                hoverScale: 1.0,
                hoverDwellDelay: 200,
                engageDelay: 170,
                cardEnterDuration: 240,
                tiltAnimDuration: 280,
                cardRadius: 9,
                cardTint: 0.35,
                cardOpacity: 1.0,
                cardTopLight: 0.07,
                cardBorder: 0.05,
                cardGlow: 0.14,
                cardDepth: 0.40,
                thumbSize: 640,
                animDuration: 400,
                glassOpacity: 0.65,
                animEasing: "OutCubic"
            }
        },
        // 「立体」= 用户 2026-09-30 定稿手感（204/28，悬停放大关）；
        // 2026-10-17 iPadOS 还原：倾角归零（参考卡近平贴）
        {
            id: "vivid",
            name: I18n.tr("Dimensional"),
            detail: I18n.tr("Large cards · relaxed motion"),
            values: {
                cardHeight: 191,
                cardWidth: 144,
                cardGapPercent: 5.5,
                stripMargin: 12,
                deckSidePeek: 24,
                focusDim: false,
                fanSpacing: 10,
                fanHoverSpread: 1.4,
                stripIconSize: 52,
                maxIconSlots: 1,
                deckRestTilt: 2,
                tiltAngle: 0,
                hoverScale: 1.0,
                hoverDwellDelay: 200,
                engageDelay: 170,
                cardEnterDuration: 280,
                tiltAnimDuration: 340,
                cardRadius: 10,
                cardTint: 0.35,
                cardOpacity: 1.0,
                cardTopLight: 0.07,
                cardBorder: 0.05,
                cardGlow: 0.20,
                cardDepth: 0.50,
                thumbSize: 640,
                animDuration: 430,
                glassOpacity: 0.65,
                animEasing: "OutCubic"
            }
        },
    ]

    // 预设命中 = 全部键与当前快照一致（手工调过任意一项即脱离高亮）
    function stagePresetActive(p): bool {
        const s = stageSnapshot;
        for (const k in p.values)
            if (s[k] !== p.values[k])
                return false;
        return true;
    }

    function stageApplyPreset(p) {
        for (const k in p.values)
            stageSet(k, p.values[k]);
    }

    function refresh() {
        if (!bridge)
            return;
        bridge.fgSchedSnapshot();
        bridge.fgSchedRunningApps();
        bridge.fgSchedMemStatus();
        bridge.stageConfigSnapshot();
    }

    Connections {
        target: fgSchedPage.bridge
        enabled: fgSchedPage.bridge !== null
        function onFgSchedSnapshotChanged(snap) {
            fgSchedPage.snapshot = snap || {};
        }
        function onFgSchedRunningAppsChanged(apps) {
            fgSchedPage.runningApps = apps || [];
        }
        function onFgSchedMemStatusChanged(st) {
            fgSchedPage.memStatus = st || {};
        }
        function onStageConfigChanged(snap) {
            fgSchedPage.stageSnapshot = snap || {};
        }
    }

    property var memStatus: ({})

    // 内存状态 5s 轮询（页面激活期间）；顺带回读 fg-sched 快照——
    // stage-mode flag 会被 shell 单独改写（重启对齐/控制中心开关），
    // 纯事件驱动的快照会陈旧，轻量轮询（本地文件读取，无 IPC）兜底
    Timer {
        interval: 5000
        repeat: true
        running: fgSchedPage.bridge !== null
        onTriggered: {
            if (fgSchedPage.bridge === null)
                return;
            fgSchedPage.bridge.fgSchedMemStatus();
            fgSchedPage.bridge.fgSchedSnapshot();
        }
    }

    Component.onCompleted: refresh()

    Demo.SettingsGroup {
        title: I18n.tr("Stage scheduling")
        backgroundColor: colors.card
        Demo.SettingsItem {
            description: !fgSchedPage.snapshot.resourceSchedulingAvailable ? I18n.tr("The stage sidebar works on its own. Resource scheduling additionally requires fg-schedd to be installed and running; it was not detected.") : I18n.tr("While the external scheduler daemon runs, foreground apps get high CPU priority and kill protection; 10 seconds after going to the background ") + I18n.tr("Lower resource priority automatically (nice ") + (fgSchedPage.snapshot.bgNice !== undefined ? "+" + fgSchedPage.snapshot.bgNice : "+5") + I18n.tr(" and disk I/O is lowered in priority") + I18n.tr("; on hybrid CPUs background is limited to efficiency cores automatically).") + I18n.tr("Apps on the list stay at full speed in the background. Changes apply within about 5 seconds.")
        }
    }
    Demo.SettingsGroup {
        title: I18n.tr("Stage sidebar")
        backgroundColor: colors.card
        Demo.SettingsItem {
            title: I18n.tr("Enable stage-manager sidebar")
            description: I18n.tr("A window-card rail docked to the screen edge: tap a card to promote it, collected apps shrink into glass cards") + I18n.tr(" (also toggleable from the control center in the top right).")
            Controls.SettingsSwitch {
                checked: fgSchedPage.snapshot.stageEnabled === true
                accentColor: colors.accent
                trackColor: colors.divider
                onToggled: function (checked) {
                    fgSchedPage.bridge.stageSidebarSet(checked);
                }
            }
        }
    }
    Demo.SettingsGroup {
        title: I18n.tr("Style preset")
        backgroundColor: colors.card
        Repeater {
            model: fgSchedPage.stagePresets
            delegate: Demo.SettingsItem {
                id: presetRow
                required property var modelData
                readonly property bool selected: fgSchedPage.stagePresetActive(modelData)
                title: modelData.name
                description: modelData.detail
                Accessible.role: Accessible.RadioButton
                Accessible.checked: selected
                Accessible.onPressAction: fgSchedPage.stageApplyPreset(modelData)
                Text {
                    text: presetRow.selected ? "✓" : ""
                    color: colors.accent
                    font.pixelSize: 16
                }
                property Item activationArea: MouseArea {
                    parent: presetRow
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: fgSchedPage.stageApplyPreset(presetRow.modelData)
                }
            }
        }
        Demo.SettingsItem {
            description: I18n.tr("A preset sets the whole look — card size and spacing, tilt, glass, fan and icon row, motion tempo — in one click. ") + I18n.tr("Nothing highlights while the live values match no preset. Fine-tuning is not exposed on purpose; the remaining behavior switches keep their stored values.")
        }
    }
    ResourceSchedulingSettings {
        colors: fgSchedPage.colors
        bridge: fgSchedPage.bridge
        snapshot: fgSchedPage.snapshot
        memStatus: fgSchedPage.memStatus
        runningApps: fgSchedPage.runningApps
        onRefreshRequested: fgSchedPage.refresh()
    }
}
