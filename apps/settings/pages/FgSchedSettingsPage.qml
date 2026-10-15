import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"
import "../components" as Controls

ColumnLayout {
    required property var colors
    property bool materialForm: false
    id: fgSchedPage

    Layout.fillWidth: true
    spacing: 8
    property var bridge: null
    property var snapshot: ({})
    property var stageSnapshot: ({})
    property var runningApps: []


    function stageSet(key, value) {
        if (bridge)
            bridge.stageConfigSet(key, String(value))
    }

    // ── 台前侧栏简单面：3 预设 + 3 主参数；全量参数收进「高级自定义」──
    property bool stageAdvanced: false

    readonly property var stagePresets: [
        { id: "lite", name: I18n.tr("Lithe"), detail: I18n.tr("Compact cards · slight tilt · crisp motion"),
          values: { cardHeight: 145, cardSpacing: 14, tiltAngle: 16,
                    deckRestTilt: 16, hoverScale: 1.0,
                    cardEnterDuration: 190, tiltAnimDuration: 220,
                    animDuration: 340, cardGlow: 0.08, cardDepth: 0.28 } },
        { id: "standard", name: I18n.tr("Standard"), detail: I18n.tr("Medium cards · moderate tilt · balanced motion"),
          values: { cardHeight: 170, cardSpacing: 20, tiltAngle: 28,
                    deckRestTilt: 28, hoverScale: 1.0,
                    cardEnterDuration: 240, tiltAnimDuration: 280,
                    animDuration: 400, cardGlow: 0.14, cardDepth: 0.40 } },
        // 「立体」= 用户 2026-09-30 定稿手感（204/28/40×2，悬停放大关）
        { id: "vivid", name: I18n.tr("Dimensional"), detail: I18n.tr("Large cards · strong tilt · relaxed motion"),
          values: { cardHeight: 204, cardSpacing: 28, tiltAngle: 40,
                    deckRestTilt: 40, hoverScale: 1.0,
                    cardEnterDuration: 280, tiltAnimDuration: 340,
                    animDuration: 430, cardGlow: 0.20, cardDepth: 0.50 } },
    ]

    // 预设命中 = 全部键与当前快照一致（拖过主参数/高级项即脱离高亮）
    function stagePresetActive(p): bool {
        const s = stageSnapshot
        for (const k in p.values)
            if (s[k] !== p.values[k])
                return false
        return true
    }

    function stageApplyPreset(p) {
        for (const k in p.values)
            stageSet(k, p.values[k])
    }

    function refresh() {
        if (!bridge)
            return
        bridge.fgSchedSnapshot()
        bridge.fgSchedRunningApps()
        bridge.fgSchedMemStatus()
        bridge.stageConfigSnapshot()
    }

    Connections {
        target: fgSchedPage.bridge
        enabled: fgSchedPage.bridge !== null
        function onFgSchedSnapshotChanged(snap) {
            fgSchedPage.snapshot = snap || {}
        }
        function onFgSchedRunningAppsChanged(apps) {
            fgSchedPage.runningApps = apps || []
        }
        function onFgSchedMemStatusChanged(st) {
            fgSchedPage.memStatus = st || {}
        }
        function onStageConfigChanged(snap) {
            fgSchedPage.stageSnapshot = snap || {}
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
                return
            fgSchedPage.bridge.fgSchedMemStatus()
            fgSchedPage.bridge.fgSchedSnapshot()
        }
    }

    Component.onCompleted: refresh()

    // ── 说明卡 ──
    Rectangle {
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: introColumn.implicitHeight + 32

        ColumnLayout {
            id: introColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 4

            Text {
                text: I18n.tr("Stage scheduling")
                color: colors.primaryText
                font { pixelSize: 15; weight: Font.DemiBold }
            }
            Text {
                Layout.fillWidth: true
                text: !fgSchedPage.snapshot.resourceSchedulingAvailable
                    ? I18n.tr("The stage sidebar works on its own. Resource scheduling additionally requires fg-schedd to be installed and running; it was not detected.")
                    : I18n.tr("While the external scheduler daemon runs, foreground apps get high CPU priority and kill protection; 10 seconds after going to the background ")
                      + I18n.tr("Lower resource priority automatically (nice ")
                      + (fgSchedPage.snapshot.bgNice !== undefined ? "+" + fgSchedPage.snapshot.bgNice : "+5")
                      + I18n.tr(" and disk I/O is lowered in priority")
                      + I18n.tr("; on hybrid CPUs background is limited to efficiency cores automatically).")
                      + I18n.tr("Apps on the list stay at full speed in the background. Changes apply within about 5 seconds.")
                color: colors.secondaryText
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── 台前侧栏（开关 + 侧栏卡动效，全部即时生效） ──
    Rectangle {
        Layout.fillWidth: true
        radius: 14
        color: colors.card
        implicitHeight: stageColumn.implicitHeight + 32

        ColumnLayout {
            id: stageColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: I18n.tr("Stage sidebar")
                color: colors.primaryText
                font { pixelSize: 14; weight: Font.Medium }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Enable stage-manager sidebar")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("A window-card rail docked to the screen edge (left/right): tap a card to promote it, collected apps shrink into glass cards")
                              + I18n.tr(" (also toggleable from the control center in the top right).")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.snapshot.stageEnabled === true
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.bridge.stageSidebarSet(checked)
                        // 开关自持；快照回读经完好绑定回写（原"回读
                        // 确认"行是参数遮蔽 no-op，已删——勿改写成对
                        // checked 属性赋值，会砸掉绑定）
                    }
                }
            }

            // ── 风格预设：一键套用整组观感（三张等宽卡） ──
            Text {
                text: I18n.tr("Style preset")
                color: colors.primaryText
                font { pixelSize: 13; weight: Font.Medium }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: fgSchedPage.stagePresets

                    delegate: Rectangle {
                        id: presetCard
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: presetColumn.implicitHeight + 20
                        radius: 12
                        property bool isActive:
                            fgSchedPage.stagePresetActive(modelData)
                        color: isActive
                            ? colors.selectedContainer
                            : (presetMouse.containsMouse
                                ? colors.searchField : colors.sidebar)
                        border.width: isActive ? 2 : 0
                        border.color: colors.accent

                        ColumnLayout {
                            id: presetColumn
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                            }
                            anchors.margins: 10
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: presetCard.modelData.name
                                color: presetCard.isActive
                                    ? colors.selectedForeground
                                    : colors.primaryText
                                font { pixelSize: 13; weight: Font.Medium }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: presetCard.modelData.detail
                                color: colors.secondaryText
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }
                        }

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fgSchedPage.stageApplyPreset(
                                presetCard.modelData)
                        }
                    }
                }
            }

            // ── 快速调节：三个主参数（其余全在高级自定义） ──
            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Card size")
                unit: " px"
                minV: 100
                maxV: 220
                current: fgSchedPage.stageSnapshot.cardHeight !== undefined
                    ? fgSchedPage.stageSnapshot.cardHeight : 148
                onCommit: function(v) { fgSchedPage.stageSet("cardHeight", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Card width")
                unit: " px"
                minV: 120
                maxV: 320
                active: true
                current: fgSchedPage.stageSnapshot.cardWidth !== undefined
                    ? fgSchedPage.stageSnapshot.cardWidth : 216
                onCommit: function(v) { fgSchedPage.stageSet("cardWidth", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Tilt strength")
                unit: "°"
                minV: 0
                maxV: 40
                decimals: 1
                // 读当前模式的"活键"：scroll 的可见倾角是静置倾斜角，
                // adaptive 才是悬停倾角——读另一个会"拖了没反应/反应
                // 减半"。写两键同值（用户手感即两键同档，不分静置/悬停）
                current: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                    ? (fgSchedPage.stageSnapshot.tiltAngle !== undefined
                        ? fgSchedPage.stageSnapshot.tiltAngle : 22)
                    : (fgSchedPage.stageSnapshot.deckRestTilt !== undefined
                        ? fgSchedPage.stageSnapshot.deckRestTilt : 10)
                onCommit: function(v) {
                    fgSchedPage.stageSet("tiltAngle", v)
                    fgSchedPage.stageSet("deckRestTilt", v)
                }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Motion speed")
                unit: "×"
                minV: 0.5
                maxV: 1.6
                decimals: 2
                // 倍率对**当前值**等比缩放（factor = 新倍率/当前倍率）：
                // 保留用户调过的三个时长配比；锚点 240 只是显示基准。
                // 三个目标值先从同一份快照取齐再写，防逐键回读互相污染
                current: (fgSchedPage.stageSnapshot.cardEnterDuration !== undefined
                    ? fgSchedPage.stageSnapshot.cardEnterDuration : 240) / 240
                onCommit: function(v) {
                    const s = fgSchedPage.stageSnapshot
                    const enter = s.cardEnterDuration !== undefined
                        ? s.cardEnterDuration : 240
                    const tilt = s.tiltAnimDuration !== undefined
                        ? s.tiltAnimDuration : 250
                    const win = s.animDuration !== undefined
                        ? s.animDuration : 420
                    const f = enter > 0 ? v / (enter / 240) : 1
                    fgSchedPage.stageSet("cardEnterDuration",
                        Math.round(enter * f))
                    fgSchedPage.stageSet("tiltAnimDuration",
                        Math.round(tilt * f))
                    fgSchedPage.stageSet("animDuration",
                        Math.round(win * f))
                }
            }

            // ── 高级自定义：现有全量参数的入口 ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Advanced customization")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Expand all parameters: layout and position, gesture and motion details, glass texture, ")
                              + I18n.tr("collect timing and window-switch animations.")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.stageAdvanced
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageAdvanced = checked
                    }
                }
            }

            // ── 全量参数（默认折叠；上面的预设/主参数即本组的高层快捷方式） ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: fgSchedPage.stageAdvanced
                spacing: 10

                // adaptive 专属（scroll 模式下不生效，按模式禁用防"调了没反应"）；
                // 上限 40 = 特效 stageanim 的钳位（>40° 顶点镜像），schema 同步
                Controls.StageSliderRow {
                    colors: fgSchedPage.colors
                    label: I18n.tr("Card tilt angle")
                unit: "°"
                minV: 0
                maxV: 40
                decimals: 1
                active: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                current: fgSchedPage.stageSnapshot.tiltAngle !== undefined
                    ? fgSchedPage.stageSnapshot.tiltAngle : 22
                onCommit: function(v) { fgSchedPage.stageSet("tiltAngle", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Card spacing")
                unit: " px"
                minV: 4
                maxV: 48
                current: fgSchedPage.stageSnapshot.cardSpacing !== undefined
                    ? fgSchedPage.stageSnapshot.cardSpacing : 16
                onCommit: function(v) { fgSchedPage.stageSet("cardSpacing", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Card height")
                unit: " px"
                minV: 100
                maxV: 220
                current: fgSchedPage.stageSnapshot.cardHeight !== undefined
                    ? fgSchedPage.stageSnapshot.cardHeight : 148
                onCommit: function(v) { fgSchedPage.stageSet("cardHeight", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Hover zoom")
                unit: "×"
                minV: 1.0
                maxV: 1.2
                decimals: 2
                current: fgSchedPage.stageSnapshot.hoverScale !== undefined
                    ? fgSchedPage.stageSnapshot.hoverScale : 1.05
                onCommit: function(v) { fgSchedPage.stageSet("hoverScale", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Click response delay")
                unit: " ms"
                minV: 60
                maxV: 500
                current: fgSchedPage.stageSnapshot.engageDelay !== undefined
                    ? fgSchedPage.stageSnapshot.engageDelay : 170
                onCommit: function(v) { fgSchedPage.stageSet("engageDelay", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Hover dwell")
                unit: " ms"
                minV: 0
                maxV: 800
                current: fgSchedPage.stageSnapshot.hoverDwellDelay !== undefined
                    ? fgSchedPage.stageSnapshot.hoverDwellDelay : 200
                onCommit: function(v) { fgSchedPage.stageSet("hoverDwellDelay", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Card entrance motion")
                unit: " ms"
                minV: 100
                maxV: 800
                current: fgSchedPage.stageSnapshot.cardEnterDuration !== undefined
                    ? fgSchedPage.stageSnapshot.cardEnterDuration : 240
                onCommit: function(v) { fgSchedPage.stageSet("cardEnterDuration", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Tilt motion")
                unit: " ms"
                minV: 100
                maxV: 800
                current: fgSchedPage.stageSnapshot.tiltAnimDuration !== undefined
                    ? fgSchedPage.stageSnapshot.tiltAnimDuration : 250
                onCommit: function(v) { fgSchedPage.stageSet("tiltAnimDuration", v)
            }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Auto-collect background windows")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("After switching the active window, non-active windows are minimized into the sidebar automatically")
                              + I18n.tr(" (windows of the same app are exempt).")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.stageSnapshot.autoMinimize !== false
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageSet("autoMinimize", checked)
                    }
                }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Auto-collect delay")
                unit: " ms"
                minV: 200
                maxV: 3000
                active: fgSchedPage.stageSnapshot.autoMinimize !== false
                current: fgSchedPage.stageSnapshot.autoMinDelay !== undefined
                    ? fgSchedPage.stageSnapshot.autoMinDelay : 650
                onCommit: function(v) { fgSchedPage.stageSet("autoMinDelay", v)
            }
            }

            // （「保留侧栏条」开关已删：全屏浮层化后卡片恒为纯悬浮，
            // 该键零消费点，翻动只改 config 死值——schema 键保留兼容）

            Text {
                text: I18n.tr("Card layout")
                color: colors.primaryText
                font.pixelSize: 13
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "scroll", label: I18n.tr("Continuous scrolling (default)"),
                          detail: I18n.tr("Cards shown in full and never overlapping; laid out with fixed spacing, scrolling continuously when they exceed the sidebar (position dots + window count at the bottom)") },
                        { id: "adaptive", label: I18n.tr("Adaptive shrink"),
                          detail: I18n.tr("All cards shown in full, scaling down as window count grows") },
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: layoutLabel.implicitWidth + 22
                        height: 28
                        radius: 9
                        property bool isActive: fgSchedPage.stageSnapshot.layoutMode === modelData.id
                        color: isActive
                            ? colors.selectedContainer
                            : (layoutMouse.containsMouse
                                ? colors.searchField : colors.sidebar)
                        border.width: isActive ? 2 : 0
                        border.color: colors.accent

                        Text {
                            id: layoutLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.isActive
                                ? colors.selectedForeground : colors.primaryText
                            font { pixelSize: 12; weight: Font.Medium }
                        }

                        MouseArea {
                            id: layoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fgSchedPage.stageSet(
                                "layoutMode", modelData.id)
                        }
                    }
                }
            }

            Text {
                text: I18n.tr("Sidebar position")
                color: colors.primaryText
                font.pixelSize: 13
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "left", label: I18n.tr("Left of screen (default)") },
                        { id: "right", label: I18n.tr("Right of screen") },
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: sideLabel.implicitWidth + 22
                        height: 28
                        radius: 9
                        property bool isActive: fgSchedPage.stageSnapshot.side === modelData.id
                        color: isActive
                            ? colors.selectedContainer
                            : (sideMouse.containsMouse
                                ? colors.searchField : colors.sidebar)
                        border.width: isActive ? 2 : 0
                        border.color: colors.accent

                        Text {
                            id: sideLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.isActive
                                ? colors.selectedForeground : colors.primaryText
                            font { pixelSize: 12; weight: Font.Medium }
                        }

                        MouseArea {
                            id: sideMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fgSchedPage.stageSet(
                                "side", modelData.id)
                        }
                    }
                }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Merged card fan spacing")
                unit: " px"
                minV: 2
                maxV: 24
                active: true
                current: fgSchedPage.stageSnapshot.fanSpacing !== undefined
                    ? fgSchedPage.stageSnapshot.fanSpacing : 8
                onCommit: function(v) { fgSchedPage.stageSet("fanSpacing", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Fan spread on hover")
                unit: " ×"
                minV: 1.0
                maxV: 2.0
                decimals: 2
                active: true
                // 悬停/武装时扇叠间距的扩散系数（1.0=不扩散）；
                // 静态快照与实时直绘两模式同源生效
                current: fgSchedPage.stageSnapshot.fanHoverSpread !== undefined
                    ? fgSchedPage.stageSnapshot.fanHoverSpread : 1.4
                onCommit: function(v) {
                    fgSchedPage.stageSet("fanHoverSpread", v)
                }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Bottom-left icon size")
                unit: " px"
                minV: 16
                maxV: 40
                active: true
                current: fgSchedPage.stageSnapshot.stripIconSize !== undefined
                    ? fgSchedPage.stageSnapshot.stripIconSize : 24
                onCommit: function(v) { fgSchedPage.stageSet("stripIconSize", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Max icons per row")
                unit: I18n.tr(" items")
                minV: 3
                maxV: 8
                active: true
                current: fgSchedPage.stageSnapshot.maxIconSlots !== undefined
                    ? fgSchedPage.stageSnapshot.maxIconSlots : 5
                onCommit: function(v) { fgSchedPage.stageSet("maxIconSlots", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Merge dwell time")
                unit: " ms"
                minV: 200
                maxV: 1200
                active: true
                current: fgSchedPage.stageSnapshot.mergeDwellMs !== undefined
                    ? fgSchedPage.stageSnapshot.mergeDwellMs : 450
                onCommit: function(v) { fgSchedPage.stageSet("mergeDwellMs", v)
            }
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: I18n.tr("Show card titles")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Off = immersive thumbnails: the card shows only window content without the title (the close button stays on hover)")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.stageSnapshot.showCardTitle !== false
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageSet("showCardTitle", checked)
                    }
                }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Rest tilt angle")
                unit: "°"
                minV: 0
                maxV: 40
                decimals: 1
                active: fgSchedPage.stageSnapshot.layoutMode === "scroll"
                current: fgSchedPage.stageSnapshot.deckRestTilt !== undefined
                    ? fgSchedPage.stageSnapshot.deckRestTilt : 10
                onCommit: function(v) { fgSchedPage.stageSet("deckRestTilt", v)
            }
            }

            Controls.StageSliderRow {
                colors: fgSchedPage.colors
                label: I18n.tr("Retreat distance")
                unit: " px"
                minV: 4
                maxV: 60
                active: fgSchedPage.stageSnapshot.layoutMode === "scroll"
                current: fgSchedPage.stageSnapshot.deckSidePeek !== undefined
                    ? fgSchedPage.stageSnapshot.deckSidePeek : 20
                onCommit: function(v) { fgSchedPage.stageSet("deckSidePeek", v)
            }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Dim retreated cards on focus")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Dim retreated cards on hover focus to emphasize the main one; off keeps them at normal brightness.")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.stageSnapshot.focusDim === true
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageSet("focusDim", checked)
                    }
                }
            }

            // adaptive 专属（scroll 模式下卡在槽内本就居中，禁用防误导）
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                opacity: fgSchedPage.stageSnapshot.layoutMode === "adaptive" ? 1.0 : 0.45

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Center cards vertically")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Adaptive: cards center vertically when they fit; anchored to the top when full.")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    enabled: fgSchedPage.stageSnapshot.layoutMode === "adaptive"
                    checked: fgSchedPage.stageSnapshot.centerCards !== false
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageSet("centerCards", checked)
                    }
                }
            }

            // ── 卡面画面模式（两态）：静态快照（关）/ 实时·合成器
            //    直绘（开）。遗留 PipeWire 流实验路径已从面板移除
            //   （本机触发宿主杀桌面；代码保留给强硬件、仅 IPC 可达），
            //    配置层互斥仍在 ──
            Text {
                Layout.fillWidth: true
                text: I18n.tr("Card content mode — current: ")
                    + (fgSchedPage.stageSnapshot.thumbLiveEffect === true
                        ? I18n.tr("Live (compositor-drawn, window content keeps updating)")
                        : I18n.tr("Static snapshot (captured on collect; stable and power-efficient)"))
                color: colors.accent
                font { pixelSize: 12; weight: Font.Medium }
                wrapMode: Text.WordWrap
            }

            // 合成器活体卡（stageanim 直绘）：隐藏窗经 KWin 离屏帧
            // 回调继续出帧（成本=窗口可见在桌面，无 screencast 管线），
            // 特效把窗口纹理按卡面透视直接画进卡里——所有卡常开实时
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: I18n.tr("Live cards (compositor-drawn)")
                        color: colors.primaryText
                        font { pixelSize: 13; weight: Font.Medium }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("Windows collected into cards show their content live (video/terminal output keeps updating). Uses the compositor direct-draw path (no PipeWire); overhead only occurs when window content updates, comparable to keeping those apps on the desktop. Falls back to static snapshots automatically if effects are unavailable.")
                        color: colors.secondaryText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }

                LiquidControls.LiquidGlassSwitch {
                    checked: fgSchedPage.stageSnapshot.thumbLiveEffect === true
                    accentColor: colors.accent
                    trackColor: colors.divider
                    onToggled: function(checked) {
                        fgSchedPage.stageSet("thumbLiveEffect", checked)
                    }
                }
            }

            }
        }
    }

    // ── 玻璃质感（卡面：圆角/背板/受光/描边/辉光/纵深/缩略图清晰度；
    //     高级自定义的一部分，默认折叠） ──
    StageAdvancedSettings {
        colors: fgSchedPage.colors
        materialForm: fgSchedPage.materialForm
        visible: fgSchedPage.stageAdvanced
        stageSnapshot: fgSchedPage.stageSnapshot
        onSettingRequested: (key, value) => fgSchedPage.stageSet(key, value)
    }

    ResourceSchedulingSettings {
        colors: fgSchedPage.colors
        bridge: fgSchedPage.bridge
        snapshot: fgSchedPage.snapshot
        memStatus: fgSchedPage.memStatus
        runningApps: fgSchedPage.runningApps
        onRefreshRequested: fgSchedPage.refresh()
    }

    Item { Layout.preferredHeight: 4 }
}
