import QtQuick
import Qt5Compat.GraphicalEffects
import "../foundation" as Foundation

// Liquid switch with velocity-continuous position and press response.
// The thumb dissolves into a glass lens; optical fades stay independent.
Item {
    id: root

    // Public API
    property bool checked: false
    property bool enabled: true
    property color accentColor: "#0a84ff"
    // 关态轨道 α .18（spec §4.6「关 α .18」；原 demo 值 .35）
    property color trackColor: Qt.rgba(0.5, 0.5, 0.55, 0.18)
    // ── Form ──────────────────────────────────────────────────────────────
    // A tonal host draws the Material 3 switch: a pill track that takes the
    // accent when on, and a handle that is 16dp off / 24dp on. The iOS track,
    // shadow and glass lens below are the liquid finish this form must not have,
    // so they are hidden rather than blended with it. It follows the
    // application-wide form by default.
    property bool materialForm: ControlForm.materialForm
    property bool reduceMotion: Foundation.AppTheme.reduceMotion
    // Material 3 handle colours: the accent's foreground when on, a neutral
    // outline when off. The glass form ignores both -- its thumb is the lens.
    property color handleOnColor: "#ffffff"
    property color handleOffColor: Qt.rgba(0.47, 0.47, 0.47, 1)
    signal toggled(bool checked)

    // Geometry — spec §4.6：开关 40×24，knob 20（原 demo 74×32 / thumb 44×26）
    implicitWidth: 40
    implicitHeight: 24

    // Internal state
    property bool _pressed: false
    property bool _hovered: false
    readonly property real _thumbX: thumbMotion.value * travel

    // 整个开关按圆角药丸裁剪（iOS 真实做法）：仅玻璃透镜按下放大溢出轨道、
    // 或 disabled 整组半透明合成时才需要 FBO+OpacityMask；静止时所有内容
    // 都在 pill 内（顶部高光已改为自带 pill 圆角的渐变矩形），直通渲染，
    // 省掉常驻的源+mask 两个 FBO。裁剪跟随弹簧几何，覆盖透镜回缩的尾段。
    layer.enabled: root._lensExpansion > 0 || root._stretch > 0 || root.opacity < 1
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: height / 2
        }
    }

    // Animation values
    property real _expansion: 0.0  // 0 = rest pill, 1 = expanded glass lens
    readonly property real _stretch: !reduceMotion && !materialForm
        ? Math.min(0.175, Math.abs(thumbMotion.velocity) * 0.018) : 0
    readonly property real _lensExpansion: expansionMotion.value

    // Computed geometry
    readonly property real thumbWidth: 20
    readonly property real thumbHeight: 20
    readonly property real travel: width - thumbWidth - 6
    readonly property real thumbRadius: thumbHeight / 2

    // Optical fades remain bounded and independent of the spring velocity.
    readonly property real progress: travel > 0 ? Math.max(0, Math.min(1, _thumbX / travel)) : 0
    property real _trackProgress: checked ? 1 : 0
    readonly property color currentTrackColor: Qt.rgba(
        trackColor.r + (accentColor.r - trackColor.r) * _trackProgress,
        trackColor.g + (accentColor.g - trackColor.g) * _trackProgress,
        trackColor.b + (accentColor.b - trackColor.b) * _trackProgress,
        1.0
    )
    Behavior on _trackProgress {
        NumberAnimation { duration: root.reduceMotion ? 0 : 120; easing.type: Easing.OutCubic }
    }

    Foundation.SpringMotion {
        id: thumbMotion
        target: root.checked ? 1 : 0
        enabled: !root.reduceMotion && root.visible
    }
    Foundation.SpringMotion {
        id: expansionMotion
        target: !root.materialForm && root._pressed ? 1 : 0
        enabled: !root.reduceMotion && root.visible
        response: 0.22
        dampingRatio: 0.85
    }

    // Expansion animation (dissolve into glass)
    Behavior on _expansion {
        NumberAnimation {
            duration: root.reduceMotion ? 0 : _pressed ? 100 : 200
            easing.type: _pressed ? Easing.OutCubic : Easing.OutQuint
        }
    }

    // §4.6 / §4.1 disabled：整体 α .38（原 demo 0.5）
    opacity: enabled ? 1.0 : 0.38

    function toggle() {
        if (!enabled) return
        // The owner confirms the value (often asynchronously). Never replace
        // its checked binding with a local assignment.
        root.toggled(!root.checked)
    }

    // Track background（Material 形态隐藏：玻璃件"hidden rather than
    // blended"，见头注释——漏门控会让玻璃拇指从 Material 轨道下透出来）
    Rectangle {
        id: track
        visible: !root.materialForm
        anchors.fill: parent
        radius: height / 2
        color: root.currentTrackColor

        // Track inner shadow
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.15) }
                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.08) }
            }
        }

        // Track highlight (subtle top sheen). A full-pill rounded rect whose
        // gradient fades out by 40% height renders identically to the old
        // flat-topped strip clipped by the root OpacityMask, but its own
        // radius keeps it inside the arc -- no mask needed at rest.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // Thumb shadow (fades out as thumb expands into glass)
    Rectangle {
        id: thumbShadow
        objectName: "switch-thumb-shadow"
        // 以中心点为基准，与 glassThumb 保持一致
        x: 3 + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        width: glassThumb.width
        height: glassThumb.height
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: (1 - root._expansion) * 0.5
        // 合并 Material 门控与原有淡出判定（同对象两条 visible = 解析错
        // crash-loop，桌面起不来——实测踩过）
        visible: !root.materialForm && opacity > 0.01
    }

    // The glass thumb/lens
    Item {
        id: glassThumb
        objectName: "switch-glass-thumb"
        visible: !root.materialForm
        // 展开时保持中心点不变，而不是左上角
        x: 3 + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter

        // Size animates from pill to expanded lens with squash-stretch
        width: root.thumbWidth * (1 + 0.4 * root._lensExpansion) * (1 - 0.2 * root._stretch)
        height: root.thumbHeight * (1 + 0.4 * root._lensExpansion) * (1 + 0.3 * root._stretch)

        // Layer 1: Base white pill (fades out when expanding)
        Rectangle {
            id: basePill
            anchors.fill: parent
            radius: height / 2
            color: "#ffffff"
            opacity: 1 - root._expansion

            // Subtle gradient for depth
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 0.5; color: "#f5f5f7" }
                GradientStop { position: 1; color: "#e8e8ed" }
            }

            // Top highlight
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

        // Layer 2: Glass refraction effect (visible when expanded)
        Item {
            id: glassLens
            anchors.centerIn: parent
            width: parent.width - 2
            height: parent.height - 2
            opacity: root._expansion

            // Chromatic aberration - RGB split edges
            // Red channel offset
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 0.2, 0.2, 0.25 * root._expansion)
                x: -0.5
            }
            // Cyan channel offset
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.2, 0.9, 1, 0.25 * root._expansion)
                x: 0.5
            }

            // Main glass body - semi-transparent with refraction gradient
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.10 + 0.15 * root._expansion)

                // Refraction gradient - shows track color through the glass
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: root.checked
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                            : Qt.rgba(1, 1, 1, 0.25)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }
                    GradientStop {
                        position: 1
                        color: root.checked
                            ? Qt.rgba(1, 1, 1, 0.25)
                            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)
                    }
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
                opacity: 0.4 + 0.4 * root._expansion
            }

            // Edge glow
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.30 * root._expansion)
            }
        }

        // Layer 3: Accent tint overlay
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.accentColor
            opacity: 0.10 * root._expansion
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
        readonly property real handleSize: (16 + 8 * thumbMotion.value) * m3Scale
        readonly property real inset: Math.max(1, 4 * m3Scale)
        readonly property real handleX: inset
            + thumbMotion.value * Math.max(1, root.width - inset * 2 - handleSize)

        // Track: accent when on, surface variant when off.
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.checked ? root.accentColor : root.trackColor
            Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 150 } }
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
            // §2.11 / §3 motion.duration.instant=100（原 demo 120 不在五档）。
            Behavior on opacity { NumberAnimation { duration: root.reduceMotion ? 0 : 100 } }
        }

        // Handle: a circle that grows into the "on" size, not the iOS lens.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: materialLayer.handleX
            width: materialLayer.handleSize
            height: materialLayer.handleSize
            radius: width / 2
            color: root.checked ? root.handleOnColor : root.handleOffColor
            Behavior on color { ColorAnimation { duration: root.reduceMotion ? 0 : 120 } }
        }
    }

    // Interaction — spec §4.6「热区 44」：视觉 40×24，命中区外扩到 ≥44×44
    // （Item 默认不裁剪，外扩部分在行内仍属本控件；行高 <44 时与相邻行无重叠）
    MouseArea {
        anchors.centerIn: parent
        width: Math.max(root.width, 44)
        height: Math.max(root.height, 44)
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: root._hovered = true
        onExited: root._hovered = false

        onPressed: {
            root._pressed = true
            // Material 形态不驱动玻璃展开（FBO+OpacityMask 纯属浪费，
            // 玻璃件已隐藏）
            if (!root.materialForm)
                root._expansion = 1.0
        }

        onReleased: {
            root._pressed = false
            if (!root.materialForm)
                root._expansion = 0.0
        }

        onClicked: root.toggle()

        onCanceled: {
            root._pressed = false
            root._expansion = 0.0
        }
    }
}
