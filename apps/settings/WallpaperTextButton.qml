import QtQuick
import Kos.Demo as Demo

// Existing wallpaper action API, with the canonical compact solid button.
Demo.LiquidActionButton {
    id: button
    property alias label: button.text
    property var colors
    property bool emphasized: false
    materialForm: true
    implicitHeight: 24
    cornerRadius: 6
    highlighted: emphasized
}
