import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,copyFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const dir=mkdtempSync(join(tmpdir(),'kos-lyrics-'));
try {
    const source=new URL('../../shell/desktop/modules/dock/',import.meta.url);
    // Keep the production service and timers, replace only the D-Bus model
    // and the deskcenter module import (stubbed locally below).
    writeFileSync(join(dir,'DockMprisService.qml'),readFileSync(new URL('DockMprisService.qml',source),'utf8')
        .replace('import Quickshell.Services.Mpris','import "."')
        .replace("import qs.desktop.modules.deskcenter\n",""));
    copyFileSync(new URL('TimedLyrics.mjs',source),join(dir,'TimedLyrics.mjs'));
    copyFileSync(new URL('tst_lyrics.qml',import.meta.url),join(dir,'tst_lyrics.qml'));
    writeFileSync(join(dir,'qmldir'),'singleton DockMprisService 1.0 DockMprisService.qml\nsingleton DeskCenterConfigService 1.0 DeskCenterConfigService.qml\nsingleton Mpris 1.0 Mpris.qml\nMprisPlayer 1.0 MprisPlayer.qml\n');
    writeFileSync(join(dir,'DeskCenterConfigService.qml'),'pragma Singleton\nimport QtQuick\nQtObject { readonly property bool desktopLyricsActive: true }\n');
    writeFileSync(join(dir,'Mpris.qml'),'pragma Singleton\nimport QtQuick\nQtObject { property var players: [] }\n');
    writeFileSync(join(dir,'MprisPlayer.qml'),`import QtQuick
QtObject {
    property var metadata: ({})
    property bool isPlaying: false
    property bool positionSupported: true
    property int playbackState: 0
    property real position: 0
    property string trackArtUrl: ""
    property string trackTitle: ""
    property string trackArtist: ""
}`);
    const result=spawnSync(process.argv[2]||'qmltestrunner',['-input',dir],{encoding:'utf8',timeout:10000,
        env:{...process.env,QT_QPA_PLATFORM:'offscreen',QT_QUICK_BACKEND:'software'}});
    const output=result.stdout+result.stderr;
    assert.equal(result.status,0,output);
    assert.doesNotMatch(output,/TypeError|ReferenceError/);
    console.log(output);
} finally {rmSync(dir,{recursive:true,force:true});}
