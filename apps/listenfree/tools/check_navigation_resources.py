"""Validate real page eviction and restoration from the native memory probe."""
import json,pathlib,sys
rows=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert rows[-1]['label']=='finished','Incomplete run'
ends={r['stage']:r for r in rows if r['label']=='end'}
for r in ends.values():
    assert sum(p['loaded'] for p in r['navigationPages'])<=2,(r['stage'],'Unbounded page cache')
for prefix in ['songs','albums','artists','discover','playlists','favorites']:
    a,b=ends[prefix+'-set'],ends[prefix+'-return']
    pa=[p for p in a['navigationPages'] if p['visible']]
    pb=[p for p in b['navigationPages'] if p['visible']]
    assert pa==pb,(prefix,pa,pb)
    def views(row):
        return {v['name']:{k:v[k] for k in ['contentX','contentY','sortColumn','sortOrder'] if k in v}
            for v in row['visibleViews'] if v['name']!='sidebarQueue'}
    assert views(a)==views(b),(prefix,views(a),views(b))
    print(prefix+': state and viewport restored')
print('PASS: at most two live pages; six real pages restore their state')
