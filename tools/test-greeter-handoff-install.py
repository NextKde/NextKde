#!/usr/bin/python3 -I
"""Only run inside disposable user/root/PID namespace; no host service access."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import stat
assert os.geteuid()==0 and not Path('/run/systemd/private').exists() and not Path('/dev/tty1').exists()
spec=importlib.util.spec_from_file_location('installer','/tests/install-greeter-handoff.py')
i=importlib.util.module_from_spec(spec);spec.loader.exec_module(i)
b=Path('/tmp/bundle');b.mkdir();files={}
for name in i.ALLOWED:
 p=b/name;p.parent.mkdir(parents=True,exist_ok=True)
 mode=0o755 if name in i.FILES or name.startswith('libexec/') else 0o644
 if name in i.FILES:
  shutil.copyfile('/usr/bin/true',p)
  rpath='$ORIGIN/../lib' if name.startswith('systemd/bin/') else ('$ORIGIN' if name.startswith('kwin/bin/') else '')
  subprocess.run(['/usr/bin/patchelf','--set-rpath',rpath,str(p)],check=True)
  if name.endswith('libkwin.so.6'):subprocess.run(['/usr/bin/patchelf','--set-soname','libkwin.so.6',str(p)],check=True)
  if name.endswith('libsystemd-shared-262.so'):subprocess.run(['/usr/bin/patchelf','--set-soname','libsystemd-shared-262.so',str(p)],check=True)
 else:p.write_bytes(b'fixture')
 p.chmod(mode);files[name]={'mode':mode,'sha256':i.digest(p.read_bytes())}
raw=json.dumps({'schema':1,'files':files,'systemDependencies':{}}).encode();(b/'manifest.json').write_bytes(raw)
h=i.digest(raw)
root=Path('/opt');root.mkdir()
i.install(b,h,root,True);assert not (root/'kos-handoff').exists()
i.install(b,h,root,False)
for p in (root/'kos-handoff').rglob('*'):
 assert p.lstat().st_uid==0 and not p.lstat().st_mode&0o022 and not p.is_symlink()
os.replace(root/'kos-handoff',root/'kos-handoff.previous')
assert not (root/'kos-handoff').exists() # SIGKILL after first upgrade rename
i.restore_files(root)
assert (root/'kos-handoff').is_dir() and not (root/'kos-handoff.previous').exists()
print('PASS interrupted upgrade recovers previous when active prefix is absent')
i.install(b,h,root,False);assert (root/'kos-handoff.previous').exists()
i.restore_files(root);assert (root/'kos-handoff.displaced').exists()
shutil.rmtree(root/'kos-handoff.displaced');i.restore_files(root,True)
assert not (root/'kos-handoff').exists()
for attack in ('bad-hash','symlink-artifact','writable-parent'):
 if attack=='bad-hash':args=(b,'0'*64,root,False)
 elif attack=='symlink-artifact':
  p=b/'libexec/kos-handoff-authorize';p.unlink();p.symlink_to('/usr/bin/true');args=(b,h,root,False)
 else:
  p.unlink();p.write_bytes(b'fixture');p.chmod(0o755);root.chmod(0o777);args=(b,h,root,False)
 try:i.install(*args)
 except (ValueError,OSError):pass
 else:raise AssertionError('unsafe install accepted: '+attack)
print('PASS fake-root check/install/root permissions/upgrade/rollback/uninstall/hash mismatch/symlink/writable ancestor; no host mutation')
