"""Run online cases sequentially; optionally lease previously authorized Windows test settings."""
import argparse,ctypes,json,pathlib,subprocess,sys,time
from ctypes import wintypes

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('cases',nargs='+',type=pathlib.Path)
p.add_argument('--manage-foreground',action='store_true',help='Temporarily disable screensaver/foreground lock; requires user authorization')
a=p.parse_args();root=pathlib.Path(__file__).resolve().parents[2]
u=ctypes.WinDLL('user32',use_last_error=True)
u.GetForegroundWindow.restype=wintypes.HWND
u.GetWindowThreadProcessId.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.DWORD)]
u.SystemParametersInfoW.argtypes=[wintypes.UINT,wintypes.UINT,ctypes.c_void_p,wintypes.UINT]
def get(action):
    value=wintypes.DWORD()
    if not u.SystemParametersInfoW(action,0,ctypes.byref(value),0):raise ctypes.WinError(ctypes.get_last_error())
    return value.value
def set_foreground_timeout(value):
    if get(0x2000)==value:return
    # SPI_SETFOREGROUNDLOCKTIMEOUT requires a thread allowed to change focus.
    message=wintypes.MSG();u.PeekMessageW(ctypes.byref(message),None,0,0,0)
    current=ctypes.windll.kernel32.GetCurrentThreadId()
    # Closing the last benchmark window briefly leaves no foreground HWND.
    # Re-read after that handoff instead of trying to attach to thread zero.
    error=87
    for attempt in range(20):
        foreground=u.GetWindowThreadProcessId(u.GetForegroundWindow(),None)
        if foreground:
            attached=current!=foreground and u.AttachThreadInput(current,foreground,True)
            try:
                if u.SystemParametersInfoW(0x2001,0,ctypes.c_void_p(value),0):return
                error=ctypes.get_last_error()
                if attempt==0:print('Foreground setting retry:',current,foreground,bool(attached),error,flush=True)
            finally:
                if attached:u.AttachThreadInput(current,foreground,False)
        time.sleep(.1)
    raise ctypes.WinError(error)
saved={};code=0
try:
    if a.manage_foreground:
        saved=dict(screenSaverActive=get(16),foregroundLockTimeoutMs=get(0x2000))
        (root/'build/performance-optimization/online-settings-before.json').write_text(json.dumps(saved,indent=2))
        u.SystemParametersInfoW(17,0,None,0);set_foreground_timeout(0)
    for case in a.cases:
        result=subprocess.run([sys.executable,str(root/'tools/performance/measure.py'),str(case)],cwd=root)
        code=max(code,result.returncode)
        if result.returncode:break
        config=json.loads(case.read_text(encoding='utf-8-sig'));directory=pathlib.Path(config['report']).parent
        validation=subprocess.run([sys.executable,str(root/'tools/performance/summarize_online.py'),str(directory)],stdout=subprocess.DEVNULL)
        verdict=json.loads((directory/'online-summary.json').read_text(encoding='utf-8'))
        print(json.dumps(dict(case=case.stem,valid=verdict['valid'],errors=verdict['errors']),ensure_ascii=True),flush=True)
        code=max(code,validation.returncode)
finally:
    if saved:
        u.SystemParametersInfoW(17,saved['screenSaverActive'],None,0)
        set_foreground_timeout(saved['foregroundLockTimeoutMs'])
        saved['screenSaverActiveVerified']=get(16);saved['foregroundLockTimeoutVerifiedMs']=get(0x2000)
        saved['restored']=saved['screenSaverActive']==saved['screenSaverActiveVerified'] and saved['foregroundLockTimeoutMs']==saved['foregroundLockTimeoutVerifiedMs']
        target=root/'docs/validation/performance-optimization-2026-09-08/online-system-settings-restored.json'
        target.write_text(json.dumps(saved,indent=2));print('Windows settings restored:',saved['restored'],flush=True)
        if not saved['restored']:code=1
sys.exit(code)
