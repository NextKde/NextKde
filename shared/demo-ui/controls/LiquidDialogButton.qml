import QtQuick
import "../foundation" as Foundation

// Solid action inside every liquid dialog: 30px high, capsule corners.
LiquidActionButton {
    id: root
    property bool primaryAction: false
    // Dialog primaries use the fixed Demo blue, never the host/system accent.
    readonly property color primaryFillColor: Foundation.AppTheme.defaultAccentSeed
    materialForm: true
    implicitHeight: 30
    leftPadding: 12
    rightPadding: leftPadding
    cornerRadius: height / 2
    // Keep focus/activation without adding a decorative outline.
    focusRingColor: "transparent"
    highlighted: primaryAction && enabled
    // Explicit role colours also cover buttons created by DialogButtonBox,
    // which can manage the highlighted property itself.
    surfaceColor: primaryAction && enabled
        ? root.primaryFillColor : Foundation.AppTheme.controlBackground
    accentColor: enabled ? root.primaryFillColor : Foundation.AppTheme.controlBackground
    textColor: !enabled ? Foundation.AppTheme.disabledText
        : destructive ? Foundation.AppTheme.destructive
        : primaryAction ? "#FFFFFF" : Foundation.AppTheme.text
}
