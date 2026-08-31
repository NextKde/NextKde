//@ pragma UseQApplication
import Quickshell
import qs.desktop

// Keeps `qs -p <repository>/shell` stable. The desktop environment itself
// lives in shell/desktop/, while independent applications never import this
// entrypoint.
ShellRoot {
    DesktopEnvironment {}
}
