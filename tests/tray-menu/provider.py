#!/usr/bin/env python3
"""Private StatusNotifierItem/DBusMenu peers with deliberately delayed layouts."""
import os
from pathlib import Path
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
EVENTS = Path(os.environ['TRAY_MENU_EVENTS'])

class Menu(dbus.service.Object):
    def __init__(self, bus, name, delay):
        super().__init__(bus, '/Menu')
        self.name, self.delay = name, delay

    @dbus.service.method('com.canonical.dbusmenu', in_signature='iias', out_signature='u(ia{sv}av)', async_callbacks=('reply', 'error'))
    def GetLayout(self, parent, depth, properties, reply, error):
        def finish():
            props = dbus.Dictionary({'label': self.name, 'enabled': True, 'visible': True}, signature='sv')
            child = dbus.Struct((1, props, dbus.Array([], signature='v')), signature='ia{sv}av')
            children = [] if self.name == 'empty' else [child]
            tree = dbus.Struct((0, dbus.Dictionary({}, signature='sv'), dbus.Array(children, signature='v')), signature='ia{sv}av')
            reply(dbus.UInt32(1), tree)
            return False
        GLib.timeout_add(self.delay, finish)

    @dbus.service.method('com.canonical.dbusmenu', in_signature='aias', out_signature='a(ia{sv})')
    def GetGroupProperties(self, ids, properties):
        return [(i, {'label': self.name, 'enabled': True, 'visible': True}) for i in ids]

    @dbus.service.method('com.canonical.dbusmenu', in_signature='i', out_signature='b')
    def AboutToShow(self, item):
        return False

    @dbus.service.method('com.canonical.dbusmenu', in_signature='isvu', out_signature='')
    def Event(self, item, event, data, timestamp):
        if event == 'clicked':
            with EVENTS.open('a') as output:
                output.write(self.name + '\n')

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Version': dbus.UInt32(3), 'TextDirection': 'ltr', 'Status': 'normal', 'IconThemePath': dbus.Array([], signature='s')}

class Item(dbus.service.Object):
    def __init__(self, name, delay):
        self.bus = dbus.SessionBus(private=True)
        self.service = 'org.kde.StatusNotifierItem.qa_' + name
        self.bus_name = dbus.service.BusName(self.service, bus=self.bus)
        super().__init__(self.bus, '/StatusNotifierItem')
        self.name = name
        self.menu = Menu(self.bus, name, delay)
        GLib.timeout_add(100, self.register)

    def register(self):
        try:
            watcher = self.bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher')
            watcher.RegisterStatusNotifierItem(self.service, dbus_interface='org.kde.StatusNotifierWatcher')
            return False
        except dbus.DBusException:
            return True

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Category': 'ApplicationStatus', 'Id': 'qa-' + self.name,
                'Title': self.name, 'Status': 'Active', 'IconName': 'dialog-information',
                'ItemIsMenu': True, 'Menu': dbus.ObjectPath('/Menu')}

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, prop):
        return self.GetAll(interface)[prop]

items = [Item('fast', 10), Item('slow', 1200), Item('late', 1800), Item('empty', 10)]
GLib.MainLoop().run()
