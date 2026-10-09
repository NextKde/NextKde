"""标记生产 QML 中的中文界面常量，并列出翻译资源待补项。"""
import json
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=[root/'music_player_desktop/AppShell.qml']
files+=list((root/'music_player_desktop/components').glob('*.qml'))
files+=list((root/'music_player_desktop/pages').glob('*.qml'))
strings=set()
pattern=re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*[\s\S]*?\*/')
for path in files:
    text=path.read_text(encoding='utf-8')
    def replace(match):
        token=match[0]
        if token.startswith('/') or not re.search('[\u4e00-\u9fff]',token):return token
        # Persistent model values and property names are not translated.
        before=text[max(0,match.start()-40):match.start()]
        after=text[match.end():match.end()+12]
        if re.search(r'\b(?:value|optionValue|objectName|settingKey):\s*$',before) or (re.search(r'[{,]\s*$',before) and re.match(r'\s*:',after)):return token
        try: source=json.loads(token) if token.startswith('"') else token[1:-1]
        except ValueError:return token
        strings.add(source)
        if re.search(r'\bqsTr\(\s*$',before):return token
        return 'qsTr('+token+')'
    updated=pattern.sub(replace,text)
    if updated!=text:path.write_text(updated,encoding='utf-8')
folder=root/'music_player_desktop/translations'
folder.mkdir(exist_ok=True)
existing=json.loads((folder/'en_US.json').read_text(encoding='utf-8')) if (folder/'en_US.json').exists() else {}
missing=sorted(strings-existing.keys())
(root/'build/translation-missing.json').write_text(json.dumps(missing,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'{len(strings)} UI strings; {len(missing)} missing English translations')
