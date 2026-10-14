pragma Singleton
import QtQuick

// No real windows/services are read or changed by this persistent-hide test.
QtObject {
    property var records: []
    property int placementRevision: 0
    property string currentDesktopId: "fixture"
}
