import assert from 'node:assert/strict';
import { responsivePointer } from './SpatialPointer.mjs';

for (const gain of [1, 2, 3, 5]) {
    assert.equal(responsivePointer(0, gain), 0);
    assert.equal(responsivePointer(1, gain), 1);
    assert.equal(responsivePointer(-1, gain), -1);
    assert.equal(responsivePointer(10, gain), 1);
    assert.equal(responsivePointer(-10, gain), -1);
    let previous = -1;
    for (let step = -100; step <= 100; step++) {
        const input = step / 100;
        const output = responsivePointer(input, gain);
        assert.ok(output >= previous && Math.abs(output) <= 1);
        assert.ok(Math.abs(output + responsivePointer(-input, gain)) < 1e-12);
        previous = output;
    }
}
assert.ok(Math.abs(responsivePointer(0.1) - 0.25) < 1e-12);
assert.equal(responsivePointer(0.5), 0.75);
assert.ok(Math.abs(responsivePointer(0.00001) / 0.00001 - 3) < 0.001);
assert.equal(responsivePointer(0.2, 1), 0.2);
assert.equal(responsivePointer(NaN), 0);
assert.equal(responsivePointer(Infinity), 0);
assert.equal(responsivePointer(0.2, NaN), responsivePointer(0.2));
console.log('PASS spatial pointer: small-movement gain, unchanged limits, smooth monotonic response, symmetry and invalid input');
