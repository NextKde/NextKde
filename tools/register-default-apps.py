#!/usr/bin/env python3
"""Register NextKDE applications and retire legacy Music installation files."""
from pathlib import Path
import argparse
import configparser
import datetime
import json
import os
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--prefix', type=Path, default=Path.home() / '.local')
parser.add_argument('--config-home', type=Path, default=Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')))
parser.add_argument('--state-home', type=Path, default=Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')))
parser.add_argument('--with-listenfree', action='store_true', help='Register ListenFree and migrate the legacy music installation')
parser.add_argument('--dry-run', action='store_true')
parser.add_argument('--no-cache', action='store_true', help='Skip desktop cache refresh when staging a package')
args = parser.parse_args()
prefix, config = args.prefix.resolve(), args.config_home.resolve()
apps = ('todo', 'calendar', 'weather', 'calculator')
selected_names = [*(f'kos-{name}' for name in apps)]
if args.with_listenfree: selected_names.append('listenfree')
for name in selected_names:
    if not os.access(prefix / 'bin' / name, os.X_OK) or not (prefix / 'share/applications' / (name + '.desktop')).is_file():
        raise SystemExit('Install the new application before registering it: ' + name)

def ini(path):
    result = configparser.ConfigParser(interpolation=None, strict=False)
    result.optionxform = str
    if path.exists(): result.read(path, encoding='utf-8')
    return result

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.nextkde-new')
    temp.write_text(text, encoding='utf-8')
    temp.replace(path)

legacy_files = []
mimes = []
mime_files = []
if args.with_listenfree:
    # Validate the replacement before retiring any old files. No user data is
    # stored in these exact installation paths.
    subprocess.run([str(prefix / 'bin/listenfree'), '--version'], check=True,
                   env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}, stdout=subprocess.DEVNULL)
    legacy_files = [prefix / path for path in (
        'bin/kos-music', 'bin/kos-music-lx-source-host', 'bin/kos-music-lx-source-host.js',
        'share/applications/kos-music.desktop', 'share/icons/hicolor/scalable/apps/kos-music.svg',
        'share/metainfo/org.nextkde.Kos.Music.metainfo.xml')]

    new_entry = ini(prefix / 'share/applications/listenfree.desktop')
    mimes = [item for item in new_entry['Desktop Entry']['MimeType'].split(';') if item]
    mime_files = [config / 'mimeapps.list']
    # Desktop-specific preferences take precedence if the user already has them.
    for name in ('kde-mimeapps.list', 'nextkde-mimeapps.list'):
        if (config / name).exists(): mime_files.append(config / name)
# Only the new compatibility desktop entry authorizes retiring the old
# standalone AppStream identity. Keep the executable, desktop shortcut, icons
# and all task data for existing pins and scripts.
todo_entry = ini(prefix / 'share/applications/kos-todo.desktop')
if todo_entry.getboolean('Desktop Entry', 'X-NextKDE-UnifiedCalendar', fallback=False):
    legacy_files.append(prefix / 'share/metainfo/org.nextkde.Kos.Todo.metainfo.xml')

buttons = config / 'kos/window-buttons.json'
previews = [prefix / location / f'kos-{app}-preview{suffix}'
            for app in apps for location, suffix in [('bin', ''), ('share/applications', '.desktop')]]
preview_dir = prefix / 'opt/nextkde-ui-preview'
paths = [*mime_files, buttons, *legacy_files, *previews]
if args.dry_run:
    print('Register:', ', '.join(selected_names))
    print('Retire preview registrations; music migration:', args.with_listenfree)
    print('Audio MIME types:', ', '.join(mimes))
    raise SystemExit(0)

registration_state = args.state_home / 'kos/application-registration'
migration_marker = registration_state / 'listenfree-migrated.json'
# Older releases already migrated defaults and left backup manifests.
migrated = args.with_listenfree and (migration_marker.exists() or any(
    json.loads(path.read_text()).get('listenfree_migration', True)
    for path in registration_state.glob('*/manifest.json')))

stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
backup = args.state_home / 'kos/application-registration' / stamp
backup.mkdir(parents=True, mode=0o700)
manifest = {'files': [], 'retiredPreview': None, 'listenfree_migration': args.with_listenfree}
for index, path in enumerate(paths):
    saved = backup / str(index)
    existed = path.exists() or path.is_symlink()
    if existed: shutil.copy2(path, saved, follow_symlinks=False)
    manifest['files'].append({'path': str(path), 'backup': str(saved), 'existed': existed})
(backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

from io import StringIO
initial_defaults = {mime: [ini(candidate).get('Default Applications', mime, fallback='')
                          for candidate in mime_files] for mime in mimes}
for path in mime_files:
    preferences = ini(path)
    if migrated and not any('kos-music.desktop' in value
                            for section in preferences.sections()
                            for value in preferences[section].values()):
        continue
    for section in ('Default Applications', 'Added Associations'):
        if not preferences.has_section(section): preferences.add_section(section)
    for mime in mimes:
        existing = initial_defaults[mime]
        # Only replace our legacy default, never another chosen player.
        current = preferences['Default Applications'].get(mime, '')
        if 'kos-music.desktop' in current.split(';'):
            preferences['Default Applications'][mime] = ';'.join(dict.fromkeys(
                'listenfree.desktop' if value == 'kos-music.desktop' else value
                for value in current.split(';') if value)) + ';'
        elif not migrated and all(value.strip(';') in ('', 'kos-music.desktop') for value in existing):
            preferences['Default Applications'][mime] = 'listenfree.desktop;'
        previous = preferences['Added Associations'].get(mime, '').split(';')
        if not migrated or 'kos-music.desktop' in previous:
            preferences['Added Associations'][mime] = ';'.join(dict.fromkeys(
                ['listenfree.desktop', *[value for value in previous if value and value != 'kos-music.desktop']])) + ';'
        if preferences.has_section('Removed Associations'):
            removed = preferences['Removed Associations'].get(mime, '').split(';')
            retained = [value for value in removed if value and value != 'kos-music.desktop'
                        and (migrated or value != 'listenfree.desktop')]
            if retained: preferences['Removed Associations'][mime] = ';'.join(retained) + ';'
            else: preferences.remove_option('Removed Associations', mime)
    stream = StringIO(); preferences.write(stream, space_around_delimiters=False)
    atomic(path, stream.getvalue())

button_data = json.loads(buttons.read_text()) if buttons.exists() else {}
for name in selected_names:
    button_data.setdefault('apps', {}).setdefault(name, {}).setdefault('showButtons', False)
for app in apps: button_data['apps'].pop(f'kos-{app}-preview', None)
managed_rules = [{'match': {'class': f'kos-{app}', 'titleRegex': 'Preview$'}, 'showButtons': False} for app in apps]
button_data['rules'] = [rule for rule in button_data.get('rules', []) if rule not in managed_rules]
atomic(buttons, json.dumps(button_data, ensure_ascii=False, indent=4) + '\n')
for path in legacy_files: path.unlink(missing_ok=True)
for path in previews: path.unlink(missing_ok=True)
if preview_dir.exists():
    retired = backup / 'retired-preview'
    shutil.move(str(preview_dir), retired)
    manifest['retiredPreview'] = {'path': str(preview_dir), 'backup': str(retired)}
    (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
if args.with_listenfree:
    atomic(migration_marker, json.dumps({'version': 1}) + '\n')
if not args.no_cache:
    for command in (['update-desktop-database', str(prefix / 'share/applications')], ['kbuildsycoca6', '--noincremental']):
        if shutil.which(command[0]): subprocess.run(command, check=True)
print('Registered:', ', '.join(selected_names))
if args.with_listenfree:
    print('Legacy music installation retired; user data and other player preferences retained.')
print('Registration backup:', backup)
