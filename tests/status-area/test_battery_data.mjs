import assert from 'node:assert/strict';
import {summary, measurement, estimateRuntime} from '../../shell/desktop/modules/bar/BatteryData.mjs';

const pack = {chargeFullMah: 4500, chargeDesignMah: 5000, energyFullWh: 49.5,
    energyDesignWh: 55, voltage: 12, currentMa: -1000, powerWatts: -12, cycles: 0, temperature: 32.5};
const single = summary([pack]);
assert.equal(single.full, 4500);
assert.equal(single.unit, 'mAh');
assert.equal(single.health, 0.9);
assert.equal(single.powerWatts, 12);
assert.equal(single.currentMa, 1000);
assert.equal(single.cycles, 0);
const multiple = summary([pack, {...pack, voltage: 8, energyFullWh: 30.5, energyDesignWh: 45}]);
assert.equal(multiple.full, 80);
assert.equal(multiple.design, 100);
assert.equal(multiple.unit, 'Wh', 'do not sum mAh across packs at different voltages');
assert.equal(multiple.health, 0.8);
assert.equal(multiple.powerWatts, 24);
assert.equal(multiple.voltage, undefined, 'pack-specific values must not describe a combined device');
assert.equal(multiple.cycles, undefined);
assert.equal(summary([pack, {}]).full, null, 'a partial sample must not look like combined capacity');
assert.equal(summary([pack, {}]).powerWatts, null);
assert.equal(summary([{energyFullWh: 40, energyDesignWh: 50}]).unit, 'Wh');
assert.equal(summary([{energyFullWh: 40, energyDesignWh: 0}]).health, null);
assert.equal(summary(undefined).health, null);
assert.equal(measurement(undefined, 'W'), '—');
assert.equal(measurement(null, 'W'), '—');
assert.equal(measurement(NaN, 'W'), '—');
assert.equal(measurement(0, 'mA', 0), '0 mA');
assert.equal(measurement(-5, '°C', 1), '-5.0 °C');
assert.equal(estimateRuntime(7200, 30, 10), 7200, 'system estimate takes precedence over instantaneous draw');
assert.equal(estimateRuntime(0, 30, 10), 10800, 'remaining energy divided by discharge power gives runtime');
assert.equal(estimateRuntime(-1, 2, 12), 600, 'invalid system estimates use the measured fallback');
assert.equal(estimateRuntime(undefined, 0.05, 10), 18);
for (const value of [undefined, null, NaN, Infinity, 0, -1]) {
    assert.equal(estimateRuntime(0, 30, value), null, 'missing or zero power must not invent runtime');
    assert.equal(estimateRuntime(0, value, 10), null, 'missing energy must not invent runtime');
}
assert.equal(estimateRuntime(Infinity, 30, 10), 10800);
assert.equal(estimateRuntime(0, Number.MAX_VALUE, Number.MIN_VALUE), null, 'overflow is unavailable');
console.log('battery data: capacities, multi-pack health, valid zeroes and runtime estimates passed');
