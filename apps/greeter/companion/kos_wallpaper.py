"""Read current KOS image settings and bytes under the account's credentials."""
import base64
import configparser
import io
import json
import os
from pathlib import Path
import stat
import sys
from urllib.parse import unquote, urlsplit
from resources import MAX_BYTES, image_copy


def read_file(path, limit, owner=None):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if owner is not None and (info.st_uid != owner or info.st_mode & 0o077 or info.st_nlink != 1):
            raise ValueError('untrusted account display consent')
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= limit:
            raise ValueError('file type/size')
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError('file byte budget')
        return data


NOTICE = '所选壁纸将在认证前向这台机器的其他使用者展示。'

def current(state_home, require_consent=False):
    if require_consent:
        consent_file = Path(state_home) / 'quickshell/kos/greeter-display.json'
        if not consent_file.exists():
            return dict(schemaVersion=1, enabled=False)
        consent = json.loads(read_file(consent_file, 1024, owner=os.getuid()))
        if set(consent) != {'schemaVersion', 'uid', 'enabled', 'notice'} or type(consent['schemaVersion']) is not int or consent['schemaVersion'] != 1 or type(consent['uid']) is not int or consent['uid'] != os.getuid() or consent['notice'] != NOTICE or type(consent['enabled']) is not bool:
            raise ValueError('invalid account display consent')
        if not consent['enabled']:
            return dict(schemaVersion=1, enabled=False)
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    parser.optionxform = str
    parser.read_string(read_file(Path(state_home) / 'quickshell/kos/wallpaper.ini', 65536).decode('utf-8'))
    config = parser['Wallpaper']
    if config.get('takeoverEnabled', 'false').lower() != 'true':
        raise ValueError('KOS wallpaper takeover is disabled')
    fit = config.get('fitMode', 'crop')
    if fit not in ('crop', 'fit', 'stretch', 'center'):
        raise ValueError('unknown KOS fitMode')
    if config.get('mode', 'image') == 'theme':
        # Pre-generated app assets only. No scene loading, window capture, or AI.
        import hashlib
        theme = config.get('themeId', '')
        if theme in ('starfield', 'blackhole', 'weather', 'forest', 'underwater'):
            app = Path(__file__).resolve().parents[1]
            expected = json.loads((app / 'companion/theme-files.json').read_text())[theme]['assets/preview.png']
            raw = read_file(app / 'wallpapers/themes' / theme / 'assets/preview.png', MAX_BYTES)
            if hashlib.sha256(raw).hexdigest() != expected:
                raise ValueError('changed built-in static fallback')
        else:
            out = io.BytesIO()
            from PIL import Image
            Image.new('RGB', (1, 1), '#16283b').save(out, format='PNG')
            raw = out.getvalue()
            fit = 'stretch'
        clean, size = image_copy(raw)
        return dict(schemaVersion=1, fit=fit, image=base64.b64encode(clean).decode(), size=size)
    if config.get('mode', 'image') != 'image':
        raise ValueError('unknown wallpaper mode')
    source = config.get('image', '')
    # QSettings quotes/escapes strings; current KOS chooses plain local paths.
    if source.startswith('"') and source.endswith('"'):
        source = source[1:-1].replace('\\"', '"').replace('\\\\', '\\')
    if source.startswith('file:'):
        url = urlsplit(source)
        if url.scheme != 'file' or url.netloc not in ('', 'localhost') or url.query or url.fragment:
            raise ValueError('non-local wallpaper')
        source = unquote(url.path)
    if not source.startswith('/'):
        raise ValueError('KOS has no explicit local image; cannot infer a Plasma fallback')
    clean, size = image_copy(read_file(source, MAX_BYTES))
    return dict(schemaVersion=1, fit=fit, image=base64.b64encode(clean).decode(), size=size)

def disable(state_home):
    target = Path(state_home) / 'quickshell/kos/greeter-display.json'
    # Revoke only the current process account's choice; no UID argument.
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(dict(schemaVersion=1, uid=os.getuid(), enabled=False, notice=NOTICE), stream)
        stream.flush(); os.fsync(stream.fileno())

if __name__ == '__main__':
    try:
        args = sys.argv[1:]
        revoke = '--disable' in args
        if revoke: args.remove('--disable')
        state_home = args[0] if len(args) == 1 else os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))
        if revoke: disable(state_home)
        else: print(json.dumps(current(state_home, require_consent=True), separators=(',', ':')))
    except (OSError, ValueError, KeyError, configparser.Error) as error:
        print('Cannot resolve current KOS wallpaper: ' + str(error), file=sys.stderr)
        sys.exit(1)
