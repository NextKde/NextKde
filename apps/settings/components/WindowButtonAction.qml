import QtQuick
import Kos.Demo as Demo

Demo.LiquidActionButton {
    id: root
    iconOnly: true
    iconSize: 14
    materialForm: true
    implicitHeight: 26
    cornerRadius: 6
    Accessible.name: text
    Demo.KosToolTip {
        target: root
        text: root.text
    }
}
