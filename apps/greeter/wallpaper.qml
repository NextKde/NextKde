import QtQuick
import Quickshell
import Quickshell.Wayland
import "qml" as Greeter

// Standalone background process; independent of authentication and desktop IPC.
ShellRoot {
    Greeter.WallpaperSource {
        id: wallpaperSource
        uid: /^\d{1,10}$/.test(Quickshell.env("KOS_GREETER_WALLPAPER_UID"))
            ? Number(Quickshell.env("KOS_GREETER_WALLPAPER_UID")) : null
    }
    Greeter.WallpaperWindows { state: wallpaperSource.state; sourceReady: wallpaperSource.ready }
}
