"""Exercise the OpenSUSE dependency selector with command stubs."""
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'kosctl').read_text()
ROOT = Path(__file__).resolve().parents[2]
ARRAYS = re.findall(r'^opensuse_\w+_packages=\(.*?^\)', SOURCE, re.M | re.S)


def function(name):
    return re.search(r'^' + name + r'\(\) \{.*?^\}', SOURCE, re.M | re.S).group()


class OpenSuseSelection(unittest.TestCase):
    def run_selection(self, missing='', plugins='ON', spatial='AUTO', failure=False):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'sudo.log'
            script = '\n'.join(ARRAYS + [function(name) for name in (
                'kwin_plugins_enabled', 'spatial_requested',
                'ensure_build_dependencies')])
            # Only intercept package-manager discovery. No host package mutation.
            script += r'''
is_nixos() { return 1; }
command() {
    if [[ "$1" == -v ]]; then
        [[ "$2" == zypper ]]
    else
        builtin command "$@"
    fi
}
rpm() {
    [[ "$1" == -q ]] || exit 91
    [[ " $MISSING " != *" $2 "* ]]
}
sudo() {
    printf '%s\n' "$@" >> "$LOG"
    return "$INSTALL_FAILURE"
}
ensure_build_dependencies
'''
            result = subprocess.run(
                ['bash', '-euc', script],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    'MISSING': missing,
                    'LOG': str(log),
                    'INSTALL_FAILURE': '1' if failure else '0',
                    'KOS_BUILD_KWIN_PLUGINS': plugins,
                    'KOS_BUILD_SPATIAL': spatial,
                },
            )
            return result.returncode, log.read_text().splitlines() if log.exists() else []

    def test_default_dependency_groups_are_explicit(self):
        groups = {
            re.search(r'^opensuse_(\w+)_packages=', array, re.M).group(1):
            set(array.split('(', 1)[1].rsplit(')', 1)[0].split())
            for array in ARRAYS
        }
        self.assertEqual(
            set(groups),
            {'core_build', 'spatial_build', 'kwin_build', 'optional_runtime'},
        )
        self.assertTrue(
            {'flatpak-devel', 'libostree-devel', 'fcitx5-devel'}
            <= groups['core_build']
        )
        self.assertIn('opencv-devel', groups['spatial_build'])
        self.assertIn('kwin6-devel', groups['kwin_build'])

    def test_documentation_lists_the_complete_default_build(self):
        expected = {
            word
            for array in ARRAYS
            if not array.startswith('opensuse_optional_runtime_packages=')
            for word in array.split('(', 1)[1].rsplit(')', 1)[0].split()
        }
        for name in ('GettingStarted.md', 'GettingStarted.zh-CN.md'):
            document = (ROOT / 'docs' / name).read_text()
            start = document.index('sudo zypper install \\\n')
            end = document.index('\n```', start)
            listed = set(
                document[start:end]
                .replace('\\', '')
                .split()[3:]
            )
            self.assertEqual(listed, expected, name)

    def test_installed_packages_do_not_reinstall(self):
        self.assertEqual(self.run_selection(), (0, []))

    def test_only_missing_required_packages_are_installed(self):
        self.assertEqual(
            self.run_selection('cmake kwin6-devel opencv-devel cliphist'),
            (0, ['zypper', '--non-interactive', 'install', '--',
                 'cmake', 'kwin6-devel', 'opencv-devel']),
        )

    def test_disabled_features_and_optional_runtime_are_not_installed(self):
        self.assertEqual(
            self.run_selection(
                'kwin6-devel opencv-devel cliphist',
                plugins='OFF',
                spatial='OFF',
            ),
            (0, []),
        )

    def test_cache_signature_covers_all_required_packages_and_converges(self):
        with tempfile.TemporaryDirectory() as directory:
            build = Path(directory)
            configure_stamp = build / 'kos-configure-inputs'
            configure_stamp.write_text('old configure inputs\n')
            script = '\n'.join(ARRAYS + [function(name) for name in (
                'kwin_plugins_enabled', 'spatial_requested',
                'opensuse_build_dependency_signature',
                'refresh_opensuse_cmake_configuration')])
            script += r'''
build_dir=$BUILD_DIR
rpm() { printf '%s=1\n' "${@: -1}"; }
command() {
    if [[ "$1" == -v ]]; then
        [[ "$2" == zypper ]]
    else
        builtin command "$@"
    fi
}
refresh_opensuse_cmake_configuration
[[ ! -f "$build_dir/kos-configure-inputs" ]]
touch "$build_dir/kos-configure-inputs"
refresh_opensuse_cmake_configuration
[[ -f "$build_dir/kos-configure-inputs" ]]
wc -l < "$build_dir/opensuse-build-dependencies"
'''
            result = subprocess.run(
                ['bash', '-euc', script],
                text=True,
                capture_output=True,
                env={
                    **os.environ,
                    'BUILD_DIR': str(build),
                    'KOS_BUILD_KWIN_PLUGINS': 'ON',
                    'KOS_BUILD_SPATIAL': 'AUTO',
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = sum(
                len(array.split('(', 1)[1].rsplit(')', 1)[0].split())
                for array in ARRAYS
                if not array.startswith('opensuse_optional_runtime_packages=')
            )
            self.assertEqual(int(result.stdout.strip()), expected)

    def test_install_failure_stops_execution(self):
        code, args = self.run_selection('cmake', failure=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(
            args,
            ['zypper', '--non-interactive', 'install', '--', 'cmake'],
        )


if __name__ == '__main__':
    if sys.argv[1:] == ['--packages']:
        print('\n'.join(dict.fromkeys(
            word
            for array in ARRAYS
            for word in array.split('(', 1)[1].rsplit(')', 1)[0].split()
        )))
    else:
        unittest.main()
