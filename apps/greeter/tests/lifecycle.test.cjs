const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(`${__dirname}/../qml/Lifecycle.js`, 'utf8'), context);
const next = context.next;
let state = 'Idle';
for (const [event, expected] of [
  ['begin', 'Authenticating'], ['prompt', 'AwaitingPrompt'], ['respond', 'Authenticating'],
  ['ready', 'ReadyToLaunch'], ['exit', 'Exiting'], ['launch', 'LaunchRequested'],
  ['acknowledged', 'Terminated']
]) { state = next(state, event); assert.equal(state, expected); }
for (const phase of ['Authenticating', 'AwaitingPrompt']) {
  assert.equal(next(phase, 'failure'), 'Idle');
  assert.equal(next(phase, 'cancel'), 'Cancelling');
}
assert.equal(next('Cancelling', 'begin'), 'Cancelling');
assert.equal(next('Cancelling', 'ready'), 'Cancelling');
assert.equal(next('Cancelling', 'inactive'), 'Idle');
for (const phase of ['Idle', 'Authenticating', 'AwaitingPrompt', 'Cancelling', 'ReadyToLaunch', 'Exiting', 'LaunchRequested']) {
  assert.equal(next(phase, 'fatal'), 'Terminated');
  assert.equal(next(phase, 'timeout'), 'Terminated');
}
assert.equal(next('Idle', 'launch'), 'Idle');
assert.equal(next('LaunchRequested', 'begin'), 'LaunchRequested');
assert.equal(next('Terminated', 'begin'), 'Terminated');
console.log('PASS: lifecycle ordering, failure, cancellation barrier, timeout, stale events');
