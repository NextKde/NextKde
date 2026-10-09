"""Opaque global backgrounds release old artwork; transparent heroes retain it."""
import json,pathlib,sys
rows=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert rows[-1]['label']=='finished','Incomplete run'
checked=0
for row in rows:
    if row['label']!='end' or row['stage'] not in ['global-second','global-third','artist-second','artist-third']:continue
    name='globalBackground' if row['stage'].startswith('global') else 'artistBackdrop'
    group=next(g for g in row['backgrounds'] if g['name']==name)
    assert group['opacity']==1,(row['stage'],'Crossfade not complete')
    expected=1 if name=='globalBackground' else 2
    assert sum(bool(layer['source']) for layer in group['layers'])==expected,(row['stage'],group['layers'])
    checked+=1
assert checked==4,checked
print('PASS: global backgrounds release old artwork; alpha heroes preserve their underlay')
