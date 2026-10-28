import QtQuick
import Kos.Ui

// App-local layout contract, following nextkdeAppDemo GalleryDesign 2.9.
// Compact geometry and liquid material are independent choices.
QtObject {
    readonly property color contentPlane: AppTheme.dark ? "#1C1C1E" : "#FFFFFF"
    readonly property color sidebarPlane: AppTheme.dark ? "#242426" : "#F5F5F7"
    readonly property color dialogPlane: AppTheme.dark ? "#2C2C2E" : "#F7F7F9"
    readonly property color controlFill: AppTheme.dark ? "#3A3A3C" : "#EDEDF0"
    readonly property color labelPrimary: AppTheme.text
    readonly property color labelSecondary: AppTheme.mutedText
    readonly property color liquidLabel: AppTheme.dark ? "#D6D6D6" : "#555555"
    readonly property color separator: AppTheme.dark ? "#3A3A3C" : "#E3E3E8"
    readonly property color accent: AppTheme.dark ? "#0A84FF" : "#007AFF"
    readonly property color selectionDisc: "#8E8E93"
    readonly property color selectionFill: AppTheme.dark ? "#48484C" : "#DCDCE0"
    readonly property color rowHoverFill: AppTheme.dark ? "#363639" : "#DBDBDD"
    readonly property color searchFill: controlFill
    readonly property color segmentTrack: controlFill
    readonly property color segmentPill: AppTheme.dark ? "#636363" : "#D1D1D1"
    readonly property color positive: "#34C759"
    readonly property color warning: "#FF9F0A"
    readonly property color statusPositive: AppTheme.dark ? "#34C759" : "#24883D"
    readonly property color statusWarning: AppTheme.dark ? "#FF9F0A" : "#A85C00"
    readonly property int sidebarWidth: 224
    readonly property int rowHeight: 30
    readonly property int rowInsetLeading: 8
    readonly property int rowInsetTrailing: 8
    readonly property int rowIconInset: 8
    readonly property int rowIconSize: 16
    readonly property int rowTextGap: 8
    readonly property int rowFontSize: 13
    readonly property int rowDetailInset: 8
    readonly property int categoryRowHeight: 28
    readonly property int categoryInset: 16
    readonly property int categoryBoxSize: 12
    readonly property int categoryBoxRadius: 3
    readonly property int categoryTextGap: 8
    readonly property int categoryFontSize: 13
    readonly property int categoryHeadingTop: 12
    readonly property int categoryHeadingBottom: 4
    readonly property int miniDisc: 18
    readonly property int toolbarHeight: 40
    readonly property int toolbarButtonSize: 26
    readonly property int toolbarIconSize: 16
    readonly property int toolbarGap: 8
    readonly property int toolbarInsetLeft: 12
    readonly property int toolbarInsetRight: 16
    readonly property int segmentWidth: 224
    readonly property int segmentHeight: 26
    readonly property int dateBandHeight: 40
    readonly property int dateBandInset: 16
    readonly property int dateTitleSize: 24
    readonly property int dateNavHeight: 26
    readonly property int dateNavTextSize: 11
    readonly property int controlHeight: 28
    readonly property int controlFontSize: 11
    readonly property int fieldHeight: 28
    readonly property int searchHeight: 28
    readonly property int searchInsetLeading: 10
    readonly property int searchInsetTrailing: 10
}
