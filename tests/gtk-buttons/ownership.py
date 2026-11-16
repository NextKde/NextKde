#!/usr/bin/env python3
"""VM-only: unregistered GTK windows release/reclaim the legacy overlay."""
import gi
import json
import subprocess
import sys
import time

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

GLib.set_prgname('org.nextkde.UnregisteredGtkOwnership')
window = Gtk.Window(title='GTK automatic ownership fixture')
window.set_default_size(550, 300)
header = Gtk.HeaderBar()
header.set_show_close_button(True)
header.set_title(window.get_title())
window.set_titlebar(header)
window.add(Gtk.Label(label='No per-application adaptation rule'))
window.show_all()
step = 0
started = time.monotonic()
failed = False


def tick():
    global step, started, failed
    try:
        state = json.loads(subprocess.check_output(['qdbus6', 'org.kde.KWin', '/Effects',
            'org.kde.kwin.Effects.debug', 'kos_bridge', 'window-controls'], text=True))
        item = next((w for w in state['windows'] if 'org.nextkde.UnregisteredGtkOwnership' in w['windowClass']), None)
        if not item:
            assert time.monotonic() - started < 8, state
            return True
        owned = item['declared'] or item['nativeControls']
        expected = step != 1
        if owned != expected or (expected and item.get('painted')) or (not expected and not item.get('painted')):
            assert time.monotonic() - started < 8, item
            return True
        if expected:
            assert not item.get('sampling') and not item.get('intercepting'), item
        print(json.dumps({'step': step, 'state': item}), flush=True)
        if step == 0:
            header.set_show_close_button(False)
        elif step == 1:
            header.set_show_close_button(True)
        else:
            window.destroy()
            Gtk.main_quit()
            return False
        step += 1
        started = time.monotonic()
    except Exception as error:
        print(repr(error), file=sys.stderr, flush=True)
        failed = True
        Gtk.main_quit()
        return False
    return True


GLib.timeout_add(150, tick)
Gtk.main()
sys.exit(1 if failed else 0)
