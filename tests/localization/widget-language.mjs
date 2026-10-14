import assert from 'node:assert/strict';
import {readFileSync, readdirSync} from 'node:fs';
import {isChinese, systemLanguage} from '../../shared/qml/i18n/SystemLanguage.mjs';
import {catalog} from '../../shared/qml/i18n/ZhCatalog.mjs';

for (const value of ['zh', 'zh-CN', 'zh_TW', 'zh-Hant-HK', 'ZH-SG']) {
    assert.equal(isChinese([value, 'en-US']), true, value);
    assert.equal(systemLanguage([value, 'en-US']), 'zh-CN', value);
}
for (const value of ['en-US', 'fr-FR', 'ja-JP', 'C', '', 'zho']) {
    assert.equal(isChinese([value, 'zh-CN']), false, value);
    assert.equal(systemLanguage([value, 'zh-CN']), 'en', value);
}
assert.equal(isChinese([]), false);
assert.equal(systemLanguage([]), 'en');

function* qmlFiles(directory) {
    for (const entry of readdirSync(directory, {withFileTypes: true})) {
        const path = new URL(entry.name, directory);
        if (entry.isDirectory()) yield* qmlFiles(new URL(entry.name + '/', directory));
        else if (entry.isFile() && entry.name.endsWith('.qml')) yield path;
    }
}

const placeholders = text => (text.match(/%(?:L?\d+|L?n)/g) || []).sort();
let checked = 0;
for (const directory of ['../../shell/desktop/', '../../apps/settings/']) {
    for (const path of qmlFiles(new URL(directory, import.meta.url))) {
        const source = readFileSync(path, 'utf8');
        if (path.pathname.includes('/apps/settings/') && source.includes('I18n.')) {
            assert.match(source, /^import\s+"[^"\n]*\/i18n"\s*$/m,
                `${path.pathname}: I18n calls require an explicit import`);
        }
        // Literal calls can be checked without evaluating any QML or launching
        // the shell. Dynamic messages are checked by their producing code.
        for (const match of source.matchAll(/I18n\.(?:tr|trPattern)\(\s*("(?:[^"\\]|\\.)*")/g)) {
            const key = JSON.parse(match[1]);
            assert.ok(Object.hasOwn(catalog, key), `${path.pathname}: missing ${key}`);
            assert.equal(typeof catalog[key], 'string', key);
            assert.ok(catalog[key].length > 0, key);
            assert.deepEqual(placeholders(catalog[key]), placeholders(key), key);
            checked++;
        }
    }
}
assert.ok(checked > 0, 'No translation calls found; check the extraction pattern');
console.log(`PASS: primary-language policy and ${checked} UI translation calls`);
