#!/usr/bin/env python3
"""Real source-install lifecycle in an isolated non-root VM/container account."""
import argparse, fcntl, json, os, pathlib, shutil, subprocess, sys, tempfile, time
p=argparse.ArgumentParser(); p.add_argument('--source',required=True); p.add_argument('--revision',required=True)
p.add_argument('--previous',default='ab37baf98ec76f88b6204ac86ddb8d5d9f0fd03f'); p.add_argument('--mode',choices=['missing','old','full'],default='full'); p.add_argument('--results',required=True)
a=p.parse_args(); source=pathlib.Path(a.source).resolve(); results=pathlib.Path(a.results).resolve(); results.mkdir(parents=True,exist_ok=True)
work=pathlib.Path(tempfile.mkdtemp(prefix='installation with spaces-')); home=work/'home'; home.mkdir()
env=os.environ.copy(); env.update(HOME=str(home),XDG_DATA_HOME=str(home/'data'),XDG_STATE_HOME=str(home/'state'),XDG_CONFIG_HOME=str(home/'config'),XDG_CACHE_HOME=str(home/'cache'),GIT_TERMINAL_PROMPT='0')
records=[]; script=source/'install.sh'; root=home/'data/kmusic-app'; desktop=home/'data/applications/kmusic.desktop'

def check(condition,message):
    if not condition: raise AssertionError(message)

def call(name,args,expected=0,code=None,extra=None,timeout=1800):
    runenv=env.copy(); runenv.update(extra or {})
    started=time.time(); result=subprocess.run(['/bin/sh',str(script)]+args,env=runenv,capture_output=True,text=True,timeout=timeout)
    (results/(name+'.jsonl')).write_text(result.stdout); (results/(name+'.stderr')).write_text(result.stderr)
    try: events=[json.loads(x) for x in result.stdout.splitlines()]
    except Exception as e: raise AssertionError(name+': stdout is not JSONL') from e
    finals=[x for x in events if x.get('type')=='result']; check(len(finals)==1,name+': expected exactly one result')
    r=finals[0]; record=dict(name=name,exitCode=result.returncode,code=r.get('code'),seconds=round(time.time()-started,2),passed=False); records.append(record)
    log=r.get('logPath')
    if log and pathlib.Path(log).is_file(): shutil.copyfile(log,results/(name+'.log'))
    check(result.returncode==expected,f'{name}: expected exit {expected}, got {result.returncode}: {r}')
    check(r.get('schemaVersion')==1 and r.get('appId')=='org.nextkde.KMusic',name+': invalid contract')
    check(r.get('success')==(expected==0),name+': incorrect success flag')
    if code: check(r.get('code')==code,name+': wrong error code')
    record['passed']=True; return r

def shim(tool,body):
    directory=work/('shim-'+tool); directory.mkdir(exist_ok=True)
    real=shutil.which(tool); check(real is not None,'tool missing: '+tool)
    path=directory/tool; path.write_text('#!/bin/sh\n'+body+'\nexec '+real+' "$@"\n'); path.chmod(0o755)
    return {'PATH':str(directory)+':'+env['PATH']}

try:
    check(os.geteuid()!=0,'must use isolated non-root account')
    (results/'os-release').write_text(pathlib.Path('/etc/os-release').read_text())
    call('invalid-version',['install','--version','main'],2,'INVALID_ARGUMENT')
    call('missing-python',['check'],11,'DEPENDENCY_UNSATISFIED',{'PATH':str(work/'empty')})
    if a.mode in ['missing','old']:
        r=call('dependency-failure',['install','--version',a.revision],11,'DEPENDENCY_UNSATISFIED')
        check(bool(r.get('details',{}).get('dependencies')),'no dependency list')
        if a.mode=='old': check(any(d['id']=='Qt6Core' and d['reason']=='version_too_old' and d['installed'] for d in r['details']['dependencies']),'old Qt not detected')
        check(not root.exists(),'failure changed application directory')
    else:
        call('preflight',['check'],0,'OK')
        call('not-installed',['status'],0,'OK')
        call('initial-install',['install','--version',a.previous],0,'INSTALLED')
        old=(root/'current').resolve(); before=(root/'manifest.json').read_bytes()
        check((old/'bin/kmusic').is_file(),'executable absent')
        check((old/'share/kmusic/providers/helper.ts').is_file(),'provider absent')
        check(desktop.is_file(),'desktop entry absent')
        check('Exec="'+str(root/'current/bin/kmusic')+'" %U' in desktop.read_text(),'incorrect absolute desktop launch path')
        call('repeat-install',['install','--version',a.previous],0,'ALREADY_INSTALLED')
        # A real subprocess executes the installer with injected transport/compiler failures.
        call('download-failure',['install','--version',a.revision],20,'DOWNLOAD_FAILED',shim('git','case " $* " in *" fetch "*) exit 70;; esac'))
        check((root/'current').resolve()==old and (root/'manifest.json').read_bytes()==before,'download failure changed installation')
        call('build-failure',['install','--version',a.revision],30,'BUILD_FAILED',shim('cmake','case "$*" in *--build*stage-*) exit 71;; esac'))
        check((root/'current').resolve()==old and (root/'manifest.json').read_bytes()==before,'build failure changed installation')
        call('upgrade-install',['install','--version',a.revision],0,'INSTALLED')
        check((root/'current').resolve()!=old and old.exists(),'upgrade did not preserve old version')
        check(json.loads((root/'manifest.json').read_text())['previous']==str(old),'rollback path missing')
        call('repeat-upgraded',['install','--version',a.revision],0,'ALREADY_INSTALLED')
        # Do not start GUI/audio. Check ELF dynamic dependencies after installation.
        linked=subprocess.run(['ldd',str(root/'current/bin/kmusic')],capture_output=True,text=True)
        (results/'ldd.txt').write_text(linked.stdout+linked.stderr)
        check(linked.returncode==0 and 'not found' not in linked.stdout,'installed binary has unresolved dynamic dependencies')
        # Startup smoke only: isolated data, no GUI interaction or visual acceptance.
        runtime=work/'runtime'; runtime.mkdir(mode=0o700)
        smokeenv=env.copy(); smokeenv.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(runtime),KOS_MUSIC_DATA_DIR=str(work/'smoke-data'),KOS_MUSIC_CACHE_DIR=str(work/'smoke-cache'))
        with (results/'startup.log').open('w') as output:
            app=subprocess.Popen([str(root/'current/bin/kmusic')],env=smokeenv,stdout=output,stderr=subprocess.STDOUT)
            try:
                time.sleep(5)
                check(app.poll() is None,'installed application exited during startup')
            finally:
                if app.poll() is None:
                    app.terminate()
                    try: app.wait(timeout=10)
                    except subprocess.TimeoutExpired: app.kill(); app.wait()
        startup=(results/'startup.log').read_text()
        for fatal in ['QQmlApplicationEngine failed to load component','is not installed','ReferenceError:','TypeError:','Cannot assign to non-existent property']:
            check(fatal not in startup,'installed QML startup error: '+fatal)
        records.append(dict(name='installed-startup-smoke',passed=True))
        sentinel=home/'data/kmusic/user-library.db'; sentinel.parent.mkdir(); sentinel.write_text('preserve me')
        lock=(home/'state/kmusic-installer/lock').open('a'); fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        call('concurrent-lock',['check'],13,'INSTALL_BUSY'); lock.close()
        readonly=work/'readonly'; readonly.mkdir(); readonly.chmod(0o500)
        call('permission-failure',['check'],12,'PERMISSION_DENIED',{'XDG_STATE_HOME':str(readonly)})
        readonly.chmod(0o700)
        call('uninstall',['uninstall'],0,'OK'); check(not root.exists() and not desktop.is_symlink(),'uninstall left application links')
        check(sentinel.read_text()=='preserve me','uninstall removed user data')
        check(call('status-after-uninstall',['status'],0,'OK')['installed'] is False,'status still installed')
        call('repeat-uninstall',['uninstall'],0,'OK')
        desktop.write_text('unmanaged user desktop entry')
        call('desktop-conflict',['install','--version',a.revision],31,'INSTALL_FAILED')
        check(desktop.read_text()=='unmanaged user desktop entry','unmanaged desktop was overwritten')
    (results/'summary.json').write_text(json.dumps(dict(passed=True,mode=a.mode,revision=a.revision,checks=records),indent=2)+'\n')
except BaseException as e:
    (results/'summary.json').write_text(json.dumps(dict(passed=False,mode=a.mode,revision=a.revision,error=str(e),checks=records),indent=2)+'\n')
    raise
finally:
    shutil.rmtree(work,ignore_errors=True)
