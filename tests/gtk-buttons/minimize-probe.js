// VM-only KWin script: Wayland does not report minimized state to GTK clients.
workspace.windowAdded.connect(function(window) {
    window.minimizedChanged.connect(function() {
        if (window.minimized) {
            print("GTK201_MINIMIZED " + window.resourceClass);
        }
    });
});
