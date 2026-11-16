import QtQuick
import Quickshell
import "."
Scope {
    FloatingWindow {
        visible: true
        implicitWidth: 680
        implicitHeight: 760
        color: "#333c42"
        Item {
            id: gallery
            anchors.fill: parent
            Row {
                Repeater {
                    model: [true, false]
                    delegate: Rectangle {
                        required property bool modelData
                        width: 340; height: 760
                        color: modelData ? "#253330" : "#e5e1d6"
                        Column {
                            x: 18; y: 18
                            width: 304
                            spacing: 18
                            Text { text: modelData ? "Dark · 2 notifications" : "Light · 2 notifications"; color: modelData ? "white" : "#222222"; font.pixelSize: 12 }
                            NotificationHistoryGroup {
                                width: parent.width
                                sourceKey: "desktop:org.test.icon"
                                appName: "QQ"
                                appIcon: ""
                                desktopEntry: "org.test.icon"
                                expanded: false
                                itemCount: 2
                                ink: modelData ? "white" : "#222222"
                                dark: modelData
                                itemsJson: JSON.stringify(Array.from({length: itemCount}, (_, index) => ({historyKey: index + 1, summary: "我的手机", body: "继续研究一下", timestamp: Date.now() - index * 120000})))
                            }
                            Text { text: modelData ? "Dark · 3 notifications" : "Light · 3 notifications"; color: modelData ? "white" : "#222222"; font.pixelSize: 12 }
                            NotificationHistoryGroup {
                                width: parent.width
                                sourceKey: "desktop:org.test.icon"
                                appName: "QQ"
                                appIcon: ""
                                desktopEntry: "org.test.icon"
                                expanded: false
                                itemCount: 3
                                ink: modelData ? "white" : "#222222"
                                dark: modelData
                                itemsJson: JSON.stringify(Array.from({length: itemCount}, (_, index) => ({historyKey: index + 1, summary: "我的手机", body: "测试通知", timestamp: Date.now() - index * 120000})))
                            }
                            Text { text: modelData ? "Dark · expanded" : "Light · expanded"; color: modelData ? "white" : "#222222"; font.pixelSize: 12 }
                            NotificationHistoryGroup {
                                width: parent.width
                                sourceKey: "desktop:org.test.icon"
                                appName: "QQ"
                                appIcon: ""
                                desktopEntry: "org.test.icon"
                                expanded: true
                                itemCount: 3
                                ink: modelData ? "white" : "#222222"
                                dark: modelData
                                itemsJson: JSON.stringify(Array.from({length: itemCount}, (_, index) => ({historyKey: index + 1, summary: ["我的手机", "新的消息", "上一条通知"][index], body: "展开后各条通知独立显示", timestamp: Date.now() - index * 120000})))
                            }
                        }
                    }
                }
            }
        }
    }
    Timer {
        running: true; interval: 700
        onTriggered: gallery.grabToImage(function(result) {
            if (!result.saveToFile(Quickshell.env("KOS_ICON_QA_IMAGE"))) throw new Error("QA save failed")
            console.log("NOTIFICATION_ICONS_TEST_PASS")
            Qt.quit()
        })
    }
}
