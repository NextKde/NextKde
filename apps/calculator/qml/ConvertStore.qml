import QtQuick
import "UnitTable.js" as Units

// The converter's state: which category is open, which two units the rows carry,
// and what the calculator's current value comes to in the other one.
//
// The arithmetic lives in the unit table; this only holds the pair and hands the
// table the number. The number is the calculator's own running value — the worth
// of the whole expression on screen — which is what the reference converts: its
// input row reads "500×200", not "200".
QtObject {
    id: store

    property string categoryId: "currency"
    property string fromUnit: Units.defaultFrom(categoryId)
    property string toUnit: Units.defaultTo(categoryId)

    // The calculator's current value, bound straight off the engine.
    property real amount: 0

    readonly property real result: convert(amount)

    // The pair follows the category, and follows it by assignment rather than
    // by binding: swap() writes these two directly, and an imperative write
    // would sever a binding anyway. The initialisers above are bindings only so
    // that the opening pair is not spelled out a second time here.
    onCategoryIdChanged: {
        fromUnit = Units.defaultFrom(categoryId)
        toUnit = Units.defaultTo(categoryId)
    }

    function convert(value) {
        return Units.convert(value, categoryId, fromUnit, toUnit)
    }

    function swap() {
        var held = fromUnit
        fromUnit = toUnit
        toUnit = held
    }
}
