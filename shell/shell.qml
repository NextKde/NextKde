//@ pragma UseQApplication
// Use the compositor's input path for Shell text fields. The Fcitx Qt
// module requests a client-side candidate panel, bypassing Kimpanel.
// Quickshell Env pragmas apply only to this process, including source/dev
// launches; applications launched by the Shell keep their original environment.
//@ pragma Env QT_IM_MODULE = wayland
//@ pragma Env QT_IM_MODULES = wayland
// Pin the state directory so every launch mode (`qs -c kos`, `qs -p <repo>/shell`,
// kosctl run/dev) shares one set of user data: dock pins, launcher custom icons,
// appearance, weather cache, and deskcenter files. Without this pragma
// Quickshell derives per-startup-path state directories, which silently forks
// user data between installed and source-tree launches.
//@ pragma StateDir $BASE/quickshell/kos
import Quickshell
import qs.desktop

// Keeps `qs -p <repository>/shell` stable. The desktop environment itself
// lives in shell/desktop/, while independent applications never import this
// entrypoint.
ShellRoot {
    DesktopEnvironment {}
}
