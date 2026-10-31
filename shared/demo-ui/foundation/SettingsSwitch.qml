import QtQuick
import QtQuick.Layouts
import "../controls" as Controls

// Ordinary compact switch for grouped forms; no nested liquid surface.
Controls.LiquidGlassSwitch {
    property string accessibleName: ""
    implicitWidth: 44
    implicitHeight: 20
    materialForm: true
    trackColor: AppTheme.dark ? "#56565A" : "#D1D1D6"
    accentColor: AppTheme.defaultAccentSeed
    Accessible.name: accessibleName
}
