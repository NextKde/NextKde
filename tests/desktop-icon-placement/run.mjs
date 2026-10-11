import assert from 'node:assert/strict';
import { copyFileSync, mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const repo = fileURLToPath(new URL('../..', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'kos-desktop-icon-placement-'));
try {
    copyFileSync(new URL('shell.qml', import.meta.url), join(dir, 'shell.qml'));
    symlinkSync(join(repo, 'shell/desktop'), join(dir, 'desktop'), 'dir');
    symlinkSync(join(repo, 'shell/Kos'), join(dir, 'Kos'), 'dir');
    for (const saved of ['0','1']) {
        const result = spawnSync(process.argv[2] || 'quickshell', ['-p', dir], {
            encoding:'utf8', timeout: 10000,
            env: {...process.env, VERIFY_SAVED:saved, QT_QPA_PLATFORM:'offscreen', QT_QUICK_BACKEND:'software',
                XDG_CONFIG_HOME:join(dir,'config'),XDG_STATE_HOME:join(dir,'state'),
                KOS_PLATFORM_SOCKET:join(dir,'absent-platform.sock'),KOS_DATA_SOCKET:join(dir,'absent-data.sock')},
        });
        const output = (result.stdout || '') + (result.stderr || '');
        assert.equal(result.status,0,output);
        assert.doesNotMatch(output,/FAIL |ReferenceError|TypeError|Binding loop/);
        assert.match(output,saved==='1'?/ICON_PLACEMENT_SAVED_PASS/:/ICON_PLACEMENT_PASS:/);
        console.log(output.split('\n').filter(line=>line.includes('ICON_PLACEMENT_')).join('\n'));
    }
} finally { rmSync(dir,{recursive:true,force:true}); }
