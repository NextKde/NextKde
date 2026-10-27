"""Observe only Notify calls; emit transient sender metadata to the daemon."""
import json
import os
import ctypes
import signal

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

# A shell/daemon restart must not leave an observer attached to the bus.
parent = os.getppid()
ctypes.CDLL(None).prctl(1, signal.SIGTERM)
if os.getppid() != parent:
    os._exit(0)

DBusGMainLoop(set_as_default=True)
control = dbus.SessionBus(private=True)
monitor = dbus.SessionBus(private=True)


def observe(_connection, message):
    if (message.get_type() != dbus.lowlevel.MESSAGE_TYPE_METHOD_CALL
            or message.get_interface() != "org.freedesktop.Notifications"
            or message.get_member() != "Notify"
            or message.get_path() != "/org/freedesktop/Notifications"):
        return dbus.lowlevel.HANDLER_RESULT_NOT_YET_HANDLED
    try:
        emit_origin(message)
    except (dbus.DBusException, ValueError, TypeError):
        pass
    # Suppress libdbus's default UnknownMethod reply on this monitor-only
    # connection. The real notification server remains the sole responder.
    return dbus.lowlevel.HANDLER_RESULT_HANDLED


def emit_origin(message):
    args = message.get_args_list()
    if len(args) != 8:
        return
    values = [str(args[index]) for index in (0, 3, 4)]
    if any(len(value.encode("utf-8")) > 16384 for value in values):
        return
    try:
        pid = int(control.call_blocking("org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", (message.get_sender(),)))
    except dbus.DBusException:
        return
    print(json.dumps(dict(appName=values[0], summary=values[1], body=values[2],
                          pid=pid), ensure_ascii=True), flush=True)


monitor.add_message_filter(observe)
monitor.call_blocking("org.freedesktop.DBus", "/org/freedesktop/DBus",
                      "org.freedesktop.DBus.Monitoring", "BecomeMonitor", "asu",
                      (["type='method_call',path='/org/freedesktop/Notifications',"
                        "interface='org.freedesktop.Notifications',member='Notify'"], 0))
# Do not print notification content to logs. stdout is a private JSONL pipe.
print('{"ready":true}', flush=True)
try:
    GLib.MainLoop().run()
except BrokenPipeError:
    os._exit(0)
