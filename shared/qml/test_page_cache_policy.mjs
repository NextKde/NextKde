import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const source = readFileSync(fileURLToPath(new URL(
    "./foundation/PageCachePolicy.js", import.meta.url)), "utf8")
    .replace(/^\.pragma library\s*/, "");
const policy = {};
vm.createContext(policy);
vm.runInContext(source, policy);

assert.deepEqual(Object.keys(policy.trim(
    { 0: 1, 1: 2, 2: 3, 3: 4 }, 3, [], 3, 4)).sort(),
    ["1", "2", "3"], "the least recently used page is evicted");

assert.deepEqual(Object.keys(policy.trim(
    { 0: 1, 1: 4, 2: 3, 3: 2 }, 1, [0], 3, 4)).sort(),
    ["0", "1", "2"], "pinned and current pages survive eviction");

assert.deepEqual(Object.keys(policy.trim(
    { 0: 1, 1: 2, 2: 3 }, 2, [0, 1], 1, 3)).sort(),
    ["0", "1", "2"], "the cache expands to fit mandatory pages");

assert.deepEqual(Object.keys(policy.trim(
    { 0: 1, 4: 2, [-1]: 3 }, 0, [], 3, 2)).sort(),
    ["0"], "stale indexes are removed when the page list changes");

assert.equal(policy.validIndex(1, 2), true);
assert.equal(policy.validIndex(2, 2), false);
assert.equal(policy.validIndex(0.5, 2), false);

console.log("KOS page cache policy: all checks passed");
