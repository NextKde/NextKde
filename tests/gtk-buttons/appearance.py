#!/usr/bin/env python3
"""VM-only regression: render real GTK controls and exercise their native actions."""
import argparse
import io
from pathlib import Path
import sys
import cairo
import gi
from PIL import Image

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
window = Gtk.Window(title='GTK native appearance regression')
window.set_default_size(500, 240)
bar = Gtk.HeaderBar(show_close_button=True)
bar.set_decoration_layout(':maximize,minimize,close')
window.set_titlebar(bar)
window.add(Gtk.Label(label='Native GTK input, KOS button appearance'))
window.show_all()
window.present()
buttons = {}
failed = False
step = 0
images = {}
provider = Gtk.CssProvider()
Gtk.StyleContext.add_provider_for_screen(window.get_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER+1)


def collect(widget):
    if isinstance(widget, Gtk.Button):
        style = widget.get_style_context()
        for name in ('close', 'minimize', 'maximize'):
            if style.has_class('titlebutton') and style.has_class(name):
                buttons[name] = widget
    if isinstance(widget, Gtk.Container):
        widget.forall(collect)


def render(name, label, scale=1):
    button = buttons[name]
    window.check_resize()
    width, height = button.get_allocated_width(), button.get_allocated_height()
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width*scale, height*scale)
    context = cairo.Context(surface)
    context.scale(scale, scale)
    button.draw(context)
    data = io.BytesIO()
    surface.write_to_png(data)
    image = Image.open(io.BytesIO(data.getvalue())).convert('RGBA')
    assert image.getchannel('A').getbbox(), (label, name, 'empty rendering')
    image.save(args.output/f'{label}-{name}-{scale}x.png')
    return image


def tick():
    global step, failed
    try:
        collect(bar)
        assert len(buttons) == 3, buttons
        if step == 0:
            assert window.is_active(), 'Fixture must be focused for active colors'
            assert buttons['close'].get_parent().get_spacing() == 0
            for name, color in [('close',(255,95,87)),('minimize',(254,188,46)),('maximize',(40,200,64))]:
                for scale in (1,2):
                    image = render(name,'normal',scale)
                    # Circle diameter must stay square and 14 px at both scales.
                    alpha = image.getchannel('A')
                    bbox = alpha.point(lambda a:255 if a > 127 else 0).getbbox()
                    assert bbox and bbox[2]-bbox[0] == bbox[3]-bbox[1], bbox
                    assert abs((bbox[2]-bbox[0])/scale-14) <= 1, bbox
                    assert sum(1 for p in image.getdata() if p[:3] == color) > 10*scale*scale
                images[name] = render(name,'always')
            buttons['maximize'].clicked()
        elif step == 1:
            assert window.is_maximized(), 'Native green button must maximize'
            restored = render('maximize','restore')
            assert restored.tobytes() != images['maximize'].tobytes(), 'Restore glyph did not change'
            buttons['maximize'].clicked()
        elif step == 2:
            assert not window.is_maximized(), 'Native green button must restore'
            provider.load_from_data(b'@define-color kos_native_glyph transparent;')
        elif step == 3:
            for name in buttons:
                image = render(name,'hover-hidden')
                center = image.getpixel((image.width//2,image.height//2))
                assert min(center[:3]) > 0, (name,center)
                assert image.tobytes() != images[name].tobytes(), name
                images['hidden-'+name] = image
                buttons[name].set_state_flags(Gtk.StateFlags.PRELIGHT, False)
        elif step == 4:
            for name in buttons:
                image = render(name,'hover-visible')
                box = (image.width//2-6,image.height//2-6,image.width//2+6,image.height//2+6)
                assert image.crop(box).tobytes() != images['hidden-'+name].crop(box).tobytes(), name
                buttons[name].unset_state_flags(Gtk.StateFlags.PRELIGHT)
            provider.load_from_data(b'@define-color kos_native_glyph #ffffff;')
        else:
            closed = []
            window.connect('delete-event', lambda *unused: closed.append(True) or True)
            buttons['close'].clicked()
            # GTK dispatches the close request through its event queue.
            GLib.timeout_add(200, finish, closed)
            return False
        step += 1
    except Exception as error:
        print(repr(error), file=sys.stderr, flush=True)
        failed = True
        window.destroy()
        Gtk.main_quit()
        return False
    return True


def finish(closed):
    global failed
    failed = not closed
    print('Native close action:', bool(closed), flush=True)
    window.destroy()
    Gtk.main_quit()
    return False


GLib.timeout_add(500, tick)
Gtk.main()
if failed:
    sys.exit(1)
print('GTK native sizes, colors, maximize/restore, glyph modes and close passed.', flush=True)
