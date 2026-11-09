import QtQuick
import QtQuick.Controls
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"
import "../../../../Kos/Ui"

Item {
    id: soundSubmenuView
    objectName: "control-center-soundpage"
    required property var service
    property real volumePreview: 0
    signal settingsRequested(string module)
    signal volumePreviewRequested(real value)
    signal draggingVolumeRequested(bool value)
    Item {
        id: soundVolumeSection
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: 14
            rightMargin: 14
        }
        height: 62

        GlassText {
            anchors { left: parent.left; top: parent.top; topMargin: 2 }
            text: I18n.tr("Master Volume")
            color: ThemeService.foregroundColor
            font { pixelSize: 11; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }

        GlassText {
            anchors { right: parent.right; top: parent.top; topMargin: 2 }
            text: Math.round(soundSubmenuView.volumePreview) + "%"
            color: ThemeService.foregroundColor
            opacity: 0.65
            font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
        }

        Canvas {
            id: submenuVolumeGlyph
            anchors { left: parent.left; leftMargin: 2; verticalCenter: submenuVolumeSlider.verticalCenter }
            width: 19
            height: 16
            renderTarget: Canvas.Image

            readonly property int volumeLevel: Math.round(soundSubmenuView.volumePreview)
            readonly property bool isMuted: soundSubmenuView.service.audioMuted
            // One resolved ink for the whole glyph: the muted body is
            // the same colour at a lower alpha, so it never has to be
            // recomputed from a light/dark pair here.
            readonly property color ink: AppearanceTokens.content.glassInk()

            onVolumeLevelChanged: requestPaint()
            onIsMutedChanged: requestPaint()
            onInkChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const fg = ink
                const bodyColor = isMuted
                    ? Qt.rgba(fg.r, fg.g, fg.b, 0.50) : fg

                ctx.fillStyle = bodyColor
                ctx.strokeStyle = fg
                ctx.lineWidth = 1.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.fillRect(1.0, 5.5, 3.2, 5.0)

                ctx.beginPath()
                ctx.moveTo(4.2, 5.5)
                ctx.lineTo(7.5, 2.5)
                ctx.lineTo(7.5, 13.5)
                ctx.lineTo(4.2, 10.5)
                ctx.closePath()
                ctx.fill()

                if (isMuted) {
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.lineWidth = 2.6
                    ctx.beginPath()
                    ctx.moveTo(0.8, 2.0)
                    ctx.lineTo(8.8, 14.0)
                    ctx.stroke()

                    ctx.globalCompositeOperation = "source-over"
                    ctx.lineWidth = 1.5
                    ctx.strokeStyle = fg
                    ctx.beginPath()
                    ctx.moveTo(0.8, 2.0)
                    ctx.lineTo(8.8, 14.0)
                    ctx.stroke()
                } else {
                    const arcs = volumeLevel > 66 ? 3 : (volumeLevel > 33 ? 2 : (volumeLevel > 0 ? 1 : 0))
                    const cx = 6.0, cy = 8.0
                    if (arcs >= 1) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, 4.2, -0.65, 0.65)
                        ctx.stroke()
                    }
                    if (arcs >= 2) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, 7.0, -0.70, 0.70)
                        ctx.stroke()
                    }
                    if (arcs >= 3) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, 9.8, -0.72, 0.72)
                        ctx.stroke()
                    }
                }
            }

            Connections {
                target: soundSubmenuView.service
                function onAudioMutedChanged() { submenuVolumeGlyph.requestPaint() }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: soundSubmenuView.service.setMuted(!soundSubmenuView.service.audioMuted)
            }
        }

        ControlCenterSlider {
            id: submenuVolumeSlider
            objectName: "submenuVolumeSlider"
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 26; rightMargin: 2; bottomMargin: 4 }
            height: 28
            value: soundSubmenuView.volumePreview / 100
            onPreviewChanged: function(v) {
                soundSubmenuView.draggingVolumeRequested(true)
                soundSubmenuView.volumePreviewRequested(Math.round(v * 100))
            }
            onCanceled: {
                soundSubmenuView.draggingVolumeRequested(false)
                soundSubmenuView.volumePreviewRequested(soundSubmenuView.service.volumePercent)
            }
            onCommitRequested: function(v) {
                soundSubmenuView.draggingVolumeRequested(false)
                if (soundSubmenuView.service.audioMuted)
                    soundSubmenuView.service.setMuted(false)
                soundSubmenuView.service.setVolume(Math.round(v * 100))
            }
        }
    }

    Item {
        id: soundOutputSection
        anchors {
            top: soundVolumeSection.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
            leftMargin: 14
            rightMargin: 14
        }
        height: 18 + audioOutputList.height + 28

        GlassText {
            text: I18n.tr("Output devices")
            color: ThemeService.foregroundColor
            opacity: 0.60
            font.pixelSize: 10
        }
        ListView {
            id: audioOutputList
            anchors { top: parent.top; topMargin: 18; left: parent.left; right: parent.right }
            // Every device stays visible up to three rows; past that the
            // list scrolls under an as-needed scrollbar instead of growing
            // into the application-volume section below.
            height: Math.min(contentHeight, 3 * 30 + 2 * spacing)
            clip: true
            spacing: 3
            model: soundSubmenuView.service.audioOutputs
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 3
                    radius: 1.5
                    color: ThemeService.foregroundColor
                    opacity: 0.35
                }
            }
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 30
                radius: 8
                color: modelData.isDefault ? Qt.rgba(0.1, 0.5, 1, 0.20) : Qt.rgba(0.5, 0.5, 0.5, 0.10)
                GlassText {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: Text.AlignVCenter
                    text: (modelData.isDefault ? "✓  " : "    ") + modelData.description
                    elide: Text.ElideRight
                    color: ThemeService.foregroundColor
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !soundSubmenuView.service.audioOutputChangeInProgress
                        && !soundSubmenuView.service.audioOutputsRefreshInProgress
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: soundSubmenuView.service.setAudioOutput(modelData.name)
                }
            }

            KosKineticScroll { flickable: audioOutputList }
        }
        GlassText {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 24
            text: soundSubmenuView.service.audioOutputChangeInProgress ? I18n.tr("Switching…")
                : soundSubmenuView.service.audioOutputError || (soundSubmenuView.service.audioOutputs.length
                    ? "" : soundSubmenuView.service.audioOutputsRefreshInProgress
                        ? I18n.tr("Reading…") : I18n.tr("No available output devices"))
            color: ThemeService.foregroundColor
            elide: Text.ElideRight
            font.pixelSize: 10
            MouseArea {
                anchors.fill: parent
                enabled: soundSubmenuView.service.audioOutputError.length > 0
                cursorShape: Qt.PointingHandCursor
                onClicked: soundSubmenuView.service.retryAudioOutputs()
            }
        }
    }

    Item {
        id: soundApplicationsSection
        anchors {
            top: soundOutputSection.bottom
            topMargin: 10
            left: parent.left
            right: parent.right
            bottom: soundFooter.top
            leftMargin: 14
            rightMargin: 14
            bottomMargin: 4
        }

        GlassText {
            id: soundApplicationsTitle
            anchors { left: parent.left; top: parent.top }
            text: I18n.tr("Application Volume")
            color: ThemeService.foregroundColor
            opacity: 0.60
            font { pixelSize: 10; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }

        GlassText {
            visible: soundSubmenuView.service.audioApplications.length === 0
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 8
            text: soundSubmenuView.service.audioApplicationsRefreshInProgress
                ? I18n.tr("Reading…") : I18n.tr("No active audio applications")
            color: ThemeService.foregroundColor
            opacity: 0.45
            font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
        }

        Column {
            anchors {
                top: soundApplicationsTitle.bottom
                topMargin: 5
                left: parent.left
                right: parent.right
            }
            spacing: 3

            Repeater {
                model: soundSubmenuView.service.audioApplications.slice(0, 3)

                delegate: Item {
                    id: appVolumeRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 58
                    property int volumePreview: Number(modelData.percent || 0)
                    property bool muted: !!modelData.muted

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: appVolumeHover.hovered
                            ? (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.055)))
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Rectangle {
                        id: appMuteButton
                        anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                        width: 28
                        height: 28
                        radius: 8
                        color: appVolumeRow.muted
                            ? Qt.rgba(1.0, 0.27, 0.23, ThemeService.isDark ? 0.30 : 0.18)
                            : (AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)))

                        GlassText {
                            anchors.centerIn: parent
                            text: appVolumeRow.muted ? "×" : "♪"
                            color: appVolumeRow.muted ? "#ff453a" : ThemeService.foregroundColor
                            font { pixelSize: appVolumeRow.muted ? 15 : 13; weight: Font.Bold }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                appVolumeRow.muted = !appVolumeRow.muted
                                soundSubmenuView.service.setApplicationMuted(appVolumeRow.modelData.id,
                                    appVolumeRow.muted)
                            }
                        }
                    }

                    GlassText {
                        id: appVolumeName
                        anchors {
                            left: appMuteButton.right
                            leftMargin: 8
                            right: appVolumePercent.left
                            rightMargin: 6
                            top: parent.top
                            topMargin: 5
                        }
                        text: appVolumeRow.modelData.name || I18n.tr("Audio application")
                        elide: Text.ElideRight
                        color: ThemeService.foregroundColor
                        font { pixelSize: 10; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
                    }

                    GlassText {
                        id: appVolumePercent
                        anchors { right: parent.right; rightMargin: 5; verticalCenter: appVolumeName.verticalCenter }
                        text: Math.round(appVolumeRow.volumePreview) + "%"
                        color: ThemeService.foregroundColor
                        opacity: 0.55
                        font { pixelSize: 9; family: AppearanceTokens.typography.textFamily }
                    }

                    ControlCenterSlider {
                        anchors {
                            left: appMuteButton.right
                            leftMargin: 8
                            right: parent.right
                            rightMargin: 4
                            bottom: parent.bottom
                            bottomMargin: 3
                        }
                        height: 27
                        value: Math.min(1, appVolumeRow.volumePreview / 150)
                        accentColor: AppearanceTokens.content.glassInk(
                            appVolumeRow.muted ? 0.25 : 0.42)
                        onPreviewChanged: function(v) {
                            appVolumeRow.volumePreview = Math.round(v * 150)
                        }
                        onCanceled: appVolumeRow.volumePreview = Qt.binding(function() {
                            return Number(appVolumeRow.modelData.percent || 0)
                        })
                        onCommitRequested: function(v) {
                            if (appVolumeRow.muted) {
                                appVolumeRow.muted = false
                                soundSubmenuView.service.setApplicationMuted(appVolumeRow.modelData.id, false)
                            }
                            soundSubmenuView.service.setApplicationVolume(appVolumeRow.modelData.id,
                                Math.round(v * 150))
                        }
                    }

                    HoverHandler { id: appVolumeHover }
                }
            }
        }
    }

    Item {
        id: soundFooter
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 38

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
            height: 1
            color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
        }

        GlassText {
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: I18n.tr("Sound settings…")
            color: soundSettingsMouse.containsMouse ? "#0a84ff" : ThemeService.foregroundColor
            font { pixelSize: 11; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }

        GlassText {
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: "›"
            color: ThemeService.foregroundColor
            opacity: 0.45
            font { pixelSize: 13; weight: Font.Bold }
        }

        MouseArea {
            id: soundSettingsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: soundSubmenuView.settingsRequested("kcm_pulseaudio")
        }
    }
}
