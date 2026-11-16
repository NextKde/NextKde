import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.wallpaper
import qs.desktop.modules.common

ShellRoot {
    id: test
    property int stage: 0
    property int ticks: 0
    property int moveWait: 0
    property int settleWait: 0
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 640
        implicitHeight: 360
        TestEvent { id: events }
        Rectangle {
            id: scene
            anchors.fill: parent
            color: "#00ff00"
            DepthWallpaperLayer {
                anchors.fill: parent
                targetScreen: window.screen
            }
            Rectangle {
                id: card
                x: 160; y: 80; width: 320; height: 200
                color: "#0000ff"
                property int clicks: 0
                MouseArea { anchors.fill: parent; onClicked: card.clicks++ }
            }
            Rectangle {
                id: otherCard
                x: 20; y: 300; width: 200; height: 40
                color: "#0000ff"
            }
            SpatialWidgetForeground {
                id: foreground
                anchors.fill: parent
                targetScreen: window.screen
                widgetRects: [{x:card.x,y:card.y,width:card.width,height:card.height},
                    {x:otherCard.x,y:otherCard.y,width:otherCard.width,height:otherCard.height}]
            }
            // Match the desktop file container's layer, including overlap.
            Rectangle { x: 180; y: 110; width: 32; height: 32; color: "yellow"; z: 3 }
        }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function capture(name) {
        scene.grabToImage(result => {
            check(result.saveToFile(Quickshell.env("CAPTURE_DIR") + "/" + name + ".png"), "capture saved")
            test.stage = ({"normal":1,"hover":12,"restored":14,"editing":3,"moved":5,"empty":7})[name]
        })
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            try {
                if (++test.ticks > 80) throw new Error("renderer timed out")
                ScreenLifecycle.activeScreen = window.screen
                if ((test.stage === 0 && (!foreground.ready || (Quickshell.env("EXPECTED_RENDERER") === "mesh" && !foreground.meshRendererAvailable))) || test.ticks < 6) return
                switch (test.stage) {
                case 0:
                    events.mouseMove(scene, 620, 340, 0, Qt.NoButton, Qt.NoModifier)
                    test.stage = 10
                    break
                case 10:
                    if (++test.settleWait < 3) return
                    test.stage = -10
                    capture("normal")
                    break
                case 1:
                    events.mouseMove(card, 80, 100, 0, Qt.NoButton, Qt.NoModifier)
                    events.mousePress(card, 80, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseRelease(card, 80, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    check(card.clicks === 1, "foreground passes clicks through")
                    test.settleWait = 0
                    test.stage = 11
                    break
                case 11:
                    if (++test.settleWait < 3) return
                    test.stage = -10
                    capture("hover")
                    break
                case 12:
                    events.mouseMove(scene, 620, 340, 0, Qt.NoButton, Qt.NoModifier)
                    test.settleWait = 0
                    test.stage = 13
                    break
                case 13:
                    if (++test.settleWait < 3) return
                    test.stage = -10
                    capture("restored")
                    break
                case 14:
                    foreground.suspended = true
                    test.stage = 2
                    break
                case 2:
                    test.stage = -2
                    capture("editing")
                    break
                case -1: break
                case -2: break
                case -3: break
                case -4: break
                case 3:
                    foreground.suspended = false
                    card.x = 80
                    foreground.pointerX = 0.6
                    foreground.pointerY = -0.4
                    test.stage = 4
                    break
                case 4:
                    if (++test.moveWait < 3) return
                    test.stage = -3
                    capture("moved")
                    break
                case 5:
                    foreground.widgetRects = []
                    test.stage = 6
                    break
                case 6:
                    test.stage = -4
                    capture("empty")
                    break
                case 7:
                    console.log("SPATIAL_WIDGET_PASS")
                    Qt.quit()
                }
            } catch (error) {
                console.error("SPATIAL_WIDGET_FAIL: " + error)
                Qt.quit()
            }
        }
    }
}
