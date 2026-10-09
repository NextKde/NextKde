"""Generate isolated cases using the user's installed sources, without copying secrets into reports."""
import argparse,json,pathlib,sqlite3

root=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--profile',type=pathlib.Path,default=root/'dist/ListenFree-Portable/data/library.sqlite')
p.add_argument('--output',type=pathlib.Path,default=root/'build/performance-optimization/online-cases')
p.add_argument('--results',type=pathlib.Path,default=root/'docs/validation/performance-optimization-2026-09-08')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
profile=a.output.resolve()/'profile.sqlite'
if not profile.exists():
    with sqlite3.connect(a.profile.resolve().as_uri()+'?mode=ro',uri=True) as source:
        with sqlite3.connect(profile) as target:source.backup(target)
with sqlite3.connect(profile) as db:
    sources=json.loads(db.execute("SELECT value FROM settings WHERE key='source.custom'").fetchone()[0])
    active=db.execute("SELECT value FROM settings WHERE key='source.activeId'").fetchone()[0]
base=dict(profile=str(profile),sourcesDirectory=str(a.profile.resolve().parent/'sources'),ignoreUserInput=True,
          runtime=str(root/'build/performance-optimization/runtime'),renderLoop='threaded',
          requireUnlocked=True,foreground=True,width=1066,height=709)
def save(name,steps,**options):
    case=dict(base,report=str(a.results.resolve()/name/'objects.json'),steps=steps,**options)
    (a.output/(name+'.json')).write_text(json.dumps(case,indent=2,ensure_ascii=False),encoding='utf-8')
steps=[dict(name='cold-plugin-loaded',ms=15000,action='setup'),
       dict(name='metadata-search',ms=15000,action='search',value='https://www.kuwo.cn/play_detail/450444')]
for i,source in enumerate(sources):
    steps += [dict(name=f'source-{i+1}-load',ms=10000,action='source',value=source['id']),
              dict(name=f'source-{i+1}-play',ms=22000,action='playResult'),
              dict(name=f'source-{i+1}-stop',ms=8000,action='stop')]
save('online-source-smoke-verified',steps)
active_source=next(s for s in sources if s['id']==active)
for round in range(1,4):
    save(f'online-acceptance-{round}',[
        dict(name='cold-without-plugin',ms=30000,action='setup'),
        dict(name='plugin-loaded',ms=15000,action='importSource',value=active_source['path']),
        dict(name='online-search',ms=12000,action='search',value='https://www.kuwo.cn/play_detail/450444'),
        dict(name='online-playing',ms=25000,action='playResult',requireLyrics=True),
        dict(name='online-lyrics',ms=15000,action='nowplaying',requirePlaying=True,requireLyrics=True),
        dict(name='online-monet',ms=10000,action='enter',style='monet',requirePlaying=True,requireLyrics=True),
        dict(name='online-fullscreen',ms=20000,action='fullscreen',requirePlaying=True,requireLyrics=True),
        dict(name='online-seek',ms=15000,seek=60000,requirePlaying=True,requireLyrics=True),
        dict(name='leave',ms=2000,action='leave'),
        dict(name='restore-window',ms=2000,action='resize',width=1066,height=709),
        dict(name='mini',ms=2000,action='mini'),
        dict(name='online-stop',ms=15000,action='stop',requireStopped=True),
        dict(name='online-clear-cooldown',ms=45000,action='clearQueue',requireStopped=True),
    ],startWithoutSource=True)
stress=[dict(name='cold-plugin-loaded',ms=15000,action='setup'),
        dict(name='dynamic-artwork-enabled',ms=1000,action='setting',key='appearance.dynamicArtworkEnabled',value=True),
        dict(name='nowplaying-open',ms=2000,action='nowplaying'),
        dict(name='online-search',ms=15000,action='search',value='周杰伦')]
for cycle in range(3):
    for index in range(3):
        stress.append(dict(name=f'switch-{cycle+1}-{index+1}',ms=15000,action='playResult',index=index))
stress += [dict(name='online-seek-forward',ms=15000,seek=90000,requirePlaying=True),
           dict(name='online-seek-backward',ms=15000,seek=5000,requirePlaying=True),
           dict(name='online-stop',ms=15000,action='stop',requireStopped=True),
           dict(name='online-clear-cooldown',ms=60000,action='clearQueue',requireStopped=True)]
save('online-switch-stress',stress,smartMix=True)
print(a.output.resolve())
