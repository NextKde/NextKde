import QtQuick
import "../foundation" as Foundation

// Liquid switch retaining its existing position/expansion/wobble motion.
// The expanded lens samples the sibling track; reflection uses LiquidSurface.
Item {
    id: root

    // Public API
    property bool checked: false
    property bool enabled: true
    property color accentColor: "#43c154"
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    property bool darkAppearance: Foundation.AppTheme.dark
    property color trackColor: Qt.rgba(0.5, 0.5, 0.55, 0.35)
    // ── Form ──────────────────────────────────────────────────────────────
    // A tonal host draws the Material 3 switch: a pill track that takes the
    // accent when on, and a handle that is 16dp off / 24dp on. The iOS track,
    // shadow and glass lens below are the liquid finish this form must not have,
    // so they are hidden rather than blended with it. It follows the
    // application-wide form by default.
    property bool materialForm: ControlForm.materialForm
    // Material 3 handle colours: the accent's foreground when on, a neutral
    // outline when off. The glass form ignores both -- its thumb is the lens.
    property color handleOnColor: "#ffffff"
    property color handleOffColor: Qt.rgba(0.47, 0.47, 0.47, 1)
    signal toggled(bool checked)

    // Geometry
    implicitWidth: 74
    implicitHeight: 32
    activeFocusOnTab: enabled
    Accessible.role: Accessible.CheckBox
    Accessible.checked: checked
    Accessible.focusable: enabled
    Accessible.focused: activeFocus
    Accessible.onPressAction: root.toggle()

    // Internal state
    property bool _pressed: false
    property bool _hovered: false
    property real _thumbX: checked ? travel : 0

    // The pressed lens must extend beyond the solid slot.
    clip: false

    // Animation values
    property real _expansion: 0.0  // 0 = rest pill, 1 = expanded glass lens
    property real _stretch: 0.0    // squash-stretch wobble

    // Computed geometry
    readonly property bool sampling: !materialForm && _expansion > .001 && glassLens.sampling
    readonly property real thumbInset: height * .05
    readonly property real thumbWidth: Math.min(height * 1.42, width - thumbInset * 2)
    readonly property real thumbHeight: height * .90
    readonly property real travel: Math.max(0, width - thumbWidth - thumbInset * 2)
    readonly property real thumbRadius: thumbHeight / 2

    // Track color crossfade based on thumb position
    readonly property real progress: travel > 0 ? Math.max(0, Math.min(1, _thumbX / travel)) : 0
    readonly property color currentTrackColor: Qt.rgba(
        trackColor.r + (accentColor.r - trackColor.r) * progress,
        trackColor.g + (accentColor.g - trackColor.g) * progress,
        trackColor.b + (accentColor.b - trackColor.b) * progress,
        1.0
    )

    // Thumb position animation
    Behavior on _thumbX {
        NumberAnimation {
            duration: root.reduceMotion ? 0 : 200
            easing.type: Easing.OutCubic
        }
    }

    // Expansion animation (dissolve into glass)
    Behavior on _expansion {
        NumberAnimation {
            duration: root.reduceMotion ? 0 : _pressed ? 120 : 200
            easing.type: _pressed ? Easing.OutCubic : Easing.OutQuint
        }
    }

    // Squash-stretch wobble
    SequentialAnimation on _stretch {
        id: wobbleAnim
        running: false
        NumberAnimation { to: 0.175; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { to: -0.08; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.04; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 50; easing.type: Easing.OutQuad }
    }

    opacity: enabled ? 1.0 : 0.5

    function toggle() {
        if (!enabled) return
        // The owner confirms the value (often asynchronously). Never replace
        // its checked binding with a local assignment.
        root.toggled(!root.checked)
        if (!reduceMotion) wobbleAnim.restart()
    }


    // Shared interaction-state entry points; Gallery review uses these same
    // paths and labels its captures as state-driven rather than pointer events.
    function _beginPress() {
        if (!enabled) return
        root.forceActiveFocus()
        settleLens.stop()
        _pressed = true
        if (!materialForm) _expansion = 1
    }
    function _endPress() {
        _pressed = false
        if (!materialForm) {
            if (reduceMotion || !enabled) _expansion = 0
            else settleLens.restart()
        }
    }
    Timer {
        id: settleLens
        interval: 100
        onTriggered: { if (!root._pressed) root._expansion = 0 }
    }
    function _setHovered(value) { _hovered = enabled && value }
    onEnabledChanged: { if (!enabled) { _setHovered(false); _endPress() } }
    Keys.onPressed: function(event) {
        if (!event.isAutoRepeat && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            _beginPress()
            event.accepted = true
        }
    }
    Keys.onReleased: function(event) {
        if (!event.isAutoRepeat && _pressed && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            _endPress()
            toggle()
            event.accepted = true
        }
    }

    // Capture a padded sibling: the protruding lens samples transparent
    // space outside the real slot instead of smearing its edge texel outward.
    Item {
        id: track
        visible: !root.materialForm
        readonly property real capturePadding: root.height * .5
        x: -capturePadding; y: -capturePadding
        width: root.width + capturePadding * 2
        height: root.height + capturePadding * 2
        Rectangle {
            x: track.capturePadding; y: track.capturePadding
            width: root.width; height: root.height
            radius: height / 2
            color: root.currentTrackColor
        }
    }
    LiquidBackdrop {
        id: trackBackdrop
        sourceItem: track
        active: !root.materialForm && root._expansion > .001
        registerAsDefault: false
    }

    // Thumb shadow (fades out as thumb expands into glass)
    Rectangle {
        id: thumbShadow
        objectName: "switch-thumb-shadow"
        // 以中心点为基准，与 glassThumb 保持一致
        x: root.thumbInset + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        width: root.thumbWidth * (1 + 0.3 * root._expansion)
        height: root.thumbHeight * (1 + 0.3 * root._expansion)
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.14)
        opacity: (1 - root._expansion) * 0.5
        // 合并 Material 门控与原有淡出判定（同对象两条 visible = 解析错
        // crash-loop，桌面起不来——实测踩过）
        visible: !root.materialForm && opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // The glass thumb/lens
    Item {
        id: glassThumb
        objectName: "switch-glass-thumb"
        visible: !root.materialForm
        // 展开时保持中心点不变，而不是左上角
        x: root.thumbInset + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter

        // Size animates from pill to expanded lens with squash-stretch
        width: root.thumbWidth * (1 + 0.42 * root._expansion) * (1 - 0.2 * root._stretch)
        height: root.thumbHeight * (1 + 0.50 * root._expansion) * (1 + 0.3 * root._stretch)

        // Layer 1: Base white pill (fades out when expanding)
        Rectangle {
            id: basePill
            anchors.fill: parent
            radius: height / 2
            color: "#ffffff"
            opacity: 1 - root._expansion


        }

        // Expanded glass samples the actual sibling track. The former red,
        // cyan and white closed strokes and parked glint are intentionally gone.
        LiquidSurface {
            id: glassLens
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            opacity: root._expansion
            radius: height / 2
            backdrop: trackBackdrop
            darkAppearance: root.darkAppearance
            tintColor: "#ffffff"
            tintStrength: .06
            blurStrength: .12
            readability: 0
            refractionStrength: 1.7
            magnification: 1.035
            edgeWidth: 6
            reflectionStrength: .42 + .12 * root._expansion
            rimColor: Qt.rgba(1, 1, 1, .12)
        }

        // Layer 3: Accent tint overlay
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.accentColor
            opacity: 0.03 * root._expansion
        }
    }

    // ── Material 3 form ───────────────────────────────────────────────────
    // Metrics scale with whatever height a host gives the switch, so a 25px row
    // stays compact while a 32px row is the Material spec exactly.
    Item {
        id: materialLayer
        anchors.fill: parent
        visible: root.materialForm

        readonly property real m3Scale: Math.min(1, root.height / 32)
        readonly property real handleSize: (root.checked ? 24 : 16) * m3Scale
        readonly property real inset: Math.max(1, 4 * m3Scale)
        readonly property real handleX: inset
            + (root.checked ? Math.max(1, root.width - inset * 2 - handleSize) : 0)

        // Track: accent when on, surface variant when off.
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.checked ? root.accentColor : root.trackColor
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        // State layer: 10% on hover, 16% pressed, centred on the handle.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: materialLayer.handleX + materialLayer.handleSize / 2 - width / 2
            width: Math.min(root.height, 40 * materialLayer.m3Scale)
            height: width
            radius: width / 2
            color: root.accentColor
            opacity: root._pressed ? 0.16 : (root._hovered ? 0.10 : 0.0)
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // Handle: a circle that grows into the "on" size, not the iOS lens.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: materialLayer.handleX
            width: materialLayer.handleSize
            height: materialLayer.handleSize
            radius: width / 2
            color: root.checked ? root.handleOnColor : root.handleOffColor
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: Foundation.AppTheme.focusRing
        visible: false
    }

    // Interaction
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: root._setHovered(true)
        onExited: root._setHovered(false)
        onPressed: root._beginPress()
        onReleased: root._endPress()
        onClicked: root.toggle()
        onCanceled: root._endPress()
    }
}
