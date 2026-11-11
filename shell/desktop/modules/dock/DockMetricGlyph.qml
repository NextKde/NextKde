import QtQuick
import qs.desktop.modules.common
BundledIcon {
    property string kind: "temperature"
    property color glyphColor: "white"
    name: kind === "clock" ? "system.clock" : "system.cpuTemperature"
    color: glyphColor
}
