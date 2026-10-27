import QtQuick
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

// IslandActionsWidget — the quick actions card.
//
// Notchy's home carries a "quickActions" card next to screen time, the
// launcher and the displays. Everything here goes through the platform
// contract, so the island never runs a command itself.
//
// The destructive actions (sign out, reboot, power off) need a second press:
// a card that can shut the machine down with one click is a card nobody
// puts on a shelf next to a screenshot button.
Item {
    id: root

    required property string widgetId

    property bool nightLightOn: false
    property bool keepAwakeOn: false
    property var powerProfiles: []
    property string powerProfile: ""
    // The action waiting for a confirming second press, and the moment it
    // stops waiting.
    property string pendingAction: ""
    property string pendingLabel: ""

    Component.onCompleted: refresh()

    function refresh() {
        PlatformClient.request("nightlight.get", {}, function(reply) {
            if (reply && reply.ok && reply.result)
                root.nightLightOn = Boolean(reply.result.enabled)
        })
        PlatformClient.request("keepawake.get", {}, function(reply) {
            if (reply && reply.ok && reply.result)
                root.keepAwakeOn = Boolean(reply.result.enabled)
        })
        PlatformClient.request("power.profiles", {}, function(reply) {
            if (!reply || !reply.ok || !reply.result)
                return
            const profiles = reply.result.profiles || []
            root.powerProfiles = profiles
            const current = reply.result.current || reply.result.active
            if (current)
                root.powerProfile = String(current)
        })
    }

    function run(action, payload, label) {
        // A destructive action waits for a second press.
        if (label && root.pendingAction !== action) {
            root.pendingAction = action
            root.pendingLabel = label
            confirmTimer.restart()
            return
        }
        root.pendingAction = ""
        root.pendingLabel = ""
        PlatformClient.request(action, payload || {}, function(reply) {
            if (!reply || !reply.ok)
                console.warn("[Island] " + action + " failed")
        })
    }

    function cyclePowerProfile() {
        if (!powerProfiles || powerProfiles.length === 0)
            return
        const names = powerProfiles.map(function(entry) {
            return typeof entry === "string" ? entry : String(entry.name || entry.id || "")
        })
        const index = names.indexOf(powerProfile)
        const next = names[(index + 1) % names.length]
        if (!next)
            return
        powerProfile = next
        PlatformClient.request("power.profile.set", { profile: next }, function(reply) {
            if (!reply || !reply.ok)
                powerProfile = ""
        })
    }

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: {
            root.pendingAction = ""
            root.pendingLabel = ""
        }
    }

    Column {
        anchors { fill: parent }
        spacing: 4

        Text {
            width: parent.width
            text: I18n.tr("Quick actions")
            color: Qt.rgba(1, 1, 1, 0.5)
            font.pixelSize: 9
        }

        Grid {
            width: parent.width
            columns: 3
            spacing: 4

            Repeater {
                model: [
                    { action: "session.lock", label: I18n.tr("Lock"), tone: 0 },
                    { action: "session.suspend", label: I18n.tr("Sleep"), tone: 0 },
                    { action: "screenshot.capture", label: I18n.tr("Capture"), tone: 0 },
                    { action: "nightlight.toggle", label: I18n.tr("Night light"), tone: 1 },
                    { action: "keepawake.set", label: I18n.tr("Keep awake"), tone: 1 },
                    { action: "power.profile.set", label: I18n.tr("Power"), tone: 2 }
                ]

                delegate: Rectangle {
                    required property var modelData

                    readonly property bool on:
                        modelData.action === "nightlight.toggle" ? root.nightLightOn
                        : modelData.action === "keepawake.set" ? root.keepAwakeOn
                        : modelData.action === "power.profile.set"
                            ? root.powerProfile.length > 0 : false

                    width: Math.floor((parent.width - 8) / 3)
                    height: 24
                    radius: 7
                    color: on ? Qt.rgba(0.29, 0.87, 0.5, 0.35)
                        : (actionTarget.hovered ? Qt.rgba(1, 1, 1, 0.10)
                                              : Qt.rgba(1, 1, 1, 0.05))
                    border.width: 1
                    border.color: on ? Qt.rgba(0.29, 0.87, 0.5, 0.5)
                        : Qt.rgba(1, 1, 1, 0.10)

                    Text {
                        anchors.fill: parent
                        text: modelData.action === "power.profile.set" && root.powerProfile.length > 0
                            ? root.powerProfile : modelData.label
                        color: Qt.rgba(1, 1, 1, 0.85)
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    IslandPointerTarget {
                        id: actionTarget
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.action === "nightlight.toggle") {
                                root.nightLightOn = !root.nightLightOn
                                root.run("nightlight.toggle", {}, "")
                            } else if (modelData.action === "keepawake.set") {
                                root.keepAwakeOn = !root.keepAwakeOn
                                root.run("keepawake.set", { enabled: root.keepAwakeOn }, "")
                            } else if (modelData.action === "power.profile.set") {
                                root.cyclePowerProfile()
                            } else {
                                root.run(modelData.action, {}, modelData.label)
                            }
                        }
                    }
                }
            }
        }

        // The destructive row. A second press confirms.
        Row {
            width: parent.width
            spacing: 4

            Repeater {
                model: [
                    { action: "session.logout", label: I18n.tr("Sign out") },
                    { action: "session.reboot", label: I18n.tr("Restart") },
                    { action: "session.poweroff", label: I18n.tr("Power off") }
                ]

                delegate: Rectangle {
                    required property var modelData

                    readonly property bool armed: root.pendingAction === modelData.action

                    width: Math.floor((parent.width - 8) / 3)
                    height: 22
                    radius: 7
                    color: armed ? Qt.rgba(0.95, 0.45, 0.35, 0.35)
                        : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: armed ? Qt.rgba(0.95, 0.45, 0.35, 0.6)
                        : Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        anchors.fill: parent
                        text: parent.armed ? I18n.tr("Confirm?") : modelData.label
                        color: parent.armed ? Qt.rgba(1, 0.85, 0.8, 0.95)
                            : Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 9
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.run(modelData.action, {}, modelData.label)
                    }
                }
            }
        }
    }
}
