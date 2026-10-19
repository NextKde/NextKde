#!/usr/bin/python3 -I
"""Prepare and install the explicit experimental bundle. Never enable services."""
import argparse
import hashlib
import fcntl
import re
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COORD = ROOT / 'apps/greeter/experimental/drm-handoff/systemd'
FILES = {
 'kwin/bin/kwin_wayland': 'build/bin/kwin_wayland',
 'kwin/bin/kwin_wayland_wrapper': 'build/bin/kwin_wayland_wrapper',
 'kwin/bin/libkwin.so.6': 'build/bin/libkwin.so.6.7.5',
 'bin/greetd': 'greetd-0.10.3/target/release/greetd',
 'systemd/bin/systemd-logind': 'systemd-build/systemd-logind',
 'systemd/lib/libsystemd-shared-262.so': 'systemd-build/src/shared/libsystemd-shared-262.so',
}
EXTRA = {
 'libexec/kos-handoff-authorize': 'kos-handoff-authorize',
 'libexec/kos-greeter-session-handoff': 'kos-greeter-session-handoff',
 'examples/greetd-vm-only.toml': 'greetd-vm-only.toml',
 'examples/plasma-kwin_wayland.service.vm-override': 'plasma-kwin_wayland.service.vm-override',
}
ALLOWED = set(FILES) | set(EXTRA)

def digest(data): return hashlib.sha256(data).hexdigest()
def command(*args):
 return subprocess.run(args,check=True,capture_output=True,text=True,timeout=30).stdout

def read_regular(path, limit=1024**3):
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
 try:
  st=os.fstat(fd)
  if not stat.S_ISREG(st.st_mode) or st.st_size>limit: raise ValueError('invalid artifact')
  with os.fdopen(fd,'rb',closefd=False) as stream: data=stream.read(limit+1)
  if len(data)>limit:raise ValueError('oversized artifact')
  return data
 finally:os.close(fd)

def trusted(path):
 for p in (path,*path.parents):
  info=p.lstat()
  if info.st_uid!=0 or info.st_mode&0o022 or stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
   raise ValueError('destination ancestors must be root-owned, unwritable, real directories')

def prepare(cache, destination):
 if os.geteuid()==0:raise ValueError('prepare as ordinary user; root only installs verified bytes')
 if destination.exists():raise ValueError('bundle destination already exists')
 destination.mkdir(parents=True,mode=0o755)
 try:
  manifest={};dependencies={};sources={}
  for relative,source in {**FILES,**EXTRA}.items():
   src=cache/source if relative in FILES else COORD/source
   data=read_regular(src)
   sources[relative]=digest(data)
   target=destination/relative;target.parent.mkdir(parents=True,exist_ok=True)
   target.write_bytes(data)
   target.chmod(0o755 if relative in FILES or relative.startswith('libexec/') else 0o644)
  for relative in ALLOWED:
   target=destination/relative
   data=read_regular(target)
   if data[:4]==b'\x7fELF':
    rpath='$ORIGIN/../lib' if relative.startswith('systemd/bin/') else ('$ORIGIN' if relative.startswith('kwin/bin/') else '')
    command('/usr/bin/patchelf','--set-rpath',rpath,str(target))
    dynamic=command('/usr/bin/readelf','-d',str(target))
    if str(cache) in dynamic or '/home/' in dynamic:raise ValueError('unsafe relocated ELF')
    listing=command('/usr/bin/ldd',str(target))
    if 'not found' in listing:raise ValueError('unresolved or user-owned loader dependency')
    for line in listing.splitlines():
     for part in line.split():
      if part.startswith('/'):
       path=Path(part).resolve()
       if path in (destination/'kwin/bin/libkwin.so.6',destination/'systemd/lib/libsystemd-shared-262.so'):
        continue
       if not str(path).startswith('/usr/lib/'):raise ValueError('dependency outside system library directory')
       dependencies[str(path)]=digest(read_regular(path))
   manifest[relative]={'sha256':digest(read_regular(target)),'mode':stat.S_IMODE(target.stat().st_mode)}
  content={'schema':1,'files':manifest,'systemDependencies':dependencies,'sourceArtifacts':sources}
  raw=(json.dumps(content,indent=2,sort_keys=True)+'\n').encode()
  (destination/'manifest.json').write_bytes(raw)
  print('Prepared bundle:',destination)
  print('Manifest SHA256:',digest(raw))
 except BaseException:
  shutil.rmtree(destination);raise

def verify(bundle, expected):
 raw=read_regular(bundle/'manifest.json',1024**2)
 if digest(raw)!=expected:raise ValueError('manifest hash mismatch')
 manifest=json.loads(raw)
 if manifest.get('schema')!=1 or set(manifest.get('files',{}))!=ALLOWED:raise ValueError('invalid file allowlist')
 data={}
 for name,entry in manifest['files'].items():
  mode=0o755 if name in FILES or name.startswith('libexec/') else 0o644
  if entry.get('mode')!=mode:raise ValueError('invalid mode')
  value=read_regular(bundle/name)
  if digest(value)!=entry.get('sha256'):raise ValueError('artifact hash mismatch: '+name)
  data[name]=(value,mode)
 for name,expected_dependency in manifest.get('systemDependencies',{}).items():
  if not name.startswith('/usr/lib/') or '..' in Path(name).parts:raise ValueError('invalid dependency path')
  if digest(read_regular(Path(name)))!=expected_dependency:raise ValueError('system library changed; prepare a new matching bundle')
 return raw,data

def install_unlocked(bundle, expected, parent, check):
 raw,data=verify(bundle,expected)
 audit_private_elf(bundle)
 if check:
  print('PASS verified bundle, pinned system dependencies and fixed file allowlist; no installation')
  return
 if os.geteuid()!=0:raise ValueError('installation requires root')
 parent.mkdir(mode=0o755,parents=False,exist_ok=True);trusted(parent)
 final=parent/'kos-handoff';backup=parent/'kos-handoff.previous'
 if os.path.lexists(final):trusted(final)
 if os.path.lexists(backup):raise ValueError('previous snapshot exists; preserve/remove it explicitly before upgrade')
 staging=Path(tempfile.mkdtemp(prefix='.kos-handoff-',dir=parent))
 os.chmod(staging,0o755)
 moved=False
 try:
  for name,(value,mode) in data.items():
   path=staging/name;path.parent.mkdir(parents=True,exist_ok=True)
   path.write_bytes(value);path.chmod(mode)
  audit_private_elf(staging)
  (staging/'manifest.json').write_bytes(raw)
  for path in staging.rglob('*'):
   os.chown(path,0,0,follow_symlinks=False)
   if path.is_dir():path.chmod(0o755)
  if final.exists():os.replace(final,backup);moved=True
  os.replace(staging,final)
  print('Installed verified files in',final,'; services unchanged.')
  if moved:print('Previous files retained at',backup)
 except BaseException:
  if moved and not final.exists():os.replace(backup,final)
  raise
 finally:
  if staging.exists():shutil.rmtree(staging)

def audit_private_elf(root):
 for name in FILES:
  target=root/name
  if read_regular(target,1024**3)[:4]!=b'\x7fELF':raise ValueError('expected ELF artifact')
  dynamic=command('/usr/bin/readelf','-d',str(target))
  paths=re.findall(r'\((?:RUNPATH|RPATH)\).*?\[(.*?)\]',dynamic)
  expected='$ORIGIN/../lib' if name.startswith('systemd/bin/') else ('$ORIGIN' if name.startswith('kwin/bin/') else '')
  if paths not in ([expected], [] if not expected else [expected]):raise ValueError('unsafe installed ELF loader path: '+name)
  if name.endswith('libkwin.so.6') and '[libkwin.so.6]' not in dynamic:raise ValueError('incorrect libkwin SONAME')
  if name.endswith('libsystemd-shared-262.so') and '[libsystemd-shared-262.so]' not in dynamic:raise ValueError('incorrect systemd SONAME')

def locked_operation(parent, operation):
 if os.geteuid()!=0:raise ValueError('file mutation requires root')
 trusted(parent)
 fd=os.open(parent/'.kos-handoff.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  info=os.fstat(fd)
  if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or info.st_mode&0o022:raise ValueError('unsafe installation lock')
  fcntl.flock(fd,fcntl.LOCK_EX)
  return operation()
 finally:os.close(fd)

def install(bundle, expected, parent, check):
 if check:return install_unlocked(bundle,expected,parent,True)
 return locked_operation(parent,lambda:install_unlocked(bundle,expected,parent,False))

def restore_files(parent, uninstall=False):
 def mutate():
  final=parent/'kos-handoff';previous=parent/'kos-handoff.previous';displaced=parent/'kos-handoff.displaced'
  if not uninstall and not os.path.lexists(final):
   trusted(previous)
   if os.path.lexists(displaced):raise ValueError('displaced snapshot already exists')
   os.replace(previous,final)
   print('Recovered interrupted upgrade prefix; services unchanged.')
   return
  trusted(final)
  if os.path.lexists(displaced):raise ValueError('displaced snapshot already exists')
  if not uninstall:trusted(previous)
  os.replace(final,displaced)
  try:
   if not uninstall:os.replace(previous,final)
  except BaseException:
   os.replace(displaced,final);raise
  print('Uninstalled active prefix' if uninstall else 'Restored previous prefix', '; services unchanged; displaced files retained at',displaced)
 return locked_operation(parent,mutate)

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 sub=parser.add_subparsers(dest='mode',required=True)
 p=sub.add_parser('prepare');p.add_argument('--build-root',type=Path,required=True);p.add_argument('--bundle',type=Path,required=True)
 p=sub.add_parser('install');p.add_argument('--bundle',type=Path,required=True);p.add_argument('--manifest-sha256',required=True);p.add_argument('--check',action='store_true')
 sub.add_parser('rollback')
 sub.add_parser('uninstall')
 args=parser.parse_args()
 if args.mode=='prepare':prepare(args.build_root.resolve(),args.bundle.absolute())
 elif args.mode=='install':install(args.bundle.absolute(),args.manifest_sha256,Path('/opt'),args.check)
 else:restore_files(Path('/opt'),args.mode=='uninstall')

if __name__=='__main__':
 try:main()
 except (ValueError,OSError,subprocess.SubprocessError) as error:raise SystemExit(str(error))
