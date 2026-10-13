import Quickshell
import qs.desktop.modules.notifications

// Instantiate the real entry point. Rendering and Dock services are stubbed
// by run-dbus.mjs; NotificationServer, observer and history remain production.
Scope {
    NotificationCenter {}
}
