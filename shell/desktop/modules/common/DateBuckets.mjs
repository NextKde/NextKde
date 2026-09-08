// Snapshot local calendar fields as values: getters on an old Date would use
// the NEW timezone after a system timezone change, hiding the transition.
export function dayKey(date) {
    return [date.getFullYear(), date.getMonth(), date.getDate(),
        date.getTimezoneOffset()].join(":");
}

export function minuteKey(date) {
    return Math.floor(date.getTime() / 60000) + ":" + date.getTimezoneOffset();
}
