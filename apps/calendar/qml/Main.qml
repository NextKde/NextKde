pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Effects
import Kos.Pim
import Kos.Ui

KosApplicationWindow {
    id: root

    modernDesign: true
    visible: true
    // LQ11: toolbar help tags are app-drawn (the `HelpTag` popup below), so
    // the attached ToolTip never renders. The two palette slots stay set for
    // any stock tooltip that might still be reached from a shared control:
    // dark panel #3C3C3C with #F2F2F2 ink, light panel #F2F2F2 with black ink.
    palette.toolTipBase: root.tahoeDark ? "#3C3C3C" : "#F2F2F2"
    palette.toolTipText: root.tahoe.labelPrimary
    title: qsTr("Calendar")
    width: 1100
    height: 720
    minimumWidth: 760
    minimumHeight: 540

    property date now: new Date()
    property date visibleMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property date selectedDate: new Date()
    property int viewIndex: 0
    property string searchQuery: ""
    property bool showEvents: true
    property bool showTasks: true
    property bool showCompletedTasks: false
    property string statusMessage: ""
    // LQ11: one help tag for the whole window, armed by whichever control is
    // hovered. Single instance by construction, so tags can never stack.
    property Item helpTagAnchor: null
    property string helpTagText: ""

    // Apple 26 ("Tahoe") design tokens. Light values are verbatim from the
    // shared Sketch library's document.tokenExport dump — see
    // tmp/ui-replication/calendar-v2/LEDGER.md §5. Values are the measured /
    // exported hexes, not theme roles, so the chrome matches the reference
    // instead of drifting with AppTheme. Dark (X03) keeps the same hierarchy
    // on a neutral charcoal ramp — no blue panel cast: the content plane is
    // slightly deeper than the sidebar, labels are near-white over neutral
    // greys, separators faint white, and the glass lifts instead of
    // whitening.
    readonly property bool tahoeDark: AppTheme.dark
    readonly property QtObject tahoe: QtObject {
        // Sidebar and content are two flush planes, not floating cards.
        readonly property color sidebarPlane:
            root.tahoeDark ? "#282828" : "#E4E4E4"
        readonly property color contentPlane:
            AppTheme.neutralPlane
        readonly property int sidebarWidth: 220

        // Glass. Two independent frames agree on one law, so this is measured,
        // not eyeballed: the body is 0.44 x backdrop + 129. Materials/Liquid
        // Glass - Over Light Backgrounds puts six pills on a grey ramp
        // (102,127,152,177,204,229) and reads back 185,186,212,223,219... and
        // the sidebar toolbar pill here on the #E4E4E4 plane reads 228 at its
        // dip — all on that line. It is a #E6E6E6 veil at 56%, which means the
        // glass *compresses* whatever is behind it instead of just adding
        // white. That is the part a flat opaque gradient cannot do: over the
        // white content plane it stays a light grey (241) rather than blowing
        // out, and over a dark backdrop it lifts hard. Dark: a neutral grey
        // veil that lifts the charcoal plane without a porcelain read; the
        // hairline flips to a faint light edge and the specular rim stays
        // restrained (no glow ring).
        readonly property color glassVeil: root.tahoeDark
            ? Qt.rgba(0x8A / 255, 0x8A / 255, 0x8A / 255, 0.22)
            : Qt.rgba(0xE6 / 255, 0xE6 / 255, 0xE6 / 255, 0.56)
        // Outermost hairline. Measured 200-210 on a 228 plane, 142 on 177.
        readonly property color glassEdge: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
        // 1px specular line just inside it: 255 against a 229 body at both the
        // top and the bottom rim, so the glass catches light on both edges.
        readonly property color glassRim: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.90)

        // Fills/Light 2 Secondary #787880 @16% over the sidebar plane
        // resolves to the #D2D2D2 the reference measures.
        readonly property color controlFill: root.tahoeDark
            ? Qt.rgba(0x78 / 255, 0x78 / 255, 0x80 / 255, 0.28)
            : Qt.rgba(0x78 / 255, 0x78 / 255, 0x80 / 255, 0.16)
        // Fills/Light 3 Tertiary #767680 @12% → the measured #D6D6D8.
        readonly property color selectionFill: root.tahoeDark
            ? Qt.rgba(0x76 / 255, 0x76 / 255, 0x80 / 255, 0.30)
            : Qt.rgba(0x76 / 255, 0x76 / 255, 0x80 / 255, 0.12)

        // M04: the mini month's "other selection" disc — the today disc's own
        // shape (filled circle + white number) in GRAY, not a hollow ring.
        // Apple systemGray. Leg-independent like todayRed: 142 reads Δ86 below
        // the 228 light plane and Δ102 above the 40 dark one, so one literal
        // serves both legs.
        readonly property color selectionDisc: "#8E8E93"

        // M04: the mini month's disc DIAMETER, shared by the today disc and the
        // "other selection" disc so the clause's "the same shape" is true by
        // construction rather than by two literals that can drift. M04's
        // literal is 18-20; the reference's own disc is 15 at 1:1, which is
        // 17.2-17.3 in this sidebar (220/192 = 1.146 by width, 28.0/24.25 =
        // 1.155 by column pitch) => 18 is the smallest number satisfying both.
        readonly property int miniDisc: 18

        // Toolbar view segment (R097). The segment sits on the CONTENT plane
        // (white 255), not on the sidebar plane, so it must not reuse the two
        // sidebar fills above. Measured 1:1 off the reference's own
        // Day/Week/Month/Year capsule on that same white plane: track
        // 249..253 (Δ2..6 below the plane) and the *selected* pill 230..235,
        // i.e. Δ≈20 BELOW its own track. The pill is the darker of the two —
        // the older white-on-grey reading here was the wrong polarity.
        // Dark leg is extrapolation (no dark reference exists): both steps
        // lift the charcoal plane, the pill the stronger one.
        // The pill is OPAQUE on purpose: the shared control paints a black@10%
        // lens shadow under it, so a translucent pill composites down to 210
        // instead of the measured 231. Dark is extrapolation (no dark reference):
        // 54 = the same 24 steps, mirrored to the dark side.
        // (Light: 231 = 24 below the 255 plane, matching the reference's 230..235.)
        readonly property color segmentTrack: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.06)
            : Qt.rgba(0x78 / 255, 0x78 / 255, 0x80 / 255, 0.025)
        readonly property color segmentPill: root.tahoeDark
            ? "#3C3C3C" : "#E7E7E7"

        // Labels/Light 1 Primary, 2 Secondary (#3C3C43 @60% → #8A8A8A).
        readonly property color labelPrimary:
            root.tahoeDark ? "#F2F2F2" : "#000000"
        // C1: reference alpha is 60%, but that reads 3.44:1 on white and
        // 2.70:1 on the #E4E4E4 sidebar plane. 0.79 is the smallest alpha
        // that clears 4.5:1 on BOTH planes (4.56 / 5.80), the minimal
        // deviation from the reference that satisfies WCAG.
        readonly property color labelSecondary: root.tahoeDark
            ? Qt.rgba(0xF2 / 255, 0xF2 / 255, 0xF2 / 255, 0.58)
            : Qt.rgba(0x3C / 255, 0x3C / 255, 0x43 / 255, 0.79)
        // Separators/Light Non-Opaque (#000000 @12%).
        readonly property color separator: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.12)

        // System Colors/Light 8 Blue, 4 Green, 3 Orange.
        readonly property color accent: "#0088FF"
        readonly property color positive: "#34C759"
        readonly property color warning: "#FF8D28"
        // C2: status-bar text sits on the white content plane, where the
        // reference green/orange read 2.22/2.31:1. The light leg darkens to
        // the smallest same-hue values clearing 4.5:1 (#24883D 4.50,
        // #B2621C 4.51); dark keeps the reference colors (7.51/7.22 on
        // #1E1E1E).
        readonly property color statusPositive:
            root.tahoeDark ? "#34C759" : "#24883D"
        readonly property color statusWarning:
            root.tahoeDark ? "#FF8D28" : "#B2621C"

        // Sidebar search field: Sidebar/Light/Search, 300x44 on a 320 plane,
        // fully rounded, filled with Fills/Light 2 over the plane.
        readonly property color searchFill:
            root.tahoeDark ? "#3A3A3A" : "#D2D2D2"
        readonly property int searchHeight: 44
        readonly property int searchInsetLeading: 10
        readonly property int searchInsetTrailing: 11

        // Rows (Items/Level 0 + States/Selected): 44 tall, selection inset 20
        // from the sidebar edge and 11 from the far side, a 20x20 marker box
        // 16 inside the selection, label 15 after the marker.
        readonly property int rowHeight: 44
        readonly property int rowInsetLeading: 20
        readonly property int rowInsetTrailing: 11
        readonly property int rowIconInset: 16
        readonly property int rowIconSize: 20
        readonly property int rowTextGap: 15
        readonly property int rowFontSize: 15
        readonly property int rowDetailInset: 12
        readonly property color rowHoverFill: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.06)
            : Qt.rgba(0x74 / 255, 0x74 / 255, 0x80 / 255, 0.08)
        readonly property color rowPressFill: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.12)
            : Qt.rgba(0x74 / 255, 0x74 / 255, 0x80 / 255, 0.14)

        // S02/S03: compact category rows for the 220px sidebar. One 12px
        // rounded checkbox at inset 12 carries the whole state (filled +
        // white check when on, hollow colored border when off); the label
        // sits 8 after the box at 13px; rows are 30 tall. Group headings are
        // 11px secondary with 6 below and 16 above.
        readonly property int categoryRowHeight: 30
        readonly property int categoryInset: 12
        readonly property int categoryBoxSize: 12
        readonly property int categoryBoxRadius: 3
        readonly property int categoryTextGap: 8
        readonly property int categoryFontSize: 13
        readonly property int categoryHeadingTop: 16
        readonly property int categoryHeadingBottom: 6

        readonly property int controlHeight: 44
        readonly property int controlRowHeight: 54
        readonly property int pillHeight: 44

        // L06: the date heading band is 48 logical px with 20px side insets
        // and a 27px single-line localised title. L07: the right navigation
        // group is 26 high with 13px text, low-contrast neutral chrome.
        readonly property int dateBandHeight: 48
        readonly property int dateBandInset: 20
        readonly property int dateTitleSize: 27
        readonly property int dateNavHeight: 26
        readonly property int dateNavTextSize: 13

        // L02: unified toolbar under the 30px dot band. 40 tall; icon buttons
        // 28x28 with 16px icons and 8px gaps; the segmented control is 228x28.
        readonly property int toolbarHeight: 40
        readonly property int toolbarButtonSize: 28
        readonly property int toolbarIconSize: 16
        readonly property int toolbarGap: 8
        // LQ02: the toolbar is now material-hosted (one floating capsule),
        // so its contents keep 8px between the button box and the capsule's
        // inner edge (capsule inset 8 + these 16 = 24 from the window edge).
        readonly property int toolbarInsetLeft: 16
        readonly property int toolbarInsetRight: 16
        // LQ02: floating-toolbar geometry from liquid-spec §3/§4 — 8px float,
        // capsule radius (= 40/2), regular fill.
        readonly property int toolbarFloat: 8
        readonly property real toolbarRadius: toolbarHeight / 2
        readonly property int segmentWidth: 228
        readonly property int segmentHeight: 28

        // LQ10: menu (liquid-spec §4 "菜单"): 30px rows, radius 16 surface,
        // 16px icons in a 20px column, plain rows inside (no nested glass).
        readonly property int menuWidth: 220
        readonly property int menuRowHeight: 30
        readonly property int menuRadius: 16
        readonly property int menuIconSize: 16
        readonly property int menuTextSize: 13
        readonly property int menuRowInset: 4
        readonly property int menuIconInset: 6
        readonly property int menuTextGap: 8
        readonly property int menuSurfaceInset: 4
        // Same reserved shadow gutter as the detail popover (E3 spread 32 +
        // offset 3 + slack): the visible card is inset, the popup grows.
        readonly property int menuShadowInset: 36

        // LQ11 help tag (tooltip): spec O02's neutral card + hairline + soft
        // shadow, 11px label, 6x10 inset, smallRadius(12). Solid, not glass:
        // a tooltip is an L2 transient and 1/1 is already spent by the menu,
        // plus the spec bans glass inside transients. E1's spread 8 + offset 1
        // needs a 9px gutter; the 10px gap makes the popup start 1px clear of
        // the control, so the tag never steals the hover that owns it.
        readonly property int helpTagDelay: 1000
        readonly property int helpTagFontSize: 11
        readonly property int helpTagPadH: 10
        readonly property int helpTagPadV: 6
        readonly property int helpTagRadius: 12
        readonly property int helpTagShadowGutter: 9
        readonly property int helpTagGap: 10
        readonly property color helpTagFill: root.tahoeDark ? "#3C3C3C" : "#F2F2F2"
        readonly property color helpTagBorder: root.tahoeDark
            ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10)

        // G03/G04 玻璃按钮投影(浅色,应用内绘制,G08)。集中命名,只调这里。
        // 用 QtQuick.Effects 的 RectangularShadow(Qt 6.9+):几何与玻璃本体
        // 完全一致(anchors.fill),blur 由效果自身向外画,不外扩形状;
        // z:-1 保证阴影在玻璃后面。
        // 色相:轻中性灰(#18000000 ≈ 黑 9.4%),无蓝偏,白底与 #E4E4E4 侧栏
        // 上都干净。单层。
        readonly property color shadowColor: "#18000000"
        // G04:blur 是边缘柔化 px,spread 0(不内收不外扩),轻微向下投影。
        readonly property real shadowBlur: 8
        readonly property real shadowSpread: 0
        readonly property real shadowOffsetY: 1.5
        readonly property real shadowOffsetX: 0
        // G03 深色分支(本轮接线,X03 验收):纯中性黑,在炭灰面上略重但
        // 克制,无蓝/棕偏,不用白色光晕充当阴影。
        readonly property color shadowColorDark: "#40000000"
        readonly property real shadowBlurDark: 10
        readonly property real shadowOffsetYDark: 2.5

        // G01/G02/G05 液态镜片(浅色):主区 header 按钮从日程视口顶部采样
        // 一条内容带,重柔化后透入镜片内部;参数集中,只调这里。
        // lensSampleBand:采样的视口可见顶部带高度(视口本地 y=0..band,
        // 即滚动时从按钮下方掠过的那部分内容);x 按钮位取并钳到视口内。
        readonly property int lensSampleBand: 84
        // lensBlur 是 MultiEffect 归一化柔化量(blurMax 48);轻微去饱和让
        // 文字细节不透上来,只留低频色调。
        readonly property real lensBlur: 0.75
        readonly property real lensSaturation: -0.25
        // 镜片内三层透明度:采样内容本身、盖在内容上的 veil、渐变剖面。
        // fallback(侧栏无背景)完全走 R002 已通过的原样路径,不受影响。
        readonly property real lensContentOpacity: 0.9
        readonly property real lensVeilOpacity: 0.55
        readonly property real lensProfileOpacity: 0.6

        // G07 交互触感(浅色):克制的 macOS 反馈。集中命名,只调这里。
        // hoverLift:悬停时镜片轻微提亮(白色叠加的峰值 alpha,不是深灰遮罩)。
        readonly property real hoverLift: 0.10
        // hoverRimBoost:细白高光边增强倍率(乘在 glassRim 的 alpha 上)。
        readonly property real hoverRimBoost: 1.6
        // pressScale:按下视觉压下(只作用于绘制 transform,布局盒不动)。
        readonly property real pressScale: 0.97
        // 恢复/进入时长(ms),无弹簧无过冲。M1:与 AppTheme motion token 同规,
        // reduceMotion 时归零,按下/悬停不做插值动画。
        readonly property int pressDuration: AppTheme.reduceMotion ? 0 : 150
        // G03:按下时阴影更淡更贴近(乘在浅色 shadow 参数上),不脏不蓝。
        readonly property real pressedShadowOpacityFactor: 0.55
        readonly property real pressedShadowBlurFactor: 0.75
        readonly property real pressedShadowOffsetFactor: 0.6
    }

    readonly property string activeView:
        ["month", "week", "day", "year"][viewIndex]
    readonly property int localeFirstDayOfWeek:
        Number(Qt.locale().firstDayOfWeek) % 7
    readonly property date weekStart: startOfWeek(selectedDate)
    readonly property var selectedItems: itemsForDate(selectedDate)
    // One scan per invalidation (occurrencesChanged, searchQuery, filters);
    // every day/hour cell then just looks up its key instead of rescanning
    // pim.occurrences + pim.todoOccurrences.
    readonly property var itemsByDate: buildItemsByDate()
    // G01/G05: the live schedule viewport the header glass samples. Null in
    // month view (the lens falls back to the static glass there).
    property Item scheduleViewport: null

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    // Sidebar row chrome, from Items/Level 0 + States/Selected: the selection
    // is a capsule inset 20 from the sidebar edge and 11 from the far side, the
    // marker box is 20x20, the label sits 15 after it, and any trailing detail
    // is right-aligned 12 inside the capsule.
    component SidebarRow: AbstractButton {
        id: row

        property string detail: ""
        property color markerColor: "transparent"
        property string markerGlyph: ""
        property bool markerFilled: false
        property bool selected: false
        property bool showSwitch: false
        property color switchColor: root.tahoe.accent
        // Child rows in Items/Level 1 sit one icon-width further in.
        property bool nested: false

        implicitHeight: root.tahoe.rowHeight
        hoverEnabled: true
        Accessible.role: row.showSwitch ? Accessible.Switch : Accessible.ListItem
        Accessible.name: row.text
        Accessible.checked: row.checked

        readonly property real nestInset: row.nested ? 24 : 0
        readonly property real markerLeft: root.tahoe.rowInsetLeading
                                           + root.tahoe.rowIconInset
                                           + row.nestInset
        readonly property real labelLeft: markerLeft + root.tahoe.rowIconSize
                                          + root.tahoe.rowTextGap

        background: Rectangle {
            x: root.tahoe.rowInsetLeading
            width: row.width - root.tahoe.rowInsetLeading
                   - root.tahoe.rowInsetTrailing
            height: row.height
            radius: height / 2
            color: row.selected ? root.tahoe.selectionFill
                : (row.hovered ? root.tahoe.rowHoverFill : "transparent")
        }

        contentItem: Item {
            Item {
                x: row.markerLeft
                anchors.verticalCenter: parent.verticalCenter
                width: root.tahoe.rowIconSize
                height: root.tahoe.rowIconSize

                Rectangle {
                    anchors.centerIn: parent
                    width: 12
                    height: 12
                    radius: 6
                    color: row.markerFilled ? row.markerColor : "transparent"
                    border.width: row.markerColor.a > 0 && !row.markerFilled ? 2 : 0
                    border.color: row.markerColor
                }

                Label {
                    anchors.centerIn: parent
                    text: row.markerGlyph
                    color: row.markerColor
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: row.labelLeft
                width: Math.max(0, row.width - row.labelLeft
                                   - root.tahoe.rowInsetTrailing
                                   - root.tahoe.rowDetailInset
                                   - detailLabel.implicitWidth - 8)
                text: row.text
                color: row.enabled ? root.tahoe.labelPrimary
                                   : root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
                elide: Text.ElideRight
            }

            Label {
                id: detailLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: row.showSwitch ? switchTrack.left : parent.right
                anchors.rightMargin: row.showSwitch ? 10
                    : root.tahoe.rowInsetTrailing + root.tahoe.rowDetailInset
                text: row.detail
                color: root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
                horizontalAlignment: Text.AlignRight
            }

            // The kit's own switch spec was not in the frames pulled for this
            // task, so this is a proportional stand-in (LEDGER.md §4).
            Rectangle {
                id: switchTrack
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.tahoe.rowInsetTrailing
                                     + root.tahoe.rowDetailInset
                visible: row.showSwitch
                width: visible ? 42 : 0
                height: 26
                radius: height / 2
                color: row.checked
                    ? row.switchColor
                    : Qt.rgba(0x78 / 255, 0x78 / 255, 0x80 / 255, 0.32)
                opacity: row.enabled ? 1 : 0.48

                Rectangle {
                    y: 3
                    x: row.checked ? parent.width - width - 3 : 3
                    width: 20
                    height: 20
                    radius: 10
                    color: "#FFFFFF"

                    Behavior on x {
                        NumberAnimation {
                            duration: AppTheme.motionFast
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // S03: compact category row for the 220px sidebar. In checkbox mode the
    // 12px rounded box is the only state carrier: filled with the category
    // colour and a white check when checked, a hollow 1px coloured border
    // when not. Legend mode (checkboxless) draws a plain filled swatch. No
    // colour dot, no switch. 30 tall, inset 12, label 8 after the box at
    // 13px, single-line elide with the tail reserved before the label.
    component CategoryRow: AbstractButton {
        id: row

        property color boxColor: root.tahoe.accent
        property string detail: ""
        property bool nested: false
        // Pure colour-swatch mode for the task-list legend: solid fill, no
        // check, no checked/unchecked reading.
        property bool swatchOnly: false

        implicitHeight: root.tahoe.categoryRowHeight
        hoverEnabled: true
        Accessible.role: row.swatchOnly ? Accessible.ListItem
                                        : Accessible.CheckBox
        Accessible.name: row.text
        Accessible.checked: row.checked

        readonly property real boxLeft: root.tahoe.categoryInset
            + (row.nested ? 24 : 0)

        background: Rectangle {
            x: 6
            width: row.width - 12
            height: row.height
            radius: 6
            color: row.hovered ? root.tahoe.rowHoverFill : "transparent"
        }

        contentItem: Item {
            // S03/LQ06: the shared liquid checkbox draws the box; the row
            // still owns interaction, so the box is a disabled visual with
            // the category colour and the reference's 12px / r3 geometry.
            LiquidCheckBox {
                id: box
                x: row.boxLeft
                anchors.verticalCenter: parent.verticalCenter
                width: root.tahoe.categoryBoxSize
                height: root.tahoe.categoryBoxSize
                enabled: false
                padding: 0
                opacity: row.enabled ? 1 : 0.48
                text: ""
                checkable: false
                checked: row.swatchOnly ? true : row.checked
                indicatorSize: root.tahoe.categoryBoxSize
                indicatorRadius: root.tahoe.categoryBoxRadius
                fillColor: row.boxColor
                fillStrength: 1
                uncheckedFillStrength: 0
                indicatorBorderWidth: row.swatchOnly ? 0 : 1
                indicatorBorderColor: row.boxColor
                checkColor: "#FFFFFF"
                checkVisible: !row.swatchOnly
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                x: row.boxLeft + root.tahoe.categoryBoxSize
                   + root.tahoe.categoryTextGap
                width: Math.max(0, parent.width - x
                                   - (detailLabel.visible
                                      ? detailLabel.implicitWidth + 8 : 0)
                                   - root.tahoe.categoryInset)
                text: row.text
                color: row.enabled ? root.tahoe.labelPrimary
                                   : root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.categoryFontSize
                elide: Text.ElideRight
            }

            Label {
                id: detailLabel
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: root.tahoe.categoryInset
                visible: row.detail.length > 0
                text: row.detail
                color: root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.categoryFontSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // Sidebar/Light/Search: a #D2D2D2 capsule with a leading magnifier, the
    // placeholder at x 47 inside it, and a dictation glyph at the far end. Both
    // glyphs are hand-drawn (no icon font ships here — LEDGER.md §6).
    component SidebarSearch: Item {
        id: field

        property alias text: input.text
        property string placeholder: qsTr("Search")
        signal edited(string value)

        implicitHeight: root.tahoe.searchHeight

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.tahoe.searchInsetLeading
            anchors.rightMargin: root.tahoe.searchInsetTrailing
            radius: height / 2
            color: root.tahoe.searchFill

            TextInput {
                id: input
                Accessible.name: field.placeholder
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                anchors.right: parent.right
                anchors.rightMargin: 47
                clip: true
                color: root.tahoe.labelPrimary
                font.pixelSize: root.tahoe.rowFontSize
                selectionColor: root.tahoe.accent
                onTextEdited: field.edited(text)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 47
                text: field.placeholder
                visible: input.text.length === 0
                color: root.tahoe.labelSecondary
                font.pixelSize: root.tahoe.rowFontSize
            }

            Item {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Rectangle {
                    x: 2
                    y: 1.5
                    width: 12
                    height: 12
                    radius: 6
                    color: "transparent"
                    border.width: 1.6
                    border.color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 12.4
                    y: 13.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    rotation: 45
                    color: root.tahoe.labelSecondary
                }
            }

            Item {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                Rectangle {
                    x: 3
                    y: 5
                    width: 14
                    height: 9
                    radius: 7
                    color: "transparent"
                    border.width: 1.6
                    border.color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 2.4
                    y: 4.4
                    width: 15.2
                    height: 4
                    color: root.tahoe.searchFill
                }

                Rectangle {
                    x: 6.5
                    y: 1
                    width: 7
                    height: 12
                    radius: 3.5
                    color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 9.2
                    y: 13
                    width: 1.6
                    height: 4
                    color: root.tahoe.labelSecondary
                }

                Rectangle {
                    x: 6.5
                    y: 16.4
                    width: 7
                    height: 1.6
                    radius: 0.8
                    color: root.tahoe.labelSecondary
                }
            }
        }
    }

    // The glass body, shared by every glass control. Three stacked pieces
    // because the reference has three: a dark hairline at the very edge, a 1px
    // white specular line inside it, and the veil between them carrying a
    // vertical profile that dips near the top and lifts toward the bottom. The
    // sidebar toolbar pill measures 238 / 228 / 234 / 250 top to bottom on a
    // 228 plane, with 255 at both rims — so the glass catches light on its top
    // *and* bottom edge, and the dark end of its gradient never goes below the
    // plane it sits on.
    //
    // G01/G02/G05: liquid lens. When `backdrop` (a content Item to sample —
    // never this button or an ancestor of it) and `backdropWindow` are set,
    // the lens samples a horizontal band of the *content* under the button
    // from that item, heavy-blurs it, and shows it inside the glass footprint
    // under the veil/gradient. The sample is live, so it follows real scroll
    // continuously; the button itself never moves. Without a backdrop the
    // component renders exactly as it did in R002 (sidebar fallback).
    //
    // Sampling is done from a sibling-level source item, and the sample is
    // masked to the pill shape, so no rectangular corners or hard edges
    // appear; the specular rim and R002 shadow are untouched and drawn on top.
    component GlassSurface: Rectangle {
        id: glass

        // Content item to sample (e.g. the schedule viewport) and the window
        // used for cross-item coordinate mapping. Both read-only inputs.
        property Item backdrop: null
        property Item backdropWindow: null
        // Optional position-based override: true forces the lens on, false
        // forces the static fallback, regardless of the backdrop presence.
        // Unset (-1) means "decide from the backdrop".
        property int activeOverride: -1
        // G07: interaction state fed by the owning button. Default off.
        property bool hovered: false
        property bool pressed: false

        // Smooth 0..1 drivers so enter/leave/press/release all glide over the
        // same duration — no jumps, no spring overshoot. Writable (not
        // readonly) because the Behavior interpolates by writing frames.
        property real hoverAmount: hovered ? 1 : 0
        property real pressAmount: pressed ? 1 : 0
        Behavior on hoverAmount { NumberAnimation {
            duration: root.tahoe.pressDuration; easing.type: Easing.OutCubic } }
        Behavior on pressAmount { NumberAnimation {
            duration: root.tahoe.pressDuration; easing.type: Easing.OutCubic } }

        readonly property bool lensActive: backdrop !== null
            && backdropWindow !== null && activeOverride !== 0

        // Position of this button inside the backdrop's coordinate space.
        // `geometryProbe` sums ancestor properties so a move/resize of any
        // ancestor also re-evaluates the mapping (same trick as listenfree's
        // GlassSurface — mapToItem alone has no geometry notifications).
        readonly property rect backdropRect: {
            if (!lensActive)
                return Qt.rect(0, 0, 0, 0)
            let probe = glass
            let geometry = 0
            while (probe) {
                geometry += probe.x + probe.y + probe.width + probe.height
                probe = probe.parent
            }
            const position = glass.mapToItem(backdrop, 0, 0)
            return Qt.rect(position.x, position.y, glass.width, glass.height)
        }

        // The lens shows what is *visually under the button*, and the button
        // sits in the header above the viewport, so the sampled area is the
        // viewport's own visible top band (backdrop-local y=0..band), taken
        // at the button's x. The button's own y in backdrop space is negative
        // (it is above the viewport) and must never be used as the sample y —
        // a negative y samples an empty area outside the source bounds and
        // the FBO comes back transparent. X is clamped so the rect always
        // lies inside the viewport; edge buttons (negative x) sample the
        // leftmost strip of the visible band.
        readonly property rect lensSampleRect: {
            if (!lensActive)
                return Qt.rect(0, 0, 0, 0)
            const band = root.tahoe.lensSampleBand
            const x = Math.max(0, Math.min(glass.backdropRect.x,
                backdrop.width - glass.width))
            return Qt.rect(x, 0, glass.width, band)
        }

        RectangularShadow {
            anchors.fill: parent
            z: -1
            offset: Qt.vector2d(root.tahoe.shadowOffsetX,
                                (root.tahoeDark ? root.tahoe.shadowOffsetYDark
                                                : root.tahoe.shadowOffsetY)
                                    * (1 - (1 - root.tahoe.pressedShadowOffsetFactor)
                                           * glass.pressAmount))
            blur: (root.tahoeDark ? root.tahoe.shadowBlurDark
                                  : root.tahoe.shadowBlur)
                * (1 - (1 - root.tahoe.pressedShadowBlurFactor)
                       * glass.pressAmount)
            spread: root.tahoe.shadowSpread
            radius: glass.radius
            // Same neutral hue in every state (G03): light grey / dark black,
            // never blue; press only lightens and tightens the shadow.
            color: root.tahoeDark ? root.tahoe.shadowColorDark
                                  : root.tahoe.shadowColor
            opacity: 1 - (1 - root.tahoe.pressedShadowOpacityFactor)
                         * glass.pressAmount
        }

        // Live content sample for the lens: the viewport's visible top band
        // at the button's x (see lensSampleRect). Independent item as source,
        // so no recursive self-sampling is possible. textureSize is small —
        // only low-frequency colour is wanted.
        ShaderEffectSource {
            id: lensSample
            visible: false
            live: glass.lensActive
            width: glass.width
            height: glass.height
            smooth: true
            sourceItem: glass.backdrop
            sourceRect: glass.lensSampleRect
            textureSize: Qt.size(48, 48)
            wrapMode: ShaderEffectSource.ClampToEdge
        }

        // Heavily blurred sample, masked to the pill so only low-frequency
        // tone inside the lens shows — no rectangular corners, no hard edges.
        MultiEffect {
            anchors.fill: parent
            visible: glass.lensActive
            source: lensSample
            blurEnabled: true
            blurMax: 48
            blur: root.tahoe.lensBlur
            saturation: root.tahoe.lensSaturation
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: lensMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            opacity: root.tahoe.lensContentOpacity
        }
        Rectangle {
            id: lensMask
            visible: false
            anchors.fill: parent
            radius: glass.radius
            layer.enabled: true
        }

        radius: height / 2
        // Lens mode: the base fill goes translucent so the blurred live
        // sample behind it shows through; the vertical profile above stays
        // and keeps its own opacity, so text/icons stay readable and the
        // specular rim is untouched. Sidebar (no backdrop) keeps the opaque
        // R002 fill exactly.
        color: glass.lensActive
            ? Qt.rgba(root.tahoe.glassVeil.r, root.tahoe.glassVeil.g,
                      root.tahoe.glassVeil.b, root.tahoe.lensVeilOpacity)
            : root.tahoe.glassVeil
        border.width: 1
        border.color: root.tahoe.glassEdge

        // G07 hover: a faint white lift so the lens brightens while the real
        // background tone still shows through — no dark overlay, no expansion.
        Rectangle {
            anchors.fill: parent
            radius: glass.radius
            color: "#FFFFFF"
            opacity: root.tahoe.hoverLift * glass.hoverAmount
            Behavior on opacity { NumberAnimation {
                duration: root.tahoe.pressDuration; easing.type: Easing.OutCubic } }
        }

        // The vertical profile, drawn inside the rim so the edges stay crisp.
        // In lens mode the profile fades so the sample tone shows through the
        // middle while the rims keep their catch-light. Dark keeps the same
        // shape but far dimmer and neutral — no white porcelain bottom edge.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, glass.radius - 1)
            opacity: glass.lensActive ? root.tahoe.lensProfileOpacity : 1
            gradient: Gradient {
                GradientStop { position: 0.00; color: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.10)
                    : Qt.rgba(1, 1, 1, 0.410) }
                GradientStop { position: 0.16; color: Qt.rgba(0, 0, 0, 0.008) }
                GradientStop { position: 0.40; color: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.015)
                    : Qt.rgba(1, 1, 1, 0.050) }
                GradientStop { position: 0.70; color: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.045)
                    : Qt.rgba(1, 1, 1, 0.150) }
                GradientStop { position: 0.88; color: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.13)
                    : Qt.rgba(1, 1, 1, 0.550) }
                GradientStop { position: 1.00; color: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.22)
                    : Qt.rgba(1, 1, 1, 1.000) }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, glass.radius - 1)
            color: "transparent"
            border.width: 1
            // G07: the specular rim strengthens on hover (moderate boost, no
            // second capsule — same line, brighter).
            // The boost MUST ride on the colour's alpha. `opacity` is a
            // QQuickItem 0…1 property, so `1 + 0.6 * hoverAmount` used to
            // compute 1.6 and clamp straight back to 1.0 — the declared 1.6x
            // never rendered (R131 measured 0.2755 rest / 0.2768 hover).
            border.color: Qt.rgba(root.tahoe.glassRim.r, root.tahoe.glassRim.g,
                                  root.tahoe.glassRim.b,
                                  Math.min(1, root.tahoe.glassRim.a
                                              * (1 + (root.tahoe.hoverRimBoost - 1)
                                                   * glass.hoverAmount)))
            opacity: 1
        }

        // G07 press: visual-only sink about the button centre. A QML
        // transform never touches the layout box or the neighbours, and the
        // lens sample mapping stays on the untransformed geometry (the
        // 3% shift amounts to <1px, below sample resolution).
        transform: Scale {
            xScale: 1 - (1 - root.tahoe.pressScale) * glass.pressAmount
            yScale: 1 - (1 - root.tahoe.pressScale) * glass.pressAmount
            origin.x: glass.width / 2
            origin.y: glass.height / 2
        }
    }

    // Circular glass button from Sidebar/Light/Toolbar. Measures ⌀40 on the
    // sidebar plane with a faint lighter-than-plane fill and a hairline edge.
    component GlassButton: AbstractButton {
        id: control

        property string symbol: ""
        property string hint: ""
        // Liquid-lens inputs, forwarded to the GlassSurface background.
        property Item lensBackdrop: null
        property Item lensBackdropWindow: null

        implicitWidth: root.tahoe.controlHeight
        implicitHeight: root.tahoe.controlHeight
        hoverEnabled: true
        Accessible.name: hint
        onHoveredChanged: hovered ? root.armHelpTag(control)
                                  : root.disarmHelpTag(control)
        onPressedChanged: if (control.pressed) root.disarmHelpTag(control)

        contentItem: Label {
            text: control.symbol
            color: root.tahoe.labelPrimary
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: GlassSurface {
            opacity: control.enabled ? 1 : 0.5
            backdrop: control.lensBackdrop
            backdropWindow: control.lensBackdropWindow
            hovered: control.hovered
            pressed: control.pressed
        }
    }

    // Labeled glass pill from the same toolbar spec: as tall as the circular
    // buttons beside it (44), fully rounded, horizontal padding 16.
    component GlassPill: AbstractButton {
        id: control

        implicitWidth: Math.max(65, contentItem.implicitWidth + 32)
        implicitHeight: root.tahoe.pillHeight
        hoverEnabled: true
        // Liquid-lens inputs, forwarded to the GlassSurface background.
        property Item lensBackdrop: null
        property Item lensBackdropWindow: null

        contentItem: Label {
            text: control.text
            color: root.tahoe.labelPrimary
            font.pixelSize: root.tahoe.rowFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: GlassSurface {
            opacity: control.enabled ? 1 : 0.5
            backdrop: control.lensBackdrop
            backdropWindow: control.lensBackdropWindow
            hovered: control.hovered
            pressed: control.pressed
        }
    }

    // LQ04: toolbar icon action. The floating capsule behind the toolbar is
    // the only glass in this region (persistent 1/2), so the button itself is
    // a host-owned plain row: no surface, no lens, no shadow — just a 28x28
    // hit area whose hover/press fill reads against the capsule. `materialForm`
    // keeps LiquidActionButton off its liquid background path entirely.
    component ToolbarButton: LiquidActionButton {
        id: control

        property string hint: ""

        materialForm: true
        iconOnly: true
        implicitWidth: root.tahoe.toolbarButtonSize
        implicitHeight: root.tahoe.toolbarButtonSize
        iconSize: root.tahoe.toolbarIconSize
        iconColor: root.tahoe.labelPrimary
        textColor: root.tahoe.labelPrimary
        surfaceColor: "transparent"
        hoverEnabled: true

        // Clicks on toolbar buttons must not steal focus from the inline
        // search input: a press that moved focus would fire the input's blur
        // handler before onClicked, and toggle() would then reopen what the
        // blur just closed. Tab keeps keyboard accessibility.
        focusPolicy: Qt.TabFocus
        Accessible.name: hint
        onHoveredChanged: hovered ? root.armHelpTag(control)
                                  : root.disarmHelpTag(control)
        onPressedChanged: if (control.pressed) root.disarmHelpTag(control)

        // Host-owned plain row. Round to match the round button footprint the
        // capsule used to carry; the fill is the same neutral row-hover token
        // the sidebar rows use, so no second material appears.
        background: Rectangle {
            radius: height / 2
            color: control.down ? root.tahoe.selectionFill
                : (control.hovered ? root.tahoe.rowHoverFill : "transparent")
            border.width: control.visualFocus ? 1 : 0
            border.color: root.tahoe.labelPrimary
        }
    }

    // L07: subdued date-navigation button for the heading band — 26 high,
    // 13px text, low-contrast neutral edge/fill (macOS light-grey nav look,
    // dark variant equally quiet). No lens, no thick glass. Arrows are a
    // local chevron vector, not a glyph font.
    component DateNavButton: AbstractButton {
        id: control

        // "" → chevron arrow (rotation from arrowRotation), otherwise text.
        property string text_: ""
        property real arrowRotation: 0
        property string hint: ""

        implicitHeight: root.tahoe.dateNavHeight
        implicitWidth: text_.length > 0
            ? textLabel.implicitWidth + 20 : root.tahoe.dateNavHeight
        hoverEnabled: true
        Accessible.name: hint
        onHoveredChanged: hovered ? root.armHelpTag(control)
                                  : root.disarmHelpTag(control)
        onPressedChanged: if (control.pressed) root.disarmHelpTag(control)

        background: Rectangle {
            radius: height / 2
            color: control.pressed
                ? root.tahoe.selectionFill
                : (control.hovered ? root.tahoe.rowHoverFill : "transparent")
            border.width: 1
            border.color: root.tahoe.separator
            opacity: control.enabled ? 1 : 0.5
        }

        contentItem: Item {
            Label {
                id: textLabel
                anchors.centerIn: parent
                visible: control.text_.length > 0
                text: control.text_
                color: root.tahoe.labelPrimary
                font.pixelSize: root.tahoe.dateNavTextSize
            }
            Item {
                anchors.centerIn: parent
                width: 14; height: 14
                visible: control.text_.length === 0
                // The two bars meet at a bottom point (caret ^); rotating the
                // holder +90° points it left (‹), -90° points it right (›)
                // — verified against the actual screenshot evidence.
                rotation: control.arrowRotation

                // Local chevron: two short bars meeting at a point, same
                // technique as the checkbox check.
                Rectangle {
                    width: 2; height: 5.4; radius: 1
                    color: root.tahoe.labelSecondary
                    rotation: -45
                    x: 3.0; y: 2.4
                }
                Rectangle {
                    width: 2; height: 5.4; radius: 1
                    color: root.tahoe.labelSecondary
                    rotation: 45
                    x: 7.2; y: 2.4
                }
            }
        }
    }

    // LQ11: help tag. Solid neutral card + 1px hairline + E1 outer shadow,
    // r12 / 11px / 6x10 (spec O02). One popup instance for the window, shown
    // 1s after hover (O01) and torn down as soon as the pointer leaves.
    // Placement follows the anchor: below by default (matches the macOS 26
    // help-tag reference), flips above when the bottom is out of room (O09),
    // and slides horizontally inside an 8px window margin. The 9px gutter
    // is reserved for the shadow, not part of the visible card.
    Popup {
        id: helpTag
        objectName: "helpTag"
        visible: false
        padding: 0
        closePolicy: Popup.NoAutoClose
        modal: false
        dim: false

        contentItem: Item {
            implicitWidth: helpTagMetrics.advanceWidth
                           + 2 * root.tahoe.helpTagPadH
                           + 2 * root.tahoe.helpTagShadowGutter
            implicitHeight: helpTagMetrics.boundingRect.height
                            + 2 * root.tahoe.helpTagPadV
                            + 2 * root.tahoe.helpTagShadowGutter

            Label {
                id: helpTagLabel
                x: root.tahoe.helpTagShadowGutter + root.tahoe.helpTagPadH
                y: root.tahoe.helpTagShadowGutter + root.tahoe.helpTagPadV
                text: root.helpTagText
                color: root.tahoe.labelPrimary
                font.pixelSize: root.tahoe.helpTagFontSize
            }
        }

        background: Item {
            Rectangle {
                id: helpTagCard
                anchors.fill: parent
                anchors.margins: root.tahoe.helpTagShadowGutter
                radius: root.tahoe.helpTagRadius
                color: root.tahoe.helpTagFill
                border.width: 1
                border.color: root.tahoe.helpTagBorder
            }
            LiquidOuterShadow {
                anchors.fill: helpTagCard
                radius: root.tahoe.helpTagRadius
                shadowLevel: 1
            }
        }
    }

    Timer {
        id: helpTagTimer
        interval: root.tahoe.helpTagDelay
        onTriggered: root.openHelpTag()
    }

    // TextMetrics measures the resolved font synchronously; sizing the popup
    // from the label's implicitWidth at open() time used stale metrics and
    // left CJK labels hanging past the card's right edge.
    TextMetrics {
        id: helpTagMetrics
        font: helpTagLabel.font
        text: root.helpTagText
    }

    function armHelpTag(item) {
        if (!item || !item.visible || item.hint.length === 0)
            return
        helpTagAnchor = item
        helpTagText = item.hint
        helpTagTimer.restart()
    }

    function disarmHelpTag(item) {
        if (helpTagAnchor !== item)
            return
        helpTagTimer.stop()
        helpTagAnchor = null
        helpTag.close()
    }

    function openHelpTag() {
        if (!helpTagAnchor || !helpTagAnchor.hovered) {
            helpTagAnchor = null
            return
        }
        // Re-parent before opening so x/y can be expressed against the
        // hovered control, which is the only stable origin across views.
        helpTag.parent = helpTagAnchor
        helpTag.open()
        positionHelpTag()
    }

    function positionHelpTag() {
        const item = helpTagAnchor
        if (!item)
            return
        const win = root.contentItem
        const origin = item.mapToItem(win, 0, 0)
        const gutter = root.tahoe.helpTagShadowGutter
        const cardW = Math.ceil(helpTagMetrics.advanceWidth)
                      + 2 * root.tahoe.helpTagPadH
        const cardH = Math.ceil(helpTagMetrics.boundingRect.height)
                      + 2 * root.tahoe.helpTagPadV
        const edge = 8
        helpTag.width = cardW + 2 * gutter
        helpTag.height = cardH + 2 * gutter
        let cardX = origin.x + (item.width - cardW) / 2
        cardX = Math.max(edge, Math.min(cardX, win.width - cardW - edge))
        let cardY = origin.y + item.height + root.tahoe.helpTagGap
        if (cardY + cardH > win.height - edge)
            cardY = origin.y - cardH - root.tahoe.helpTagGap
        helpTag.x = cardX - origin.x - gutter
        helpTag.y = cardY - origin.y - gutter
    }

    // The reference's month arrows are 5x9 px of ink at 1:1 (x22..27 /
    // y350..358, ~1 px stroke). Its mini month's column pitch is 24.25 where
    // ours is 28.0 (x1.155), so the scaled target is 5.8x10.4 and the 1:1
    // target is 5x9; the shape below lands between them by construction, so
    // the scale choice is not load-bearing at this size. Drawn as a local
    // vector for the same reason DateNavButton is: the "‹" glyph this
    // replaced rendered only 4x5 of ink at 13px.
    component MiniMonthChevron: Item {
        id: chevron

        // Ink envelope, not a box: two bars at 45 meeting at a point on the
        // left. The two bars' ink spans x0.18..5.62 / y0.24..10.18 inside
        // this item, so these two numbers put the item's centre AT the ink's
        // centre (2.90, 5.21) — that is what makes the 180° rotation below
        // exactly mirror rather than shift.
        implicitWidth: 5.8
        implicitHeight: 10.42

        Rectangle {
            width: 1.4
            height: 6.3
            radius: 0.6
            color: root.tahoe.labelSecondary
            rotation: 45
            x: 2.2
            y: -0.19
        }

        Rectangle {
            width: 1.4
            height: 6.3
            radius: 0.6
            color: root.tahoe.labelSecondary
            rotation: -45
            x: 2.2
            y: 4.31
        }
    }

    // LQ10: menu rows are plain (spec §4: no glass inside a menu) and reuse
    // the sidebar's fill language for hover — rowHoverFill / pressFill, same
    // tokens SidebarRow uses — on an 8px rounded inset, not a capsule, so a
    // 30px menu row reads as a row rather than a second selection pill.
    component MenuActionRow: MenuItem {
        id: menuAction

        property string iconName: ""
        property bool destructive: false

        implicitHeight: root.tahoe.menuRowHeight
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0

        background: Rectangle {
            x: root.tahoe.menuRowInset
            width: menuAction.width - 2 * root.tahoe.menuRowInset
            height: menuAction.height
            radius: 8
            color: menuAction.down ? root.tahoe.rowPressFill
                : (menuAction.hovered || menuAction.highlighted
                   ? root.tahoe.rowHoverFill : "transparent")
        }

        contentItem: Item {
            VectorIcon {
                x: root.tahoe.menuIconInset
                anchors.verticalCenter: parent.verticalCenter
                size: root.tahoe.menuIconSize
                name: menuAction.iconName
                color: menuAction.destructive ? AppTheme.destructive
                                              : root.tahoe.labelPrimary
                opacity: menuAction.enabled ? 1 : 0.38
            }

            Label {
                x: root.tahoe.menuIconInset + root.tahoe.menuIconSize
                   + root.tahoe.menuTextGap
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, menuAction.width - x - 10)
                text: menuAction.text
                color: menuAction.destructive ? AppTheme.destructive
                                              : root.tahoe.labelPrimary
                opacity: menuAction.enabled ? 1 : 0.38
                font.pixelSize: root.tahoe.menuTextSize
                elide: Text.ElideRight
            }
        }
    }

    component MenuGroupSeparator: MenuSeparator {
        implicitHeight: 9
        leftPadding: 0
        rightPadding: 0
        topPadding: 0
        bottomPadding: 0
        // The Basic style paints a full-bleed background line; the menu owns
        // its separator (10px inset, 1px hairline), so drop the style's.
        background: null

        contentItem: Item {
            Rectangle {
                x: 10
                y: (parent.height - height) / 2
                width: Math.max(0, parent.width - 20)
                height: 1
                color: root.tahoe.separator
            }
        }
    }

    function activationOption(activationArgs, name) {
        const prefix = name + "="
        for (let index = 0; index < activationArgs.length; index++) {
            const argument = String(activationArgs[index])
            if (argument === name && index + 1 < activationArgs.length)
                return String(activationArgs[index + 1])
            if (argument.startsWith(prefix))
                return argument.slice(prefix.length)
        }
        return ""
    }

    function handleActivation(activationArgs, workingDirectory) {
        const requestedView = activationOption(activationArgs, "--view")
        // P2-9: "year" was silently dropped even though viewIndex 3 exists;
        // the fourth view now has a CLI activation path to match Ctrl+4.
        const requestedViewIndex = ["month", "week", "day", "year"].indexOf(requestedView)
        if (requestedViewIndex >= 0)
            viewIndex = requestedViewIndex

        const requested = activationOption(activationArgs, "--date")
        if (requested === "today") {
            showToday()
            return
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(requested))
            return
        const parts = requested.split("-").map(Number)
        const date = new Date(parts[0], parts[1] - 1, parts[2], 12)
        if (Number.isNaN(date.getTime())
                || date.getFullYear() !== parts[0]
                || date.getMonth() !== parts[1] - 1
                || date.getDate() !== parts[2])
            return
        selectedDate = date
        visibleMonth = new Date(date.getFullYear(), date.getMonth(), 1)
        Qt.callLater(updateEventRange)
    }

    function value(record, key, fallback) {
        if (record === null || record === undefined)
            return fallback
        const result = record[key]
        return result === undefined || result === null ? fallback : result
    }

    function sameDay(left, right) {
        return left.getFullYear() === right.getFullYear()
            && left.getMonth() === right.getMonth()
            && left.getDate() === right.getDate()
    }

    function dateKey(date) {
        return AppTheme.formatDate(date, "yyyy-MM-dd")
    }

    function startOfWeek(date) {
        const offset = (date.getDay() - localeFirstDayOfWeek + 7) % 7
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() - offset)
    }

    function monthDate(offset) {
        return new Date(visibleMonth.getFullYear(), visibleMonth.getMonth() + offset, 1)
    }

    function dateForMonthCell(index) {
        const first = new Date(visibleMonth.getFullYear(), visibleMonth.getMonth(), 1)
        const offset = (first.getDay() - localeFirstDayOfWeek + 7) % 7
        return new Date(first.getFullYear(), first.getMonth(), index - offset + 1)
    }

    function weekdayName(column, format) {
        const jsDay = (localeFirstDayOfWeek + column) % 7
        const qtDay = jsDay === 0 ? 7 : jsDay
        return Qt.locale().dayName(qtDay, format)
    }

    function addDayRange(bucket, startKey, endKey, item) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(startKey))
            return
        const start = new Date(startKey + "T00:00:00")
        const end = /^\d{4}-\d{2}-\d{2}$/.test(endKey)
            ? new Date(endKey + "T00:00:00") : start
        for (let day = start; day <= end;
                day = new Date(day.getFullYear(), day.getMonth(),
                               day.getDate() + 1)) {
            const key = dateKey(day)
            if (bucket[key] === undefined)
                bucket[key] = []
            bucket[key].push(item)
        }
    }

    function buildItemsByDate() {
        const result = ({})
        const representedTodos = new Map()
        const events = pim.occurrences ?? []
        const todos = pim.todoOccurrences ?? []

        if (showEvents) {
            for (let index = 0; index < events.length; index++) {
                const event = events[index]
                if (!matchesSearch(event))
                    continue
                const item = { kind: "event", record: event }
                const start = String(value(event, "start", "")).slice(0, 10)
                const end = String(value(event, "end", "")).slice(0, 10)
                // Keep the old per-day semantics: a multi-day event lands on
                // its start day and every strictly-covered day, not the end.
                addDayRange(result, start,
                    end > start ? previousDateKey(end) : start, item)
                const todoId = String(value(event, "linkedTodoId", ""))
                if (todoId.length > 0) {
                    let todoDays = representedTodos.get(todoId)
                    if (todoDays === undefined)
                        representedTodos.set(todoId,
                            todoDays = Object.create(null))
                    addDayRange(todoDays, start,
                        end > start ? previousDateKey(end) : start, item)
                }
            }
        }

        if (showTasks) {
            for (let index = 0; index < todos.length; index++) {
                const todo = todos[index]
                if (!matchesSearch(todo))
                    continue
                const due = String(value(todo, "due", "")).slice(0, 10)
                const id = String(value(todo, "seriesId",
                                        value(todo, "id", "")))
                const days = representedTodos.get(id)
                if (days !== undefined && days[due] !== undefined)
                    continue
                if (!showCompletedTasks
                        && Boolean(value(todo, "completed", false)))
                    continue
                addDayRange(result, due, due,
                            { kind: "todo", record: todo })
            }
        }

        for (const key in result) {
            result[key].sort(function(left, right) {
                const leftAllDay = itemAllDay(left)
                const rightAllDay = itemAllDay(right)
                if (leftAllDay !== rightAllDay)
                    return leftAllDay ? -1 : 1
                const byDateTime =
                    itemDateTime(left).localeCompare(itemDateTime(right))
                if (byDateTime !== 0)
                    return byDateTime
                // R083: two items can share an identical start (the fixture's
                // Thu all-day pair does), and upstream order is then whatever
                // the model happened to emit. Tiebreak on the UID so the
                // rendered order is stable run to run.
                const byId =
                    itemStableId(left).localeCompare(itemStableId(right))
                return byId !== 0 ? byId : itemTitle(left).localeCompare(
                                        itemTitle(right))
            })
        }
        return result
    }

    function previousDateKey(key) {
        const date = new Date(key + "T00:00:00")
        return dateKey(new Date(date.getFullYear(), date.getMonth(),
                                date.getDate() - 1))
    }

    function itemsForDate(date) {
        return itemsByDate[dateKey(date)] ?? []
    }

    function matchesSearch(record) {
        const query = searchQuery.trim().toLocaleLowerCase()
        if (query.length === 0)
            return true
        const haystack = (String(value(record, "title", "")) + "\n"
            + String(value(record, "description", "")) + "\n"
            + String(value(record, "location", ""))).toLocaleLowerCase()
        return haystack.indexOf(query) >= 0
    }

    function itemRecord(item) {
        return value(item, "record", ({}))
    }

    function itemTitle(item) {
        return String(value(itemRecord(item), "title", qsTr("Untitled")))
    }

    // E02 (R-CHIP user ruling 2026-10-17): the timed chip's second line is
    // the time range ("11AM – 1PM" on the ref). Todos render their due time
    // only; no end is invented when the record lacks one. R246/P1-1: the
    // format follows the locale — 12-hour locales keep the compact style
    // (minutes only when nonzero; the start meridiem dropped when both ends
    // share the same period, "12 – 2PM") with meridiem text from the locale;
    // 24-hour locales render plain "HH:MM – HH:MM" with no meridiem.
    function itemSecondary(item) {
        if (itemAllDay(item))
            return ""
        const startMatch = itemDateTime(item).match(/T(\d{2}:\d{2})/)
        if (!startMatch)
            return ""
        const endText = String(value(itemRecord(item), "end", ""))
        const endMatch = endText.match(/T(\d{2}:\d{2})/)
        const startClock = AppTheme.formatClock(startMatch[1])
        if (!endMatch)
            return startClock
        const endClock = AppTheme.formatClock(endMatch[1])
        if (AppTheme.localeUses24hClock())
            return startClock + " – " + endClock
        const startSuffix = AppTheme.meridiemText(parseInt(startMatch[1], 10))
        const endSuffix = AppTheme.meridiemText(parseInt(endMatch[1], 10))
        if (startSuffix === endSuffix)
            return startClock.slice(0, startClock.length - startSuffix.length) + " – " + endClock
        return startClock + " – " + endClock
    }

    function itemDateTime(item) {
        const record = itemRecord(item)
        return String(value(record, item.kind === "todo" ? "due" : "start", ""))
    }

    // R083: the record's stable identity — the UID, which the store exposes as
    // `seriesId`. Only for ORDERING ties; never for display.
    function itemStableId(item) {
        const record = itemRecord(item)
        return String(value(record, "seriesId", value(record, "id", "")))
    }

    // P1-2: locale-aware via AppTheme.formatClock — 24h locales keep "HH:MM",
    // 12h locales get the compact form ("11AM" / "1:30PM").
    function itemTime(item) {
        if (itemAllDay(item))
            return qsTr("All day")
        const match = itemDateTime(item).match(/T(\d{2}:\d{2})/)
        return match ? AppTheme.formatClock(match[1]) : "--:--"
    }

    // P01: full date/time line for the detail popover. Events get a
    // locale-formatted date plus the start–end range (the stored end is
    // exclusive, so the displayed end for a same-day timed event is the
    // literal stored end; multi-day/all-day ranges show a date range).
    // Tasks show their due date/time. No end is invented when absent.
    function itemDetailsRange(item) {
        const record = itemRecord(item)
        const startText = String(value(record, item.kind === "todo" ? "due" : "start", ""))
        const start = new Date(startText)
        if (Number.isNaN(start.getTime()))
            return itemTime(item)
        const dateLine = AppTheme.formatDate(start, Locale.LongFormat)
        if (item.kind === "todo")
            return dateLine + " · " + itemTime(item)
        if (itemAllDay(item)) {
            const endText = String(value(record, "end", ""))
            const end = new Date(endText)
            // Stored end is exclusive: the last covered day is end − 1.
            if (!Number.isNaN(end.getTime()) && endText.length >= 10
                    && sameDay(start, end)) {
                return dateLine + " · " + qsTr("All day")
            }
            if (!Number.isNaN(end.getTime()) && endText.length >= 10) {
                const lastDay = new Date(end.getFullYear(), end.getMonth(),
                                         end.getDate() - 1)
                return dateLine + " – " + AppTheme.formatDate(lastDay, Locale.LongFormat)
                    + " · " + qsTr("All day")
            }
            return dateLine + " · " + qsTr("All day")
        }
        const endText = String(value(record, "end", ""))
        const end = new Date(endText)
        if (Number.isNaN(end.getTime()) || endText.length < 16)
            return dateLine + " · " + itemTime(item)
        if (sameDay(start, end)) {
            // P1-2: same locale-aware clock formatting as itemTime.
            const endMatch = endText.match(/T(\d{2}:\d{2})/)
            const endClock = endMatch ? AppTheme.formatClock(endMatch[1])
                                      : itemTime(item)
            return dateLine + " · " + itemTime(item) + " – " + endClock
        }
        return dateLine + " – " + AppTheme.formatDate(end, Locale.LongFormat)
            + " · " + itemTime(item)
    }

    function itemHour(item) {
        const match = itemDateTime(item).match(/T(\d{2}):/)
        return match ? Number(match[1]) : 0
    }

    function itemAllDay(item) {
        return Boolean(value(itemRecord(item), "allDay", false))
    }

    function itemCompleted(item) {
        const record = itemRecord(item)
        return item.kind === "todo"
            ? Boolean(value(record, "completed", false))
            : Boolean(value(record, "linkedTodoCompleted", false))
    }

    function itemTodoId(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return String(value(record, "seriesId", value(record, "id", "")))
        return String(value(record, "linkedTodoId", ""))
    }

    // P2-9: Qt.darker(color, 1.0) is an identity transform — dropped. The
    // accent fallback also gave every unknown list the accent color, so
    // unknown ids now land in a small stable palette, hashed from the id.
    readonly property var listPalette: ["#0A84FF", "#34C759", "#FF9F0A",
        "#BF5AF2", "#FF375F", "#64D2FF"]

    function listColor(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return String(value(list, "color", AppTheme.accent))
        }
        let hash = 0
        const key = String(id)
        for (let index = 0; index < key.length; index++)
            hash = (hash * 31 + key.charCodeAt(index)) & 0x7fffffff
        return root.listPalette[hash % root.listPalette.length]
    }

    function listName(id) {
        for (let index = 0; index < pim.lists.length; index++) {
            const list = pim.lists[index]
            if (String(value(list, "id", "")) === String(id))
                return String(value(list, "name", qsTr("List")))
        }
        return qsTr("List")
    }

    function itemColor(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return listColor(value(record, "listId", "inbox"))
        return AppTheme.accent
    }

    function itemSubtitle(item) {
        const record = itemRecord(item)
        if (item.kind === "todo")
            return listName(value(record, "listId", "inbox"))
        const location = String(value(record, "location", ""))
        return location.length > 0 ? location
            : (String(value(record, "linkedTodoId", "")).length > 0
                ? qsTr("Linked with Todo") : qsTr("Calendar event"))
    }

    function openItem(item) {
        // P01: single/double click on an existing item first opens the
        // compact detail popover; the editors are reached through its Edit
        // action. Double-click on empty grid time still opens the editor
        // directly (create flow untouched).
        itemDetails.showItem(item)
    }

    function toggleItem(item, completed) {
        const todoId = itemTodoId(item)
        if (todoId.length > 0)
            pim.updateTodo(todoId, { completed: completed })
    }

    function updateEventRange() {
        let first
        let last
        if (activeView === "month") {
            first = dateForMonthCell(0)
            last = dateForMonthCell(41)
        } else if (activeView === "week") {
            first = weekStart
            last = new Date(first.getFullYear(), first.getMonth(), first.getDate() + 6)
        } else if (activeView === "year") {
            first = new Date(selectedDate.getFullYear(), 0, 1)
            last = new Date(selectedDate.getFullYear(), 11, 31)
        } else {
            first = selectedDate
            last = selectedDate
        }
        pim.setEventRange(dateKey(first), dateKey(last))
    }

    function showToday() {
        now = new Date()
        const today = new Date(now.getTime())
        selectedDate = today
        visibleMonth = new Date(today.getFullYear(), today.getMonth(), 1)
        Qt.callLater(updateEventRange)
    }

    function shiftView(offset) {
        if (activeView === "year") {
            selectedDate = new Date(selectedDate.getFullYear() + offset,
                                    selectedDate.getMonth(), selectedDate.getDate())
            visibleMonth = new Date(selectedDate.getFullYear(), 0, 1)
            Qt.callLater(updateEventRange)
            return
        }
        if (activeView === "month") {
            const currentDay = selectedDate.getDate()
            const target = monthDate(offset)
            const lastDay = new Date(target.getFullYear(), target.getMonth() + 1, 0).getDate()
            visibleMonth = target
            selectedDate = new Date(target.getFullYear(), target.getMonth(),
                                    Math.min(currentDay, lastDay))
        } else {
            const days = activeView === "week" ? 7 : 1
            selectedDate = new Date(selectedDate.getFullYear(), selectedDate.getMonth(),
                                    selectedDate.getDate() + offset * days)
            visibleMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1)
        }
        Qt.callLater(updateEventRange)
    }

    function headerTitle() {
        if (activeView === "year")
            return String(visibleMonth.getFullYear())
        if (activeView === "month")
            return AppTheme.formatDate(visibleMonth, "MMMM yyyy")
        if (activeView === "day")
            return AppTheme.formatDate(selectedDate, Locale.LongFormat)
        const end = new Date(weekStart.getFullYear(), weekStart.getMonth(),
                             weekStart.getDate() + 6)
        // Week range follows locale word order via I18n templates (P2-5/I5).
        return AppTheme.formatWeekRange(weekStart, end)
    }

    // The reference pairs the header title with a count line ("67 Messages,
    // 12 Unread"); this is the calendar's equivalent. selectedItems is already
    // bound, so reading it here costs nothing.
    function showStatus(message) {
        statusMessage = message
        statusTimer.restart()
    }

    onVisibleMonthChanged: {
        if (activeView === "month")
            Qt.callLater(updateEventRange)
    }
    onSelectedDateChanged: {
        if (activeView !== "month")
            Qt.callLater(updateEventRange)
    }
    onViewIndexChanged: Qt.callLater(updateEventRange)

    PimClient { id: pim }

    Connections {
        target: pim

        function onOperationSucceeded(operation, itemId) {
            if (operation === "createEvent")
                root.showStatus(qsTr("Event created"))
            else if (operation === "updateEvent")
                root.showStatus(qsTr("Event updated"))
            else if (operation === "updateTodo")
                root.showStatus(qsTr("Task updated in Calendar and Todo"))
            else if (operation === "removeEvent")
                root.showStatus(qsTr("Event removed"))
            else if (operation === "removeTodo")
                root.showStatus(qsTr("Task removed"))
            else if (operation === "importIcalendar")
                root.showStatus(qsTr("Calendar imported"))
            else if (operation === "exportIcalendar")
                root.showStatus(qsTr("Calendar exported"))
            Qt.callLater(root.updateEventRange)
        }
    }

    Timer {
        id: statusTimer
        interval: 3500
        onTriggered: root.statusMessage = ""
    }

    FileDialog {
        id: importDialog
        title: qsTr("Import iCalendar")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("iCalendar files (*.ics)"), qsTr("All files (*)")]
        onAccepted: pim.importIcalendar(selectedFile.toString(), false)
    }

    FileDialog {
        id: exportDialog
        title: qsTr("Export iCalendar")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "ics"
        nameFilters: [qsTr("iCalendar files (*.ics)")]
        onAccepted: pim.exportIcalendar(selectedFile.toString())
    }

    // P01: compact neutral detail popover. Opens on item activation, clamps
    // into the content viewport, and hands the record to the existing
    // editors only through its Edit action. One connection, made once; the
    // pending record is swapped per open.
    property var pendingDetailsRecord: null
    property bool pendingDetailsIsTodo: false

    EventDetailsPopover {
        id: itemDetails
        parent: root.contentItem
        z: 50
        onEditRequested: {
            if (root.pendingDetailsIsTodo)
                taskEditor.openForTodo(root.pendingDetailsRecord)
            else
                eventEditor.openForEvent(root.pendingDetailsRecord)
        }

        function showItem(item) {
            const record = root.itemRecord(item)
            root.pendingDetailsRecord = record
            root.pendingDetailsIsTodo = item.kind === "todo"
            // root-qualified: the popover's own string properties would
            // otherwise shadow the window helper functions here.
            itemTitle = root.itemTitle(item)
            kindColor = root.itemColor(item)
            kindCompleted = root.itemCompleted(item)
            itemTime = root.itemDetailsRange(item)
            itemLocation = String(root.value(record, "location", ""))
            itemNotes = String(root.value(record, "description", ""))
            openAt(null)
        }
    }

    EventEditorDialog {
        id: eventEditor
        parent: root.contentItem
        availableLists: pim.lists
        onSaveRequested: function(uid, event) {
            if (uid.length > 0)
                pim.updateEvent(uid, event)
            else
                pim.createEvent(event)
        }
        onDeleteRequested: uid => pim.removeEvent(uid)
    }

    CalendarTaskEditorDialog {
        id: taskEditor
        objectName: "taskEditorDialog"
        parent: root.contentItem
        availableLists: pim.lists
        onSaveRequested: function(uid, todo) { pim.updateTodo(uid, todo) }
        onDeleteRequested: uid => pim.removeTodo(uid)
    }

    KosSettingsDialog {
        id: settingsDialog
        settings: root.applicationSettings
        applicationName: qsTr("Calendar")
    }

    Shortcut { sequences: [StandardKey.New]; onActivated: eventEditor.openForDate(root.selectedDate) }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.showToday() }
    Shortcut { sequence: "Ctrl+1"; onActivated: root.viewIndex = 0 }
    Shortcut { sequence: "Ctrl+2"; onActivated: root.viewIndex = 1 }
    Shortcut { sequence: "Ctrl+3"; onActivated: root.viewIndex = 2 }
    // P2-9: the Year segment had no keyboard path (REVIEW P2, clue 8).
    Shortcut { sequence: "Ctrl+4"; onActivated: root.viewIndex = 3 }
    Shortcut { sequences: [StandardKey.Find]; onActivated: toolbarSearch.toggle() }

    // Window framework: two flush planes. The sidebar runs the full height of
    // the window at its left edge — macOS keeps the window controls over it —
    // and everything right of it is plain paper. Backgrounds from the shared
    // library (LEDGER.md §5). Both planes reach the very top of the window so
    // the 30px dot band is the planes' own top strip, not a separate
    // titlebar; the corner clipping follows the shared windowCornerRadius
    // rule (square when maximized/fullscreen).
    Item {
        id: windowChrome
        anchors.fill: parent

        // Clip the planes to the window's rounded corners (top-left/right);
        // the corner radius itself comes from KosApplicationWindow.
        Rectangle {
            id: chromeMask
            anchors.fill: parent
            radius: root.windowCornerRadius
            visible: false
            layer.enabled: true
        }
        layer.enabled: root.windowCornerRadius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: chromeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // 窗口顶部 30px 安全区承载窗口圆点,侧栏面与内容面从它下面开始,
        // 工具栏内容与三圆点完整分开。
        readonly property int topSafeInset: 30

        // 自绘窗口圆点:几何照抄 apps/settings/main.qml(14px 圆点、间距 14、
        // 右缘距窗口右 14.5、上缘距窗口顶 10.5),锚定窗口边缘,不嵌在带
        // margin 的工具栏里。
        Row {
            anchors {
                right: parent.right
                rightMargin: 14.5
                top: parent.top
                topMargin: 10.5
            }
            spacing: 14
            z: 10
            Repeater {
                model: [
                    { color: "#28c840", act: "max" },
                    { color: "#febc2e", act: "min" },
                    { color: "#ff5f57", act: "close" }
                ]
                delegate: Rectangle {
                    id: windowDot
                    required property var modelData
                    width: 14; height: 14; radius: 7
                    color: modelData.color
                    // P1-A6b: 键盘聚焦时给最小可见反馈（常态外观 0.85 不变）。
                    opacity: activeFocus ? 1.0 : 0.85
                    border.width: activeFocus ? 1 : 0
                    border.color: AppTheme.text
                    activeFocusOnTab: true
                    function activate() {
                        if (modelData.act === "min")
                            root.showMinimized()
                        else if (modelData.act === "max")
                            root.visibility === Window.Maximized
                                ? root.showNormal() : root.toggleFullScreen()
                        else
                            root.close()
                    }
                    Keys.onReturnPressed: windowDot.activate()
                    Keys.onEnterPressed: windowDot.activate()
                    Keys.onSpacePressed: windowDot.activate()
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.act === "min" ? qsTr("Minimize")
                        : modelData.act === "max" ? qsTr("Zoom") : qsTr("Close")
                    MouseArea {
                        // P1-A6b: 命中区放大到 22×22 居中（中心距 28 不重叠），
                        // 视觉圆点仍是 14×14。
                        anchors.centerIn: parent
                        width: 22; height: 22
                        cursorShape: Qt.PointingHandCursor
                        onClicked: windowDot.activate()
                    }
                }
            }
        }

        // LQ05: the sidebar is the second persistent glass surface (2/2).
        // The calendar has no wallpaper or scrolling content behind it, so the
        // flat underlay stands in for the sampled desktop: regular fill (§3,
        // white .58 / #1C1C1E .52) over 212 / 53 composites exactly to the
        // reference's measured 237 light plane and the existing 40 dark plane.
        Rectangle {
            id: sidebarPlane
            objectName: "calendarSidebarUnderlay"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: sidebar.width
            color: root.tahoeDark ? "#353535" : "#D4D4D4"
        }
        LiquidSurface {
            id: sidebarMaterial
            objectName: "calendarSidebarMaterial"
            anchors.fill: sidebarPlane
            radius: 0
            tintColor: root.tahoeDark ? "#1C1C1E" : "#FFFFFF"
            tintStrength: root.tahoeDark ? 0.52 : 0.58
            // Unsampled surface: pigmented diffuse finish only, never a fake
            // blur; the flat reference plane carries no specular glint.
            diffuseStrength: 1
            reflectionStrength: 0
            rimColor: "transparent"
        }

        Rectangle {
            anchors.left: sidebarPlane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.tahoe.contentPlane

            // L01: the sidebar and main canvas are one continuous plane pair
            // joined by a single hairline at their seam.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: root.tahoe.separator
            }
        }

        // L02: the unified toolbar. One 40px row directly under the 30px dot
        // band, floating above both planes (the planes still cover the whole
        // window from y=0). Left: sidebar toggle, add. Right: search toggle,
        // more. The segmented control is centred over the *current main
        // region* (L03): sidebar expanded → x sidebarWidth..width, collapsed
        // → x 0..width, with a binding-animated x so it follows the collapse.
        Item {
            id: toolbar
            objectName: "calendarToolbar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset
            height: root.tahoe.toolbarHeight
            z: 5

            // Dynamic main-region centre: sidebar width animates, so the
            // centre binding tracks it continuously.
            readonly property real mainLeft: sidebar.width
            readonly property real mainWidth: width - mainLeft

            // LQ02: L1 persistent material 1/2 — one floating regular-glass
            // capsule carrying the whole toolbar. It is intentionally static
            // (no backdrop): the toolbar sits above the opaque window planes,
            // which are flush, so there is no scrolling content under it to
            // refract; the bezel, specular arc and outer shadow carry the
            // material instead. Persistent glass stays 1/2 until the sidebar
            // becomes the second (LQ05).
            Item {
                id: toolbarMaterial
                objectName: "calendarToolbarMaterial"
                anchors.fill: parent
                anchors.leftMargin: root.tahoe.toolbarFloat
                anchors.rightMargin: root.tahoe.toolbarFloat
                z: -1

                LiquidOuterShadow {
                    anchors.fill: parent
                    radius: root.tahoe.toolbarRadius
                    shadowLevel: 2
                    outwardOffset: LiquidStyle.controlShadowOutset
                }
                LiquidSurface {
                    anchors.fill: parent
                    radius: root.tahoe.toolbarRadius
                    // Regular fill from liquid-spec §3: white .58 / #1C1C1E .52.
                    tintColor: root.tahoeDark ? "#1C1C1E" : "#FFFFFF"
                    tintStrength: root.tahoeDark ? 0.52 : 0.58
                    rimColor: root.tahoeDark
                        ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.45)
                    edgeWidth: 14
                    reflectionStrength: 1
                }
            }

            ToolbarButton {
                id: sidebarToggleButton
                objectName: "toolbarSidebarToggle"
                anchors.left: parent.left
                anchors.leftMargin: root.tahoe.toolbarInsetLeft
                anchors.verticalCenter: parent.verticalCenter
                iconName: "panel"
                hint: root.sidebarExpanded ? qsTr("Hide sidebar")
                                           : qsTr("Show sidebar")
                onClicked: root.sidebarExpanded = !root.sidebarExpanded
            }

            ToolbarButton {
                id: addButton
                objectName: "toolbarAdd"
                anchors.left: sidebarToggleButton.right
                anchors.leftMargin: root.tahoe.toolbarGap
                anchors.verticalCenter: parent.verticalCenter
                iconName: "plus"
                hint: qsTr("Add event")
                enabled: pim.connected && pim.writable
                onClicked: eventEditor.openForDate(root.selectedDate)
            }

            LiquidSegmentedControl {
                id: viewSegment
                objectName: "toolbarViewSegment"
                anchors.verticalCenter: parent.verticalCenter
                x: toolbar.mainLeft
                   + Math.max(0, (toolbar.mainWidth - width) / 2)
                width: root.tahoe.segmentWidth
                height: root.tahoe.segmentHeight
                // L05: strict mutual exclusion with the search field. The
                // segment is hidden the moment the search opens and only
                // reappears once the field has fully collapsed (width == 0) —
                // sequential transition, no cross-fade, so no frame ever
                // shows both text areas.
                opacity: toolbarSearch.active || toolbarSearch.width > 0 ? 0 : 1
                visible: opacity > 0
                // R100/C05+L03: the reference's segment reads Day · Week ·
                // Month · Year — granularity ascending, left to right — and
                // L03 words it "Day/week/month segment". Ours was the exact
                // reverse. `viewIndex` keeps its own published contract
                // (0=month / 1=week / 2=day / 3=year: `activeView` :255,
                // Ctrl+1..4, `--view` :1054, the page cache :2495
                // and the review harness), so the segment mirrors it instead
                // of redefining it: segment i = viewIndex (2 - i) for i <= 2,
                // and the 4th segment (i == 3) maps to the year view. Weeks
                // still land on segment 1, so the pill's measured geometry
                // (R097/R098) is untouched.
                labels: [qsTr("Day"), qsTr("Week"), qsTr("Month"), qsTr("Year")]
                currentIndex: root.viewIndex <= 2 ? 2 - root.viewIndex : 3
                // LQ03: this capsule sits ON the toolbar's L1 glass, so it must
                // not draw a second LiquidSurface (glass-on-glass is banned).
                // materialForm paints a plain track + opaque pill; measured
                // against the reference: track 228x28 r=14, pill inset 2
                // (24 high, 52 wide in a 56 slot), track α .025 over the
                // plane (249..253), pill #E7E7E7 (230..235), hairline edge
                // (~222 at the rounded ends). All four labels stay at
                // labelPrimary — only the pill marks the selection.
                materialForm: true
                backgroundColor: root.tahoe.segmentTrack
                // The default material outline (α .14) is tuned for a dialog
                // plane; here it drew a crisp grey ring the reference does not
                // have (reference top edge is 249..253, i.e. no visible line;
                // only the rounded ends darken to ~222 through edge AA). α .05
                // keeps a hairline hint without the ring. Extrapolated value.
                borderColor: root.tahoeDark
                    ? Qt.rgba(1, 1, 1, 0.10)
                    : Qt.rgba(0x28 / 255, 0x40 / 255, 0x64 / 255, 0.05)
                selectionColor: root.tahoe.segmentPill
                textColor: root.tahoe.labelPrimary
                // R099/C05: the reference has NO muted label state here — all
                // four segment labels carry the same pure-black ink (peak 0,
                // top-5% mean 15–23) and the pill alone marks the selection.
                // `labelSecondary` (≈147 at 1:1) was 130 levels too light.
                mutedTextColor: root.tahoe.labelPrimary
                onSelectionRequested: index =>
                    root.viewIndex = index <= 2 ? 2 - index : 3
            }

            ToolbarButton {
                id: searchToggleButton
                objectName: "toolbarSearchToggle"
                anchors.right: moreButton.left
                anchors.rightMargin: root.tahoe.toolbarGap
                anchors.verticalCenter: parent.verticalCenter
                iconName: "search"
                hint: qsTr("Search")
                onClicked: toolbarSearch.toggle()
            }

            // L05: inline search, strictly inside the 40px toolbar. Opening
            // hides the segment (fade above) and grows the field leftward
            // from the search button; no second row, no overlap with the dots
            // band or the left button group. Idempotent open/close; Escape
            // closes and clears from anywhere in the window. z above the
            // segment so the width transition cross-fades cleanly instead of
            // compositing into it.
            Item {
                id: toolbarSearch
                objectName: "toolbarSearch"
                z: 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: searchToggleButton.left
                anchors.rightMargin: 6
                readonly property int maxWidth: Math.min(280, Math.max(0,
                    toolbar.mainWidth - 2 * root.tahoe.toolbarButtonSize
                        - 3 * root.tahoe.toolbarGap - 24))
                width: active ? maxWidth : 0
                height: root.tahoe.toolbarButtonSize
                visible: width > 0
                property bool active: false
                // Deferred close for clicks elsewhere in the window: the blur
                // arrives during the press, but the click target may itself
                // want the field (the search toggle). Waiting one event-loop
                // turn lets the press target act first, and the deferred close
                // then no-ops if toggle() already handled it.
                property bool blurPending: false
                // True between open() and the field actually being visible
                // (width animation finished). The delayed focus below is
                // armed only in this window; a close() cancels it. Any blur
                // during "opening" is the field's own geometry settling —
                // the input must not close itself because forceActiveFocus
                // ran while width was still 0.
                property bool opening: false
                function open() {
                    blurPending = false
                    if (active) return
                    active = true
                    opening = true
                    // Focus once the field is actually on screen: while the
                    // width animates from 0 the item is not laid out yet, and
                    // an immediate forceActiveFocus lands on a zero-size item
                    // whose subsequent blur re-triggers the close path.
                    focusTimer.restart()
                }
                function close() {
                    blurPending = false
                    opening = false
                    focusTimer.stop()
                    if (!active) return
                    active = false
                    input.text = ""
                    root.searchQuery = ""
                    input.focus = false
                }
                function toggle() { active ? close() : open() }
                // Any blur-driven close clears the query: closing the search
                // must never leave a hidden filter running.
                function requestBlurClose() {
                    if (blurPending || opening) return
                    blurPending = true
                    Qt.callLater(function() {
                        if (!blurPending || !toolbarSearch.active) return
                        close()
                    })
                }

                // Focus after the width animation settles (motionFast ~150ms
                // plus one frame). If the search was closed before this fires
                // the timer is stopped and nothing happens.
                Timer {
                    id: focusTimer
                    interval: AppTheme.motionFast + 50
                    onTriggered: {
                        if (!toolbarSearch.active) return
                        toolbarSearch.opening = false
                        input.forceActiveFocus()
                    }
                }

                Behavior on width { NumberAnimation {
                    duration: AppTheme.motionFast; easing.type: Easing.OutCubic } }

                // The field is clipped by its own width, so the text/input
                // never leaks outside during the width animation.
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.tahoe.searchFill
                    border.width: input.activeFocus ? 1 : 0
                    border.color: root.tahoe.accent
                    clip: true

                    TextInput {
                        id: input
                        objectName: "toolbarSearchInput"
                        Accessible.name: qsTr("Search")
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.tahoe.labelPrimary
                        font.pixelSize: root.tahoe.categoryFontSize
                        selectionColor: root.tahoe.accent
                        text: root.searchQuery
                        onTextEdited: root.searchQuery = text
                        onActiveFocusChanged: {
                            // Blur from clicking elsewhere: defer one event-
                            // loop turn so the click target (e.g. the search
                            // toggle) acts first and the deferred close
                            // no-ops. Blurs while the field is still opening
                            // (geometry settling before the delayed focus)
                            // are ignored; blur caused by close() itself runs
                            // after active went false and is also ignored.
                            if (!activeFocus && toolbarSearch.active
                                    && !toolbarSearch.opening
                                    && !toolbarSearch.blurPending)
                                toolbarSearch.requestBlurClose()
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        visible: input.text.length === 0
                        text: qsTr("Search")
                        color: root.tahoe.labelSecondary
                        font.pixelSize: root.tahoe.categoryFontSize
                    }
                }
            }

            // More: three dots, host-owned plain row like its neighbours.
            ToolbarButton {
                id: moreButton
                objectName: "toolbarMore"
                anchors.right: parent.right
                anchors.rightMargin: root.tahoe.toolbarInsetRight
                anchors.verticalCenter: parent.verticalCenter
                iconName: "more"
                hint: qsTr("Calendar actions")
                onClicked: {
                    // LQ10: right-align the visible card to the button and
                    // keep the reserved shadow gutter inside the window.
                    const inset = root.tahoe.menuShadowInset
                    const surface = root.tahoe.menuWidth
                    const maxX = root.width - moreButton.x
                                 - (surface + 2 * inset)
                    const popupX = Math.min(moreButton.width - surface - inset,
                                            maxX)
                    actionsMenu.popup(moreButton, popupX,
                                      moreButton.height + 2 - inset)
                }
            }

            // L05: Escape always reaches the open search, whichever item in
            // this window holds focus — the input's own key handler is not
            // enough once it has lost focus. Scoped to the toolbar, enabled
            // only while the search is open.
            Shortcut {
                sequence: "Escape"
                enabled: toolbarSearch.active
                onActivated: toolbarSearch.close()
            }

            // LQ10: app-owned menu presentation. The menu is the one L2
            // transient glass surface (regular fill + E3 shadow, spec §4) and
            // its rows stay plain — no second glass layer. The popup grows by
            // a 36px shadow gutter on every side so the E3 shadow is never
            // clipped; only the inset card is visible.
            Menu {
                id: actionsMenu
                width: root.tahoe.menuWidth + 2 * root.tahoe.menuShadowInset
                padding: root.tahoe.menuShadowInset
                         + root.tahoe.menuSurfaceInset

                background: Item {
                    Rectangle {
                        id: menuPlane
                        anchors.fill: parent
                        anchors.margins: root.tahoe.menuShadowInset
                        radius: root.tahoe.menuRadius
                        color: AppTheme.neutralPlane
                        border.width: 1
                        border.color: root.tahoeDark
                            ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)
                    }
                    LiquidOuterShadow {
                        anchors.fill: menuPlane
                        radius: root.tahoe.menuRadius
                        shadowLevel: 3
                    }
                    LiquidSurface {
                        anchors.fill: menuPlane
                        radius: root.tahoe.menuRadius
                        tintColor: root.tahoeDark ? "#1C1C1E" : "#FFFFFF"
                        tintStrength: root.tahoeDark ? 0.52 : 0.58
                        rimColor: root.tahoeDark
                            ? Qt.rgba(1, 1, 1, 0.30)
                            : Qt.rgba(1, 1, 1, 0.45)
                        edgeWidth: 14
                        reflectionStrength: 1
                    }
                }

                MenuActionRow {
                    text: qsTr("New task…")
                    iconName: "plus"
                    enabled: pim.connected && pim.writable
                    onTriggered: taskEditor.openForTodo(null)
                }
                MenuGroupSeparator {}
                MenuActionRow {
                    text: qsTr("Import iCalendar…")
                    iconName: "download"
                    enabled: pim.connected && pim.writable
                    onTriggered: importDialog.open()
                }
                MenuActionRow {
                    text: qsTr("Export iCalendar…")
                    iconName: "preview"
                    enabled: pim.connected && pim.ready
                    onTriggered: exportDialog.open()
                }
                MenuGroupSeparator {}
                MenuActionRow {
                    text: qsTr("Calendar settings")
                    iconName: "settings"
                    onTriggered: settingsDialog.open()
                }
            }
        }

        // Same collapse contract KosSidebar uses: the body keeps its expanded
        // geometry while the viewport closes, so filters, scroll position and
        // focus survive. Flush and square instead of a floating card.
        Item {
            id: sidebar
            objectName: "applicationSidebar"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset + root.tahoe.toolbarHeight
            anchors.bottom: parent.bottom
            width: root.sidebarExpanded ? root.tahoe.sidebarWidth : 0
            // Clip only while collapsing/expanding so the animated width never
            // spills onto the content plane; fully expanded the clip is off,
            // so the top glass pill's shadow can reach into the safe area.
            clip: !root.sidebarExpanded || width < root.tahoe.sidebarWidth
            enabled: root.sidebarExpanded

            Behavior on width {
                NumberAnimation {
                    duration: AppTheme.motionNormal
                    easing.type: Easing.InOutCubic
                }
            }

            ColumnLayout {
                width: root.tahoe.sidebarWidth
                height: sidebar.height
                spacing: 0

                // L04: the sidebar no longer carries its own toolbar row or a
                // standing search field — those live in the unified toolbar.
                // The body starts with the Today row.

                SidebarRow {
                    id: todayNavigation

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.tahoe.rowHeight
                    text: qsTr("Today")
                    detail: AppTheme.formatDate(root.now, "ddd")
                    markerColor: root.tahoe.accent
                    markerFilled: true
                    onClicked: root.showToday()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 3
                    Layout.bottomMargin: 3
                    color: root.tahoe.separator
                }

                // S02/S03: categories and task lists directly under the
                // Today row; the mini calendar anchors the sidebar bottom
                // (M01). The mid section is one real scrolling viewport
                // (Flickable over a naturally-sized Column): fillHeight with
                // minimumHeight 0, so in a short window it is this area that
                // scrolls — every group heading, category row and task list
                // stays reachable — while the fixed mini-calendar block
                // below can never be pushed off-window.
                Flickable {
                    id: categoriesViewport
                    objectName: "calendarCategoriesViewport"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    contentWidth: width
                    contentHeight: categoriesColumn.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: categoriesColumn
                        width: categoriesViewport.width
                        spacing: 0

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.tahoe.categoryInset
                            Layout.topMargin: root.tahoe.categoryHeadingTop
                            Layout.bottomMargin: root.tahoe.categoryHeadingBottom
                            Layout.preferredHeight: 16
                            text: qsTr("Calendars")
                            color: root.tahoe.labelSecondary
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Events")
                            checkable: true
                            boxColor: root.tahoe.accent
                            checked: root.showEvents
                            onToggled: root.showEvents = checked
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Scheduled tasks")
                            checkable: true
                            boxColor: root.tahoe.positive
                            checked: root.showTasks
                            onToggled: root.showTasks = checked
                        }

                        CategoryRow {
                            Layout.fillWidth: true
                            text: qsTr("Show completed")
                            checkable: true
                            nested: true
                            boxColor: root.tahoe.warning
                            checked: root.showCompletedTasks
                            enabled: root.showTasks
                            Accessible.name: qsTr("Show completed tasks")
                            onToggled: root.showCompletedTasks = checked
                        }

                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: root.tahoe.categoryInset
                            Layout.topMargin: root.tahoe.categoryHeadingTop
                            Layout.bottomMargin: root.tahoe.categoryHeadingBottom
                            Layout.preferredHeight: 16
                            text: qsTr("Task lists")
                            color: root.tahoe.labelSecondary
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                        }

                        Repeater {
                            model: pim.lists

                            delegate: CategoryRow {
                                id: listLegend

                                required property var modelData

                                Layout.fillWidth: true
                                swatchOnly: true
                                text: String(root.value(listLegend.modelData,
                                                        "name", qsTr("List")))
                                boxColor: String(root.value(listLegend.modelData,
                                    "color", root.tahoe.accent))
                            }
                        }
                    }
                }

                // M01: the mini calendar is a fixed, never-compressed block
                // (26 heading + 18 weekday + 6*21 rows = 170) pinned to the
                // sidebar bottom with a 12px bottom margin. min/preferred/max
                // all pin the same height, so no layout state can shrink or
                // stretch it.
                Item {
                    id: miniCalendar

                    readonly property real fixedHeight:
                        headingRow.height + 18 + 6 * cellHeight

                    Layout.fillWidth: true
                    Layout.leftMargin: root.tahoe.categoryInset
                    Layout.rightMargin: root.tahoe.categoryInset
                    Layout.bottomMargin: 12
                    Layout.minimumHeight: fixedHeight
                    Layout.preferredHeight: fixedHeight
                    Layout.maximumHeight: fixedHeight
                    readonly property real cellWidth: width / 7
                    readonly property real cellHeight: 21

                    // M02: month title centred between two equal 28x28
                    // arrows; title and grid share the same inset area.
                    RowLayout {
                        id: headingRow
                        objectName: "miniCalendarHeading"
                        width: parent.width
                        height: 26
                        spacing: 2

                        KosToolButton {
                            id: prevMonthButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            text: ""
                            flat: true
                            Accessible.name: qsTr("Previous month")
                            onClicked: root.visibleMonth = root.monthDate(-1)

                            MiniMonthChevron {
                                anchors.centerIn: parent
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: AppTheme.formatDate(root.visibleMonth, "MMMM yyyy")
                            color: root.tahoe.labelPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        KosToolButton {
                            id: nextMonthButton
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            text: ""
                            flat: true
                            Accessible.name: qsTr("Next month")
                            onClicked: root.visibleMonth = root.monthDate(1)

                            MiniMonthChevron {
                                anchors.centerIn: parent
                                rotation: 180
                            }
                        }
                    }

                    // Weekday row: 10px secondary, seven equal columns.
                    Repeater {
                        model: 7

                        delegate: Label {
                            required property int index
                            x: index * miniCalendar.cellWidth
                            y: headingRow.height
                            width: miniCalendar.cellWidth
                            height: 18
                            text: root.weekdayName(index, Locale.NarrowFormat)
                            color: root.tahoe.labelSecondary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }

                    Repeater {
                        model: 42

                        delegate: AbstractButton {
                            id: miniDay

                            required property int index
                            readonly property date cellDate: root.dateForMonthCell(index)
                            readonly property bool inVisibleMonth:
                                cellDate.getMonth() === root.visibleMonth.getMonth()
                            readonly property bool selected:
                                root.sameDay(cellDate, root.selectedDate)
                            readonly property bool today:
                                root.sameDay(cellDate, root.now)

                            x: (index % 7) * miniCalendar.cellWidth
                            y: headingRow.height + 18
                                + Math.floor(index / 7) * miniCalendar.cellHeight
                            width: miniCalendar.cellWidth
                            height: miniCalendar.cellHeight
                            hoverEnabled: true
                            opacity: inVisibleMonth ? 1 : 0.5
                            Accessible.name: AppTheme.formatDate(cellDate, Locale.LongFormat)
                            onClicked: {
                                root.selectedDate = cellDate
                                if (cellDate.getMonth()
                                    !== root.visibleMonth.getMonth()) {
                                    root.visibleMonth = new Date(
                                        cellDate.getFullYear(),
                                        cellDate.getMonth(), 1)
                                }
                            }

                            // M03: Control stretches contentItem to the cell,
                            // which warped a direct circle of this size into an
                            // ellipse. So the contentItem is a plain filler
                            // Item and the fixed circle sits centred inside it.
                            // (R094: 20 -> 15, the ref's own disc. R117: ->
                            // tahoe.miniDisc = 18, M04's literal.)
                            contentItem: Item {
                                Rectangle {
                                    width: root.tahoe.miniDisc
                                    height: root.tahoe.miniDisc
                                    radius: width / 2
                                    anchors.centerIn: parent
                                    // P2-9: white 11px DemiBold on todayRed
                                    // #E5484D measured 3.91:1 and on
                                    // selectionDisc #8E8E93 3.26:1 (WCAG,
                                    // python3; small text needs 4.5). The
                                    // shared tokens stay untouched — today
                                    // markers and the year view depend on
                                    // them — so the mini month applies the
                                    // minimal Qt.darker factor that clears
                                    // 4.5: white-on-#D24247 = 4.56, white-
                                    // on-#76767A = 4.52. Slightly deeper
                                    // discs than the ref; deviation noted
                                    // in state.md.
                                    color: miniDay.today
                                        ? Qt.darker(AppTheme.todayRed, 1.09)
                                        : (miniDay.selected
                                            ? Qt.darker(root.tahoe.selectionDisc, 1.20)
                                            : (miniDay.hovered
                                                ? root.tahoe.rowHoverFill : "transparent"))

                                    Label {
                                        anchors.centerIn: parent
                                        text: String(miniDay.cellDate.getDate())
                                        color: miniDay.today || miniDay.selected
                                            ? "#FFFFFF"
                                            : root.tahoe.labelPrimary
                                        font.pixelSize: 11
                                        font.weight: miniDay.today || miniDay.selected
                                            ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }

                            background: null
                        }
                    }
                }

                // S05: no standing status card. A small, low-key one-liner
                // only while the PIM service is unreachable — no placeholder
                // when healthy.
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.tahoe.categoryInset
                    Layout.rightMargin: root.tahoe.categoryInset
                    Layout.bottomMargin: 6
                    visible: !pim.connected
                    text: qsTr("Waiting for the local PIM service")
                    color: root.tahoe.labelSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // Content plane: the unified toolbar sits above; below it a title row
        // (date heading + prev/Today/next, L06/L07 review later) and then the
        // view.
        ColumnLayout {
            anchors.left: sidebarPlane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: parent.topSafeInset + root.tahoe.toolbarHeight
            anchors.bottom: parent.bottom
            spacing: 0

            // L06: 48px date heading band. Single 27px localised title on the
            // left (20 inset, strictly limited to the space before the
            // navigation group — long week/day titles elide, never squeeze
            // the nav); L07 subdued nav group on the right. No subtitle line.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.tahoe.dateBandHeight

                Label {
                    id: dateTitle
                    objectName: "dateTitle"
                    anchors.left: parent.left
                    anchors.leftMargin: root.tahoe.dateBandInset
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, dateNavGroup.x
                                       - root.tahoe.dateBandInset - 16)
                    text: root.headerTitle()
                    color: root.tahoe.labelPrimary
                    font.pixelSize: root.tahoe.dateTitleSize
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                BusyIndicator {
                    anchors.right: dateNavGroup.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    running: pim.busy
                    visible: running
                }

                RowLayout {
                    id: dateNavGroup
                    objectName: "dateNavGroup"
                    anchors.right: parent.right
                    anchors.rightMargin: root.tahoe.dateBandInset
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    DateNavButton {
                        objectName: "dateNavPrevious"
                        hint: qsTr("Previous period")
                        arrowRotation: 90
                        onClicked: root.shiftView(-1)
                    }
                    DateNavButton {
                        objectName: "dateNavToday"
                        hint: qsTr("Show today")
                        text_: qsTr("Today")
                        onClicked: root.showToday()
                    }
                    DateNavButton {
                        objectName: "dateNavNext"
                        hint: qsTr("Next period")
                        arrowRotation: -90
                        onClicked: root.shiftView(1)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                Layout.fillHeight: false

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.tahoe.separator
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.statusMessage.length > 0 || (pim.errorMessage.length > 0 && pim.ready)

                // A5: the row clears itself after 3.5s, which a screen reader
                // can neither announce on appearance nor re-read afterwards.
                // The Alert role asks the platform to speak it, and hovering
                // the row pauses the timer so the text stays put while read.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            statusTimer.stop()
                        else
                            statusTimer.restart()
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: pim.errorMessage.length > 0 ? pim.errorMessage : root.statusMessage
                    color: pim.errorMessage.length > 0
                        ? root.tahoe.statusWarning : root.tahoe.statusPositive
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.Alert
                    Accessible.name: text
                }
            }

            KosPageCache {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.viewIndex
                // Keep the active view and one recent view warm. Retaining all
                // four would only defer StackLayout's original memory cost.
                cacheLimit: 2
                pages: [monthPage, weekPage, dayPage, yearPage]

                Component {
                    id: monthPage
                    ColumnLayout {
                        spacing: 0

                        CalendarMonthView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visibleDate: root.visibleMonth
                            selectedDate: root.selectedDate
                            currentTime: root.now
                            firstDayOfWeek: root.localeFirstDayOfWeek
                            itemsForDate: root.itemsForDate
                            itemTitle: root.itemTitle
                            itemColor: root.itemColor
                            itemCompleted: root.itemCompleted
                            onDateSelected: function(date) { root.selectedDate = date }
                            onItemActivated: function(item) { root.openItem(item) }
                            onCreateRequested: function(date) { eventEditor.openForDate(date) }
                        }

                    }
                }

                Component {
                    id: weekPage
                    CalendarScheduleView {
                        id: weekSchedule
                        firstDate: root.weekStart
                        currentTime: root.now
                        dayCount: 7
                        selectedDate: root.selectedDate
                        itemsForDate: root.itemsForDate
                        itemTitle: root.itemTitle
                        itemSecondary: root.itemSecondary
                        itemColor: root.itemColor
                        itemCompleted: root.itemCompleted
                        itemAllDay: root.itemAllDay
                        itemRecord: root.itemRecord
                        itemHour: root.itemHour
                        onDateSelected: function(date) { root.selectedDate = date }
                        onItemActivated: function(item) { root.openItem(item) }
                        onCreateRequested: function(date, hour) {
                            eventEditor.openForDate(date, hour)
                        }
                        onVisibleChanged: {
                            if (visible) root.scheduleViewport = weekSchedule.contentViewport
                            else if (root.scheduleViewport === weekSchedule.contentViewport)
                                root.scheduleViewport = null
                        }
                        Component.onCompleted: {
                            if (visible) root.scheduleViewport = weekSchedule.contentViewport
                        }
                    }
                }

                Component {
                    id: dayPage
                    CalendarScheduleView {
                        id: daySchedule
                        firstDate: root.selectedDate
                        currentTime: root.now
                        dayCount: 1
                        selectedDate: root.selectedDate
                        itemsForDate: root.itemsForDate
                        itemTitle: root.itemTitle
                        itemSecondary: root.itemSecondary
                        itemColor: root.itemColor
                        itemCompleted: root.itemCompleted
                        itemAllDay: root.itemAllDay
                        itemRecord: root.itemRecord
                        itemHour: root.itemHour
                        onDateSelected: function(date) { root.selectedDate = date }
                        onItemActivated: function(item) { root.openItem(item) }
                        onCreateRequested: function(date, hour) {
                            eventEditor.openForDate(date, hour)
                        }
                        onVisibleChanged: {
                            if (visible) root.scheduleViewport = daySchedule.contentViewport
                            else if (root.scheduleViewport === daySchedule.contentViewport)
                                root.scheduleViewport = null
                        }
                        Component.onCompleted: {
                            if (visible) root.scheduleViewport = daySchedule.contentViewport
                        }
                    }
                }

                Component {
                    id: yearPage

                    // R-YEAR step 1: 12-month skeleton from the mini-month
                    // idiom. Step 2: day-cell click selects (stays in year
                    // view; today red disc / selected gray disc, mini-month
                    // idiom), event dots per day, month-label click still
                    // routes to month view.
                    Item {
                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            columns: 3
                            columnSpacing: 16
                            rowSpacing: 12

                            Repeater {
                                model: 12

                                ItemDelegate {
                                    id: yearMonthCell
                                    required property int index
                                    readonly property date monthStart:
                                        new Date(root.visibleMonth.getFullYear(), index, 1)
                                    readonly property int firstOffset:
                                        (monthStart.getDay() - root.localeFirstDayOfWeek + 7) % 7
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    onClicked: {
                                        root.selectedDate = monthStart
                                        root.visibleMonth = monthStart
                                        root.viewIndex = 0
                                    }

                                    contentItem: ColumnLayout {
                                        spacing: 4

                                        Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: AppTheme.formatDate(
                                                yearMonthCell.monthStart, "MMMM")
                                            color: root.tahoe.labelPrimary
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 7
                                            columnSpacing: 0
                                            rowSpacing: 0

                                            Repeater {
                                                model: 42

                                                Item {
                                                    id: yearDayCell
                                                    required property int index
                                                    readonly property date cellDate:
                                                        new Date(
                                                            yearMonthCell.monthStart.getFullYear(),
                                                            yearMonthCell.monthStart.getMonth(),
                                                            index - yearMonthCell.firstOffset + 1)
                                                    readonly property bool inMonth:
                                                        cellDate.getMonth()
                                                            === yearMonthCell.monthStart.getMonth()
                                                    readonly property bool isToday:
                                                        cellDate.getFullYear() === root.now.getFullYear()
                                                            && cellDate.getMonth() === root.now.getMonth()
                                                            && cellDate.getDate() === root.now.getDate()
                                                    readonly property bool isSelected:
                                                        yearDayCell.inMonth && root.sameDay(cellDate, root.selectedDate)
                                                    readonly property int eventCount:
                                                        yearDayCell.inMonth
                                                            ? root.itemsForDate(yearDayCell.cellDate).length
                                                            : 0
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 20

                                                    // P1-9 (A9): the year cell was
                                                    // pointer-only; add keyboard
                                                    // focus plus an accessible
                                                    // identity (date + item count).
                                                    activeFocusOnTab: yearDayCell.inMonth
                                                    Keys.onReturnPressed: yearDayCell.activate()
                                                    Keys.onSpacePressed: yearDayCell.activate()
                                                    function activate() {
                                                        if (yearDayCell.inMonth)
                                                            root.selectedDate = yearDayCell.cellDate
                                                    }
                                                    Accessible.role: yearDayCell.inMonth
                                                        ? Accessible.ListItem : Accessible.NoRole
                                                    Accessible.name: yearDayCell.inMonth
                                                        ? qsTr("%1; %2 items").arg(
                                                              AppTheme.formatDate(cellDate, Locale.LongFormat)).arg(eventCount)
                                                        : ""
                                                    Accessible.focusable: true
                                                    Accessible.onPressAction: yearDayCell.activate()

                                                    // Focus ring only: resting
                                                    // cell keeps its plain look.
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: "transparent"
                                                        border.color: root.tahoe.accent
                                                        border.width: 1
                                                        visible: yearDayCell.activeFocus
                                                    }

                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 14
                                                        height: 14
                                                        radius: 7
                                                        color: yearDayCell.isToday
                                                            ? AppTheme.todayRed
                                                            : (yearDayCell.isSelected
                                                                ? root.tahoe.selectionDisc
                                                                : "transparent")
                                                    }

                                                    Rectangle {
                                                        // Extrapolated (no year-view reference): mini-month idiom dot.
                                                        visible: yearDayCell.eventCount > 0
                                                        width: 3
                                                        height: 3
                                                        radius: 1.5
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.bottom: parent.bottom
                                                        color: root.tahoe.accent
                                                    }

                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: yearDayCell.inMonth
                                                            ? String(yearDayCell.cellDate.getDate())
                                                            : ""
                                                        color: yearDayCell.isToday || yearDayCell.isSelected
                                                            ? "#FFFFFF"
                                                            : root.tahoe.labelPrimary
                                                        font.pixelSize: 10
                                                        font.weight: yearDayCell.isToday || yearDayCell.isSelected
                                                            ? Font.DemiBold : Font.Normal
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: yearDayCell.inMonth
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.selectedDate = yearDayCell.cellDate
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: updateEventRange()
}
