#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
from unittest.mock import patch
REPO = Path(__file__).resolve().parents[3]
def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, REPO/'tools'/filename)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module
sync = load('sync', 'sync-greeter-shell.py')
installer = load('installer', 'greeter-install.py')
with tempfile.TemporaryDirectory() as tmp:
    target = Path(tmp)/'kos'; target.mkdir()
    (target/'shell.qml').write_text('existing shell root')
    (target/'desktop').mkdir(); (target/'desktop/old.qml').write_text('legacy')
    (target/'Kos/native').mkdir(parents=True); (target/'Kos/native/plugin.so').write_bytes(b'plugin')
    (target/'apps').mkdir(); (target/'apps/custom').write_text('preserve')
    before = sync.inventory(target)
    sync.synchronize(target, check=True)
    assert sync.inventory(target) == before
    original = sync.os.rename
    def fail(source, destination):
        if Path(source).name == 'Kos' and '.kos-shell-stage-' in str(source):
            raise OSError('injected replace failure')
        return original(source, destination)
    with patch.object(sync.os, 'rename', side_effect=fail):
        try: sync.synchronize(target)
        except OSError: pass
        else: raise AssertionError('fault injection did not run')
    assert sync.inventory(target) == before
    sync.synchronize(target)
    assert installer.shell_compatibility(target) == []
    assert (target/'Kos/native/plugin.so').read_bytes() == b'plugin'
    assert (target/'apps/custom').read_text() == 'preserve'
    assert (target/'shell.qml').read_text() == 'existing shell root'
    assert not (target/'Kos/Ui/wallpapers').is_symlink()
    assert not (target/'desktop/old.qml').exists()
    (target/'desktop/modules/common/SessionEntryService.qml').unlink()
    assert installer.shell_compatibility(target)
print('PASS dry-run, transactional failure restoration, dependency materialization, stale removal, native/apps/root preservation, capability detection')
