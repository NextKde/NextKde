import QtQuick
import QtQuick.Effects

// iOS-style liquid glass slider with true refraction.
// Uses ShaderEffect to bend the track colors through the glass thumb,
// with chromatic aberration and specular highlights.
Item {
    id: root

    SystemPalette {
        id: controlPalette
        colorGroup: SystemPalette.Active
    }

    implicitWidth: 240
    implicitHeight: 44

    property real value: 0.0
    property bool enabled: true
    property color accentColor: "#0a84ff"
    property color trackColor: Qt.rgba(0.5, 0.5, 0.55, 0.35)
    readonly property bool darkAppearance: {
        const color = controlPalette.window
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
    }
    property color thumbColor: darkAppearance ? "#ffffff" : "#e7f1ff"
    property color thumbBorderColor: darkAppearance
        ? "transparent" : "#6ba6df"
    property real trackHeight: 6
    property real thumbWidth: 36
    property real thumbHeight: 18

    // Internal state
    property bool _pressed: false
    property bool _hovered: false
    property real _dragOffset: 0
    // 提交后短暂屏蔽 x 动画：外部服务异步写回（带量化偏差，如 54% -> 54.18%）时
    // 拇指直接跳变对齐，避免松开后滑一小步；之后恢复外部变化时的平滑动画
    property bool _suppressXAnimation: false
    Timer {
        id: suppressXAnimTimer
        interval: 400
        onTriggered: root._suppressXAnimation = false
    }

    // Geometry
    readonly property real visualValue: Math.max(0, Math.min(1, value))
    readonly property real edgeInset: thumbWidth / 2
    readonly property real travel: Math.max(1, width - edgeInset * 2)
    readonly property real thumbCenterX: edgeInset + visualValue * travel

    // Expansion animation (0 = rest white pill, 1 = fully expanded glass lens)
    property real _expansion: 0.0
    Behavior on _expansion {
        NumberAnimation {
            duration: root._pressed ? 270 : 460
            easing.type: root._pressed ? Easing.OutBack : Easing.OutQuint
            easing.overshoot: root._pressed ? 1.36 : 1.0
        }
    }

    // Squash-stretch wobble
    property real _stretch: 0.0
    SequentialAnimation on _stretch {
        id: wobbleAnim
        running: false
        NumberAnimation { to: 0.175; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { to: -0.08; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.04; duration: 120; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 100; easing.type: Easing.OutQuad }
    }

    signal previewChanged(real value)
    signal commitRequested(real value)

    opacity: enabled ? 1.0 : 0.45

    function positionForPointer(pointerX) {
        return Math.max(0, Math.min(1, (pointerX - edgeInset) / travel))
    }

    function triggerWobble() {
        wobbleAnim.restart()
    }

    // Track container - this is what gets refracted through the glass
    Item {
        id: trackContainer
        anchors.fill: parent

        // Track background
        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: root.trackHeight
            radius: height / 2
            color: root.trackColor

            // Inner shadow for depth
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.12) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.03) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.06) }
                }
            }
        }

        // Progress fill
        Rectangle {
            id: progress
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, Math.min(parent.width, root.thumbCenterX))
            height: root.trackHeight
            radius: height / 2
            color: root.accentColor

            // Glass sheen on progress
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
    }

    // The glass thumb/lens - uses layer effect for refraction
    Item {
        id: glassThumb
        // 中心固定在 thumbCenterX：x/width 用固定基准尺寸，展开形变走 transform Scale，
        // 避免收缩动画期间 x 绑定重算 + Behavior 滞后导致拇指中心偏移
        x: root.thumbCenterX - root.thumbWidth / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.thumbWidth
        height: root.thumbHeight

        transform: Scale {
            origin.x: root.thumbWidth / 2
            origin.y: root.thumbHeight / 2
            xScale: (1 + 0.5 * root._expansion) * (1 - 0.2 * root._stretch)
            yScale: (1 + 0.5 * root._expansion) * (1 + 0.4 * root._stretch)
        }

        Behavior on x {
            NumberAnimation {
                duration: root._pressed || root._suppressXAnimation ? 0 : 200
                easing.type: Easing.OutQuint
            }
        }

        // Layer 1: Base white pill (fades out when expanding)
        Rectangle {
            id: basePill
            anchors.fill: parent
            radius: height / 2
            color: root.thumbColor
            border.width: 1
            border.color: root.thumbBorderColor
            opacity: 1 - root._expansion

            // 均匀的玻璃白渐变：不再叠加顶部高光层，避免拇指出现白色蒙层
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.lighter(root.thumbColor, 1.04) }
                GradientStop { position: 0.5; color: root.thumbColor }
                GradientStop { position: 1; color: Qt.darker(root.thumbColor, 1.06) }
            }
        }

        // Layer 2: Glass refraction effect (visible when expanded)
        Item {
            id: glassLens
            anchors.fill: parent
            opacity: root._expansion

            // Chromatic aberration - RGB split edges
            // Red channel offset
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 0.2, 0.2, 0.25 * root._expansion)
                x: -0.5
            }
            // Cyan channel offset
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.2, 0.9, 1, 0.25 * root._expansion)
                x: 0.5
            }

            // Main glass body - semi-transparent with refraction gradient
            // This simulates bending the track colors through the lens
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.08 + 0.12 * root._expansion)

                // Refraction gradient - shows track colors through the glass
                // Left side shows accent (progress), right side shows track
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: root.thumbCenterX > root.width * 0.25
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                            : Qt.rgba(1, 1, 1, 0.25)
                    }
                    GradientStop {
                        position: 0.3
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }
                    GradientStop {
                        position: 0.7
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }
                    GradientStop {
                        position: 1
                        color: root.thumbCenterX < root.width * 0.75
                            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.5)
                            : Qt.rgba(0.5, 0.5, 0.55, 0.35)
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
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.2) }
                    }
                }
            }

            // Specular highlight - very subtle, almost invisible
            Rectangle {
                id: specularHighlight
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: root._dragOffset * 0.15
                width: parent.width * 0.4
                height: parent.height * 0.25
                radius: width / 2

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.25) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.08) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
                opacity: 0.3 + 0.3 * root._expansion
            }

            // Edge glow - soft rim light
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35 * root._expansion)
            }

            // Inner glow - soft fill from edges
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: height / 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(1, 1, 1, 0.1 * root._expansion)
            }
        }

        // Layer 3: Accent tint overlay (subtle color bleed when expanded)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.accentColor
            opacity: 0.12 * root._expansion
        }
    }

    // Mouse interaction
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real startX: 0
        property real startValue: 0

        onEntered: root._hovered = true
        onExited: root._hovered = false

        onPressed: function(mouse) {
            root._pressed = true
            root._expansion = 1.0
            root.triggerWobble()
            startX = mouse.x
            startValue = root.value
            root.previewChanged(root.positionForPointer(mouse.x))
        }

        onPositionChanged: function(mouse) {
            if (!pressed) return
            root._dragOffset = mouse.x - startX
            root.previewChanged(root.positionForPointer(mouse.x))
        }

        onReleased: function() {
            root._pressed = false
            root._expansion = 0.0
            root._dragOffset = 0
            // 提交后屏蔽 x 动画 400ms，等外部服务异步写回对齐（见 _suppressXAnimation）
            root._suppressXAnimation = true
            suppressXAnimTimer.restart()
            // 提交当前显示值，而不是用松开瞬间的鼠标位置重新计算：
            // 松手时鼠标常会无意识前带 1~2px，重算会让 thumb 松开后再滑一小步
            root.commitRequested(root.value)
        }

        onCanceled: {
            root._pressed = false
            root._expansion = 0.0
            root._dragOffset = 0
        }
    }
}
