// Aggregate only comparable quantities. A pack voltage/current/cycle count is
// meaningful for one battery, not for a mixture of independent battery packs.
export function sum(rows, key) {
    if (!rows.length || !rows.every(row => Number.isFinite(row[key]) && row[key] >= 0)) return null;
    return rows.reduce((total, row) => total + row[key], 0);
}

export function summary(rows) {
    rows = Array.isArray(rows) ? rows : [];
    const chargeFull = sum(rows, "chargeFullMah"), chargeDesign = sum(rows, "chargeDesignMah");
    const energyFull = sum(rows, "energyFullWh"), energyDesign = sum(rows, "energyDesignWh");
    // mAh values can only be added at the same nominal voltage. Multi-pack
    // systems use Wh, matching UPower's combined display-device semantics.
    const chargeBased = rows.length === 1 && chargeFull > 0 && chargeDesign > 0;
    const full = chargeBased ? chargeFull : energyFull;
    const design = chargeBased ? chargeDesign : energyDesign;
    const one = rows.length === 1 ? rows[0] : {};
    const powers = rows.map(row => ({power: Number.isFinite(row.powerWatts) ? Math.abs(row.powerWatts) : null}));
    return {full, design, unit: chargeBased ? "mAh" : "Wh",
        health: full > 0 && design > 0 ? full / design : null,
        powerWatts: sum(powers, "power"), voltage: one.voltage,
        currentMa: Number.isFinite(one.currentMa) ? Math.abs(one.currentMa) : null,
        cycles: one.cycles, temperature: one.temperature};
}

export function measurement(value, unit, decimals = 2) {
    return Number.isFinite(value) ? value.toFixed(decimals) + " " + unit : "—";
}

// UPower's smoothed discharge estimate wins. If it is still unavailable, use
// remaining energy (Wh), not full/design capacity, and the current draw (W).
// Zero draw is unknown rather than an infinite runtime.
export function estimateRuntime(systemSeconds, energyWh, drawWatts) {
    if (Number.isFinite(systemSeconds) && systemSeconds > 0) return systemSeconds;
    if (!(Number.isFinite(energyWh) && energyWh > 0
        && Number.isFinite(drawWatts) && drawWatts > 0)) return null;
    const seconds = energyWh / drawWatts * 3600;
    return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
}
