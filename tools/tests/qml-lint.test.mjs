import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

const syntax = fileURLToPath(new URL('../qmllint-changed.mjs', import.meta.url));
const duplicates = fileURLToPath(new URL('../qml-duplicate-handlers.mjs', import.meta.url));
function fixture(fn) {
    const cwd = mkdtempSync(join(tmpdir(), 'qml-gate-'));
    const git = (...args) => execFileSync('git', args, {cwd, encoding: 'utf8'}).trim();
    const run = (script, args = [], env = {}) => spawnSync(process.execPath, [script, ...args], {
        cwd, encoding: 'utf8', env: {...process.env, ...env},
    });
    try {
        git('init', '-q'); git('config', 'user.name', 'Lint fixture'); git('config', 'user.email', 'lint@example.invalid');
        writeFileSync(join(cwd, 'README'), 'fixture'); git('add', '.'); git('commit', '-qm', 'base');
        fn({cwd, git, run, base: git('rev-parse', 'HEAD')});
    } finally { rmSync(cwd, {recursive: true, force: true}); }
}
function expect(result, status) { assert.equal(result.status, status, result.stdout + result.stderr); }

test('committed PR changes, spaces and modern JS are checked', () => fixture(({cwd, git, run, base}) => {
    writeFileSync(join(cwd, 'Space name.qml'), 'import QtQuick\nItem { property var dataValue: null; property var result: dataValue?.value ?? 0 }');
    git('add', '.'); git('commit', '-qm', 'valid');
    expect(run(syntax, ['--base', base]), 0);
    const result = run(duplicates, ['--base', base]); expect(result, 0); assert.match(result.stdout, /1 files/);
    writeFileSync(join(cwd, 'Space name.qml'), 'import QtQuick\nItem { property var dataValue: null; property var result: dataValue?.value ?? 0\n width: ) }');
    git('add', '.'); git('commit', '-qm', 'invalid');
    expect(run(syntax, ['--base', base]), 1);
}));
test('duplicate bindings fail, sibling objects and comments do not', () => fixture(({cwd, run}) => {
    const path = join(cwd, 'Example.qml');
    writeFileSync(path, 'import QtQuick\nItem { width: 1; width: 2 }');
    expect(run(duplicates), 1);
    writeFileSync(path, 'import QtQuick\nItem {\n Component.onCompleted: {}\n Component.onCompleted: {}\n}');
    expect(run(duplicates), 1);
    writeFileSync(path, 'import QtQuick\nItem { /* } width: 3 { */ Item { width: 1 } Item { width: 2 } }');
    expect(run(duplicates), 0);
}));
test('deleted files are skipped and missing executable fails closed', () => fixture(({cwd, git, run, base}) => {
    writeFileSync(join(cwd, 'Old.qml'), 'import QtQuick\nItem {}'); git('add', '.'); git('commit', '-qm', 'add');
    const withFile = git('rev-parse', 'HEAD');
    git('rm', 'Old.qml'); git('commit', '-qm', 'delete');
    const result = run(syntax, ['--base', withFile]); expect(result, 0); assert.match(result.stdout, /0 files/);
    expect(run(syntax, ['--base', base], {QMLLINT: '/missing/qmllint'}), 1);
}));
