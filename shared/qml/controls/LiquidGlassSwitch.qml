import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

// iOS-style liquid glass switch with pure QML rendering.
// The thumb dissolves into a glass lens when toggled, with chromatic aberration,
// specular highlights, and squash-stretch wobble animation.
Item {
    id: root

    // Public API
    property bool checked: false
    property bool enabled: true
    property color accentColor: "#0a84ff"
    property color trackColor: Qt.rgba(0.5, 0.5, 0.55, 0.35)
    signal toggled(bool checked)

    // Geometry
    implicitWidth: 74
    implicitHeight: 32

    // Internal state
    property bool _pressed: false
    property bool _hovered: false
    property real _thumbX: checked ? travel : 0

    // 整个开关按圆角药丸裁剪（iOS 真实做法）：玻璃透镜按下时放大溢出轨道、
    // 阴影等任何内部元素，都会被外层圆角裁掉，不会露出超出圆角的蒙层
    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: height / 2
        }
    }

    // Animation values
    property real _expansion: 0.0  // 0 = rest pill, 1 = expanded glass lens
    property real _stretch: 0.0    // squash-stretch wobble

    // Computed geometry
    readonly property real thumbWidth: 44
    readonly property real thumbHeight: 26
    readonly property real travel: width - thumbWidth - 6
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
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    // Expansion animation (dissolve into glass)
    Behavior on _expansion {
        NumberAnimation {
            duration: _pressed ? 120 : 200
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
        root.checked = !root.checked
        root.toggled(root.checked)
        wobbleAnim.restart()
    }

    // Track background
    Rectangle {
        id: track
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

        // Track highlight (subtle top sheen)
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.4
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.12) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // Thumb shadow (fades out as thumb expands into glass)
    Rectangle {
        id: thumbShadow
        // 以中心点为基准，与 glassThumb 保持一致
        x: 3 + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        width: root.thumbWidth * (1 + 0.3 * root._expansion)
        height: root.thumbHeight * (1 + 0.3 * root._expansion)
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: (1 - root._expansion) * 0.5
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // The glass thumb/lens
    Item {
        id: glassThumb
        // 展开时保持中心点不变，而不是左上角
        x: 3 + root._thumbX - (width - root.thumbWidth) / 2
        anchors.verticalCenter: parent.verticalCenter

        // Size animates from pill to expanded lens with squash-stretch
        width: root.thumbWidth * (1 + 0.4 * root._expansion) * (1 - 0.2 * root._stretch)
        height: root.thumbHeight * (1 + 0.4 * root._expansion) * (1 + 0.3 * root._stretch)

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

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

    // Interaction
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: root._hovered = true
        onExited: root._hovered = false

        onPressed: {
            root._pressed = true
            root._expansion = 1.0
        }

        onReleased: {
            root._pressed = false
            root._expansion = 0.0
            root.toggle()
        }

        onCanceled: {
            root._pressed = false
            root._expansion = 0.0
        }
    }
}
