#!/usr/bin/env python3
"""Manage Firefox's own titlebar-button CSS; never launch or automate the browser."""
import argparse
import configparser
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[2]
OWNER = 'nextkde-firefox-buttons'
BEGIN = '/* NextKde Firefox buttons: begin */'
END = '/* NextKde Firefox buttons: end */'
PREF = 'toolkit.legacyUserProfileCustomizations.stylesheets'
PREF_RE = re.compile(r'^\s*user_pref\("' + re.escape(PREF) + r'",\s*(true|false)\);\s*$', re.M)


def read(path):
    return path.read_text() if path.exists() else ''


def write(path, text):
    if path.is_symlink():
        raise ValueError(f'Refusing managed symlink: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream: stream.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def strip(text):
    if text.count(BEGIN) != text.count(END) or text.count(BEGIN) > 1 or (BEGIN in text and text.index(BEGIN) > text.index(END)):
        raise ValueError('Malformed NextKde Firefox block; original file left untouched')
    return re.sub(re.escape(BEGIN) + r'.*?' + re.escape(END) + r'\n?', '', text, flags=re.S)


def append(text, body):
    clean = strip(text)
    return clean + ('\n' if clean and not clean.endswith('\n') else '') + BEGIN + '\n' + body + '\n' + END + '\n'


def css(mode):
    # The same colors, X/bar proportions and triangular maximize semantics as KWin.
    shapes = {
        'CLOSE': '<path d="M3.92 3.92L10.08 10.08M10.08 3.92L3.92 10.08" stroke="black" stroke-opacity=".627" stroke-width="2.24" stroke-linecap="round"/>',
        'MINIMIZE': '<path d="M3.92 7H10.08" stroke="black" stroke-opacity=".627" stroke-width="2.24" stroke-linecap="round"/>',
        'MAXIMIZE': '<path d="M3.22 3.22H8.66L3.22 8.66ZM10.78 10.78H5.34L10.78 5.34Z" fill="black" fill-opacity=".753"/>',
        'RESTORE': '<path d="M6.77 6.77H1.33L6.77 1.33ZM7.23 7.23H12.67L7.23 12.67Z" fill="black" fill-opacity=".753"/>'}
    text = (ROOT/'shared/firefox/window-buttons.css').read_text()
    for key, shape in shapes.items():
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">' + shape + '</svg>'
        text = text.replace('@'+key+'@', 'url("data:image/svg+xml,' + quote(svg, safe='') + '")')
    hover = ('.titlebar-buttonbox { --kos-visible-glyph: none; }\n'
             '.titlebar-buttonbox:hover, .titlebar-buttonbox:focus-within { --kos-visible-glyph: var(--kos-button-glyph); }') if mode == 'hover' else ''
    return text.replace('@HOVER@', hover)


def discover(home, config):
    found = set()
    for base in (home/'.mozilla/firefox', config/'mozilla/firefox'):
        ini = base/'profiles.ini'
        if not ini.exists(): continue
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(ini)
        for section in parser.sections():
            if not section.startswith('Profile') or not parser.has_option(section, 'Path'): continue
            path = Path(parser[section]['Path'])
            if parser[section].get('IsRelative', '1') == '1': path = base/path
            if path.is_dir(): found.add(path.absolute())
    return sorted(found)


def state_path(config): return config/'kos/firefox-buttons-state.json'


def load(config):
    path = state_path(config)
    return json.loads(read(path)) if path.exists() else {'profiles': {}}


def save(config, state): write(state_path(config), json.dumps(state, indent=2, ensure_ascii=False)+'\n')


def qualify(config, remove=False):
    path = config/'kos/window-buttons.json'
    data = json.loads(read(path)) if path.exists() else {}
    if not isinstance(data, dict) or not isinstance(data.get('rules', []), list): raise ValueError('Invalid window-button rules')
    entries = [r for r in data.get('rules', []) if not (isinstance(r, dict) and r.get('owner') == OWNER)]
    if not remove:
        # Do not suppress server-side decoration or unrelated GTK dialogs.
        entries.append({'owner': OWNER, 'match': {'class': 'firefox', 'type': 'normal'}, 'nativeGtkControls': True})
    data['rules'] = entries
    write(path, json.dumps(data, indent=2)+'\n')


def external_pref(profile):
    path = profile/'user.js'
    if not path.is_symlink(): return False
    if (PREF_RE.findall(read(path)) or [None])[-1] != 'true':
        raise ValueError(f'Theme-managed user.js must already enable {PREF}: {path}')
    return True


def install(config, profiles):
    if not profiles: raise ValueError('No native Firefox profiles found; supply --profile PATH')
    state = load(config)
    rules_path = config/'kos/window-buttons.json'
    rules = json.loads(read(rules_path)) if rules_path.exists() else {}
    if not isinstance(rules, dict) or not isinstance(rules.get('rules', []), list):
        raise ValueError('Invalid window-button rules; profiles left untouched')
    # Preflight every file before changing any profile.
    for profile in profiles:
        if not profile.is_dir(): raise ValueError(f'Profile does not exist: {profile}')
        managed = ['chrome/userChrome.css'] if external_pref(profile) else ['user.js', 'chrome/userChrome.css']
        for path in (profile/relative for relative in managed):
            if path.is_symlink() or path.parent.is_symlink(): raise ValueError(f'Refusing managed symlink: {path}')
            strip(read(path))
    for profile in profiles:
        key = str(profile.absolute())
        if key not in state['profiles']:
            state['profiles'][key] = {'files': {}, 'pref': (PREF_RE.findall(read(profile/'prefs.js')) or ['false'])[-1]}
        entry = state['profiles'][key]
        entry['managePref'] = not external_pref(profile)
        for relative in (['user.js'] if entry['managePref'] else []) + ['chrome/userChrome.css']:
            path = profile/relative
            entry['files'].setdefault(relative, {'original': read(path), 'existed': path.exists()})
    save(config, state)
    appearance = config/'kos/window-appearance.json'
    enabled = json.loads(read(appearance)).get('enabled', True) if appearance.exists() else True
    buttons = config/'kos/window-buttons.json'
    mode = json.loads(read(buttons)).get('default', {}).get('glyphMode', 'always') if buttons.exists() else 'always'
    sync(config, enabled, mode)
    qualify(config)


def sync(config, enabled, mode):
    state = load(config)
    if not state['profiles']: return
    updates = []
    for name, entry in state['profiles'].items():
        profile = Path(name)
        if not profile.is_dir(): continue  # Never recreate deleted profiles.
        for relative, body in [('user.js', f'user_pref("{PREF}", true);'), ('chrome/userChrome.css', css(mode))]:
            if relative == 'user.js' and not entry.get('managePref', True):
                external_pref(profile)
                continue
            path = profile/relative
            if path.is_symlink() or path.parent.is_symlink(): raise ValueError(f'Refusing managed symlink: {path}')
            current = read(path)
            # Keep the loader opt-in during switch-off; only remove our CSS.
            updated = append(current, body) if enabled or relative == 'user.js' else strip(current)
            entry['files'][relative]['installed'] = updated
            updates.append((path, updated))
    save(config, state)  # Recovery information precedes writes.
    for path, updated in updates: write(path, updated)


def uninstall(config):
    state = load(config)
    for name, entry in state['profiles'].items():
        profile = Path(name)
        for relative, record in entry['files'].items():
            path = profile/relative
            if not path.exists(): continue
            current = read(path)
            if current == record.get('installed'):
                if record['existed']: write(path, record['original'])
                else: path.unlink()
            else: write(path, strip(current))
        # Quit Firefox before uninstall: it owns prefs.js while running.
        prefs = profile/'prefs.js'
        current = read(prefs)
        if entry.get('managePref', True) and (PREF_RE.findall(current) or [None])[-1] == 'true':
            write(prefs, PREF_RE.sub(f'user_pref("{PREF}", {entry["pref"]});', current))
    qualify(config, remove=True)
    state_path(config).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'uninstall'])
    parser.add_argument('--profile', action='append', type=Path)
    args = parser.parse_args()
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config')).absolute()
    try:
        if args.action == 'install': install(config, args.profile or discover(Path.home(), config))
        else: uninstall(config)
    except (OSError, ValueError, configparser.Error) as error:
        parser.exit(1, str(error)+'\n')
    print('Firefox profile configuration updated. Restart Firefox; reload KWin configuration or log in again to apply the overlay rule.')


if __name__ == '__main__': main()
