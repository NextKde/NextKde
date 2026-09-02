//@ pragma UseQApplication
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
