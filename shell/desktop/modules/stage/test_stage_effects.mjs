import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { effectSwitchCommand, reconfigureEffectCommand, shellQuote } from './stage-effects.mjs';

const dir = mkdtempSync(join(tmpdir(), 'stage-effects-'));
// Absolute interpreter: the Fedora scenario below runs with a PATH that holds
// nothing but the mocks.
const python = spawnSync('bash', ['-c', 'command -v python3'], { encoding: 'utf8' }).stdout.trim();
const bash = spawnSync('bash', ['-c', 'command -v bash'], { encoding: 'utf8' }).stdout.trim();
const mock = `#!${python}
import json, os, sys
p=os.environ['STAGE_TEST_STATE']
s=json.load(open(p)); args=sys.argv[1:]; cmd=os.path.basename(sys.argv[0])
s['calls'].append([cmd]+args)
rc=0; out=''
if cmd in ('qdbus6', 'qdbus-qt6'):
    op=args[-2].split('.')[-1]; effect=args[-1]
    if op=='isEffectLoaded': out=str(s['loaded'][effect]).lower()
    elif op=='loadEffect':
        if s.get('failLoad')==effect: out='false'
        else: s['loaded'][effect]=True; out='true'
    elif op=='unloadEffect':
        if s.get('failUnload')==effect: rc=1
        else: s['loaded'][effect]=False
elif cmd=='kreadconfig6': out=s['config'].get(args[args.index('--key')+1], '__missing__')
else:
    key=args[args.index('--key')+1]
    if s.get('failWrite')==key and args[-1]=='true': rc=1
    elif args[-1]=='--delete': s['config'].pop(key, None)
    else: s['config'][key]=args[-1]
json.dump(s, open(p,'w'))
if out: print(out)
sys.exit(rc)
`;
for (const cmd of ['qdbus6', 'kreadconfig6', 'kwriteconfig6'])
    writeFileSync(join(dir, cmd), mock, { mode: 0o755 });
let cases = 0;
function run(enabled, changes = {}, commit = ':', path = dir + ':' + process.env.PATH) {
    const initial = { loaded: { stageanim13: !enabled, kos_dock_window_animation: enabled },
        config: {}, calls: [], ...changes };
    const statePath = join(dir, 'state.json');
    writeFileSync(statePath, JSON.stringify(initial));
    const result = spawnSync(bash, ['-c', effectSwitchCommand(enabled, 'stageanim13', commit)],
        { env: { ...process.env, PATH: path, STAGE_TEST_STATE: statePath }, encoding: 'utf8' });
    assert.equal(result.error, undefined);
    cases++;
    return { initial, result, state: JSON.parse(readFileSync(statePath, 'utf8')) };
}
try {
    for (const enabled of [true, false]) {
        const next = enabled ? 'stageanim13' : 'kos_dock_window_animation';
        const previous = enabled ? 'kos_dock_window_animation' : 'stageanim13';
        let { result, state } = run(enabled);
        assert.equal(result.status, 0, result.stderr);
        assert.equal(state.loaded[next], true);
        assert.equal(state.loaded[previous], false);
        assert.equal(state.config[next + 'Enabled'], 'true');
        assert.equal(state.config[previous + 'Enabled'], 'false');
        for (const changes of [{ failLoad: next }, { failUnload: previous }, { failWrite: next + 'Enabled' }]) {
            const r = run(enabled, changes);
            assert.notEqual(r.result.status, 0);
            assert.deepEqual(r.state.loaded, r.initial.loaded);
            assert.deepEqual(r.state.config, r.initial.config, JSON.stringify(r.state.calls));
        }
        const failedCommit = run(enabled, {}, 'false');
        assert.notEqual(failedCommit.result.status, 0);
        assert.deepEqual(failedCommit.state.loaded, failedCommit.initial.loaded);
        assert.deepEqual(failedCommit.state.config, failedCommit.initial.config, JSON.stringify(failedCommit.state.calls));
    }
    const alreadyLoaded = run(true, { loaded: { stageanim13: true, kos_dock_window_animation: true }, failLoad: 'stageanim13' });
    assert.equal(alreadyLoaded.result.status, 0);
    const bothOff = run(true, { loaded: { stageanim13: false, kos_dock_window_animation: false }, failLoad: 'stageanim13' });
    assert.notEqual(bothOff.result.status, 0);
    assert.deepEqual(bothOff.state.loaded, bothOff.initial.loaded);
    assert.throws(() => effectSwitchCommand(true, 'bad;id'));
    // Fedora ships the Qt 6 D-Bus CLI as qdbus-qt6 and no qdbus6: Stage must
    // still switch, through whichever name the system has.
    const fedora = mkdtempSync(join(tmpdir(), 'stage-effects-fedora-'));
    try {
        for (const cmd of ['qdbus-qt6', 'kreadconfig6', 'kwriteconfig6'])
            writeFileSync(join(fedora, cmd), mock, { mode: 0o755 });
        const onFedora = run(true, {}, ':', fedora);
        assert.equal(onFedora.result.status, 0, onFedora.result.stderr);
        assert.equal(onFedora.state.loaded.stageanim13, true);
        assert.ok(onFedora.state.calls.some(call => call[0] === 'qdbus-qt6'));
        const statePath = join(dir, 'state.json');
        writeFileSync(statePath, JSON.stringify({ loaded: {}, config: {}, calls: [] }));
        const reconfigure = spawnSync(bash, ['-c', reconfigureEffectCommand('stageanim13')],
            { env: { ...process.env, PATH: fedora, STAGE_TEST_STATE: statePath }, encoding: 'utf8' });
        assert.equal(reconfigure.status, 0, reconfigure.stderr);
        assert.deepEqual(JSON.parse(readFileSync(statePath, 'utf8')).calls, [['qdbus-qt6', 'org.kde.KWin',
            '/Effects', 'org.kde.kwin.Effects.reconfigureEffect', 'stageanim13']]);
        assert.throws(() => reconfigureEffectCommand('bad;id'));
    } finally { rmSync(fedora, { recursive: true, force: true }); }
    const quoted = spawnSync('bash', ['-c', 'printf %s ' + shellQuote("a b'$(false)")], { encoding: 'utf8' });
    assert.equal(quoted.stdout, "a b'$(false)");
    console.log(`stage-effects: ${cases} transition scenarios passed`);
} finally { rmSync(dir, { recursive: true, force: true }); }
