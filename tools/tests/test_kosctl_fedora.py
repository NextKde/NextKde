"""Exercise the actual dependency selector with command stubs; run only in CI/VM."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'kosctl').read_text()
ARRAYS = re.findall(r'^fedora_\w+_packages=\(.*?^\)', SOURCE, re.M | re.S)

def function(name):
    return re.search(r'^' + name + r'\(\) \{.*?^\}', SOURCE, re.M | re.S).group()

class FedoraSelection(unittest.TestCase):
    def run_selection(self, missing='', plugins='ON', spatial='AUTO', failure=False):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'sudo.log'
            script = '\n'.join(ARRAYS + [function(name) for name in (
                'fedora_package_installed', 'kwin_plugins_enabled',
                'spatial_requested', 'ensure_build_dependencies')])
            # Only intercept package-manager discovery. No host package mutation.
            script += r'''
is_nixos() { return 1; }
command() {
    if [[ "$1" == -v ]]; then
        [[ "$2" == dnf ]]
    else
        builtin command "$@"
    fi
}
rpm() {
    [[ "$1" == -q && "$2" == --whatprovides ]] || exit 91
    [[ " $MISSING " != *" $3 "* ]]
}
sudo() {
    printf '%s\n' "$@" >> "$LOG"
    return "$INSTALL_FAILURE"
}
ensure_build_dependencies
'''
            result = subprocess.run(['bash', '-euc', script], text=True, capture_output=True,
                env={**os.environ, 'MISSING': missing, 'LOG': str(log),
                     'INSTALL_FAILURE': '1' if failure else '0',
                     'KOS_BUILD_KWIN_PLUGINS': plugins, 'KOS_BUILD_SPATIAL': spatial})
            return result.returncode, log.read_text().splitlines() if log.exists() else []

    def test_installed_virtual_provider_does_not_reinstall(self):
        self.assertEqual(self.run_selection(), (0, []))

    def test_only_missing_required_packages_are_installed(self):
        self.assertEqual(self.run_selection('zlib-devel opencv-devel cliphist'),
                         (0, ['dnf', 'install', '-y', 'zlib-devel', 'opencv-devel']))

    def test_disabled_features_and_optional_runtime_are_not_installed(self):
        self.assertEqual(self.run_selection('kwin-devel opencv-devel cliphist', 'OFF', 'OFF'),
                         (0, []))

    def test_install_failure_stops_execution(self):
        code, args = self.run_selection('cmake', failure=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(args, ['dnf', 'install', '-y', 'cmake'])

if __name__ == '__main__':
    if sys.argv[1:] == ['--packages']:
        print('\n'.join(dict.fromkeys(word for array in ARRAYS
            for word in array.split('(', 1)[1].rsplit(')', 1)[0].split())))
    else:
        unittest.main()
