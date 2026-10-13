#!/usr/bin/env python3
"""Filesystem transactions with fake systemd/logind; never changes host services."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch

REPO=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('installer',REPO/'tools/greeter-install.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class Transaction(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='kos-install-fake-')
  self.root=Path(self.temp.name)/'root';self.root.mkdir()
  self.bundle=Path(self.temp.name)/'bundle';self.bundle.mkdir()
  for relative in ('app/shell.qml','app/cover.qml','app/bin/kos-greeter-session','app/bin/kos-greeter-ui','app/bin/kos-user-session','app/companion/entry.py','app/companion/greeter_config.py','app/companion/session_output.py','app/companion/plasma_session.py'):
   path=self.bundle/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('# fixture\n')
   path.chmod(0o755 if relative.startswith('app/bin/') else 0o644)
  self.manifest()
  self.inst=m.Installer(self.root)
  self.units=self.root/'etc/systemd/system';self.units.mkdir(parents=True)
  self.config=self.root/m.FILES[0];self.config.parent.mkdir(parents=True);self.config.write_bytes(b'original config\n');self.config.chmod(0o640)
  (self.units/'display-manager.service').symlink_to('/usr/lib/systemd/system/plasmalogin.service')
  wants=self.units/'graphical.target.wants';wants.mkdir();(wants/'plasmalogin.service').symlink_to('/usr/lib/systemd/system/plasmalogin.service')
  self.links=self.inst.links('plasmalogin.service')
  self.boot=self.root/'proc/sys/kernel/random/boot_id';self.boot.parent.mkdir(parents=True);self.boot.write_text('boot-one')
  self.active={'greetd.service':'inactive','plasmalogin.service':'active'}
  self.calls=[];self.fail=None;self.sessions=['old 1000 user'];self.services={'old':'plasmalogin'}
  self.patches=[patch.object(m,'systemctl',side_effect=self.systemctl),patch.object(m,'properties',side_effect=self.properties),
    patch.object(m,'run',side_effect=self.command),patch.object(self.inst,'preflight',return_value=('plasmalogin.service',{'ActiveState':'active'})),
    patch.object(self.inst,'installed_check'),patch.object(m,'require_caller_shell')]
  for p in self.patches:p.start()
 def tearDown(self):
  for p in reversed(self.patches):p.stop()
  self.temp.cleanup()
 def manifest(self):
  value={str(p.relative_to(self.bundle)):dict(hash=hashlib.sha256(p.read_bytes()).hexdigest(),mode=stat.S_IMODE(p.stat().st_mode))
         for p in self.bundle.rglob('*') if p.is_file() and p.name!='manifest.json'}
  (self.bundle/'manifest.json').write_text(json.dumps(value))
 def command(self,*args,**kwargs):
  if 'list-sessions' in args:return subprocess.CompletedProcess(args,0,'\n'.join(self.sessions),'')
  if 'show-session' in args:return subprocess.CompletedProcess(args,0,self.services.get(args[2],''),'')
  if 'terminate-session' in args:self.calls.append(('terminate',args[2]));return subprocess.CompletedProcess(args,0,'','')
  raise AssertionError('Unexpected command (host access prevented): '+repr(args))
 def systemctl(self,*args,**kwargs):
  self.calls.append(args)
  if self.fail==args:
   self.fail=None;raise RuntimeError('injected systemctl failure')
  if args[0]=='disable':
   unit=args[1]
   for rel,target in self.inst.links('plasmalogin.service').items():
    if Path(target).name==unit:(self.root/rel).unlink()
  if args[:2]==('enable','--force'):
   alias=self.units/'display-manager.service';alias.unlink(missing_ok=True);alias.symlink_to('/usr/lib/systemd/system/greetd.service')
   path=self.units/'graphical.target.wants/greetd.service';path.parent.mkdir(parents=True,exist_ok=True);path.symlink_to('/usr/lib/systemd/system/greetd.service')
  if args[0]=='start':self.active[args[1]]='active'
  if args[0]=='stop':self.active[args[1]]='inactive'
  return subprocess.CompletedProcess(args,0,'','')
 def properties(self,unit):
  if unit=='display-manager.service':
   alias=self.units/unit
   name=Path(os.readlink(alias)).name if alias.is_symlink() else unit
   return dict(Id=name,ActiveState=self.active.get(name,'inactive'))
  return dict(Id=unit,ActiveState=self.active.get(unit,'inactive'))
 def assert_restored(self):
  self.assertEqual(self.config.read_bytes(),b'original config\n')
  self.assertEqual(stat.S_IMODE(self.config.stat().st_mode),0o640)
  self.assertEqual(self.inst.links('plasmalogin.service'),self.links)
  self.assertFalse(self.inst.app.exists());self.assertFalse(self.inst.state.exists())
 def old_policy(self):
  self.inst.install(self.bundle)
  old=b'[Unit]\nOnFailure=kos-greeter-recover.service\n[Service]\nRestart=no\n'
  (self.root/m.FILES[1]).write_bytes(old)
  data=self.inst.load();data['installed_files']=self.inst.current_files();self.inst.save(data)
  self.calls.clear();return old,data
 def test_policy_migrates_identical_bundle_preserving_first_snapshot(self):
  old,data=self.old_policy();original_files=json.dumps(data['files'],sort_keys=True)
  self.inst.install(self.bundle)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),m.GREETER_POLICY)
  self.assertEqual(json.dumps(self.inst.load()['files'],sort_keys=True),original_files)
  self.assertEqual(self.inst.load()['installed_links'],data['installed_links'])
  self.assertEqual(self.calls,[('daemon-reload',)])
  self.inst.verify_receipt(self.inst.load())
 def test_policy_migration_failure_restores_old_receipt(self):
  old,data=self.old_policy();self.fail=('daemon-reload',)
  with self.assertRaises(RuntimeError):self.inst.install(self.bundle)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),old)
  self.assertEqual(self.inst.load(),data)
  self.assertFalse((self.inst.state/'policy-update.json').exists())
 def test_policy_interruption_restores_before_next_update(self):
  old,data=self.old_policy()
  record=dict(state=data,before=old.hex(),after=hashlib.sha256(m.GREETER_POLICY).hexdigest())
  m.atomic(self.inst.state/'policy-update.json',json.dumps(record).encode(),0o600)
  self.inst.save(dict(data,phase='policy-updating'))
  m.atomic(self.root/m.FILES[1],m.GREETER_POLICY)
  self.inst.recover_policy();self.assertEqual(self.inst.load(),data)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),old)
 def test_policy_committed_interruption_only_cleans_journal(self):
  old,data=self.old_policy()
  record=dict(state=data,before=old.hex(),after=hashlib.sha256(m.GREETER_POLICY).hexdigest())
  m.atomic(self.inst.state/'policy-update.json',json.dumps(record).encode(),0o600)
  m.atomic(self.root/m.FILES[1],m.GREETER_POLICY)
  committed=dict(data,installed_files=self.inst.current_files());self.inst.save(committed)
  self.inst.recover_policy();self.assertEqual(self.inst.load(),committed)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),m.GREETER_POLICY)
 def test_policy_upgrade_branch_migrates_without_restart(self):
  old,data=self.old_policy();self.upgrade_bundle()
  with patch.object(self.inst,'publish'):self.inst.install(self.bundle)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),m.GREETER_POLICY)
  self.assertEqual(self.inst.load()['files'],data['files'])
  self.assertFalse(any(call[0] in ('start','stop','restart','enable','disable') for call in self.calls))
 def test_old_rollback_can_handle_pending_policy_phase(self):
  old,data=self.old_policy()
  record=dict(state=data,before=old.hex(),after=hashlib.sha256(m.GREETER_POLICY).hexdigest())
  m.atomic(self.inst.state/'policy-update.json',json.dumps(record).encode(),0o600)
  self.inst.save(dict(data,phase='policy-updating'))
  m.atomic(self.root/m.FILES[1],m.GREETER_POLICY)
  # Old rollback code has no migration recovery method; its existing receipt
  # check only applies to phase=installed and restores original file snapshots.
  with patch.object(self.inst,'recover_policy'):
   self.inst.rollback()
  self.assert_restored()
 def test_policy_config_commit_failure_restores_old_policy(self):
  old,data=self.old_policy();real=self.inst.save;calls=0
  def fail(value):
   nonlocal calls
   calls+=1
   if calls==2:raise OSError('policy state commit')
   real(value)
  with patch.object(self.inst,'save',side_effect=fail),self.assertRaisesRegex(OSError,'policy state commit'):
   self.inst.install(self.bundle)
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),old)
  self.assertEqual(self.inst.load(),data)
 def test_policy_admin_change_is_not_overwritten(self):
  old,data=self.old_policy()
  record=dict(state=data,before=old.hex(),after=hashlib.sha256(m.GREETER_POLICY).hexdigest())
  m.atomic(self.inst.state/'policy-update.json',json.dumps(record).encode(),0o600)
  self.inst.save(dict(data,phase='policy-updating'))
  (self.root/m.FILES[1]).write_bytes(b'admin change')
  with self.assertRaisesRegex(RuntimeError,'changed during'):self.inst.recover_policy()
  self.assertEqual((self.root/m.FILES[1]).read_bytes(),b'admin change')
 def test_shell_check_precedes_every_install_branch(self):
  self.inst.install(self.bundle)
  self.calls.clear()
  with patch.object(m, 'require_caller_shell', side_effect=RuntimeError('incompatible Shell')):
   with self.assertRaisesRegex(RuntimeError, 'incompatible Shell'): self.inst.install(self.bundle)
   self.upgrade_bundle()
   with self.assertRaisesRegex(RuntimeError, 'incompatible Shell'): self.inst.install(self.bundle)
  self.assertEqual(self.calls, [])
 def test_install_boot_default_and_exact_rollback(self):
  self.inst.install(self.bundle)
  self.assertEqual(self.properties('display-manager.service')['Id'],'greetd.service')
  self.assertNotIn(('stop','plasmalogin.service'),self.calls)
  self.assertNotIn(('start','greetd.service'),self.calls)
  self.inst.rollback();self.assert_restored()
  self.inst.rollback();self.assert_restored()
 def test_files_only_preserves_enablement(self):
  self.inst.install(self.bundle,enable=False)
  self.assertEqual(self.inst.links('plasmalogin.service'),self.links)
  self.inst.rollback();self.assert_restored()
 def test_identical_install_keeps_first_snapshot(self):
  self.inst.install(self.bundle)
  original=(self.inst.state/'state.json').read_bytes();calls=len(self.calls)
  self.inst.install(self.bundle)
  self.assertEqual((self.inst.state/'state.json').read_bytes(),original)
  self.assertEqual(len(self.calls),calls)
 def test_enable_failure_restores(self):
  self.fail=('enable','--force','greetd.service')
  with self.assertRaises(RuntimeError):self.inst.install(self.bundle)
  self.assert_restored()
 def test_copy_failure_restores(self):
  real=m.atomic
  def fault(path,*args,**kwargs):
   if path==self.inst.app/'cover.qml':raise OSError('injected disk failure')
   return real(path,*args,**kwargs)
  with patch.object(m,'atomic',side_effect=fault),self.assertRaises(OSError):self.inst.install(self.bundle)
  self.assert_restored()
 def test_snapshot_write_failure_has_no_residue(self):
  real=m.atomic
  def fault(path,*args,**kwargs):
   if path.name=='state.json':raise OSError('injected snapshot failure')
   return real(path,*args,**kwargs)
  with patch.object(m,'atomic',side_effect=fault),self.assertRaises(OSError):self.inst.install(self.bundle)
  self.assert_restored()
  self.assertEqual(list((self.root/'var/lib').glob('.kos-greeter-snapshot-*')),[])
 def test_symlink_backup_failure_has_no_residue(self):
  self.config.unlink();self.config.symlink_to('/not-owned')
  with self.assertRaises(RuntimeError):self.inst.install(self.bundle)
  self.assertFalse(self.inst.state.exists());self.assertFalse(self.inst.app.exists())
  self.assertTrue(self.config.is_symlink())
 def test_umask_077_public_payload_private_recovery(self):
  old=os.umask(0o077)
  try:self.inst.install(self.bundle)
  finally:os.umask(old)
  for directory,_,files in os.walk(self.inst.app):
   self.assertEqual(stat.S_IMODE(Path(directory).stat().st_mode),0o755)
   for f in files:self.assertTrue((Path(directory)/f).stat().st_mode&0o004)
  self.assertEqual(stat.S_IMODE(self.inst.state.stat().st_mode),0o700)
  self.assertEqual(stat.S_IMODE((self.inst.state/'state.json').stat().st_mode),0o600)
  self.assertEqual(stat.S_IMODE((self.root/'etc/systemd/user/kos-shell.service.d').stat().st_mode),0o755)
 def test_failed_daemon_cleanup_only_new_greetd_sessions(self):
  self.inst.install(self.bundle)
  self.active['greetd.service']='failed'
  self.sessions+=['new 1000 user','other 1001 other'];self.services.update(new='greetd',other='sshd')
  self.inst.rollback(recover=True)
  self.assertIn(('terminate','new'),self.calls);self.assertNotIn(('terminate','old'),self.calls);self.assertNotIn(('terminate','other'),self.calls)
  self.assert_restored()
 def test_new_boot_does_not_protect_reused_session_id(self):
  self.inst.install(self.bundle);self.boot.write_text('boot-two')
  self.services['old']='greetd'
  self.inst.rollback(recover=True)
  self.assertIn(('terminate','old'),self.calls)
 def test_external_config_change_preserves_recovery(self):
  self.inst.install(self.bundle);self.config.write_text('administrator change')
  calls=len(self.calls)
  with self.assertRaisesRegex(RuntimeError,'changed after installation'):self.inst.rollback()
  self.assertEqual(len(self.calls),calls);self.assertTrue(self.inst.state.exists())
 def test_recovery_failure_retains_snapshot_then_retry(self):
  self.inst.install(self.bundle);self.fail=('start','plasmalogin.service')
  with self.assertRaises(RuntimeError):self.inst.rollback()
  self.assertTrue(self.inst.state.exists());self.assertTrue(self.inst.app.exists())
  self.inst.rollback();self.assert_restored()
 def test_recovery_script_self_contained(self):
  self.inst.install(self.bundle)
  copy=self.inst.state/'rollback.py'
  spec=importlib.util.spec_from_file_location('standalone_recovery',copy)
  standalone=importlib.util.module_from_spec(spec);spec.loader.exec_module(standalone)
  self.assertNotEqual(standalone.REPO,REPO)
  with patch.object(standalone,'systemctl',side_effect=self.systemctl),patch.object(standalone,'properties',side_effect=self.properties),patch.object(standalone,'run',side_effect=self.command):
   standalone.Installer(self.root).rollback()
  self.assert_restored()
 def test_bundle_replacement_symlink_bad_mode_and_fifo_rejected(self):
  p=self.bundle/'app/cover.qml';p.write_text('changed')
  with self.assertRaises(RuntimeError):self.inst.validate_bundle(self.bundle)
  p.unlink();p.symlink_to(self.config)
  with self.assertRaises(RuntimeError):self.inst.validate_bundle(self.bundle)
  p.unlink();os.mkfifo(p)
  with self.assertRaises(RuntimeError):m.read_regular(p)
 def upgrade_bundle(self):
  (self.bundle/'app/cover.qml').write_text('new version')
  self.manifest()
 def test_upgrade_preserves_snapshot_service_and_removes_old_files(self):
  self.inst.install(self.bundle)
  data=self.inst.load();backup=(self.inst.state/'backup'/m.FILES[0]).read_bytes()
  (self.inst.app/'obsolete.qml').write_text('old')
  self.active['greetd.service']='active';self.calls.clear()
  self.upgrade_bundle()
  with patch.object(self.inst,'publish') as publish:self.inst.install(self.bundle)
  publish.assert_called_once()
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'new version')
  self.assertFalse((self.inst.app/'obsolete.qml').exists())
  self.assertEqual(self.calls,[])
  updated=self.inst.load()
  for key in ('files','links','sessions','boot_id','original','original_active','enabled','created_dirs'):
   self.assertEqual(updated[key],data[key])
  self.assertEqual((self.inst.state/'backup'/m.FILES[0]).read_bytes(),backup)
  self.assertFalse((self.inst.state/'upgrade.json').exists())
  self.inst.rollback();self.assert_restored()
 def test_upgrade_failed_readability_restores_previous_app(self):
  self.inst.install(self.bundle);before=(self.inst.state/'state.json').read_bytes()
  self.upgrade_bundle()
  with patch.object(self.inst,'publish'),patch.object(self.inst,'installed_check',side_effect=RuntimeError('unreadable')),self.assertRaisesRegex(RuntimeError,'unreadable'):
   self.inst.install(self.bundle)
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
  self.assertEqual((self.inst.state/'state.json').read_bytes(),before)
  self.assertFalse((self.inst.state/'upgrade-app').exists())
 def test_upgrade_failed_copy_does_not_modify_live_app(self):
  self.inst.install(self.bundle);self.upgrade_bundle();real=m.atomic
  def fault(path,*args,**kwargs):
   if path==self.inst.state/'upgrade-app/cover.qml':raise OSError('disk full')
   return real(path,*args,**kwargs)
  with patch.object(m,'atomic',side_effect=fault),self.assertRaisesRegex(OSError,'disk full'):self.inst.install(self.bundle)
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
  self.assertFalse((self.inst.state/'upgrade-app').exists())
 def test_upgrade_preserves_files_only_selection_and_rejects_activation(self):
  self.inst.install(self.bundle,enable=False);self.upgrade_bundle();self.calls.clear()
  with patch.object(self.inst,'publish'):self.inst.install(self.bundle)
  self.assertFalse(self.inst.load()['enabled']);self.assertEqual(self.inst.links('plasmalogin.service'),self.links)
  self.assertEqual(self.calls,[])
  with self.assertRaisesRegex(RuntimeError,'omit --activate-now'):self.inst.install(self.bundle,now=True)
 def test_upgrade_external_config_and_pending_rollback_refused(self):
  self.inst.install(self.bundle);self.upgrade_bundle();self.config.write_text('admin edit')
  with self.assertRaisesRegex(RuntimeError,'changed after installation'):self.inst.install(self.bundle)
  data=self.inst.load();data['phase']='rolling-back';self.inst.save(data)
  with self.assertRaisesRegex(RuntimeError,'pending rollback'):self.inst.install(self.bundle)
 def interrupted_upgrade(self, exchanged=False, committed=False):
  self.inst.install(self.bundle);old=self.inst.load();stage=self.inst.state/'upgrade-app'
  shutil.copytree(self.inst.app,stage);(stage/'cover.qml').write_text('new version')
  record=dict(id='fixture-upgrade',old_inode=self.inst.app.stat().st_ino,new_inode=stage.stat().st_ino)
  m.atomic(self.inst.state/'upgrade.json',json.dumps(record).encode(),0o600)
  if exchanged:self.inst.exchange_apps(stage)
  if committed:self.inst.save(dict(old,upgradeId=record['id'],digest='new-digest'))
 def test_upgrade_interruption_before_exchange_recovers_old(self):
  self.interrupted_upgrade();self.inst.recover_upgrade()
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
  self.assertFalse((self.inst.state/'upgrade.json').exists())
 def test_upgrade_interruption_after_exchange_recovers_old(self):
  self.interrupted_upgrade(exchanged=True);self.inst.recover_upgrade()
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
  self.inst.rollback();self.assert_restored()
 def test_upgrade_interruption_after_commit_keeps_new(self):
  self.interrupted_upgrade(exchanged=True,committed=True);self.inst.recover_upgrade()
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'new version')
  self.assertFalse((self.inst.state/'upgrade-app').exists())
 def test_upgrade_state_commit_failure_restores_old(self):
  self.inst.install(self.bundle);self.upgrade_bundle()
  with patch.object(self.inst,'publish'),patch.object(self.inst,'save',side_effect=OSError('commit failure')),self.assertRaisesRegex(OSError,'commit failure'):
   self.inst.install(self.bundle)
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
 def test_upgrade_preserves_other_account_public_data(self):
  self.inst.install(self.bundle)
  public=self.inst.app/'public-display/2001';public.mkdir(parents=True);(public/'manifest.json').write_text('other account')
  self.upgrade_bundle()
  with patch.object(self.inst,'publish'):self.inst.install(self.bundle,sync=False)
  self.assertEqual((public/'manifest.json').read_text(),'other account')
 def test_upgrade_same_filesystem_required(self):
  self.inst.install(self.bundle);self.upgrade_bundle()
  from types import SimpleNamespace
  real=Path.stat
  def info(path,*args,**kwargs):
   if path==self.inst.app:return SimpleNamespace(st_dev=-1)
   return real(path,*args,**kwargs)
  with patch.object(Path,'stat',info),self.assertRaisesRegex(RuntimeError,'same filesystem'):self.inst.install(self.bundle)
 def test_upgrade_publish_failure_restores_old_publication(self):
  self.inst.install(self.bundle)
  public=self.inst.app/'public-display/2001';public.mkdir(parents=True);(public/'manifest.json').write_text('old publication')
  self.upgrade_bundle()
  def fail(*args):
   (public/'manifest.json').write_text('changed');raise RuntimeError('publish failure')
  with patch.object(self.inst,'publish',side_effect=fail),self.assertRaisesRegex(RuntimeError,'publish failure'):self.inst.install(self.bundle)
  self.assertEqual((public/'manifest.json').read_text(),'old publication')
  self.assertEqual((self.inst.app/'cover.qml').read_text(),'# fixture\n')
 def test_upgrade_no_sync_revokes_only_caller_with_real_store(self):
  resources=REPO/'apps/greeter/companion/resources.py'
  dest=self.bundle/'app/companion/resources.py';dest.write_bytes(resources.read_bytes());dest.chmod(0o644)
  self.manifest();self.inst.install(self.bundle)
  spec=importlib.util.spec_from_file_location('upgrade_resources',resources)
  r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
  import io
  from PIL import Image
  blob=io.BytesIO();Image.new('RGB',(20,20),'red').save(blob,format='PNG')
  store=r.Store(self.inst.app/'public-display')
  for uid in (1000,1001):store.publish(uid,blob.getvalue(),consent=True,notice=r.NOTICE)
  self.upgrade_bundle()
  with patch.dict(os.environ,{'SUDO_UID':'1000'}):self.inst.install(self.bundle,sync=False)
  self.assertIsNone(store.consume(1000));self.assertIsNotNone(store.consume(1001))
 def test_refresh_publishes_and_revokes_only_requesting_account(self):
  import io
  from PIL import Image
  resources=REPO/'apps/greeter/companion/resources.py'
  dest=self.bundle/'app/companion/resources.py';dest.write_bytes(resources.read_bytes());dest.chmod(0o644)
  self.manifest();self.inst.install(self.bundle)
  uid=os.geteuid() or 1000
  blob=io.BytesIO();Image.new('RGB',(20,20),'#123456').save(blob,format='PNG')
  (self.bundle/'wallpaper.png').write_bytes(blob.getvalue())
  (self.bundle/'wallpaper.json').write_text(json.dumps(dict(uid=uid,fit='crop')))
  self.manifest()
  with patch.dict(os.environ,{'SUDO_UID':str(uid)}):self.inst.refresh(self.bundle)
  manifest=self.inst.app/'public-display'/str(uid)/'manifest.json'
  value=json.loads(manifest.read_text());self.assertEqual(value['expiresAt']-value['issuedAt'],86400)
  with patch.dict(os.environ,{'SUDO_UID':str(uid)}):self.inst.refresh(self.bundle,sync=False)
  self.assertFalse(manifest.exists())
 def test_readability_keeps_publisher_lock_private(self):
  self.inst.app.mkdir(parents=True)
  public=self.inst.app/'public-display/1000';(public/'v-fixture').mkdir(parents=True)
  lock=public/'.lock';lock.write_bytes(b'');lock.chmod(0o600)
  manifest=public/'manifest.json';manifest.write_text('{}');manifest.chmod(0o644)
  image=public/'v-fixture/wallpaper.png';image.write_bytes(b'fixture');image.chmod(0o644)
  source=self.inst.app/'shell.qml';source.write_text('fixture');source.chmod(0o644)
  files=self.inst.runtime_files()
  self.assertNotIn(str(lock),files)
  self.assertIn(str(manifest),files);self.assertIn(str(image),files);self.assertIn(str(source),files)
  # Exercise the actual check, modeling an account that can only read public
  # file modes. Previously the 0600 publisher lock made this fail.
  from types import SimpleNamespace
  def command(*args,**kwargs):
   if '-c' not in args:return subprocess.CompletedProcess(args,0,'','')
   unreadable=[p for p in args[3:] if not Path(p).stat().st_mode&0o004]
   if unreadable:raise subprocess.CalledProcessError(1,args,stderr='Unreadable Greeter runtime files: '+', '.join(unreadable))
   return subprocess.CompletedProcess(args,0,'','')
  with patch.object(m.pwd,'getpwnam',return_value=SimpleNamespace(pw_uid=2000,pw_gid=2000)),patch.object(m,'run',side_effect=command):
   m.Installer.installed_check(self.inst)
   manifest.chmod(0o600)
   with self.assertRaisesRegex(RuntimeError,'Unreadable Greeter runtime files:.*manifest.json'):
    m.Installer.installed_check(self.inst)
  self.assertEqual(stat.S_IMODE(lock.stat().st_mode),0o600)
 def test_reload_user_is_scoped_without_environment_import(self):
  uid=os.geteuid() or 1000
  self.active['user@'+str(uid)+'.service']='active'
  with patch.object(m,'run',return_value=subprocess.CompletedProcess([],0,'','')) as command:
   self.inst.reload_user(dict(caller_uid=uid))
  self.assertEqual(command.call_args.args,('/usr/bin/systemctl','--user','daemon-reload'))
  self.assertEqual(command.call_args.kwargs['user'],uid)
  self.assertEqual(set(command.call_args.kwargs['env']),{'XDG_RUNTIME_DIR','DBUS_SESSION_BUS_ADDRESS'})
 def test_saved_getty_is_restored(self):
  self.active['getty@tty1.service']='active';self.inst.install(self.bundle)
  self.active['getty@tty1.service']='inactive';self.inst.rollback()
  self.assertIn(('start','getty@tty1.service'),self.calls)
 def test_manual_rollback_cleans_failed_daemon_session(self):
  self.inst.install(self.bundle);self.active['greetd.service']='failed'
  self.sessions.append('new 1000 user');self.services['new']='greetd'
  self.inst.rollback();self.assertIn(('terminate','new'),self.calls)
 def test_temporary_state_preflight_refuses_without_host_calls(self):
  (self.root/'run/kos-greeter-test').mkdir(parents=True)
  with self.assertRaisesRegex(RuntimeError,'Temporary test'):
   m.Installer.preflight(self.inst)
  self.assertEqual(self.calls,[])
 def test_lock_contention(self):
  fd=self.inst.lock()
  try:
   with self.assertRaisesRegex(RuntimeError,'Another installation'):self.inst.lock()
  finally:os.close(fd)
 def test_active_install_failure_restores_previous_manager(self):
  self.fail=('start','greetd.service')
  with patch.object(m,'recovery_tty'),self.assertRaises(RuntimeError):self.inst.install(self.bundle,now=True)
  self.assert_restored();self.assertEqual(self.active['plasmalogin.service'],'active')

if __name__=='__main__':unittest.main()
