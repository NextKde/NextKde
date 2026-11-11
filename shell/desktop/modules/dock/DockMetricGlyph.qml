import QtQuick
import qs.desktop.modules.common
BundledIcon {
    property string kind: "temperature"
    property color glyphColor: "white"
    name: kind === "clock" ? "time" : "cpu-temperature"
    color: glyphColor
}
