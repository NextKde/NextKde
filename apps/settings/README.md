# Settings

Standalone Qt Quick settings application. It is opened from the gear button
in the top bar and runs as its own process. Build the small native host once:

```sh
cmake -S apps/settings -B .build/apps/settings
cmake --build .build/apps/settings
```

The host exposes only explicit Settings IPC methods to QML. It does not import
desktop UI. The Dock page is the first real consumer of that contract.
