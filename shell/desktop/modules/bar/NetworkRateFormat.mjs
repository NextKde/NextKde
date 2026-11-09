// Rate and byte formatting for the Network traffic panel.
//
// This is a literal port of the Forma panel's `number()` helper: the same
// unit ladder, the same three precision branches and the same trailing-zero
// trimming. The panel used to render those strings from C++, so keeping the
// exact output here is what keeps the header numbers and process rows visually
// identical after the QML rewrite.
//
// NetworkService.formatRate is intentionally NOT used: it is the bar readout's
// fixed-two-decimal formatter and a separate contract locks it down.

const RATE_UNITS = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"];
const BYTE_UNITS = ["B", "KB", "MB", "GB", "TB"];

export function format(value, bytes = false) {
    if (!Number.isFinite(value) || value < 0)
        return "—";
    const units = bytes ? BYTE_UNITS : RATE_UNITS;
    let scaled = value;
    let unit = 0;
    while (scaled >= 1024 && unit < 4) {
        scaled /= 1024;
        ++unit;
    }
    let digits = scaled.toFixed(scaled < 10 && unit ? 2 : scaled < 100 && unit ? 1 : 0);
    if (digits.indexOf(".") >= 0) {
        while (digits.endsWith("0"))
            digits = digits.slice(0, -1);
        if (digits.endsWith("."))
            digits = digits.slice(0, -1);
    }
    return digits + " " + units[unit];
}

// The large readout lays the number and unit out as two labels. An invalid
// sample formats as an em dash in both slots, exactly like the native scene's
// `parts.value(0)` / `parts.value(1)` fallback.
export function rateParts(value) {
    const text = format(value);
    if (text === "—")
        return { number: "—", unit: "—" };
    const split = text.indexOf(" ");
    return { number: text.slice(0, split), unit: text.slice(split + 1) };
}

export function bytes(value) {
    return format(value, true);
}
