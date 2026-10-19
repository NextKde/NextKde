"""Verify the app-shipped, reviewed theme bundle before loading any QML."""
import hashlib
import json
from pathlib import Path
import sys

THEMES = ('starfield', 'blackhole', 'weather', 'forest', 'underwater')

def ready(root, theme):
    if theme not in THEMES:
        return False
    try:
        expected = json.loads(Path(__file__).with_name('theme-files.json').read_text())[theme]
        base = Path(root) / 'themes' / theme
        return all(hashlib.sha256((base / name).read_bytes()).hexdigest() == digest for name, digest in expected.items())
    except (OSError, ValueError, KeyError):
        return False

if __name__ == '__main__':
    theme = sys.argv[1] if len(sys.argv) == 2 else ''
    print(json.dumps(dict(theme=theme, ready=ready(Path(__file__).resolve().parents[1] / 'wallpapers', theme))))
