pragma ComponentBehavior: Bound

import QtQuick

// The whole calculator core. Everything runs on QML's own JavaScript engine:
// the expression is a token array, evaluation is a recursive-descent walk, and
// number formatting goes through Number.prototype.toLocaleString with a plain
// grouping fallback for engines that ignore the options object.
//
// Tokens are either JS numbers or single display characters — "+", "-", "×",
// "÷", "^" (xʸ), "√" (ʸ√x), "E" (EE) and the parentheses. Keeping the operator
// token identical to what the display shows means the history line is just the
// tokens joined back together.
//
// The transcendental helpers are spelled out with exp/log rather than leaning
// on the ES6 Math additions, so a V4 build that ships without them degrades to
// a wrong-looking button instead of a broken keypad.
QtObject {
    id: engine

    // --- expression state --------------------------------------------
    property var tokens: []
    property string entry: "0"
    property bool typing: false
    property bool failed: false
    property string display: "0"
    // What the whole expression comes to as it stands — not the operand being
    // typed. The converter reads this, and "500 × 200" is worth 100,000 the
    // moment the last digit lands, not 200.
    property real value: 0
    // The line the display shows above the result: the tokens as they were
    // typed. Blank until the sum is more than one operand, and left standing
    // after "=" — that is the state the reference is photographed in.
    property string expression: ""
    // Set by "=" and cleared by the next digit, so a number typed after a
    // result starts a new sum instead of extending the old one.
    property bool evaluated: false

    // --- scientific state --------------------------------------------
    property bool second: false
    property bool radians: false
    property real memory: 0

    // Emitted once per "=" with the finished line and its result.
    signal calculated(string expression, string result)

    // --- display ------------------------------------------------------
    function updateDisplay() {
        if (failed) {
            display = qsTr("Error")
            expression = ""
            return
        }
        display = typing ? formatEntry(entry) : formatNumber(currentValue())
        value = runningValue()
        updateExpression()
    }

    // The tokens with the half-typed entry appended, evaluated. A trailing
    // operator is dropped first so that "500 ×" is still worth 500 rather than
    // falling off the end of the parse.
    function runningValue() {
        if (failed)
            return NaN
        var list = tokens.slice()
        if (typing)
            list.push(isFinite(parseFloat(entry)) ? parseFloat(entry) : 0)
        while (list.length > 0 && isBinaryOperator(list[list.length - 1]))
            list.pop()
        return list.length === 0 ? 0 : evaluate(list)
    }

    // The expression line is the tokens as typed with the half-typed entry
    // still appended, so "500" "×" "2" "0" "0" reads as 500×200 the whole way.
    // A lone operand is not an expression: the reference shows nothing above a
    // bare number, and nothing above a fresh 0.
    function updateExpression() {
        var text = ""
        var compound = false
        for (var i = 0; i < tokens.length; i++) {
            if (typeof tokens[i] === "string")
                compound = true
            text += typeof tokens[i] === "number"
                ? formatNumber(tokens[i]) : tokens[i]
        }
        if (typing)
            text += formatEntry(entry)
        expression = compound ? text : ""
    }

    function currentValue() {
        if (typing)
            return isFinite(parseFloat(entry)) ? parseFloat(entry) : 0
        if (tokens.length > 0 && tokens[tokens.length - 1] === ")")
            return evaluate(tokens.slice(operandStart(tokens)))
        for (var i = tokens.length - 1; i >= 0; i--)
            if (typeof tokens[i] === "number")
                return tokens[i]
        return 0
    }

    function operandStart(list) {
        var depth = 0
        for (var i = list.length - 1; i >= 0; i--) {
            if (list[i] === ")") depth++
            else if (list[i] === "(" && --depth === 0) return i
        }
        return list.length - 1
    }

    // Grouping for the digits as they are typed, so a trailing "." survives.
    function formatEntry(text) {
        var negative = text.charAt(0) === "-"
        var body = negative ? text.slice(1) : text
        var dot = body.indexOf(".")
        var whole = dot < 0 ? body : body.slice(0, dot)
        var fraction = dot < 0 ? "" : body.slice(dot)
        return (negative ? "-" : "") + group(whole) + fraction
    }

    function group(digits) {
        return String(digits).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    }

    function formatNumber(value) {
        if (typeof value !== "number" || !isFinite(value))
            return qsTr("Error")
        // Twelve significant digits absorb binary rounding so 0.1+0.2 reads as
        // 0.3; the display trims to ten below that via maximumFractionDigits.
        var rounded = Number(value.toPrecision(12))
        var text = null
        try {
            text = rounded.toLocaleString(Qt.locale().name, {
                maximumFractionDigits: 10,
                minimumFractionDigits: 0
            })
        } catch (error) {
            text = null
        }
        // Engines without Intl return the bare number; fall back to grouping.
        if (typeof text !== "string" || text.length === 0
                || (Math.abs(rounded) >= 1000 && text === String(rounded)))
            text = groupedNumber(rounded)
        return text
    }

    function groupedNumber(value) {
        var negative = value < 0
        var text = Math.abs(value).toFixed(10)
        text = text.replace(/0+$/, "").replace(/\.$/, "")
        var parts = text.split(".")
        parts[0] = group(parts[0])
        return (negative ? "-" : "") + parts.join(".")
    }

    // --- entry --------------------------------------------------------
    function digit(key) {
        if (failed)
            clear()
        // A digit typed after "=" starts a new sum rather than extending the
        // result: without this the result would sit in `tokens` as an operand
        // and the next sum would read "100,0005+".
        if (evaluated) {
            tokens = []
            evaluated = false
        }
        if (!typing) {
            if (tokens.length > 0 && tokens[tokens.length - 1] === ")")
                tokens = tokens.concat(["×"])
            entry = key === "." ? "0." : key
            typing = true
        } else if (key === ".") {
            if (entry.indexOf(".") >= 0)
                return
            entry += "."
        } else if (entry === "0") {
            entry = key
        } else {
            entry += key
        }
        updateDisplay()
    }

    function backspace() {
        if (failed) {
            clear()
            return
        }
        if (!typing)
            return
        entry = entry.length > 1 ? entry.slice(0, -1) : "0"
        if (entry === "" || entry === "-")
            entry = "0"
        updateDisplay()
    }

    function commit() {        if (!typing)
            return
        var value = parseFloat(entry)
        tokens = tokens.concat([isFinite(value) ? value : 0])
        entry = "0"
        typing = false
    }

    function isBinaryOperator(token) {
        return ["+", "-", "×", "÷", "^", "√", "E"].indexOf(token) >= 0
    }

    function operator(key) {
        if (failed)
            return
        commit()
        evaluated = false
        var next = tokens.slice()
        if (next.length > 0 && isBinaryOperator(next[next.length - 1]))
            next[next.length - 1] = key
        else
            next.push(key)
        tokens = next
        updateDisplay()
    }

    function equals() {
        if (failed)
            return
        commit()
        var next = tokens.slice()
        while (next.length > 0 && isBinaryOperator(next[next.length - 1]))
            next.pop()
        if (next.length === 0)
            return
        var line = formatExpression(next)
        var result = evaluate(next)
        failed = !isFinite(result)
        tokens = failed ? [] : [result]
        entry = "0"
        typing = false
        evaluated = true
        updateDisplay()
        if (!failed) {
            // The finished line stays above the result, which is the state the
            // reference is photographed in. updateDisplay has just cleared it —
            // a lone result is not an expression — so it is put back here.
            expression = line
            calculated(line, formatNumber(result))
        }
    }

    function clear() {
        tokens = []
        entry = "0"
        typing = false
        failed = false
        evaluated = false
        second = false
        updateDisplay()
    }

    function toggleSign() {
        if (failed)
            return
        if (typing) {
            entry = entry.charAt(0) === "-" ? entry.slice(1) : "-" + entry
            updateDisplay()
        } else {
            setCurrentValue(-currentValue())
        }
    }

    function percent() {
        if (failed)
            return
        setCurrentValue(currentValue() / 100)
    }

    function openParen() {
        if (failed)
            return
        if (evaluated) {
            tokens = []
            evaluated = false
        }
        commit()
        if (tokens.length > 0 && (typeof tokens[tokens.length - 1] === "number"
                                 || tokens[tokens.length - 1] === ")"))
            tokens = tokens.concat(["×"])
        tokens = tokens.concat(["("])
        updateDisplay()
    }

    function closeParen() {
        if (failed)
            return
        commit()
        tokens = tokens.concat([")"])
        updateDisplay()
    }

    // Replace the operand the next key would act on, committing a half-typed
    // entry first so a function never silently drops it.
    function setCurrentValue(value) {
        var next = tokens.slice()
        if (typing) {
            next.push(isFinite(parseFloat(entry)) ? parseFloat(entry) : 0)
            entry = "0"
            typing = false
        }
        if (next.length > 0 && next[next.length - 1] === ")")
            next = next.slice(0, operandStart(next)).concat([value])
        else if (next.length > 0 && typeof next[next.length - 1] === "number")
            next[next.length - 1] = value
        else
            next.push(value)
        tokens = next
        updateDisplay()
    }

    // --- scientific ---------------------------------------------------
    function unary(fn) {
        if (failed)
            return
        var result = fn(currentValue())
        if (!isFinite(result)) {
            failed = true
            updateDisplay()
            return
        }
        setCurrentValue(result)
    }

    function constant(value) {
        if (failed)
            clear()
        setCurrentValue(value)
    }

    function factorial(value) {
        if (value < 0 || Math.abs(value - Math.round(value)) > 1e-9)
            return NaN
        if (value > 170)
            return Infinity
        var result = 1
        for (var i = 2; i <= Math.round(value); i++)
            result *= i
        return result
    }

    function cubeRoot(value) {
        return value < 0 ? -Math.pow(-value, 1 / 3) : Math.pow(value, 1 / 3)
    }

    function sinh(value) {
        return (Math.exp(value) - Math.exp(-value)) / 2
    }

    function cosh(value) {
        return (Math.exp(value) + Math.exp(-value)) / 2
    }

    function tanh(value) {
        var doubled = Math.exp(2 * value)
        return (doubled - 1) / (doubled + 1)
    }

    function memoryAdd(sign) {
        if (failed)
            return
        memory += sign * currentValue()
    }

    function memoryRecall() {
        if (failed)
            return
        setCurrentValue(memory)
    }

    function toggleRadians() {
        radians = !radians
    }

    function angleToRadians(value) {
        return radians ? value : value * Math.PI / 180
    }

    function angleFromRadians(value) {
        return radians ? value : value * 180 / Math.PI
    }

    // --- evaluation ---------------------------------------------------
    function evaluate(list) {
        var pos = 0

        function peek() {
            return pos < list.length ? list[pos] : null
        }

        function parseExpression() {
            var value = parseTerm()
            while (peek() === "+" || peek() === "-") {
                var op = list[pos++]
                var right = parseTerm()
                value = op === "+" ? value + right : value - right
            }
            return value
        }

        function parseTerm() {
            var value = parsePower()
            while (peek() === "×" || peek() === "÷") {
                var op = list[pos++]
                var right = parsePower()
                value = op === "×" ? value * right : value / right
            }
            return value
        }

        function parsePower() {
            var value = parseExponent()
            if (peek() === "^" || peek() === "√") {
                var op = list[pos++]
                var right = parsePower()
                value = op === "^" ? Math.pow(value, right) : Math.pow(right, 1 / value)
            }
            return value
        }

        function parseExponent() {
            var value = parseFactor()
            while (peek() === "E") {
                pos++
                value = value * Math.pow(10, parseFactor())
            }
            return value
        }

        function parseFactor() {
            if (peek() === "(") {
                pos++
                var value = parseExpression()
                if (peek() === ")")
                    pos++
                return value
            }
            if (peek() === "-") {
                pos++
                return -parseFactor()
            }
            var token = list[pos++]
            return typeof token === "number" ? token : 0
        }

        return parseExpression()
    }

    function formatExpression(list) {
        var text = ""
        for (var i = 0; i < list.length; i++)
            text += typeof list[i] === "number" ? formatNumber(list[i]) : list[i]
        return text
    }

    // --- key routing ---------------------------------------------------
    // Every keypad routes through here, so the two keypads cannot drift apart
    // on what a shared key means.
    function press(key) {
        switch (key) {
        case "0": case "1": case "2": case "3": case "4":
        case "5": case "6": case "7": case "8": case "9": case ".":
            digit(key)
            break
        case "+": case "-": case "×": case "÷": case "^": case "√": case "E":
            operator(key)
            break
        case "=": equals(); break
        case "ac": clear(); break
        case "⌫": backspace(); break
        case "sign": toggleSign(); break
        case "percent": percent(); break
        case "(": openParen(); break
        case ")": closeParen(); break
        case "x²": unary(function(v) { return v * v }); break
        case "x³": unary(function(v) { return v * v * v }); break
        case "eˣ": unary(Math.exp); break
        case "10ˣ": unary(function(v) { return Math.pow(10, v) }); break
        case "1/x": unary(function(v) { return 1 / v }); break
        case "²√x": unary(Math.sqrt); break
        case "³√x": unary(cubeRoot); break
        case "ln": unary(Math.log); break
        case "log₁₀": unary(function(v) { return Math.log(v) / Math.LN10 }); break
        case "x!": unary(factorial); break
        case "sin": unary(function(v) { return Math.sin(angleToRadians(v)) }); break
        case "cos": unary(function(v) { return Math.cos(angleToRadians(v)) }); break
        case "tan": unary(function(v) { return Math.tan(angleToRadians(v)) }); break
        case "sin⁻¹": unary(function(v) { return angleFromRadians(Math.asin(v)) }); break
        case "cos⁻¹": unary(function(v) { return angleFromRadians(Math.acos(v)) }); break
        case "tan⁻¹": unary(function(v) { return angleFromRadians(Math.atan(v)) }); break
        case "sinh": unary(sinh); break
        case "cosh": unary(cosh); break
        case "tanh": unary(tanh); break
        case "sinh⁻¹": unary(function(v) { return Math.log(v + Math.sqrt(v * v + 1)) }); break
        case "cosh⁻¹": unary(function(v) { return Math.log(v + Math.sqrt(v * v - 1)) }); break
        case "tanh⁻¹": unary(function(v) { return 0.5 * Math.log((1 + v) / (1 - v)) }); break
        case "e": constant(Math.E); break
        case "π": constant(Math.PI); break
        case "Rand": constant(Math.random()); break
        case "mc": memory = 0; break
        case "m+": memoryAdd(1); break
        case "m-": memoryAdd(-1); break
        case "mr": memoryRecall(); break
        case "2nd": second = !second; break
        case "Rad": toggleRadians(); break
        default: break
        }
    }

    Component.onCompleted: updateDisplay()
}
