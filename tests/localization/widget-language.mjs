import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {english, isChinese} from '../../shell/desktop/modules/common/Translations.mjs';
for (const value of ['zh', 'zh-CN', 'zh_TW', 'zh-Hant-HK', 'ZH-SG'])
    assert.equal(isChinese([value, 'en-US']), true, value);
for (const value of ['en-US', 'fr-FR', 'ja-JP', 'C', '', 'zho'])
    assert.equal(isChinese([value, 'zh-CN']), false, value);
assert.equal(isChinese([]), false);
const files = [
    'bar/BarDateStatus.qml', 'deskcenter/DeskCenterWindow.qml',
    'deskcenter/DesktopFilesService.qml', 'deskcenter/FreeSlotDesktopDemo.qml',
    'dock/DesktopLyrics.qml', 'dock/DockClockWidget.qml', 'dock/DockMusicPlayer.qml',
    'dock/DockMusicPopup.qml', 'weather/DockWeatherWidget.qml',
    'weather/WeatherPopup.qml', 'weather/WeatherService.qml',
];
for (const file of files) {
    const source = readFileSync(new URL('../../shell/desktop/modules/' + file, import.meta.url), 'utf8');
    for (const match of source.matchAll(/I18n\.text\(("(?:[^"\\]|\\.)*")\)/g)) {
        const key = JSON.parse(match[1]);
        assert.ok(english[key], `${file}: missing ${key}`);
        assert.ok(!/[\u4e00-\u9fff]/u.test(english[key]), `${file}: untranslated ${key}`);
    }
}
console.log(`PASS: primary-language policy and ${Object.keys(english).length} widget translations`);
