# Development & debugging

[← NextKDE](../README.md) · [Contributing](../CONTRIBUTING.md)

Run commands from the repository root. Run project tests and graphical verification in a virtual machine.

## Development and debugging

Preview the UI without installing it (reuses installed services):

```sh
./tools/kosctl run
```

To debug source QML, run this in one terminal and leave it running; press
`Ctrl+C` to stop it:

```sh
./tools/kosctl dev
```

It starts only the source QML and reuses systemd's `kos-platform.service` and
`kos-data.service`. It does not build, deploy, restart services, or create a
second socket pair.

Settings opened from the source Shell's gear automatically targets that same
source session. You can also launch it manually from a second terminal:

```sh
KOS_SHELL_DIR="$PWD/shell" kos-settings
```

Do not combine `qs -c` and `qs -p`: they are mutually exclusive. A Settings
app opened separately from the desktop menu still targets the installed Shell;
use the source Shell's gear or the command above while debugging.

QML changes hot-reload live under `kosctl dev` (see above). To ship them to an installed desktop, use `install` + `start` like the C++/Go/KWin path below.

After changing C++, Go, or KWin plugins:

```sh
./tools/kosctl install
./tools/kosctl start
```

`start` applies Shell, platform-service, and data-service updates immediately.
Updated KWin effect binaries load after the next logout/login or reboot; this
avoids hot-replacing plugins inside the running compositor.

> `kosctl dev` reuses the already-installed `kos-platform` and `kos-data` from
> systemd — it does not rebuild them for you. After changing platform's C++ or
> data-service's Go, install and restart the service before `dev` connects to
> the new code:
>
> - platform (C++): `./tools/kosctl install && ./tools/kosctl start` restarts `kos-platform.service`
> - data-service (Go): same — restarts `kos-data.service`
>
> Only Shell QML hot-reloads under `dev`; platform, data-service, and KWin
> plugins do not — they must be reinstalled and their services restarted.

Useful commands:

```sh
./tools/kosctl doctor
./tools/kosctl run
./tools/kosctl dev
./tools/kosctl shortcuts install
./tools/kosctl glass-settings
```

Architecture and test documentation lives in [docs/](../docs/). Before opening a
pull request you **must** run:

```sh
git diff --check
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
./tools/run-tests.sh          # data / service layer tests (required)
```

`./tools/run-tests.sh` is the single entry point, and CI runs the same command.
It defaults to the **data / service layer** — the part that must never crash,
the part that needs no display, and the part CI verifies:

```sh
./tools/run-tests.sh              # data layer (default)
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --all        # includes the UI layer; needs a graphical session
./tools/run-tests.sh --help       # all options
```

If you touch QML or the UI, also run `--all`: the UI layer needs a QML engine
(and a compositor for the panel tests), so it cannot run in the CI container and
should be run in a virtual machine with a graphical session.


### Optional standalone applications

The repository also includes independent Qt Quick applications for Calendar,
Todo, Weather, and ListenFree. They are not built with the Shell by default.
Use `apps-dev` or `apps-release` to build them together, or the `calendar-dev`,
`todo-dev`, `weather-dev`, and `listenfree-dev` presets for one application.
The legacy local Music application uses the separate `music-dev` preset:

```sh
cmake --preset apps-dev
cmake --build --preset apps-dev
ctest --preset apps-dev
```

Run `./tools/install-apps.sh` for a per-user install and service registration.
See [apps/README.md](../apps/README.md) for dependencies and module details. Weather
shares the `kos-data-service` Open-Meteo cache with the Shell; Calendar and Todo
share the on-demand PIM service.

