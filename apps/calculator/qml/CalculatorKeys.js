.pragma library

// Key tables for both keypads. A key is a plain object: where it sits in the
// grid, what it says, and which of the palette's roles paints it. Superscripts
// are the Unicode characters the reference's own labels use, so no rich-text
// layout is needed to draw x² or log₁₀.
//
// Roles: "number", "function" (the basic keypad's AC / ± / %), "operator" (the
// orange column), "scientific" (the scientific keypad's dark group) and
// "sciLight" (the two cells its reference lifts above the number block). Each
// table names the group its own reference paints, so a key's colour is stated
// where the key is written down rather than inferred from the keypad.

function digit(row, column, label) {
    return { row: row, column: column, label: label, key: label, role: "number" }
}

// The basic keypad's bottom row collapses 0 across two columns; with the
// history column open the wide key becomes the calculator badge that closes it
// and 0 takes a column of its own.
function basicKeys(historyOpen) {
    var keys = [
        { row: 0, column: 0, label: "AC", key: "ac", role: "function" },
        { row: 0, column: 1, label: "+/−", key: "sign", role: "function" },
        { row: 0, column: 2, label: "%", key: "percent", role: "function" },
        { row: 0, column: 3, label: "÷", key: "÷", role: "operator" },

        digit(1, 0, "7"), digit(1, 1, "8"), digit(1, 2, "9"),
        { row: 1, column: 3, label: "×", key: "×", role: "operator" },

        digit(2, 0, "4"), digit(2, 1, "5"), digit(2, 2, "6"),
        { row: 2, column: 3, label: "−", key: "-", role: "operator" },

        digit(3, 0, "1"), digit(3, 1, "2"), digit(3, 2, "3"),
        { row: 3, column: 3, label: "+", key: "+", role: "operator" },

        { row: 4, column: 2, label: ".", key: ".", role: "number" },
        { row: 4, column: 3, label: "=", key: "=", role: "operator" }
    ]

    if (historyOpen) {
        keys.push({ row: 4, column: 0, label: "", key: "@history",
                    role: "number", icon: "calculator", badge: true })
        keys.push({ row: 4, column: 1, label: "0", key: "0", role: "number" })
    } else {
        keys.push({ row: 4, column: 0, columnSpan: 2, label: "0", key: "0",
                    role: "number" })
    }
    return keys
}

// The scientific keypad is the ten-column grid the landscape reference draws:
// six columns of scientific keys, the two cells it lifts out of that group
// (AC and %), its three-column number block, and the orange operator column.
// The arrangement is the reference's own, cell for cell — including the delete
// key it puts at the end of the function columns and the +/- it moves down into
// the number block.
function scientificKeys() {
    var keys = [
        { row: 0, column: 0, label: "(", key: "(", role: "scientific" },
        { row: 0, column: 1, label: ")", key: ")", role: "scientific" },
        { row: 0, column: 2, label: "mc", key: "mc", role: "scientific" },
        { row: 0, column: 3, label: "m+", key: "m+", role: "scientific" },
        { row: 0, column: 4, label: "m-", key: "m-", role: "scientific" },
        { row: 0, column: 5, label: "mr", key: "mr", role: "scientific" },
        { row: 0, column: 6, label: "", key: "⌫", role: "scientific",
          icon: "backspace" },
        { row: 0, column: 7, label: "AC", key: "ac", role: "sciLight" },
        { row: 0, column: 8, label: "%", key: "percent", role: "sciLight" },
        { row: 0, column: 9, label: "÷", key: "÷", role: "operator" },

        { row: 1, column: 0, label: "2ⁿᵈ", key: "2nd", role: "scientific", toggle: true },
        { row: 1, column: 1, label: "x²", key: "x²", role: "scientific" },
        { row: 1, column: 2, label: "x³", key: "x³", role: "scientific" },
        { row: 1, column: 3, label: "xʸ", key: "^", role: "scientific" },
        { row: 1, column: 4, label: "eˣ", key: "eˣ", role: "scientific" },
        { row: 1, column: 5, label: "10ˣ", key: "10ˣ", role: "scientific" },
        digit(1, 6, "7"), digit(1, 7, "8"), digit(1, 8, "9"),
        { row: 1, column: 9, label: "×", key: "×", role: "operator" },

        { row: 2, column: 0, label: "¹/ₓ", key: "1/x", role: "scientific" },
        { row: 2, column: 1, label: "²√x", key: "²√x", role: "scientific" },
        { row: 2, column: 2, label: "³√x", key: "³√x", role: "scientific" },
        { row: 2, column: 3, label: "ʸ√x", key: "√", role: "scientific" },
        { row: 2, column: 4, label: "ln", key: "ln", role: "scientific" },
        { row: 2, column: 5, label: "log₁₀", key: "log₁₀", role: "scientific" },
        digit(2, 6, "4"), digit(2, 7, "5"), digit(2, 8, "6"),
        { row: 2, column: 9, label: "−", key: "-", role: "operator" },

        { row: 3, column: 0, label: "x!", key: "x!", role: "scientific" },
        { row: 3, column: 1, label: "sin", key: "sin", role: "scientific",
          alternate: { label: "sin⁻¹", key: "sin⁻¹" } },
        { row: 3, column: 2, label: "cos", key: "cos", role: "scientific",
          alternate: { label: "cos⁻¹", key: "cos⁻¹" } },
        { row: 3, column: 3, label: "tan", key: "tan", role: "scientific",
          alternate: { label: "tan⁻¹", key: "tan⁻¹" } },
        { row: 3, column: 4, label: "e", key: "e", role: "scientific" },
        { row: 3, column: 5, label: "EE", key: "E", role: "scientific" },
        digit(3, 6, "1"), digit(3, 7, "2"), digit(3, 8, "3"),
        { row: 3, column: 9, label: "+", key: "+", role: "operator" },

        { row: 4, column: 0, label: "Rand", key: "Rand", role: "scientific" },
        { row: 4, column: 1, label: "sinh", key: "sinh", role: "scientific",
          alternate: { label: "sinh⁻¹", key: "sinh⁻¹" } },
        { row: 4, column: 2, label: "cosh", key: "cosh", role: "scientific",
          alternate: { label: "cosh⁻¹", key: "cosh⁻¹" } },
        { row: 4, column: 3, label: "tanh", key: "tanh", role: "scientific",
          alternate: { label: "tanh⁻¹", key: "tanh⁻¹" } },
        { row: 4, column: 4, label: "π", key: "π", role: "scientific" },
        { row: 4, column: 5, label: "Rad", key: "Rad", role: "scientific", toggle: true },
        { row: 4, column: 6, label: "+/−", key: "sign", role: "number" },
        digit(4, 7, "0"),
        { row: 4, column: 8, label: ".", key: ".", role: "number" },
        { row: 4, column: 9, label: "=", key: "=", role: "operator" }
    ]
    return keys
}
