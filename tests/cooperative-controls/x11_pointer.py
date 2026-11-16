"""Send real pointer events only to the test's nested KWin X11 output (VM only)."""
import ctypes as C
import subprocess
import time


def click(output_display, point=None, *, move_only=False, capture_path=None, button=1):
    x11 = C.CDLL('libX11.so.6')
    ptr, ulong, integer = C.c_void_p, C.c_ulong, C.c_int
    x11.XOpenDisplay.argtypes = [C.c_char_p]; x11.XOpenDisplay.restype = ptr
    x11.XDefaultRootWindow.argtypes = [ptr]; x11.XDefaultRootWindow.restype = ulong
    x11.XInternAtom.argtypes = [ptr, C.c_char_p, integer]; x11.XInternAtom.restype = ulong
    x11.XQueryTree.argtypes = [ptr, ulong, C.POINTER(ulong), C.POINTER(ulong), C.POINTER(C.POINTER(ulong)), C.POINTER(C.c_uint)]
    x11.XGetWindowProperty.argtypes = [ptr, ulong, ulong, C.c_long, C.c_long, integer, ulong,
        C.POINTER(ulong), C.POINTER(integer), C.POINTER(ulong), C.POINTER(ulong), C.POINTER(ptr)]
    x11.XGetGeometry.argtypes = [ptr, ulong, C.POINTER(ulong), C.POINTER(integer), C.POINTER(integer),
        C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
    x11.XTranslateCoordinates.argtypes = [ptr, ulong, ulong, integer, integer, C.POINTER(integer), C.POINTER(integer), C.POINTER(ulong)]
    x11.XFlush.argtypes = [ptr]; x11.XCloseDisplay.argtypes = [ptr]; x11.XFree.argtypes = [ptr]
    display = x11.XOpenDisplay(output_display.encode())
    assert display, 'Cannot open outer X11 display for nested-output input'
    try:
        pid = int(subprocess.check_output(['qdbus6', 'org.freedesktop.DBus', '/',
                  'org.freedesktop.DBus.GetConnectionUnixProcessID', 'org.kde.KWin'], text=True))
        root = x11.XDefaultRootWindow(display)
        atom = x11.XInternAtom(display, b'_NET_WM_PID', False)
        def find(window, depth=0):
            if depth > 5: return None
            actual, n, after, fmt, data = ulong(), ulong(), ulong(), integer(), ptr()
            x11.XGetWindowProperty(display, window, atom, 0, 1, False, 6,
                                  C.byref(actual), C.byref(fmt), C.byref(n), C.byref(after), C.byref(data))
            own = bool(data and n.value and C.cast(data, C.POINTER(ulong))[0] == pid)
            if data: x11.XFree(data)
            if own:
                r, x, y, w, h, border, bits = ulong(), integer(), integer(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
                x11.XGetGeometry(display, window, C.byref(r), C.byref(x), C.byref(y), C.byref(w), C.byref(h), C.byref(border), C.byref(bits))
                if w.value >= 1000 and h.value >= 700: return window
            r, parent, children, count = ulong(), ulong(), C.POINTER(ulong)(), C.c_uint()
            x11.XQueryTree(display, window, C.byref(r), C.byref(parent), C.byref(children), C.byref(count))
            ids = [children[i] for i in range(count.value)]
            if children: x11.XFree(children)
            for child in ids:
                found = find(child, depth+1)
                if found: return found
            return None
        window = find(root)
        assert window, 'Test compositor output window not found; no pointer events sent'
        x, y, child = integer(), integer(), ulong()
        x11.XTranslateCoordinates(display, window, root, 0, 0, C.byref(x), C.byref(y), C.byref(child))
        if capture_path:
            from PIL import Image
            class XImage(C.Structure):
                _fields_ = [('width', integer), ('height', integer), ('xoffset', integer), ('format', integer),
                    ('data', ptr), ('byte_order', integer), ('bitmap_unit', integer), ('bitmap_bit_order', integer),
                    ('bitmap_pad', integer), ('depth', integer), ('bytes_per_line', integer), ('bits_per_pixel', integer)]
            r, gx, gy, width, height, border, depth = ulong(), integer(), integer(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
            x11.XGetGeometry(display,window,C.byref(r),C.byref(gx),C.byref(gy),C.byref(width),C.byref(height),C.byref(border),C.byref(depth))
            x11.XGetImage.argtypes=[ptr,ulong,integer,integer,C.c_uint,C.c_uint,ulong,integer]
            x11.XGetImage.restype=C.POINTER(XImage)
            x11.XDestroyImage.argtypes=[C.POINTER(XImage)]
            raw=x11.XGetImage(display,window,0,0,width.value,height.value,ulong(-1),2)
            assert raw
            try:
                info=raw.contents
                assert info.bits_per_pixel==32 and info.byte_order==0
                data=C.string_at(info.data,info.bytes_per_line*info.height)
                Image.frombytes('RGB',(info.width,info.height),data,'raw','BGRX',info.bytes_per_line).save(capture_path)
            finally: x11.XDestroyImage(raw)
            return
        assert 0 <= point[0] < 1100 and 0 <= point[1] < 760
        # XWayland may not route XTest's global cursor into the nested output.
        # Send native X11 input events directly to that output, never another app.
        class ButtonEvent(C.Structure):
            _fields_ = [('type', integer), ('serial', ulong), ('send_event', integer),
                ('display', ptr), ('window', ulong), ('root', ulong), ('subwindow', ulong),
                ('time', ulong), ('x', integer), ('y', integer), ('x_root', integer),
                ('y_root', integer), ('state', C.c_uint), ('button', C.c_uint), ('same_screen', integer)]
        class Event(C.Union):
            _fields_ = [('button', ButtonEvent), ('pad', C.c_long * 24)]
        x11.XSendEvent.argtypes = [ptr, ulong, integer, C.c_long, C.POINTER(Event)]
        def send(kind, mask, detail):
            event = Event()
            event.button = ButtonEvent(kind, 0, True, display, window, root, 0, 0,
                round(point[0]), round(point[1]), round(x.value+point[0]), round(y.value+point[1]), 0, detail, True)
            x11.XSendEvent(display, window, False, mask, C.byref(event))
        send(6, 1 << 6, 0)
        x11.XFlush(display)
        time.sleep(.15)
        if not move_only:
            send(4, 1 << 2, button)
            send(5, 1 << 3, button)
        x11.XFlush(display)
    finally:
        x11.XCloseDisplay(display)
