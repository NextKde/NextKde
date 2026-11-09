#!/usr/bin/env python3
"""Install native GTK traffic lights and qualify individual CSD windows.

Run as the desktop user. No toolkit guessing, process injection or Flatpak overrides.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import firefox_buttons

ROOT = Path(__file__).resolve().parents[2]
BEGIN = '/* NextKde native GTK buttons: begin */'
END = '/* NextKde native GTK buttons: end */'
ENV_BEGIN = '# NextKde native GTK module: begin'
ENV_END = '# NextKde native GTK module: end'
OWNER = 'nextkde-native-gtk'
# Chromium consumes this GTK setting too. Keep original right-side layouts,
# and use the normal right-side layout when no suitable original exists.
LAYOUT = ':minimize,maximize,close'
LEGACY_LAYOUT = 'close,minimize,maximize:'
SCHEMA = 'org.gnome.desktop.wm.preferences'
KEY = 'button-layout'


def read(path):
    return path.read_text() if path.exists() else ''


def atomic_write(path, text):
    if path.is_symlink():
        raise ValueError(f'{path} is a symlink; configure this integration through its owner')
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def json_read(path, default):
    return json.loads(read(path)) if path.exists() else default


def json_write(path, value):
    atomic_write(path, json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def strip_css(text):
    if (text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1
            or (BEGIN in text and text.index(BEGIN) > text.index(END))):
        raise ValueError('Malformed NextKde CSS block; refusing to replace user CSS')
    return re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', text, flags=re.S)


def strip_env(text):
    if text.count(ENV_BEGIN) != text.count(ENV_END) or text.count(ENV_BEGIN) > 1:
        raise ValueError('Malformed NextKde GTK startup block')
    return re.sub(re.escape(ENV_BEGIN) + r'.*?' + re.escape(ENV_END) + r'\n?', '', text, flags=re.S)


def layout_setting(text, replacement=None, *, write=False, key="gtk-decoration-layout"):
    """Edit just this key in [Settings], preserving unrelated text and comments."""
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.strip() == '[Settings]'), None)
    if start is None:
        if not write or replacement is None:
            return None if not write else text
        return text + ('\n' if text and not text.endswith('\n') else '') + '[Settings]\n' + replacement
    end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
    found = [i for i in range(start + 1, end) if re.match(r'\s*' + re.escape(key) + r'\s*=', lines[i])]
    if len(found) > 1:
        raise ValueError('Duplicate gtk-decoration-layout keys')
    if not write:
        return lines[found[0]] if found else None
    if found:
        lines[found[0]] = replacement or ''
    elif replacement is not None:
        lines.insert(start + 1, replacement)
    return ''.join(lines)


def gsettings(*args):
    return subprocess.check_output(['gsettings', *args], text=True, stderr=subprocess.PIPE).strip()


def glyph_css(version, mode):
    if mode != 'hover':
        return ''
    if version == '3.0':
        selectors = [f'headerbar button.titlebutton.{kind}' for kind in ('close', 'minimize', 'maximize')]
        return ('\n@define-color kos_native_glyph transparent;\n' + ',\n'.join(s + ' image' for s in selectors) + ' { opacity: 0; }\n'
                + ',\n'.join(s + ':hover image' for s in selectors) + ' { opacity: 1; }\n')
    selectors = [f'windowcontrols button.{kind}' for kind in ('close', 'minimize', 'maximize')]
    # Filter only the icon, not the image node's circular background.
    return ('\n' + ',\n'.join(s + ' > image' for s in selectors) + ' { -gtk-icon-filter: opacity(0); }\n'
            + ',\n'.join(s + ':hover > image' for s in selectors) + ' { -gtk-icon-filter: none; }\n')


def layout_for_install(config, state):
    # Earlier versions forcibly installed a left layout. Recover the original
    # right layout from their backup without replacing that recovery record.
    candidates = [state.get('gsettings')]
    for version in ('3.0', '4.0'):
        path = config / f'gtk-{version}/settings.ini'
        entry = state.get('files', {}).get(str(path))
        line = entry.get('layout') if entry else layout_setting(read(path))
        if line:
            candidates.append(line.split('=', 1)[1].strip())
    controls = {'close', 'minimize', 'maximize'}
    for candidate in candidates:
        if not isinstance(candidate, str):
            continue
        candidate = candidate.strip("'")
        if candidate.count(':') != 1:
            continue
        leading, trailing = candidate.split(':')
        if not controls.intersection(leading.split(',')) and controls.issubset(trailing.split(',')):
            return candidate
    return LAYOUT


def install(config, glyph_mode='always', gtk3_module=None):
    if gtk3_module and not Path(gtk3_module).is_file():
        raise ValueError(f'GTK detection module is missing: {gtk3_module}')
    state_path = config / 'kos/gtk-buttons-state.json'
    state = json_read(state_path, {'files': {}, 'gsettings': None})
    if shutil.which('gsettings') and state['gsettings'] is None:
        try:
            state['gsettings'] = gsettings('get', SCHEMA, KEY)
        except subprocess.CalledProcessError:
            pass  # settings.ini remains the fallback without this schema.
    installed_layout = layout_for_install(config, state)
    updates = []
    for version in ('3.0', '4.0'):
        css_path = config / f'gtk-{version}/gtk.css'
        ini_path = config / f'gtk-{version}/settings.ini'
        for path in (css_path, ini_path):
            if path.is_symlink():
                raise ValueError(f'{path} is a symlink; configure this integration through its owner')
        css, ini = read(css_path), read(ini_path)
        # Keep the original bytes for exact restoration when nobody edited them.
        for path, original in ((css_path, css), (ini_path, ini)):
            state['files'].setdefault(str(path), {'original': original, 'existed': path.exists()})
        clean = strip_css(css)
        asset = (ROOT / f'shared/gtk/gtk-{version}.css').read_text() + glyph_css(version, glyph_mode)
        updated = clean + ('\n' if clean and not clean.endswith('\n') else '') + BEGIN + '\n' + asset + END + '\n'
        state['files'][str(ini_path)].setdefault('layout', layout_setting(ini))
        updated_ini = layout_setting(ini, f'gtk-decoration-layout={installed_layout}\n', write=True)
        entry = state['files'][str(ini_path)]
        if version == '3.0' and gtk3_module:
            line = layout_setting(ini, key='gtk-modules')
            modules = line.split('=', 1)[1].strip().split(':') if line else []
            previous = entry.get('module')
            modules = [m for m in modules if m and m != previous and m != str(gtk3_module)]
            modules.append(str(gtk3_module))
            updated_ini = layout_setting(updated_ini, 'gtk-modules=' + ':'.join(modules) + '\n', write=True, key='gtk-modules')
            entry['module'] = str(gtk3_module)
        updates.extend(((css_path, updated), (ini_path, updated_ini)))
    if gtk3_module:
        # Plasma sources these before launching applications. GtkSettings' module
        # property alone is not a reliable startup loader on Wayland.
        env_path = config / 'plasma-workspace/env/kos-gtk-window-controls.sh'
        if env_path.is_symlink():
            raise ValueError(f'{env_path} is managed by another configuration owner')
        original = read(env_path)
        state['files'].setdefault(str(env_path), {'original': original, 'existed': env_path.exists()})
        quoted = shlex.quote(str(gtk3_module))
        script = (ENV_BEGIN + '\n'
                  'case ":${GTK_MODULES:-}:" in\n'
                  '  *:' + quoted + ':*) ;;\n'
                  '  *) export GTK_MODULES="${GTK_MODULES:+${GTK_MODULES}:}"' + quoted + ' ;;\n'
                  'esac\n' + ENV_END + '\n')
        clean = strip_env(original)
        updates.append((env_path, clean + ('\n' if clean and not clean.endswith('\n') else '') + script))
    # Save recovery information before changing user settings.
    for path, updated in updates:
        state['files'][str(path)]['installed'] = updated
    if shutil.which('gsettings') and state['gsettings'] is None:
        try:
            state['gsettings'] = gsettings('get', SCHEMA, KEY)
        except subprocess.CalledProcessError:
            pass  # settings.ini remains the fallback on desktops without this schema.
    state['installedLayout'] = installed_layout
    state['gsettings_installed'] = repr(installed_layout)
    json_write(state_path, state)
    for path, updated in updates:
        atomic_write(path, updated)
    if state['gsettings'] is not None:
        gsettings('set', SCHEMA, KEY, installed_layout)


def rules(config, app=None, title=None, remove=False):
    path = config / 'kos/window-buttons.json'
    data = json_read(path, {})
    if not isinstance(data, dict) or not isinstance(data.get('rules', []), list):
        raise ValueError('Invalid window-buttons.json; refusing to overwrite it')
    match = {'class': app, 'type': 'normal'}
    if title:
        match['title'] = title
    entries = data.get('rules', [])
    entries = [r for r in entries if not (isinstance(r, dict) and r.get('owner') == OWNER
               and (app is None or r.get('match') == match))]
    if not remove:
        if not app or any(c.isspace() for c in app):
            raise ValueError('Use one exact app ID / WM_CLASS token')
        for version in ('3.0', '4.0'):
            if BEGIN not in read(config / f'gtk-{version}/gtk.css'):
                raise ValueError('Install GTK styles before adapting an application')
        # Existing user rules win ties; more specific rules still win in the plugin.
        entries.append({'owner': OWNER, 'match': match, 'nativeGtkControls': True})
    data['rules'] = entries
    if path.exists() or entries:
        json_write(path, data)


def restore_styles(config):
    state_path = config / 'kos/gtk-buttons-state.json'
    state = json_read(state_path, None)
    if state is None:
        return
    for name, entry in state['files'].items():
        path = Path(name)
        if not path.exists():
            continue  # Preserve a user's subsequent deletion.
        current = read(path)
        if current == entry['installed']:
            if entry['existed']:
                atomic_write(path, entry['original'])
            else:
                path.unlink(missing_ok=True)
        elif path.name == 'gtk.css':
            atomic_write(path, strip_css(current))
        elif path.name == 'kos-gtk-window-controls.sh':
            atomic_write(path, strip_env(current))
        elif path.name == 'settings.ini':
            installed_layout = layout_setting(entry['installed'])
            if layout_setting(current) == installed_layout:
                current = layout_setting(current, entry['layout'], write=True)
            if entry.get('module'):
                line = layout_setting(current, key='gtk-modules')
                if line:
                    modules = [m for m in line.split('=', 1)[1].strip().split(':') if m != entry['module']]
                    current = layout_setting(current, 'gtk-modules=' + ':'.join(modules) + '\n' if any(modules) else None, write=True, key='gtk-modules')
            atomic_write(path, current)
    if state['gsettings'] is not None and shutil.which('gsettings'):
        if gsettings('get', SCHEMA, KEY) == state.get('gsettings_installed', repr(state.get('installedLayout', LEGACY_LAYOUT))):
            gsettings('set', SCHEMA, KEY, state['gsettings'])
    state_path.unlink()


def uninstall(config):
    rules(config, remove=True)
    reload_bridge()
    restore_styles(config)


def reload_bridge():
    command = shutil.which('qdbus6') or shutil.which('qdbus')
    if command:
        result = subprocess.run([command, 'org.kde.KWin', '/Effects',
                                 'org.kde.kwin.Effects.reconfigureEffect', 'kos_bridge'],
                                capture_output=True, text=True)
        if result.returncode == 0:
            return
    print('KWin reload unavailable; reload kos_bridge or log out and back in.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('install', help='Install styles and right-side window-button layout')
    sub.add_parser('uninstall', help='Restore settings and remove managed adaptation rules')
    sync = sub.add_parser('sync', help='Internal: apply the shared WindowSettings switch and icon mode')
    sync.add_argument('--enabled', choices=['true', 'false'], required=True)
    sync.add_argument('--gtk3-module')
    sync.add_argument('--glyph-mode', choices=['always', 'hover'], required=True)
    for name in ('adapt', 'fallback'):
        command = sub.add_parser(name)
        command.add_argument('app', help='Exact app ID / WM_CLASS token qualified in the VM')
        command.add_argument('--title', help='Limit to an exact window title for mixed/custom applications')
    args = parser.parse_args()
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')).absolute()
    try:
        if args.action == 'sync':
            if args.enabled == 'true':
                install(config, args.glyph_mode, args.gtk3_module)
            else:
                restore_styles(config)
            firefox_buttons.sync(config, args.enabled == 'true', args.glyph_mode)
            # Settings owns reconfiguration. In particular, installation must
            # never ask a running compositor to reload freshly replaced plugins.
            return
        elif args.action == 'install':
            install(config)
        elif args.action == 'uninstall':
            uninstall(config)
        else:
            rules(config, args.app, args.title, remove=args.action == 'fallback')
        reload_bridge()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')
    print('Restart affected GTK applications. Unqualified applications retain their overlay.')


if __name__ == '__main__':
    main()
