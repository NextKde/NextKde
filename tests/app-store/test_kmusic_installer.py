"""Isolated contract tests. Run in VM/CI; filesystem and subprocess faults are injected."""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

source = pathlib.Path(os.environ.get('KMUSIC_SOURCE_DIR', str(pathlib.Path(__file__).resolve().parents[3]/'KMusic')))
spec = importlib.util.spec_from_file_location('installer', source/'packaging/installer.py')
i = importlib.util.module_from_spec(spec); spec.loader.exec_module(i)
A='a'*40; B='b'*40

class InstallerContract(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.home=pathlib.Path(self.tmp.name)/'home with spaces'; self.home.mkdir()
        self.root=self.home/'data/kmusic-app'; self.version=A; self.fault=None; self.calls=[]
        self.original_read=pathlib.Path.read_text
        self.distro='arch'
        def read(path,*args,**kwargs):
            if str(path)=='/etc/os-release': return 'ID='+self.distro+'\n'
            return self.original_read(path,*args,**kwargs)
        self.stack=contextlib.ExitStack()
        for p in [patch.object(i.os,'geteuid',return_value=1000), patch.object(i.pathlib.Path,'home',return_value=self.home),
                  patch.object(i.pathlib.Path,'read_text',read), patch.object(i.platform,'machine',return_value='x86_64'),
                  patch.dict(os.environ,{'XDG_DATA_HOME':str(self.home/'data'),'XDG_STATE_HOME':str(self.home/'state')}),
                  patch.object(i,'dependencies'),patch.object(i,'run',side_effect=self.fake_run)]: self.stack.enter_context(p)
    def tearDown(self):
        if i.log: i.log.close(); i.log=None
        self.stack.close(); self.tmp.cleanup()
    def fake_run(self,args,cwd=None,code='DEPENDENCY_UNSATISFIED',timeout=1800):
        self.calls.append(args)
        if self.fault=='download' and 'fetch' in args: i.fail('DOWNLOAD_FAILED','injected download failure')
        if args[0]=='git' and 'rev-parse' in args: return '0'*40 if self.fault=='integrity' else self.version
        if args[0]=='git' and 'status' in args: return '+bad submodule' if self.fault=='submodule' else ''
        if self.fault=='build' and args[:2]==['cmake','--build']: i.fail('BUILD_FAILED','injected compiler failure')
        if args[:2]==['cmake','--install']:
            if self.fault=='install': i.fail('INSTALL_FAILED','injected staging failure')
            dest=pathlib.Path(args[args.index('--prefix')+1]); (dest/'bin').mkdir(parents=True)
            (dest/'bin/kmusic').write_text('fixture executable')
            (dest/'share/applications').mkdir(parents=True); (dest/'share/applications/kmusic.desktop').write_text('[Desktop Entry]\nExec=kmusic %U\n')
            (dest/'share/icons/hicolor/scalable/apps').mkdir(parents=True); (dest/'share/icons/hicolor/scalable/apps/kmusic.svg').write_text('<svg/>')
        return ''
    def invoke(self,args):
        output=io.StringIO(); code=0; i.action='unknown'; i.stage='arguments'; i.log_path=None
        with patch.object(i.sys,'argv',['install.sh']+args), contextlib.redirect_stdout(output):
            try: i.entrypoint()
            except SystemExit as e: code=e.code
        if i.log: i.log.close(); i.log=None
        lines=[json.loads(line) for line in output.getvalue().splitlines()]
        results=[x for x in lines if x['type']=='result']; self.assertEqual(len(results),1)
        result=results[0]; self.assertEqual(result['schemaVersion'],1); self.assertEqual(result['success'],code==0)
        return code,result
    def install(self,sha=A):
        self.version=sha; return self.invoke(['install','--version',sha])
    def test_supported_distro_contract(self):
        for distro in ['arch','ubuntu','debian']:
            with self.subTest(distro=distro):
                self.distro=distro; code,r=self.invoke(['check']); self.assertEqual(code,0); self.assertEqual(r['distribution'],distro)
    def test_install_idempotency_upgrade_uninstall(self):
        self.assertEqual(self.invoke(['status'])[1]['installed'],False)
        self.assertEqual(self.install()[1]['code'],'INSTALLED')
        old=(self.root/'current').resolve(); self.calls.clear()
        self.assertEqual(self.install()[1]['code'],'ALREADY_INSTALLED'); self.assertFalse(self.calls)
        self.assertEqual(self.install(B)[0],0); self.assertTrue(old.exists())
        self.assertNotEqual((self.root/'current').resolve(),old)
        manifest=json.loads((self.root/'manifest.json').read_text()); self.assertEqual(manifest['previous'],str(old))
        entry=(self.home/'data/applications/kmusic.desktop').read_text(); self.assertIn('Exec="',entry); self.assertIn('home with spaces',entry)
        user_data=self.home/'data/kmusic/library.db'; user_data.parent.mkdir(); user_data.write_text('keep')
        self.assertEqual(self.invoke(['uninstall'])[0],0); self.assertEqual(user_data.read_text(),'keep')
        self.assertFalse(self.root.exists()); self.assertFalse((self.home/'data/applications/kmusic.desktop').is_symlink())
        self.assertFalse(self.invoke(['uninstall'])[1]['changed'])
    def test_failed_upgrade_preserves_old_install(self):
        self.install(); old=(self.root/'current').resolve(); before=(self.root/'manifest.json').read_bytes()
        for fault,expected in [('download',20),('integrity',21),('submodule',21),('build',30),('install',31)]:
            with self.subTest(fault=fault):
                self.fault=fault; self.assertEqual(self.install(B)[0],expected)
                self.assertEqual((self.root/'current').resolve(),old); self.assertEqual((self.root/'manifest.json').read_bytes(),before)
                self.assertEqual(list(self.root.glob('stage-*')),[])
    def test_publish_failure_rolls_back(self):
        self.install(); old=(self.root/'current').resolve(); before=(self.root/'manifest.json').read_bytes()
        with patch.object(i,'atomic_json',side_effect=OSError('injected manifest failure')):
            self.assertEqual(self.install(B)[0],31)
        self.assertEqual((self.root/'current').resolve(),old); self.assertEqual((self.root/'manifest.json').read_bytes(),before)
        self.assertTrue((self.home/'data/applications/kmusic.desktop').exists())
    def test_fresh_publish_failure_removes_registration(self):
        with patch.object(i,'atomic_json',side_effect=OSError('injected manifest failure')): self.assertEqual(self.install()[0],31)
        self.assertFalse((self.root/'current').is_symlink())
        self.assertFalse((self.home/'data/applications/kmusic.desktop').is_symlink())
    def test_missing_dependencies_never_download(self):
        with patch.object(i,'dependencies',side_effect=i.Failure('DEPENDENCY_UNSATISFIED','missing',{'dependencies':[{'id':'qt6','required':'>=6.8','installed':None,'reason':'missing'}]})):
            code,r=self.install(); self.assertEqual(code,11); self.assertEqual(r['details']['dependencies'][0]['reason'],'missing')
        self.assertFalse(self.calls); self.assertFalse(self.root.exists())
    def test_invalid_arguments(self):
        for args in [[],['wrong'],['install'],['install','--version','main'],['status','--force'],['install','--version','x'*40]]:
            with self.subTest(args=args): self.assertEqual(self.invoke(args)[0],2)
    def test_root_refused(self):
        with patch.object(i.os,'geteuid',return_value=0): self.assertEqual(self.invoke(['check'])[0],12)
    def test_platform_refused(self):
        self.distro='fedora'; self.assertEqual(self.invoke(['check'])[0],10)
        self.distro='arch'
        with patch.object(i.platform,'machine',return_value='riscv64'): self.assertEqual(self.invoke(['check'])[0],10)
    def test_relative_xdg_refused(self):
        with patch.dict(os.environ,{'XDG_DATA_HOME':'relative'}): self.assertEqual(self.invoke(['check'])[0],2)
    def test_unmanaged_desktop_preserved(self):
        p=self.home/'data/applications/kmusic.desktop'; p.parent.mkdir(parents=True); p.write_text('owned by user')
        self.assertEqual(self.install()[0],31); self.assertEqual(p.read_text(),'owned by user')
    def test_lock_conflict(self):
        with patch.object(i.fcntl,'flock',side_effect=BlockingIOError): self.assertEqual(self.invoke(['check'])[0],13)
    def test_cancelled_returns_result(self):
        with patch.object(i,'dependencies',side_effect=KeyboardInterrupt): self.assertEqual(self.invoke(['check'])[0],130)
    def test_corrupt_manifest_reports_internal_error(self):
        self.root.mkdir(parents=True); (self.root/'manifest.json').write_text('{bad')
        self.assertEqual(self.invoke(['status'])[0],99)
    def test_uninstall_failure_reported(self):
        self.install()
        with patch.object(i.shutil,'rmtree',side_effect=OSError('injected delete failure')):
            self.assertEqual(self.invoke(['uninstall'])[0],32)
    def test_missing_current_is_repaired(self):
        self.install(); (self.root/'current').unlink()
        self.assertEqual(self.install()[1]['code'],'INSTALLED')
        self.assertTrue((self.root/'current/bin/kmusic').exists())
    def test_permission_failure(self):
        with patch.object(i.pathlib.Path,'mkdir',side_effect=PermissionError): self.assertEqual(self.invoke(['check'])[0],12)

class Dependencies(unittest.TestCase):
    def test_all_missing_structured(self):
        with tempfile.TemporaryDirectory() as td, patch.object(i.shutil,'which',return_value=None):
            with self.assertRaises(i.Failure) as caught: i.dependencies(pathlib.Path(td))
        self.assertEqual(caught.exception.code,'DEPENDENCY_UNSATISFIED')
        self.assertGreater(len(caught.exception.details['dependencies']),1)
        for d in caught.exception.details['dependencies']:
            self.assertEqual(set(d),{'id','required','installed','reason'}); self.assertEqual(d['reason'],'missing')
    def test_old_versions(self):
        with tempfile.TemporaryDirectory() as td, patch.object(i.shutil,'which',side_effect=lambda tool:'/fake/'+tool if tool in ['cmake','node'] else None), patch.object(i,'run',side_effect=lambda args,**kw:'cmake version 3.20.0' if args[0]=='cmake' else 'v20.19.2'):
            with self.assertRaises(i.Failure) as caught: i.dependencies(pathlib.Path(td))
        entries={d['id']:d for d in caught.exception.details['dependencies']}
        self.assertEqual(entries['node']['reason'],'version_too_old'); self.assertEqual(entries['cmake']['reason'],'version_too_old')

if __name__=='__main__': unittest.main(verbosity=2)
