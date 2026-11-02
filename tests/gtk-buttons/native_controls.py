#!/usr/bin/env python3
"""VM GUI regression: run separately for GTK 3.0 and 4.0 in an isolated desktop."""
import argparse
import json
from pathlib import Path
import sys
import gi

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('version', choices=['3.0', '4.0'])
parser.add_argument('--dark', action='store_true')
parser.add_argument('--glyph-mode', choices=['always', 'hover'], default='always')
parser.add_argument('--hold', action='store_true', help='Keep the window for compositor screenshots')
parser.add_argument('--kwin-log', type=Path, help='Nested KWin log with minimize-probe.js loaded')
args = parser.parse_args()
gi.require_version('Gtk', args.version)
from gi.repository import Gtk, GLib, Gio, Gdk

major = int(args.version[0])
GLib.set_prgname(f'org.nextkde.Gtk{major}Controls')
app = Gtk.Application(application_id=f'org.nextkde.Gtk{major}Controls', flags=Gio.ApplicationFlags.NON_UNIQUE)
errors = []
checks = []
window = None
buttons = {}
minimize_events_before = 0


def minimize_events():
    return args.kwin_log.read_text().count(f'GTK201_MINIMIZED org.nextkde.Gtk{major}Controls')


def descendants(widget):
    yield widget
    if major == 3 and isinstance(widget, Gtk.Container):
        children = []
        widget.forall(lambda child: children.append(child))
    elif major == 4:
        children = []
        child = widget.get_first_child()
        while child:
            children.append(child)
            child = child.get_next_sibling()
    else:
        children = []
    for child in children:
        yield from descendants(child)


def check(value, label):
    checks.append(label)
    if not value:
        errors.append(label)


def maximized():
    return window.is_maximized()


def step(index=0):
    global minimize_events_before
    try:
        # GTK 3 rebuilds title buttons after maximize/restore.
        buttons.clear()
        for widget in descendants(window.get_titlebar()):
            if isinstance(widget, Gtk.Button):
                for kind in ('close', 'minimize', 'maximize'):
                    if widget.get_style_context().has_class(kind):
                        buttons[kind] = widget
        if index == 0:
            check(set(buttons) == {'close', 'minimize', 'maximize'}, 'three native controls')
            leading, trailing = Gtk.Settings.get_default().get_property('gtk-decoration-layout').split(':')
            controls = {'close', 'minimize', 'maximize'}
            check(not controls.intersection(leading.split(','))
                  and controls.issubset(trailing.split(',')), 'native controls remain on the right')
            if len(buttons) != 3:
                raise RuntimeError('Missing native controls')
            print(json.dumps({'button_sizes': {name: [button.get_allocated_width(), button.get_allocated_height()]
                                              for name, button in buttons.items()}}), flush=True)
            if major == 3:
                expected = {'close': (255, 95, 87), 'minimize': (254, 188, 46), 'maximize': (40, 200, 64)}
                for name, button in buttons.items():
                    color = button.get_style_context().get_background_color(Gtk.StateFlags.NORMAL)
                    rgb = tuple(round(component * 255) for component in (color.red, color.green, color.blue))
                    check(rgb == expected[name], f'{name} native color')
                    icon = next(child for child in descendants(button) if isinstance(child, Gtk.Image))
                    # Widget.opacity is an independent API property; CSS opacity
                    # must be read from the image's style context.
                    opacity = icon.get_style_context().get_property('opacity', Gtk.StateFlags.NORMAL)
                    check(opacity == (0 if args.glyph_mode == 'hover' else 1), f'{name} shared glyph mode')
            else:
                # GTK 4 buttons fill the header's height; their centered image
                # paints the circular light while retaining the larger hit area.
                for name, button in buttons.items():
                    light = button.get_child()
                    width, height = light.get_allocated_width(), light.get_allocated_height()
                    check(width == height == 22, f'{name} circular light')
            buttons['maximize'].emit('clicked')
        elif index == 1:
            check(maximized(), 'green maximizes')
            fullscreen = (window.get_window().get_state() & Gdk.WindowState.FULLSCREEN) if major == 3 else window.is_fullscreen()
            check(not fullscreen, 'green does not fullscreen')
            buttons['maximize'].emit('clicked')
        elif index == 2:
            check(not maximized(), 'green restores')
            if args.kwin_log:
                minimize_events_before = minimize_events()
            buttons['minimize'].emit('clicked')
        elif index == 3:
            if args.kwin_log:
                minimized = minimize_events() > minimize_events_before
                check(minimized, 'yellow minimizes (compositor)')
            elif major == 3 and 'X11' in type(window.get_window()).__name__:
                minimized = bool(window.get_window().get_state() & Gdk.WindowState.ICONIFIED)
                check(minimized, 'yellow minimizes')
            else:
                print('SKIP minimize state: Wayland requires --kwin-log and minimize-probe.js', flush=True)
            window.present()
        elif index == 4:
            print(json.dumps({'gtk': args.version, 'checks': checks, 'failures': errors}), flush=True)
            if args.hold:
                return False
            buttons['close'].emit('clicked')
            return False
        GLib.timeout_add(800, step, index + 1)
    except Exception as error:
        errors.append(str(error))
        print(json.dumps({'failures': errors}), flush=True)
        app.quit()
    return False


def activate(application):
    global window
    settings = Gtk.Settings.get_default()
    settings.set_property('gtk-application-prefer-dark-theme', args.dark)
    window = Gtk.ApplicationWindow(application=application, title=f'NextKde GTK {major} native controls')
    window.set_default_size(640, 300)
    header = Gtk.HeaderBar()
    if major == 3:
        header.set_show_close_button(True)
        header.set_title(f'GTK {major} — native traffic lights')
    else:
        header.set_show_title_buttons(True)
    header.pack_end(Gtk.Button(label='Toolbar button'))
    window.set_titlebar(header)
    label = Gtk.Label(label='Red: close    Yellow: minimize    Green: maximize / restore\nToolbar buttons retain their original style.')
    if major == 3:
        window.add(label)
        window.show_all()
    else:
        window.set_child(label)
    window.present()
    GLib.timeout_add(1000, step)


app.connect('activate', activate)
app.run([])
check(not window.get_visible(), 'red closes')
print(json.dumps({'gtk': args.version, 'checks': checks, 'failures': errors}), flush=True)
sys.exit(bool(errors))
