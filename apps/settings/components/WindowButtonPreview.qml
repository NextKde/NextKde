import QtQuick
import Kos.Icons as Symbols
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Shapes
import Kos.Demo as Demo
import "../../../shared/qml/foundation" as Foundation
import "../../../shared/qml/i18n"

// A local illustration only: never connects to WindowSettings or a real window.
ColumnLayout {
    id: root
    required property var colors
    property bool materialForm: false
    property real playhead: 0
    property bool ready: false
    readonly property Flickable viewport: {
        let item = parent;
        while (item) {
            if (item instanceof Flickable)
                return item;
            item = item.parent;
        }
        return null;
    }
    // Read each ancestor's y so layout changes and scrolling both update this.
    readonly property real illustrationTop: {
        let item = illustration;
        let top = 0;
        while (item && viewport && item !== viewport.contentItem) {
            top += item.y;
            item = item.parent;
        }
        return viewport ? top - viewport.contentY : 0;
    }
    readonly property bool inView: visible
        && (!root.Window.window || (root.Window.window.visible
            && root.Window.window.visibility !== Window.Minimized))
        && (!viewport || (illustrationTop + illustration.height / 2 > 0
            && illustrationTop + illustration.height / 2 < viewport.height))
    readonly property bool reducedMotion: Foundation.AppTheme.reduceMotion
    readonly property bool dark: Demo.AppTheme.dark
    readonly property int step: playhead < 1300 ? 0 : playhead < 3000 ? 1
        : playhead < 5300 ? 2 : playhead < 8200 ? 3
        : playhead < 11100 ? 4 : playhead < 13000 ? 5 : 6
    readonly property real overlayOpacity: progress(1300, 1900) * (1 - progress(13200, 13900))
    readonly property real moveProgress: progress(5900, 7400)
    readonly property real coverProgress: progress(9000, 10400)
    readonly property real editingOpacity: progress(4400, 4650) * (1 - progress(12000, 12300))
    readonly property bool rightPressed: (playhead >= 4150 && playhead < 4450)
        || (playhead >= 11700 && playhead < 12000)
    readonly property bool leftPressed: (playhead >= 5700 && playhead < 7600)
        || (playhead >= 8800 && playhead < 10600)
    readonly property real pointerX: playhead < 5300
        ? 344 - 48 * progress(3200, 4000)
        : playhead < 8200 ? 296 - 18 * moveProgress
        : playhead < 11100 ? 278 + 66 * progress(8300, 8750) + 26 * coverProgress
        : 370 - 74 * progress(11200, 11600)
    readonly property real pointerY: playhead < 5300
        ? 92 - 63 * progress(3200, 4000)
        : playhead < 8200 ? 29 + 4 * moveProgress
        : playhead < 11100 ? 33 - progress(8300, 8750) : 32
    readonly property string gesture: step === 2 ? I18n.tr("Right-click")
        : step === 3 ? I18n.tr("Drag to move")
        : step === 4 ? I18n.tr("Drag an edge") : I18n.tr("Right-click to finish")
    readonly property string caption: step === 0
        ? I18n.tr("The app's original window buttons.")
        : step === 1 ? I18n.tr("KOS buttons and background cover the original buttons.")
        : step === 2 ? I18n.tr("Right-click the background to enter adjustment mode.")
        : step === 3 ? I18n.tr("Hold the left mouse button and drag to reposition the buttons.")
        : step === 4 ? I18n.tr("Drag an edge to resize the background; buttons stay fixed.")
        : step === 5 ? I18n.tr("Right-click again to save the position and size.")
        : I18n.tr("Hide the KOS overlay; keep the original buttons.")
    spacing: 6
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 6
    Layout.bottomMargin: 6

    function progress(start, end) {
        const t = Math.max(0, Math.min(1, (playhead - start) / (end - start)));
        return t * t * (3 - 2 * t);
    }

    function showStep(index) {
        if (playback)
            playback.stop();
        playhead = [0, 2400, 4800, 7800, 10800, 12500, 14500][index];
    }

    function play() {
        playback.stop();
        playhead = 0;
        playback.start();
    }

    function syncPlayback() {
        if (!ready)
            return;
        if (inView && !reducedMotion)
            play();
        else
            playback.stop();
    }

    // Loop while the illustration is in the viewport. Manual pause/step selection
    // stays put until the user replays it or scrolls away and back.
    onInViewChanged: syncPlayback()
    onReducedMotionChanged: {
        showStep(step);
        syncPlayback();
    }
    Component.onCompleted: {
        ready = true;
        syncPlayback();
    }
    SequentialAnimation {
        id: playback
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "playhead"
            from: 0
            to: 15000
            duration: 15000
        }
        PauseAnimation { duration: 1500 }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: I18n.tr("Illustration only")
            color: root.colors.secondaryText
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
        Basic.Button {
            id: playbackButton
            objectName: root.objectName + "Play"
            implicitHeight: 24
            implicitWidth: contentItem.implicitWidth + 16
            horizontalPadding: 8
            verticalPadding: 4
            hoverEnabled: true
            text: root.reducedMotion ? I18n.tr("Next step")
                : playback.running ? I18n.tr("Pause demonstration") : I18n.tr("Play demonstration")
            contentItem: Text {
                text: playbackButton.text
                textFormat: Text.PlainText
                font.pixelSize: 11
                color: root.colors.primaryText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 6
                color: Demo.AppTheme.controlBackground
                border.width: playbackButton.visualFocus ? 2 : 0
                border.color: Demo.AppTheme.focusRing
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Demo.AppTheme.text
                    opacity: playbackButton.down ? 0.13 : playbackButton.hovered ? 0.07 : 0
                }
            }
            onClicked: {
                if (root.reducedMotion)
                    root.showStep((root.step + 1) % 7);
                else if (playback.running)
                    playback.stop();
                else
                    root.play();
            }
        }
    }

    Rectangle {
        id: illustration
        Layout.fillWidth: true
        implicitHeight: 184 + captionLabel.implicitHeight + 12
        radius: 10
        gradient: Gradient {
            GradientStop { position: 0; color: root.dark ? "#26282d" : "#f0f1f4" }
            GradientStop { position: 1; color: root.dark ? "#202226" : "#e6e8ed" }
        }
        clip: true
        Accessible.role: Accessible.Graphic
        Accessible.name: root.caption

        // Uniform scaling keeps the pointer and its target together in narrow panes.
        Item {
            id: scene
            width: 400
            height: 164
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            scale: Math.min(1, Math.max(0, (parent.width - 16) / width))
            Accessible.ignored: true

            // Soft, inexpensive shadow layers; no shader or captured backdrop.
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    x: miniWindow.x - (5 - index)
                    y: miniWindow.y + 4 - (5 - index)
                    width: miniWindow.width + (5 - index) * 2
                    height: miniWindow.height + (5 - index) * 2
                    radius: miniWindow.radius + (5 - index)
                    color: root.dark ? "#06000000" : "#02000000"
                }
            }
            Rectangle {
                id: miniWindow
                x: 12; y: 16
                width: 376; height: 132
                radius: 10
                color: root.dark ? "#303136" : "#fcfcfd"
                border.width: 1
                border.color: root.dark ? "#54555a" : "#c8c9ce"

                Rectangle {
                    x: 1; y: 1
                    width: parent.width - 2; height: 52
                    radius: 9
                    gradient: Gradient {
                        GradientStop { position: 0; color: root.dark ? "#414247" : "#f5f5f7" }
                        GradientStop { position: 1; color: root.dark ? "#38393e" : "#ebebee" }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 8
                        color: root.dark ? "#38393e" : "#ebebee"
                    }
                }
                Text {
                    x: 18; y: 20
                    width: 196
                    text: I18n.tr("Example app")
                    color: root.dark ? "#e1e1e5" : "#55555c"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Rectangle {
                    x: 1; y: 53
                    width: parent.width - 2; height: 1
                    color: root.dark ? "#222328" : "#d7d7dc"
                }
                Rectangle {
                    x: 12; y: 66
                    width: 62; height: 52; radius: 5
                    color: root.dark ? "#393a40" : "#f0f1f4"
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            x: 9; y: 10 + index * 13
                            width: index === 0 ? 43 : 30
                            height: 4; radius: 2
                            color: root.dark ? "#55565e" : "#d2d5dd"
                        }
                    }
                }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: 88; y: 72 + index * 15
                        width: index === 0 ? 126 : index === 1 ? 104 : 78
                        height: index === 0 ? 6 : 4; radius: 2
                        color: root.dark ? "#56575f" : "#d9dbe1"
                    }
                }

                Row {
                    x: 266; y: 14
                    Repeater {
                        model: ["minimize", "maximize", "close"]
                        Item {
                            required property string modelData
                            width: 32; height: 28
                            Symbols.Icon {
                                anchors.centerIn: parent
                                size: 10
                                name: modelData === "maximize" ? "square" : modelData === "minimize" ? "minus" : "xmark"
                                color: root.colors.secondaryText
                            }
                        }
                    }
                }

                Item {
                    id: overlay
                    width: parent.width; height: parent.height
                    x: -18 * root.moveProgress
                    y: 4 * root.moveProgress
                    opacity: root.overlayOpacity

                    Rectangle {
                        id: cover
                        x: 266 - 8 * root.coverProgress
                        y: 14 - 4 * root.coverProgress
                        width: 96 + 34 * root.coverProgress
                        height: 28 + 8 * root.coverProgress
                        radius: 7
                        color: root.dark ? "#3d3e43" : "#efeff2"
                        border.width: 1
                        border.color: root.dark ? "#53545b" : "#dedee3"
                    }
                    Foundation.KosWindowControls {
                        x: 274; y: 21
                        targetWindow: QtObject { readonly property int visibility: 0 }
                        compositorIntegration: false
                        enabled: false
                        actions: ["minimize", "maximize", "close"]
                        circleSize: 14
                        buttonWidth: 14
                        buttonHeight: 14
                        spacing: 18
                        Accessible.ignored: true
                    }
                    Rectangle {
                        anchors.fill: cover
                        radius: cover.radius
                        color: "transparent"
                        border.width: 1
                        border.color: root.colors.accent
                        opacity: root.editingOpacity
                    }
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            x: cover.x + (index % 2 === 0 ? 0 : cover.width) - width / 2
                            y: cover.y + (index < 2 ? 0 : cover.height) - height / 2
                            width: 5; height: 5; radius: 1.5
                            color: root.dark ? "#eeeeef" : "#ffffff"
                            border.width: 1
                            border.color: root.colors.accent
                            opacity: root.editingOpacity
                        }
                    }
                }

                // A visible secondary-button press precedes the adjustment outline.
                Rectangle {
                    x: root.pointerX - width / 2
                    y: root.pointerY - height / 2
                    width: 30; height: 30; radius: 15
                    color: "transparent"
                    border.width: 2
                    border.color: root.colors.accent
                    opacity: root.rightPressed ? 0.65 : 0
                }
                Item {
                    x: root.pointerX; y: root.pointerY
                    width: 24; height: 26
                    opacity: root.progress(3100, 3400) * (1 - root.progress(12500, 12900))
                    scale: root.rightPressed || root.leftPressed ? 0.92 : 1
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            strokeWidth: 1.2
                            strokeColor: "#ffffff"
                            fillColor: "#202126"
                            joinStyle: ShapePath.RoundJoin
                            PathSvg {
                                path: root.step === 4
                                    ? "M -9 0 L -3 -5 L -3 -2 L 3 -2 L 3 -5 L 9 0 L 3 5 L 3 2 L -3 2 L -3 5 Z"
                                    : "M 0 0 L 0 19 L 5 14 L 9 23 L 12 21 L 8 13 L 15 13 Z"
                            }
                        }
                    }
                }
                Rectangle {
                    x: 230; y: 89
                    width: 132; height: 28; radius: 14
                    color: root.dark ? "#46474e" : "#ffffff"
                    border.width: 1
                    border.color: root.dark ? "#5b5c64" : "#dedfe5"
                    opacity: root.progress(3400, 3700) * (1 - root.progress(12500, 12900))
                    Rectangle {
                        x: 10; y: 5
                        width: 13; height: 18; radius: 6
                        color: root.dark ? "#33343a" : "#f3f4f6"
                        border.width: 1
                        border.color: root.colors.secondaryText
                        Rectangle {
                            x: root.step === 2 || root.step === 5 ? 7 : 2
                            y: 2; width: 4; height: 6; radius: 2
                            color: root.colors.accent
                            opacity: root.rightPressed || root.leftPressed ? 1 : 0.35
                        }
                    }
                    Text {
                        x: 29; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 36
                        text: root.gesture
                        font.pixelSize: 10
                        color: root.colors.primaryText
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Text {
            id: captionLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 8
            text: root.caption
            textFormat: Text.PlainText
            color: root.colors.secondaryText
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
