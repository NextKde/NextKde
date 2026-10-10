// Increase small movements while retaining the original [-1, 1] camera range.
// The normalized rational curve is continuous and never reaches a hard plateau.
export function responsivePointer(value, sensitivity = 3) {
    if (!Number.isFinite(value)) return 0;
    const pointer = Math.max(-1, Math.min(1, value));
    const gain = Number.isFinite(sensitivity) ? Math.max(1, sensitivity) : 3;
    return gain * pointer / (1 + (gain - 1) * Math.abs(pointer));
}
