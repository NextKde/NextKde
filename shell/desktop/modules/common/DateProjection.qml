import QtQuick 2.15
import "DateBuckets.mjs" as DateBuckets

// No extra timer: consume the existing clock and only notify consumers when
// their calendar/minute bucket changes, including clock jumps and DST.
QtObject {
    id: projection
    property date sourceDate: new Date()
    readonly property date dayDate: _dayDate
    readonly property date minuteDate: _minuteDate
    property date _dayDate: new Date(0)
    property date _minuteDate: new Date(0)
    property string _dayKey: ""
    property string _minuteKey: ""

    function refresh() {
        const nextDay = DateBuckets.dayKey(sourceDate)
        const nextMinute = DateBuckets.minuteKey(sourceDate)
        if (nextDay !== _dayKey) {
            _dayKey = nextDay
            _dayDate = sourceDate
        }
        if (nextMinute !== _minuteKey) {
            _minuteKey = nextMinute
            _minuteDate = sourceDate
        }
    }

    onSourceDateChanged: refresh()
    Component.onCompleted: refresh()
}
