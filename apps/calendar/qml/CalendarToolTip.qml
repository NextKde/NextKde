import QtQuick
import QtQuick.Window
import Kos.Demo as Demo

Demo.KosToolTip {
    id: tip
    backdrop: Demo.LiquidBackdrop {
        registerAsDefault: false
        sourceItem: tip.hostWindow ? tip.hostWindow.calendarScene : null
        active: tip.visible && !tip.reduceTransparency
        blur: 0.85
    }
}
