import QtQuick
import QtTest
import "../../apps/calculator/qml" as Calculator
import "../../apps/calculator/qml/UnitTable.js" as Units

TestCase {
    name: "CalculatorRelease"
    Calculator.CalculatorEngine { id: engine }

    function init() { engine.clear(); engine.memory = 0; engine.radians = false }
    function enter(keys) { for (const key of keys) engine.press(key) }

    function test_precedence() {
        enter(["2", "+", "3", "×", "4", "="])
        compare(engine.value, 14)
        verify(!engine.failed)
    }
    function test_parentheses() {
        enter(["(", "2", "+", "3", ")", "×", "4", "="])
        compare(engine.value, 20)
    }
    function test_equals_after_parentheses() {
        enter(["(", "2", "+", "3", ")", "="])
        compare(engine.value, 5)
    }
    function test_replacing_trailing_operator() {
        enter(["2", "+", "×", "3", "="])
        compare(engine.value, 6)
    }
    function test_live_conversion_value() {
        enter(["5", "0", "0", "×", "2", "0", "0"])
        compare(engine.value, 100000)
    }
    function test_decimal_rounding() {
        enter(["0", ".", "1", "+", "0", ".", "2", "="])
        verify(Math.abs(engine.value - 0.3) < 1e-12)
        verify(engine.display.indexOf("000000000") < 0)
    }
    function test_new_expression_after_result() {
        enter(["2", "+", "3", "=", "4", "+", "1", "="])
        compare(engine.value, 5)
    }
    function test_division_by_zero_recovery() {
        enter(["1", "÷", "0", "="])
        verify(engine.failed)
        enter(["7"])
        verify(!engine.failed)
        compare(engine.value, 7)
    }
    function test_scientific_and_memory() {
        enter(["9", "0", "sin"])
        verify(Math.abs(engine.value - 1) < 1e-12)
        enter(["m+", "ac", "mr"])
        compare(engine.value, 1)
    }
    function test_length_conversion() {
        compare(Units.convert(2.5, "length", "km", "m"), 2500)
        compare(Units.convert(2500, "length", "m", "km"), 2.5)
    }
    function test_affine_temperature_conversion() {
        compare(Units.convert(32, "temperature", "°F", "°C"), 0)
        compare(Units.convert(100, "temperature", "°C", "°F"), 212)
        verify(Math.abs(Units.convert(273.15, "temperature", "K", "°C")) < 1e-10)
    }
}
