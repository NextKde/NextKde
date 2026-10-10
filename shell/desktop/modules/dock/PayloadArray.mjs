// PayloadArray.mjs — coerce array-shaped values from socket payloads.
// Pure ES module, no QML dependencies.
//
// Why this exists: payloads delivered through a QML signal (`eventReceived`)
// cross the QML/C++ boundary as QVariant values. A JSON array nested in such
// a payload comes back on Qt 6.12 as a QV4 sequence: `typeof` is "object",
// `length` and indexing work, and even `constructor.name` is "Array" — but
// `Array.isArray()` returns false. Guards written as `Array.isArray(x)` then
// silently discard every real payload list (observed with KWin window
// snapshots and virtual-desktop lists, which left the Dock with no running
// tasks). Coerce both shapes here instead of trusting Array.isArray.
//
// Returns null for anything that is not array-like, so callers can keep
// distinguishing "no list in the payload" from "an empty list".

export function toArray(value) {
    if (Array.isArray(value))
        return value
    if (value && typeof value === "object" && typeof value.length === "number")
        return Array.from(value)
    return null
}
