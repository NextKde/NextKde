"""External process-tree memory + Windows GPU-counter sampler, isolated profiles."""
import argparse,atexit,ctypes,json,os,pathlib,re,shutil,sqlite3,statistics,struct,subprocess,sys,threading,time
import psutil
from ctypes import wintypes
from windows_memory import footprint
p=argparse.ArgumentParser();p.add_argument('config',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[2];cfg=json.loads(a.config.read_text(encoding='utf-8-sig'))
wts=ctypes.windll.wtsapi32
wts.WTSQuerySessionInformationW.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(ctypes.c_ulong)]
wts.WTSFreeMemory.argtypes=[ctypes.c_void_p]
def session_locked():
    data=ctypes.c_void_p();size=ctypes.c_ulong()
    if not wts.WTSQuerySessionInformationW(None,0xffffffff,25,ctypes.byref(data),ctypes.byref(size)):return None
    try:
        if size.value<20:return None
        level,padding,session,state,flags=struct.unpack('<5I',ctypes.string_at(data,20))
        return flags==0 if level==1 and flags in (0,1) else None
    finally:wts.WTSFreeMemory(data)
if cfg.get('requireUnlocked') and session_locked() is not False:
    sys.exit('Windows session is locked or unknown; foreground measurement requires user unlock.')
# Keep the display awake for this benchmark only; do not change the power plan.
ctypes.windll.kernel32.SetThreadExecutionState(0x80000003)
atexit.register(lambda: ctypes.windll.kernel32.SetThreadExecutionState(0x80000000))
out=pathlib.Path(cfg['report']).parent;out.mkdir(parents=True,exist_ok=True)
(out/'case.json').write_text(json.dumps(cfg,indent=2,ensure_ascii=False),encoding='utf-8')
runtime=pathlib.Path(cfg.get('runtime',root/'build/performance-optimization/runtime'));data=out/'data';data.mkdir(exist_ok=True)
profile=pathlib.Path(cfg.get('profile',root/'dist/ListenFree-Portable/data/library.sqlite')).resolve()
with sqlite3.connect(profile.as_uri()+'?mode=ro',uri=True) as source:
    with sqlite3.connect(data/'library.sqlite') as target:
        source.backup(target)
        values={'lyrics.pendingEmbedded':'{}','library.autoWatch':'false','playback.autoPlayOnLaunch':'false','window.startInFullScreen':'false','tray.enabled':'false','playback.transition.smart':'true' if cfg.get('smartMix',False) else 'false',
                'appearance.dynamicArtworkEnabled':'false'}
        for key,value in values.items():target.execute("INSERT INTO settings(key,value,value_type) VALUES(?,?,'string') ON CONFLICT(key) DO UPDATE SET value=excluded.value",(key,value))
        if cfg.get('sourcesDirectory'):
            source_dir=pathlib.Path(cfg['sourcesDirectory']).resolve()
            entries=target.execute("SELECT value FROM settings WHERE key='source.custom'").fetchone()
            for entry in json.loads(entries[0] if entries else '[]'):
                source_file=source_dir/pathlib.Path(entry['path']).name
                if not source_file.is_file():raise FileNotFoundError(source_file)
                (data/'sources').mkdir(exist_ok=True)
                shutil.copy2(source_file,data/'sources'/source_file.name)
        if cfg.get('startWithoutSource'):
            target.execute("UPDATE settings SET value='[]' WHERE key='source.custom'")
            target.execute("UPDATE settings SET value='' WHERE key='source.activeId'")
env=dict(os.environ)
for key in ['QT_PLUGIN_PATH','QML2_IMPORT_PATH','QML_IMPORT_PATH','QT_QPA_PLATFORM_PLUGIN_PATH','QT_SCALE_FACTOR','QT_SCREEN_SCALE_FACTORS','LISTENFREE_CLADDAGH_REGRESSION']:
    env.pop(key,None)
env.update(PATH=str(runtime)+';'+os.environ['SystemRoot']+'/System32;'+os.environ['SystemRoot'],QMMP_PLUGINS=str(runtime/'qmmp'),
           LISTENFREE_QMMP_OUTPUT='null',QT_FORCE_STDERR_LOGGING='1',QSG_INFO='1',QSG_RENDER_LOOP=cfg.get('renderLoop','basic'))
env.pop('LISTENFREE_COUNT_COVERS',None)
if cfg.get('countCoverRequests'):env['LISTENFREE_COUNT_COVERS']='1'
if cfg.get('audioOutput'):env['LISTENFREE_QMMP_OUTPUT']=cfg['audioOutput']
for key,value in cfg.get('environment',{}).items():
    if not key.startswith(('QT_','QSG_','QML_')):raise ValueError('Only Qt diagnostic environment overrides are supported')
    env[key]=str(value)

user32=ctypes.windll.user32
user32.GetForegroundWindow.restype=ctypes.c_void_p
user32.GetWindowThreadProcessId.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulong)]
user32.IsWindowVisible.argtypes=[ctypes.c_void_p]
user32.GetWindowTextW.argtypes=[ctypes.c_void_p,ctypes.c_wchar_p,ctypes.c_int]
user32.SetForegroundWindow.argtypes=[ctypes.c_void_p]
user32.AttachThreadInput.argtypes=[ctypes.c_ulong,ctypes.c_ulong,ctypes.c_int]
def foreground_pid():
    pid=ctypes.c_ulong();user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),ctypes.byref(pid));return pid.value
def activate_window(pid):
    handles=[]
    callback=ctypes.WINFUNCTYPE(ctypes.c_int,ctypes.c_void_p,ctypes.c_void_p)
    def visit(hwnd,unused):
        owner=ctypes.c_ulong();user32.GetWindowThreadProcessId(hwnd,ctypes.byref(owner))
        if owner.value==pid and user32.IsWindowVisible(hwnd):
            caption=ctypes.create_unicode_buffer(256);user32.GetWindowTextW(hwnd,caption,len(caption))
            # QML popup/native helper windows can also be visible. Activate the
            # application's main window, never an auxiliary zero-size HWND.
            if caption.value=='ListenFree':handles.insert(0,hwnd)
            else:handles.append(hwnd)
        return True
    user32.EnumWindows(callback(visit),0)
    if not handles:return False
    user32.SetForegroundWindow(handles[0])
    if foreground_pid()==pid:return True
    # The user authorized keeping this test window in the foreground. Attach
    # only for activation, then immediately restore the separate input queues.
    message=wintypes.MSG();user32.PeekMessageW(ctypes.byref(message),None,0,0,0)
    current=ctypes.windll.kernel32.GetCurrentThreadId()
    foreground=user32.GetWindowThreadProcessId(user32.GetForegroundWindow(),None)
    attached=current!=foreground and user32.AttachThreadInput(current,foreground,True)
    try:user32.SetForegroundWindow(handles[0])
    finally:
        if attached:user32.AttachThreadInput(current,foreground,False)
    return foreground_pid()==pid

class CounterValue(ctypes.Union):_fields_=[('large',ctypes.c_longlong),('double',ctypes.c_double)]
class Formatted(ctypes.Structure):_fields_=[('status',ctypes.c_ulong),('value',CounterValue)]
class CounterItem(ctypes.Structure):_fields_=[('name',ctypes.c_wchar_p),('value',Formatted)]
class GpuCounters:
    def __init__(self):
        self.dll=ctypes.WinDLL('pdh');self.query=ctypes.c_void_p();self.counters={};self.error=''
        self.dll.PdhOpenQueryW.argtypes=[ctypes.c_wchar_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)]
        self.dll.PdhAddEnglishCounterW.argtypes=[ctypes.c_void_p,ctypes.c_wchar_p,ctypes.c_size_t,ctypes.POINTER(ctypes.c_void_p)]
        self.dll.PdhCollectQueryData.argtypes=[ctypes.c_void_p]
        self.dll.PdhGetFormattedCounterArrayW.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.POINTER(ctypes.c_ulong),ctypes.POINTER(ctypes.c_ulong),ctypes.c_void_p]
        status=self.dll.PdhOpenQueryW(None,0,ctypes.byref(self.query))
        if status:self.error=f'open {status}';return
        for key,counter in [('dedicated','Dedicated Usage'),('shared','Shared Usage')]:
            handle=ctypes.c_void_p();status=self.dll.PdhAddEnglishCounterW(self.query,'\\GPU Process Memory(*)\\'+counter,0,ctypes.byref(handle))
            if status:self.error=f'add {status}'
            else:self.counters[key]=handle
    def sample(self,pids):
        if not self.counters:return {'error':self.error}
        self.dll.PdhCollectQueryData(self.query);result={};matches=0
        for key,handle in self.counters.items():
            size=ctypes.c_ulong();count=ctypes.c_ulong()
            self.dll.PdhGetFormattedCounterArrayW(handle,0x400,ctypes.byref(size),ctypes.byref(count),None)
            if not size.value:continue
            buf=ctypes.create_string_buffer(size.value)
            status=self.dll.PdhGetFormattedCounterArrayW(handle,0x400,ctypes.byref(size),ctypes.byref(count),buf)
            if status:result['error']=f'array {status}';continue
            array=ctypes.cast(buf,ctypes.POINTER(CounterItem));total=0
            for i in range(count.value):
                item=array[i]
                if any(item.name.startswith(f'pid_{pid}_') for pid in pids) and item.value.status in (0,1):
                    total+=item.value.value.large;matches+=1
            result[key+'_mib']=total/1048576
        result['matched_counters']=matches;return result
pathlib.Path(cfg['report']).write_text('',encoding='utf-8')
pathlib.Path(cfg['report']+'.stage').write_text('starting',encoding='utf-8')
gpu=GpuCounters();samples=[];start=time.monotonic();last_gpu=-1;gpu_value={};last_stage='';activation_attempted=False;last_activation=-1
with (out/'stderr.log').open('w',encoding='utf-8') as stderr,(out/'samples.jsonl').open('w',encoding='utf-8') as stream:
    proc=subprocess.Popen([str(runtime/'listenfree.exe'),'--data-dir',str(data),'--audit-config',str(a.config.resolve())],cwd=runtime,env=env,
                          stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
    def save_diagnostics():
        for raw in iter(proc.stderr.readline,b''):
            line=raw.decode('utf-8','replace')
            line=re.sub(r'https?://[^\s\"<>]+','<URL>',line)
            line=re.sub(r'(?i)((?:cookie|authorization)\s*[:=]\s*).*',r'\1<REDACTED>',line)
            stderr.write(line)
        stderr.flush()
    log_thread=threading.Thread(target=save_diagnostics,daemon=True);log_thread.start()
    main=psutil.Process(proc.pid);print(json.dumps({'pid':proc.pid,'out':str(out)}),flush=True)
    deadline=sum(s.get('ms',15000) for s in cfg['steps'])/1000+45
    try:
        while proc.poll() is None:
            elapsed=time.monotonic()-start
            if elapsed>deadline:raise TimeoutError('diagnostic did not finish')
            try:stage=pathlib.Path(cfg['report']+'.stage').read_text(encoding='utf-8')
            except FileNotFoundError:stage=last_stage or 'starting'
            if not stage:stage=last_stage or 'starting'
            if stage=='finished':
                proc.wait(timeout=15)
                break
            if cfg.get('foreground') and foreground_pid()!=proc.pid and stage!='starting' and elapsed-last_activation>=.25:
                last_activation=elapsed
                activated=activate_window(proc.pid)
                if not activation_attempted and activated:
                    print(json.dumps({'foregroundRequested':True,'ownForeground':True}),flush=True)
                    activation_attempted=True
            row={'seconds':round(elapsed,3),'stage':stage,'processes':[],'ownForeground':foreground_pid()==proc.pid,'foregroundPid':foreground_pid(),'sessionLocked':session_locked()}
            try:
                processes=[main]+main.children(recursive=True)
                for child in processes:
                    mem=child.memory_info();native=footprint(child.pid);cpu=child.cpu_times()
                    row['processes'].append({'pid':child.pid,'name':child.name(),'ws':mem.rss/1048576,'pws':native['pwsMiB'],'uss':native['ussMiB'],'commit':mem.private/1048576,
                        'cpu':cpu.user+cpu.system,'threads':child.num_threads(),'handles':child.num_handles()})
                if elapsed-last_gpu>=1:gpu_value=gpu.sample([c.pid for c in processes]);last_gpu=elapsed
                row['gpu']=gpu_value;samples.append(row);stream.write(json.dumps(row)+'\n');stream.flush()
                if cfg.get('requireUnlocked') and row['sessionLocked'] is not False:
                    raise RuntimeError('Windows locked during measurement; this run is invalid.')
                if stage!=last_stage:
                    print(json.dumps({'stage':stage,'pws':round(sum(x['pws'] for x in row['processes']),2),'commit':round(sum(x['commit'] for x in row['processes']),2),'gpu':gpu_value}),flush=True);last_stage=stage
            except(psutil.NoSuchProcess,psutil.AccessDenied):pass
            time.sleep(.25)
    finally:
        if proc.poll() is None:proc.kill();proc.wait()
        log_thread.join(timeout=5)
results=[]
for stage in dict.fromkeys(r['stage'] for r in samples):
    rows=[r for r in samples if r['stage']==stage]
    if not rows:continue
    tail=[r for r in rows if r['seconds']>=rows[-1]['seconds']-5]
    result={'stage':stage,'seconds':round(rows[-1]['seconds']-rows[0]['seconds'],2),'samples':len(rows)}
    for key in ['pws','uss','ws','commit']:
        result[key+'_median']=statistics.median(sum(p[key] for p in r['processes']) for r in tail)
        result[key+'_peak']=max(sum(p[key] for p in r['processes']) for r in rows)
    for key in ['dedicated_mib','shared_mib']:
        values=[r['gpu'][key] for r in tail if key in r.get('gpu',{}) and r['gpu'].get('matched_counters',0)>0]
        result['gpu_'+key]=statistics.median(values) if values else None
    duration=tail[-1]['seconds']-tail[0]['seconds'];c0=sum(c['cpu'] for c in tail[0]['processes']);c1=sum(c['cpu'] for c in tail[-1]['processes'])
    result['cpu_one_core_pct']=(c1-c0)/duration*100 if duration else None
    result['threads']=sum(c['threads'] for c in tail[-1]['processes']);result['handles']=sum(c['handles'] for c in tail[-1]['processes'])
    results.append(result)
try:objects=json.loads(pathlib.Path(cfg['report']).read_text(encoding='utf-8'));finished=objects[-1]['label']=='finished'
except(FileNotFoundError,json.JSONDecodeError):finished=False
output={'exit':proc.returncode,'finished':finished,'memorySchema':2,'pwsDefinition':'QueryWorkingSet: Shared=0; USS additionally counts shareable pages with ShareCount<=1', 'logicalCPUs':psutil.cpu_count(),'ramGiB':psutil.virtual_memory().total/2**30,'renderLoop':env['QSG_RENDER_LOOP'],'renderReadbackMs':cfg.get('renderReadbackMs',0),'stages':results}
(out/'summary.json').write_text(json.dumps(output,indent=2),encoding='utf-8');print(json.dumps({'exit':proc.returncode,'finished':finished}),flush=True)
sys.exit(0 if proc.returncode==0 and finished else 1)
