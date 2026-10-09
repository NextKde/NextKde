#!/usr/bin/env python3
"""Report actual missing app build dependencies with Arch/Ubuntu package names."""
import argparse
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile

# (probe, Arch package, Ubuntu/Debian package)
TOOLS = [
    ('bash', 'bash', 'bash'), ('cmake', 'cmake', 'cmake'),
    ('ninja', 'ninja', 'ninja-build'), ('c++', 'gcc', 'g++'), ('cc', 'gcc', 'gcc'),
    ('curl', 'curl', 'curl'), ('tar', 'tar', 'tar'), ('bzip2', 'bzip2', 'bzip2'),
    ('patch', 'patch', 'patch'), ('sha256sum', 'coreutils', 'coreutils'),
    ('pkg-config', 'pkgconf', 'pkg-config'), ('flock', 'util-linux', 'util-linux'),
]
LIBRARIES = [
    ('Qt6Core >= 6.10', 'qt6-base', 'qt6-base-dev'),
    ('Qt6Widgets', 'qt6-base', 'qt6-base-dev'), ('Qt6DBus', 'qt6-base', 'qt6-base-dev'),
    ('Qt6Sql', 'qt6-base', 'qt6-base-dev'), ('Qt6Test', 'qt6-base', 'qt6-base-dev'),
    ('Qt6Quick', 'qt6-declarative', 'qt6-declarative-dev'),
    ('Qt6QuickControls2', 'qt6-declarative', 'qt6-declarative-dev'),
    ('Qt6QuickDialogs2', 'qt6-declarative', 'qt6-declarative-dev'),
    ('Qt6Multimedia', 'qt6-multimedia', 'qt6-multimedia-dev'),
    ('Qt6ShaderTools', 'qt6-shadertools', 'qt6-shadertools-dev'),
    ('Qt6WebEngineWidgets', 'qt6-webengine', 'qt6-webengine-dev'),
    ('libavformat', 'ffmpeg', 'libavformat-dev'), ('libavcodec', 'ffmpeg', 'libavcodec-dev'),
    ('libavutil', 'ffmpeg', 'libavutil-dev'), ('libswresample', 'ffmpeg', 'libswresample-dev'),
    ('libcurl', 'curl', 'libcurl4-openssl-dev'), ('libpulse', 'libpulse', 'libpulse-dev'),
    ('libsecret-1', 'libsecret', 'libsecret-1-dev'), ('icu-uc', 'icu', 'libicu-dev'),
    ('openssl', 'openssl', 'libssl-dev'), ('zlib', 'zlib', 'zlib1g-dev'),
]
CMAKE_PACKAGES = {
    'Qt6LinguistTools': ('qt6-tools', 'qt6-tools-dev'),
    'KF6WindowSystem': ('kwindowsystem', 'libkf6windowsystem-dev'),
    'KF6CalendarCore': ('kcalendarcore', 'libkf6calendarcore-dev'),
    'Utf8Cpp': ('utf8cpp', 'libutfcpp-dev'),
    'SQLiteDriver': ('qt6-base', 'libqt6sql6-sqlite'),
}

for module, package in (
    ('QtCore', 'qtcore'), ('QtQml', 'qtqml'), ('QtQml_Models', 'qtqml-models'),
    ('QtQml_WorkerScript', 'qtqml-workerscript'),
    ('QtQuick_Effects', 'qtquick-effects'), ('QtQuick_Shapes', 'qtquick-shapes'),
    ('QtMultimedia', 'qtmultimedia'),
    ('QtQuick', 'qtquick'), ('QtQuick_Window', 'qtquick-window'),
    ('QtQuick_Layouts', 'qtquick-layouts'), ('QtQuick_Controls', 'qtquick-controls'),
    ('QtQuick_Templates', 'qtquick-templates'), ('QtQuick_Dialogs', 'qtquick-dialogs')):
    CMAKE_PACKAGES['Qml_' + module] = ('qt6-multimedia' if module == 'QtMultimedia' else 'qt6-declarative', 'qml6-module-' + package)

def distribution(path=Path('/etc/os-release')):
    values = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                values[key] = value.strip('"\'')
    ids = [values.get('ID', ''), *values.get('ID_LIKE', '').split()]
    if 'arch' in ids: return 'arch'
    if any(value in ids for value in ('ubuntu', 'debian')): return 'ubuntu'
    return 'other'

def install_command(family, packages):
    packages = sorted(set(packages))
    if family == 'arch': return 'sudo pacman -S --needed ' + shlex.join(packages)
    if family == 'ubuntu': return 'sudo apt update && sudo apt install ' + shlex.join(packages)
    return None

def run(command):
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-only', action='store_true')
    args = parser.parse_args()
    family = distribution()
    missing = []
    tools = TOOLS + ([] if args.sdk_only else [
        ('busctl', 'systemd', 'systemd'), ('systemctl', 'systemd', 'systemd'),
        ('readlink', 'coreutils', 'coreutils'), ('go', 'go', 'golang-go')])
    for executable, arch, ubuntu in tools:
        if not shutil.which(executable): missing.append((executable, arch, ubuntu))
    if shutil.which('cmake'):
        version = run(['cmake', '--version']).stdout
        match = re.search(r'(\d+)\.(\d+)', version)
        if match and tuple(map(int, match.groups())) < (3, 28):
            missing.append(('CMake >= 3.28 (installed ' + match.group(0) + ')', 'cmake', 'cmake'))
    if not args.sdk_only and shutil.which('go'):
        version = run(['go', 'version']).stdout
        match = re.search(r'go(\d+)\.(\d+)', version)
        if match and tuple(map(int, match.groups())) < (1, 26):
            missing.append(('Go >= 1.26 (installed ' + match.group(0) + ')', 'go', 'golang-go'))
    if shutil.which('pkg-config'):
        for probe, arch, ubuntu in LIBRARIES:
            if run(['pkg-config', '--exists', probe]).returncode:
                missing.append((probe, arch, ubuntu))
    qt_version = run(['pkg-config', '--modversion', 'Qt6Core']).stdout.strip() if shutil.which('pkg-config') else ''
    qt_match = re.match(r'(\d+)\.(\d+)', qt_version)
    old_qt = qt_match and tuple(map(int, qt_match.groups())) < (6, 10)
    # CMake checks honor CMAKE_PREFIX_PATH and native multiarch paths. Do not
    # assume /usr/lib or a particular CPU architecture for Frameworks/tools.
    if not missing:
        with tempfile.TemporaryDirectory(prefix='kos-deps-') as build:
            result = run(['cmake', '-S', str(Path(__file__).parent / 'app-dependencies'),
                '-B', build, '-G', 'Ninja', '-DKOS_SDK_ONLY=' + ('ON' if args.sdk_only else 'OFF'),
                '-DKOS_BUILD_TAGLIB=' + ('ON' if run(['pkg-config', '--exists', 'taglib >= 2.3.1']).returncode else 'OFF')])
            for package in re.findall(r'KOS_MISSING:(\w+)', result.stdout):
                missing.append((package, *CMAKE_PACKAGES[package]))
            if result.returncode:
                print('Dependency discovery failed:\n' + result.stdout)
                return 1
    if missing:
        print('Missing or incompatible application dependencies:')
        for label, arch, ubuntu in missing:
            print('  - ' + label + ' (' + (arch if family == 'arch' else ubuntu if family == 'ubuntu' else arch + ' / ' + ubuntu) + ')')
        command = install_command(family, [entry[1 if family == 'arch' else 2] for entry in missing])
        if command: print('\nInstall the missing packages:\n' + command)
        if any(label.startswith(('Go >=', 'CMake >=')) for label, _, _ in missing):
            print('If the distro package is too old, install a supported newer toolchain; reinstalling the old version is insufficient.')
        if old_qt:
            print('\nInstalled Qt is ' + qt_version + '; ListenFree requires Qt >= 6.10.')
            print('Ubuntu 22.04/24.04/25.10 stock Qt is too old; use Ubuntu 26.04+ or a complete compatible Qt/KF6 toolchain.')
            print('Installing the same older Qt package again will not satisfy this requirement.')
        return 1
    print('Application system dependencies are ready (' + family + ', Qt ' + qt_version + ').')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
