"""将已审阅的中英对照打包为 Qt 翻译字典。"""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
folder=root/'music_player_desktop/translations'
translations={}
for line in (folder/'en_US.tsv').read_text(encoding='utf-8').splitlines():
    if not line or line.startswith('#'):continue
    source, translated=line.split('|',1)
    source=source.replace(r'\n','\n')
    translated=translated.replace(r'\n','\n')
    if source in translations:raise ValueError('重复翻译：'+source)
    translations[source]=translated
(folder/'en_US.json').write_text(json.dumps(translations,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(translations)} translations')
