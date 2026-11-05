import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as MenuIdentity from './AppMenuIdentity.mjs';

const item = (id, label, extra = {}) => ({ id, label, enabled: true, hasChildren: true, ...extra });
const previous = [item(1, 'File'), item(2, 'Edit')];
assert.equal(MenuIdentity.resolve(previous, 1, [item(9, 'Help'), item(11, 'File'), item(12, 'Edit')]), 2);
assert.equal(MenuIdentity.resolve(previous, 1, [item(2, 'Help'), item(12, 'Edit')]), 1);
assert.equal(MenuIdentity.resolve(previous, 1, []), -1);
assert.equal(MenuIdentity.resolve(previous, 1, [item(2, 'Help')]), -1);
assert.equal(MenuIdentity.resolve(previous, 1, [item(3, 'Edit'), item(4, 'Edit')]), -1);
assert.equal(MenuIdentity.resolve([item(1, 'Edit'), item(2, 'Edit')], 1, [item(3, 'Edit')]), -1);
assert.equal(MenuIdentity.resolve(previous, 1, [item(3, 'Edit', { hasChildren: false })]), -1);

// Execute the production opening functions with a controllable transport and
// deferred delegate recreation; no duplicate implementation of the flow.
const qml = readFileSync(new URL('./GlobalMenu.qml', import.meta.url), 'utf8');
const functions = qml.slice(qml.indexOf('    function freshRoot('), qml.indexOf('    onMaximumWidthChanged:'));
function harness() {
    const requests = [], deferred = [], presented = [];
    const state = { items: previous, _openingSerial: 0, visibleCount: 2,
        service: 'app', path: '/menu', popupRootId: 0, activeOpeningId: 0,
        MenuIdentity, menuPopup: { visible: false, hide() {} },
        menuItems: { itemAt: index => ({ index }) }, overflowButton: { overflow: true },
        Qt: { callLater: fn => deferred.push(fn) },
        AppMenuService: { requestLayout: (id, callback) => requests.push({ id, callback, layout: true }) },
        PlatformClient: { request: (op, payload, callback) => requests.push({ op, payload, callback }) },
        updateVisibleCount() {}, hydrate: (children, depth, done) => done(children),
        presentMenu: (...args) => presented.push(args) };
    Object.defineProperty(state.AppMenuService, 'items', { set: value => { state.items = value; } });
    state.root = state;
    vm.createContext(state);
    vm.runInContext(functions, state);
    return { state, requests, presented, flush: () => { while (deferred.length) deferred.shift()(); } };
}
{
    const h = harness();
    h.state.openItem(1);
    h.requests.shift().callback([item(8, 'Edit'), item(9, 'File')]);
    h.flush();
    const open = h.requests.shift();
    assert.equal(open.op, 'appmenu.open');
    assert.equal(open.payload.id, 8);
    assert.equal(h.requests.length, 0, 'wait for opened event before layout');
    open.callback({ ok: true });
    const layout = h.requests.shift();
    assert.equal(layout.id, 8);
    layout.callback([item(81, 'Copy', { hasChildren: false })]);
    assert.equal(h.presented[0][0], 8);
    assert.equal(h.presented[0][1].index, 0, 'use refreshed delegate, not the former index');
}
for (const fresh of [[], [item(2, 'Help')], [item(8, 'Edit', { enabled: false })]]) {
    const h = harness();
    h.state.openItem(1);
    h.requests.shift().callback(fresh);
    h.flush();
    assert.equal(h.requests.length, 0, 'never send old IDs after failed/missing/disabled refresh');
    assert.equal(h.presented.length, 0);
}
{
    const h = harness();
    h.state.openItem(1);
    h.state._openingSerial++;
    h.requests.shift().callback([item(8, 'Edit')]);
    h.flush();
    assert.equal(h.state.items, previous, 'stale response must not replace another application menu');
    assert.equal(h.requests.length, 0);
}
console.log('App menu refresh: identity, failure, ordering and stale callbacks passed');
