import QtQuick 2.15
import QtTest 1.2

TestCase {
    name: "DateProjection"
    DateProjection { id: projection; sourceDate: new Date(2026, 8, 8, 12, 30, 0) }
    SignalSpy { id: daySpy; target: projection; signalName: "dayDateChanged" }
    SignalSpy { id: minuteSpy; target: projection; signalName: "minuteDateChanged" }

    function test_notifications() {
        projection.sourceDate = new Date(2026, 8, 8, 12, 30, 0)
        daySpy.clear()
        minuteSpy.clear()
        for (let second = 1; second < 60; second++)
            projection.sourceDate = new Date(2026, 8, 8, 12, 30, second)
        compare(daySpy.count, 0)
        compare(minuteSpy.count, 0)
        projection.sourceDate = new Date(2026, 8, 8, 12, 31, 0)
        compare(daySpy.count, 0)
        compare(minuteSpy.count, 1)
        projection.sourceDate = new Date(2026, 8, 8, 13, 31, 0)
        compare(minuteSpy.count, 2)
        projection.sourceDate = new Date(2027, 8, 8, 13, 31, 0)
        compare(daySpy.count, 1)
        compare(minuteSpy.count, 3)
        compare(projection.dayDate.getFullYear(), 2027)
        // A backwards clock adjustment also updates the projections.
        projection.sourceDate = new Date(2026, 8, 8, 12, 30, 0)
        compare(daySpy.count, 2)
        compare(minuteSpy.count, 4)
    }
}
