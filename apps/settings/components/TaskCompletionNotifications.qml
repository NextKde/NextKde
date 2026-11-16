import QtQuick
import "../../../shared/qml/i18n"

QtObject {
    id: root
    readonly property string completedTitle: I18n.tr("Application task completed")
    readonly property string cancelledTitle: I18n.tr("Application task cancelled")
    readonly property string failedTitle: I18n.tr("Application task failed")
    readonly property string resultHint: I18n.tr("Open Settings to view the result.")
    readonly property Connections completion: Connections {
        target: typeof appStore !== "undefined" ? appStore : null
        function onTaskFinished(name, code) {
            if (typeof taskNotifications === "undefined") return
            const title = code === "" ? root.completedTitle
                : code === "CANCELLED" ? root.cancelledTitle : root.failedTitle
            taskNotifications.send(title, name + " — " + root.resultHint)
        }
    }
}
