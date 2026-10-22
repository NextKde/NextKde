<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/nextkde-logo-dark.svg">
    <img src="docs/images/nextkde-logo.svg" width="80" height="80" alt="NextKDE logo">
  </picture>
</p>

<h1 align="center">NextKDE</h1>

<p align="center"><strong>A Quickshell desktop for KDE Plasma.</strong><br>
Liquid glass, a floating dock, and a workspace you can make your own.</p>

<p align="center">
  <a href="#get-started">Get started</a> ·
  <a href="#the-desktop">Explore</a> ·
  <a href="docs/Development.md">Develop</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center"><code>Plasma 6 / Wayland</code> &nbsp; <code>Quickshell 0.3.x</code> &nbsp; <code>Qt 6</code></p>

![NextKDE desktop with the top bar, floating dock, desktop widgets, and appearance settings](docs/images/desktop.png)

<p align="center"><sub>The NextKDE desktop · macOS appearance · Theme settings</sub></p>

---

## The desktop

NextKDE's **KOS Desktop Shell** brings the bar, dock, launcher, search,
notifications, and settings together on KDE Plasma 6 Wayland. It works with
KWin, NetworkManager, PipeWire, BlueZ, and systemd.

| A workspace at a glance | A desktop in motion | Your choice of appearance |
| :--- | :--- | :--- |
| Clock, weather, calendar, system metrics, app usage, and media widgets. | A floating dock, window previews, app search, and a fullscreen launcher. | Liquid glass, soft-light and frosted materials, or a tonal Material Design interface. |

- **Top bar & system menu** — app menus, system status, and the NextKDE logo menu for settings and session actions.
- **Control center** — Wi-Fi, Bluetooth, volume, brightness, screenshots, and Do Not Disturb.
- **Desktop files** — open, rename, copy, move, delete, and choose an application.
- **Settings & motion** — configure the bar, dock, launcher, shortcuts, window decoration, and animations.

Calendar, Calculator, Todo and Weather are available as
[optional standalone applications](apps/README.md). `./tools/kosctl install apps`
installs these four. ListenFree and its audio SDK require an explicit
`./tools/kosctl install apps --with-listenfree`;
see the [application installation guide](docs/GettingStarted.md#optional-standalone-applications).

Source selection requires Git and Python 3.9+. Only the latest official release is maintained; see [release policy](docs/Releasing.md).
Default `update` selects the [latest official Release](https://github.com/SuceV587/NextKde/releases/latest)
and stops if none is available. To explicitly try development, use `./tools/kosctl update main`
(or `--version main` for the Debian installer). `./tools/kosctl version` reports
installed files and source separately. Source selection does not install or restart the desktop.

## Get started

Use a **KDE Plasma 6 Wayland** session with **KWin 6.6+**, **Quickshell 0.3.x**,
and **Qt 6.6+**. Installation builds the platform service, Settings, KWin effects,
and window decoration.

After preparing the dependencies for your distribution:

```sh
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update &&
./tools/kosctl doctor &&
./tools/kosctl install &&
./tools/kosctl start
```

| Distribution | Installation guide |
| :--- | :--- |
| Arch Linux | [Dependencies and setup](docs/GettingStarted.md#1-install-requirements) |
| Debian 13 | [Installer and manual setup](docs/GettingStarted.md#debian-13-trixie) |
| Ubuntu 26.04 | [Packages and setup](docs/GettingStarted.md#ubuntu-2604-resolute) |
| Fedora 44 | [Packages and setup](docs/GettingStarted.md#fedora-44-community-contributed) |
| openSUSE Tumbleweed | [zypper packages and setup](docs/GettingStarted.md#opensuse-tumbleweed-community-contributed) |
| NixOS | [Flake quick start](docs/nixos-quickstart.md) |

Read the [installation guide](docs/GettingStarted.md) for desktop takeover,
optional lock screen setup, first-login notes, updating, and uninstalling.

<details>
<summary><strong>Everyday commands</strong></summary>

Update and apply:

```sh
./tools/kosctl update &&
./tools/kosctl install &&
./tools/kosctl start
```

Check services:

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

Uninstall:

```sh
./tools/kosctl uninstall
```

Updated KWin effect binaries load after your next logout/login or reboot.
See the [daily-use guide](docs/GettingStarted.md#daily-use) for details.

</details>

Read the [documentation index](docs/README.md) for canonical guides and AI contributor references.

## Under the surface

```text
Quickshell Shell ──► kos-platform ──────► KWin / network / audio / Bluetooth
                 └─► kos-data-service ─► metrics / desktop data / weather
```

| Explore the project | Guide |
| :--- | :--- |
| How the pieces fit together | [Project architecture](docs/ProjectArchitecture.md) |
| Glass, color, and appearance | [Appearance architecture](docs/AppearanceArchitecture.md) |
| Dock behavior and configuration | [Dock architecture](docs/DockArchitecture.md) |
| Desktop icon layout | [Desktop icons](docs/DesktopIcons.md) |
| Spatial wallpapers | [Depth engine](docs/DepthEngine.md) |
| Source sessions, builds, and debugging | [Development guide](docs/Development.md) |
| Changes and pull requests | [Contributing](CONTRIBUTING.md) |

Next steps include per-screen layouts, consistent widgets across displays,
expanded settings and applications, and better keyboard navigation and accessibility.

---

## License

See [LICENSE](LICENSE) for the project license. The bundled Glass effect has
its own [license](kwin/glass-effect/LICENSE).
