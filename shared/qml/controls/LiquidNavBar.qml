import QtQuick
import Qt5Compat.GraphicalEffects

// Liquid glass bottom navigation bar, ported from the vue-web-liquid-glass
// LiquidGlassBottomNavBar component. Interaction is click-only (desktop):
// clicking an item slides the thumb over with a spring settle. The glass
// look follows LiquidGlassSwitch (pure QML gradients, no shaders):
//   - opaque white pill at rest, dissolves into a refracting glass lens
//     while active; the lens fades out 280 ms after the click
//   - spring physics: velocity = diff * 0.5 (Vue rAF loop) -> elastic
//     settle with squash & stretch wobble
//   - the thumb transform carries a 100 ms ease-out (physics layer is
//     frame-driven, the display layer eases toward it)
//   - item layer sits above the thumb at rest, below it while the lens is
//     active, so items show through the translucent glass
Item {
    id: root

    // ---- Public API (mirrors the Vue component props) ----
    property var model: []            // [{ id, label?, icon }] - icon is a text symbol
    property int currentIndex: 0
    property string size: "medium"    // tiny | small | medium | large | XL
    property real barHeight: 0        // 0 = use preset height; otherwise scale the
                                      // chosen preset proportionally to this height
    property bool disabled: false
    property color accentColor: "#ff453a"
    property color itemColor: "#ffffff"
    property real labelFontPixelSize: 0 // 0 = use the selected size preset
    property int labelFontWeight: Font.Normal
    property bool alwaysShowGlass: false

    signal selectionChanged(int index)

    // ---- Size presets ----
    // Each preset defines the look at its native height. When barHeight is set,
    // every dimension is scaled proportionally so the component adapts to any
    // height while keeping the same proportions and breathing space.
    readonly property var presets: ({
        tiny:   { height: 34, itemWidth: 56,  thumbHeight: 24, fontSize: 7,  iconSize: 14, thumbScale: 1.3,  thumbScaleY: 1.3  },
        small:  { height: 42, itemWidth: 60,  thumbHeight: 38, fontSize: 8,  iconSize: 16, thumbScale: 1.3,  thumbScaleY: 1.3  },
        medium: { height: 54, itemWidth: 80,  thumbHeight: 50, fontSize: 9,  iconSize: 20, thumbScale: 1.3,  thumbScaleY: 1.3  },
        large:  { height: 67, itemWidth: 100, thumbHeight: 62, fontSize: 11, iconSize: 24, thumbScale: 1.3,  thumbScaleY: 1.25 },
        XL:     { height: 80, itemWidth: 120, thumbHeight: 72, fontSize: 13, iconSize: 28, thumbScale: 1.3,  thumbScaleY: 1.25 }
    })

    readonly property var dims: presets[size] ?? presets.medium
    readonly property real scaleFactor: barHeight > 0 ? barHeight / dims.height : 1
    readonly property real sliderHeight: barHeight > 0 ? barHeight : dims.height
    readonly property real itemWidth: dims.itemWidth * scaleFactor
    readonly property real sliderWidth: itemWidth * Math.max(1, model.length)
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

    implicitWidth: sliderWidth
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
    Behavior on _displayX { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    Behavior on _displayScaleX { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
    Behavior on _displayScaleY { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }

    readonly property bool _isActive: alwaysShowGlass || _glassVisible

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
        if (index < 0 || index >= root.model.length)
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

    onCurrentIndexChanged: {
        // Animate to the new slot (spring settle)
        physicsTimer.start()
    }

    onModelChanged: {
        if (root.model.length > 0) {
            root._currentThumbX = targetX(root._selectedIndex)
            root.syncDisplay()
        }
    }

    Component.onCompleted: {
        if (root.model.length > 0) {
            root._currentThumbX = targetX(root._selectedIndex)
            root.syncDisplay()
        }
    }

    // ---- Glass background (the pill strip) ----
    // Same structure as the LiquidGlassSwitch track: tinted base, inner
    // depth gradient and a subtle top sheen. The layer+OpacityMask clips
    // the flat-topped sheen to the pill arc so no white corner masks show
    // (the same trick the switch uses for its whole body).
    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.10)

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: track.width
                height: track.height
                radius: track.height / 2
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.10) }
                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.03) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.08) }
            }
        }

        // Track highlight (subtle top sheen)
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.4
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // ---- Click targets (z 30: below the thumb, above the background) ----
    // The glass lens expands the moment you press, then slides on click.
    // NOTE: Repeater does not lay out delegates - x MUST be set explicitly,
    // otherwise every MouseArea stacks at (0,0).
    Repeater {
        model: root.model
        delegate: MouseArea {
            required property var modelData
            required property int index
            x: index * root.itemWidth
            z: 30
            width: root.itemWidth
            height: root.sliderHeight
            enabled: !root.disabled
            cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor

            onPressed: {
                // Timers are scoped ids, not root properties
                hideGlassTimer.stop()
                root._glassVisible = true
                // Safety net: if onClicked never fires (press then drag away),
                // the glass still fades out on its own
                hideGlassTimer.start()
            }
            onClicked: root.select(index)
        }
    }

    // ---- The glass/white thumb (z 40) ----
    Item {
        id: thumb
        x: root._displayX
        y: root.sliderHeight / 2
        z: 40
        width: root.thumbWidth
        height: root.thumbHeight

        // Clip thumb contents (top highlight, aberration borders) to the
        // pill arc, exactly like the switch. The thumb's movement/growth is
        // transform-based, so the cached mask simply scales along.
        layer.enabled: true
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
        Rectangle {
            id: thumbBase
            anchors.fill: parent
            radius: height / 2
            color: "#ffffff"
            opacity: root._isActive ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 100 } }

            // Subtle gradient + top highlight, same as the switch base pill
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 0.5; color: "#f5f5f7" }
                GradientStop { position: 1; color: "#e8e8ed" }
            }
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.5
                height: parent.height * 0.35
                radius: width / 2
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.7) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }

        // Layer 2: glass lens while active - same look as the switch lens
        Item {
            id: glassLens
            anchors.fill: parent
            opacity: root._isActive ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            // Chromatic aberration - RGB split edges
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 0.2, 0.2, 0.25)
                x: -0.5
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.2, 0.9, 1, 0.25)
                x: 0.5
            }

            // Main glass body - semi-transparent with refraction gradient
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.10)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.25) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.25) }
                }

                // Inner depth shadow
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.0) }
                        GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.0) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.15) }
                    }
                }
            }

            // Specular highlight (soft, diffused)
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.4
                height: parent.height * 0.25
                radius: width / 2
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.5) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.2) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            // Edge glow - soft rim light
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.30)
            }

            // Accent tint overlay (subtle color bleed when active)
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.accentColor
                opacity: 0.10
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
            Behavior on opacity { NumberAnimation { duration: 100 } }
            Behavior on scale { NumberAnimation { duration: 100 } }

            Column {
                anchors.centerIn: parent
                spacing: modelData.label && modelData.label.toString().length > 0 ? 2 : 0
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.icon || ""
                    color: index === root.currentIndex ? root.accentColor : root.itemColor
                    font.pixelSize: root.iconSize
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: modelData.label && modelData.label.toString().length > 0
                    text: modelData.label || ""
                    color: index === root.currentIndex ? root.accentColor : root.itemColor
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
