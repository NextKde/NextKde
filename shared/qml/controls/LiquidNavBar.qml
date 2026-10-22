import QtQuick
import QtQuick.Window
import "../foundation" as Foundation
import QtQuick.Controls as Controls
import Qt5Compat.GraphicalEffects

// Desktop click navigation with the existing spring/display animation layers.
// Shared LiquidSurface supplies directional reflection and optional in-window
// sampling; active delegates retain their existing placement beneath the lens.
Item {
    id: root

    // ---- Public API (mirrors the Vue component props) ----
    property var model: []            // [{ id, label?, icon }] - icon is a text symbol
    property int currentIndex: 0
    property string size: "medium"    // tiny | small | medium | large | XL
    property real barHeight: 0        // 0 = use preset height; otherwise scale the
                                      // chosen preset proportionally to this height
    property real itemWidthOverride: 0 // >0 widens each item beyond the preset (e.g.
                                      // to fit a 4-char CJK label) without changing
                                      // the preset height/pill look.
    property bool sizeToLabels: false
    property real labelHorizontalPadding: 10
    property bool disabled: false
    property color accentColor: "#ff453a"
    // Foreground painted over the selected thumb. Liquid form historically
    // uses the accent itself over a white pill; Material callers can provide
    // the matching on-primary role for a filled primary thumb.
    property color selectedItemColor: accentColor
    property color itemColor: "#ffffff"
    property color trackColor: Qt.rgba(1, 1, 1, 0.10)
    property real labelFontPixelSize: 0 // 0 = use the selected size preset
    property int labelFontWeight: Font.Normal
    property bool alwaysShowGlass: false
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property LiquidBackdrop backdrop: LiquidStyle.backdropForItem(root, root.Window.window)
    readonly property bool sampling: _isActive && lensSurface.sampling
    HoverHandler { id: materialHover }
    property int _pressedIndex: -1
    // ── Form ──────────────────────────────────────────────────────────────
    // A tonal host draws the Material 3 navigation: one flat container colour in
    // the selected pill, a hairline-free track, and no lens. The glass lens and
    // the vertical washes below are the liquid finish this form must not have, so
    // they are switched off rather than blended. Follows the application-wide
    // form by default.
    property bool materialForm: ControlForm.materialForm

    signal selectionChanged(int index)

    // ---- Size presets ----
    // Each preset defines the look at its native height. When barHeight is set,
    // every dimension is scaled proportionally so the component adapts to any
    // height while keeping the same proportions and breathing space.
    readonly property var presets: ({
        tiny:   { height: 34, itemWidth: 56,  thumbHeight: 24, fontSize: 7,  iconSize: 14, thumbScale: 1.4,  thumbScaleY: 1.4  },
        small:  { height: 42, itemWidth: 60,  thumbHeight: 38, fontSize: 8,  iconSize: 16, thumbScale: 1.4,  thumbScaleY: 1.4  },
        medium: { height: 54, itemWidth: 80,  thumbHeight: 50, fontSize: 9,  iconSize: 20, thumbScale: 1.4,  thumbScaleY: 1.4  },
        large:  { height: 67, itemWidth: 100, thumbHeight: 62, fontSize: 11, iconSize: 24, thumbScale: 1.4,  thumbScaleY: 1.35 },
        XL:     { height: 80, itemWidth: 120, thumbHeight: 72, fontSize: 13, iconSize: 28, thumbScale: 1.4,  thumbScaleY: 1.35 }
    })

    readonly property var dims: presets[size] ?? presets.medium
    readonly property real scaleFactor: barHeight > 0 ? barHeight / dims.height : 1
    readonly property real sliderHeight: barHeight > 0 ? barHeight : dims.height
    readonly property real minimumItemWidth: itemWidthOverride > 0
        ? itemWidthOverride : dims.itemWidth * scaleFactor
    FontMetrics {
        id: labelMetrics
        font.pixelSize: root.fontSize
        font.weight: Math.max(root.labelFontWeight, Font.DemiBold)
    }
    readonly property real preferredItemWidth: {
        let result = minimumItemWidth
        if (sizeToLabels) {
            for (const item of model) {
                // Reserve the selected label's 1.05 scale as well as padding.
                result = Math.max(result, (Math.ceil(labelMetrics.advanceWidth(
                    String(item.label || ""))) + labelHorizontalPadding * 2 + 1) * 1.05)
            }
        }
        return Math.ceil(result)
    }
    // Layouts may constrain the preferred width. All geometry must use the
    // resulting width, including labels, click targets and selection physics.
    readonly property real itemWidth: width / Math.max(1, model.length)
    readonly property real sliderWidth: width
    readonly property real thumbWidth: Math.max(itemWidth * 0.5, itemWidth - 12 * scaleFactor)
    readonly property real thumbHeight: dims.thumbHeight * scaleFactor
    readonly property real iconSize: Math.max(6, Math.round(dims.iconSize * scaleFactor))
    readonly property real fontSize: labelFontPixelSize > 0
        ? labelFontPixelSize
        : Math.max(6, Math.round(dims.fontSize * scaleFactor))
    readonly property real minThumbX: (itemWidth - thumbWidth) / 2
    readonly property real maxThumbX: sliderWidth - thumbWidth - (itemWidth - thumbWidth) / 2
    readonly property int _selectedIndex: model.length > 0
        ? Math.max(0, Math.min(model.length - 1, currentIndex)) : 0

    implicitWidth: preferredItemWidth * Math.max(1, model.length)
    implicitHeight: sliderHeight

    // ---- Physics layer (frame-driven, no animation) ----
    property bool _glassVisible: false
    property real _currentThumbX: 0
    property real _wobbleScaleX: 1
    property real _wobbleScaleY: 1
    property real _baseScale: 1
    property real _baseScaleY: 1

    // ---- Display layer (100 ms ease-out, mirrors the CSS transition-transform) ----
    property real _displayX: 0
    property real _displayScaleX: 1
    property real _displayScaleY: 1
    Behavior on _displayX { NumberAnimation { duration: root.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
    Behavior on _displayScaleX { NumberAnimation { duration: root.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
    Behavior on _displayScaleY { NumberAnimation { duration: root.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }

    readonly property bool _isActive: !root.materialForm
        && (alwaysShowGlass || _glassVisible)

    // Thumb base scale: 1 at rest, thumbScale preset while active. It feeds
    // the display layer, so the visible growth is eased like the CSS
    // transition-transform, while the wobble stays frame-driven on top.
    on_IsActiveChanged: {
        _baseScale = _isActive ? dims.thumbScale : 1
        _baseScaleY = _isActive ? dims.thumbScaleY : 1
        _displayScaleX = _baseScale * _wobbleScaleX
        _displayScaleY = _baseScaleY * _wobbleScaleY
    }

    opacity: disabled ? 0.5 : 1.0

    // ---- Spring physics loop (ported from the Vue requestAnimationFrame loop) ----
    Timer {
        id: physicsTimer
        interval: 16
        repeat: true
        onTriggered: {
            root.updatePhysics()
            root.syncDisplay()
        }
    }

    // Glass hides with a fast 280 ms fadeout regardless of animation state
    Timer {
        id: hideGlassTimer
        interval: 280
        onTriggered: root._glassVisible = false
    }

    function lerp(start, end, t) {
        return start * (1 - t) + end * t
    }

    function targetX(index) {
        return index * root.itemWidth + (root.itemWidth - root.thumbWidth) / 2
    }

    function updatePhysics() {
        const dest = targetX(root._selectedIndex)
        const diff = dest - root._currentThumbX
        const newVelocity = diff * 0.5
        root._currentThumbX += newVelocity

        // Wobble: higher speed = more stretch in X, squash in Y (max 1.5)
        const speed = Math.abs(newVelocity)
        const stretchFactor = 1 + Math.min(speed * 0.02, 0.5)
        const squashFactor = 1 / stretchFactor
        root._wobbleScaleX = lerp(root._wobbleScaleX, stretchFactor, 0.2)
        root._wobbleScaleY = lerp(root._wobbleScaleY, squashFactor, 0.2)

        const settled = Math.abs(diff) < 0.1 && Math.abs(root._wobbleScaleX - 1) < 0.01
        if (settled) {
            root._currentThumbX = dest
            root._wobbleScaleX = 1
            root._wobbleScaleY = 1
            physicsTimer.stop()
        }
    }

    function syncDisplay() {
        root._displayX = root._currentThumbX
        root._displayScaleX = root._baseScale * root._wobbleScaleX
        root._displayScaleY = root._baseScaleY * root._wobbleScaleY
    }

    function select(index) {
        if (root.disabled || !root.enabled || index < 0 || index >= root.model.length)
            return
        if (index !== root.currentIndex) {
            root.currentIndex = index
            root.selectionChanged(index)
        }
        // Show the glass briefly when switching by click
        hideGlassTimer.stop()
        root._glassVisible = true
        hideGlassTimer.start()
    }

    function _beginPress(index) {
        if (disabled || !enabled || index < 0 || index >= model.length) return
        const target = clickTargets.itemAt(index)
        if (target) target.forceActiveFocus()
        _pressedIndex = index
        hideGlassTimer.stop()
        _glassVisible = true
        // Preserve the existing safety timeout when a click is cancelled.
        hideGlassTimer.start()
    }
    function _endPress() { _pressedIndex = -1 }
    function _selectAndFocus(index) {
        const targetIndex = Math.max(0, Math.min(model.length - 1, index))
        select(targetIndex)
        const target = clickTargets.itemAt(targetIndex)
        if (target) target.forceActiveFocus()
    }
    function settleWithoutMotion() {
        physicsTimer.stop()
        _currentThumbX = targetX(_selectedIndex)
        _wobbleScaleX = 1; _wobbleScaleY = 1
        syncDisplay()
    }
    onReduceMotionChanged: { if (reduceMotion) settleWithoutMotion() }
    onDisabledChanged: { if (disabled) _endPress() }
    onEnabledChanged: { if (!enabled) _endPress() }
    onCurrentIndexChanged: {
        if (reduceMotion) settleWithoutMotion()
        else physicsTimer.start()
    }

    onModelChanged: {
        if (root.model.length > 0) {
            root._currentThumbX = targetX(root._selectedIndex)
            root.syncDisplay()
        }
    }

    onItemWidthChanged: {
        root._currentThumbX = targetX(root._selectedIndex)
        root.syncDisplay()
    }

    Component.onCompleted: {
        if (root.model.length > 0) {
            root._currentThumbX = targetX(root._selectedIndex)
            root.syncDisplay()
        }
    }

    // Preserve the track fill; only the non-Material finish reflects light.
    Item {
        id: track
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            visible: root.materialForm
            radius: height / 2
            color: root.trackColor
        }
        LiquidSurface {
            anchors.fill: parent
            visible: !root.materialForm
            radius: height / 2
            backdrop: root.backdrop
            convexLens: true
            edgeShadeStrength: .08
            blurStrength: 0
            readability: 0
            edgeWidth: Math.min(10, height * .28)
            refractionStrength: materialHover.hovered ? 4.5 : 3
            magnification: materialHover.hovered ? 1.045 : 1.025
            reflectionStrength: materialHover.hovered ? .72 : .50
            tintColor: Foundation.AppTheme.dark ? "#20252f" : "#ffffff"
            tintStrength: .30
            Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
        }
    }

    // ---- Click targets (z 30: below the thumb, above the background) ----
    // The glass lens expands the moment you press, then slides on click.
    // NOTE: Repeater does not lay out delegates - x MUST be set explicitly,
    // otherwise every MouseArea stacks at (0,0).
    Repeater {
        id: clickTargets
        model: root.model
        delegate: MouseArea {
            id: targetDelegate
            required property var modelData
            required property int index
            activeFocusOnTab: enabled
            Accessible.role: Accessible.PageTab
            Accessible.name: String(modelData.label || modelData.id || index)
            Accessible.selected: index === root.currentIndex
            Accessible.focusable: enabled
            Accessible.focused: activeFocus
            Accessible.onPressAction: root.select(index)
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Left) root._selectAndFocus(index - 1)
                else if (event.key === Qt.Key_Right) root._selectAndFocus(index + 1)
                else if (event.key === Qt.Key_Home) root._selectAndFocus(0)
                else if (event.key === Qt.Key_End) root._selectAndFocus(root.model.length - 1)
                else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.select(index)
                else return
                event.accepted = true
            }
            x: index * root.itemWidth
            z: 30
            width: root.itemWidth
            height: root.sliderHeight
            enabled: !root.disabled
            cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
            hoverEnabled: true
            Controls.ToolTip.visible: containsMouse && Boolean(modelData.label)
            Controls.ToolTip.text: String(modelData.label || "")
            Controls.ToolTip.delay: 600

            onPressed: root._beginPress(index)
            onReleased: root._endPress()
            onCanceled: root._endPress()
            onClicked: root.select(index)

        }
    }

    readonly property int _focusedIndex: {
        for (let i = 0; i < clickTargets.count; ++i) {
            const target = clickTargets.itemAt(i)
            if (target && target.activeFocus) return i
        }
        return -1
    }
    Rectangle {
        z: 80
        x: root._focusedIndex * root.itemWidth + 3
        y: 3
        width: root.itemWidth - 6
        height: root.sliderHeight - 6
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: Foundation.AppTheme.focusRing
        visible: false
    }

    // ---- The glass/white thumb (z 40) ----
    Item {
        id: thumb
        x: root._displayX
        y: root.sliderHeight / 2
        z: 40
        width: root.thumbWidth
        height: root.thumbHeight

        // Keep the existing expanded-lens compositing mask through crossfade.
        layer.enabled: glassLens.opacity > 0
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: thumb.width
                height: thumb.height
                radius: thumb.height / 2
            }
        }

        // Vue transform: translateX(x) translateY(-50%) scale(s) scaleY(sy).
        // In QML the position is applied first (x/y), then the transform
        // list: scale around the centre, then shift that centre to y = 0.
        // The display layer (_display*) carries the 100 ms ease-out.
        transform: [
            Scale {
                xScale: root._displayScaleX
                yScale: root._displayScaleY
                origin.x: root.thumbWidth / 2
                origin.y: root.thumbHeight / 2
            },
            Translate { y: -root.thumbHeight / 2 }
        ]

        // Layer 1: opaque white pill at rest, dissolves while the lens is active
        Item {
            id: thumbBase
            anchors.fill: parent
            opacity: root._isActive ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 100 } }
            Rectangle {
                anchors.fill: parent
                visible: root.materialForm
                radius: height / 2
                color: root.accentColor
            }
            LiquidSurface {
                anchors.fill: parent
                visible: !root.materialForm
                radius: height / 2
                backdrop: root.backdrop
                convexLens: true
                edgeShadeStrength: .08
                blurStrength: 0
                readability: 0
                edgeWidth: Math.min(10, height * .28)
                refractionStrength: materialHover.hovered ? 4.5 : 3
                magnification: materialHover.hovered ? 1.045 : 1.025
                reflectionStrength: materialHover.hovered ? .72 : .50
                tintColor: Foundation.AppTheme.dark ? "#20252f" : "#ffffff"
                tintStrength: .80
                Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            }
        }

        // Layer 2: glass lens while active - same look as the switch lens
        Item {
            id: glassLens
            anchors.fill: parent
            opacity: root._isActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 100 } }

            LiquidSurface {
                id: lensSurface
                anchors.fill: parent
                radius: height / 2
                backdrop: root.backdrop
                convexLens: true
                edgeShadeStrength: .08
                blurStrength: 0
                readability: 0
                edgeWidth: Math.min(10, height * .28)
                refractionStrength: materialHover.hovered ? 4.5 : 3
                magnification: materialHover.hovered ? 1.045 : 1.025
                reflectionStrength: materialHover.hovered ? .72 : .50
                tintColor: root._isActive ? "#ffffff" : (Foundation.AppTheme.dark ? "#20252f" : "#ffffff")
                tintStrength: root._isActive ? .06 : .80
                Behavior on refractionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on magnification { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on reflectionStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
                Behavior on tintStrength { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : Foundation.AppTheme.motionFast } }
            }


        }
    }

    // ---- Default item delegate (icon + optional label) ----
    // Users can override this with their own Component by setting
    // root.itemDelegate. The delegate receives `modelData` and `index` from
    // the Repeater and should size itself to root.itemWidth x root.sliderHeight.
    property Component itemDelegate: defaultItemDelegate

    Component {
        id: defaultItemDelegate
        Item {
            required property var modelData
            required property int index
            z: root._isActive ? 20 : 50
            x: index * root.itemWidth
            width: root.itemWidth
            height: root.sliderHeight
            opacity: index === root.currentIndex ? 1.0 : 0.6
            scale: index === root.currentIndex ? 1.05 : 1.0
            Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 100 } }
            Behavior on scale { NumberAnimation { duration: root.reduceMotion ? 0 : 100 } }

            Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width / 1.05 - root.labelHorizontalPadding * 2)
                spacing: modelData.icon && modelData.label ? 2 : 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Boolean(modelData.icon)
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.icon || ""
                    color: index === root.currentIndex
                        ? root.selectedItemColor : root.itemColor
                    font.pixelSize: root.iconSize
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    objectName: "liquid-nav-label-" + index
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: Boolean(modelData.label
                        && modelData.label.toString().length > 0)
                    text: modelData.label || ""
                    color: index === root.currentIndex
                        ? root.selectedItemColor : root.itemColor
                    font.pixelSize: root.fontSize
                    font.weight: index === root.currentIndex
                        ? Math.max(root.labelFontWeight, Font.DemiBold)
                        : root.labelFontWeight
                }
            }
        }
    }

    // ---- Items layer ----
    // At rest: z 50 (above the opaque thumb). While the glass lens is active:
    // z 20 (below it, so the translucent lens covers them - Vue behaviour)
    Repeater {
        model: root.model
        delegate: root.itemDelegate
    }
}
