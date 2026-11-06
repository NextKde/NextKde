# Application store

Calendar (including Todo), Calculator, Weather and ListenFree are independent
applications. The recommended Settings/`kos-apps` backend downloads signed
GitHub Release Flatpak bundles, using structured libflatpak transactions. It does
not require a hosted NextKde app repository or a Flathub listing. Signed manifests
pin version/ref/commit/size/hash; reviewed public keys ship in core and are never
trusted from the downloaded bundle. `gpgv` is a runtime dependency. The local
bundle-publisher policy contains the dedicated public key for all four app IDs.
The runtime-source policy approves only the reviewed Flathub runtime URL/key,
not Flathub applications; users must configure that remote separately. See the
[independent-app contract](../../../docs/app-store/IndependentApps.md) for the
full primary fingerprint and review evidence. No signed production bundle is
published, so new installation/update remains unavailable. No online
remote is added, no source fallback occurs, and no legacy migration is automatic.
Libflatpak may create a URL-less local origin/key record even before a refused or
cancelled deployment; complete rollback is not claimed. Runtime sources must be
separately configured and approved. Read-only inventory and ordinary offline user
uninstall remain available and preserve data. Settings and CLI share the backend;
Discover is not promised to discover GitHub bundle updates.

For existing source installs, Settings bundles the reviewed `installer.py` lifecycle
engine; it never downloads new installer code during a release check. The fixed
repository registry discovers each app's stable GitHub Release and bounded
`<appId>.app-release.json` manifest (ListenFree retains `app-release.json`). Explicit **Check for updates** and **Update** do not
require a NextKDE release. A release manifest pins the source commit and archive
SHA-256. GitHub repository publication permissions are the trust boundary;
these checks do not constitute a separate cryptographic signature.

The same engine is distributed as `packaging/installer.py` in each application
repository and exposed by `./install.sh`. It supports offline status/uninstall,
owned-file removal, preserved user data, and staged source builds. See
[the independent-app contract](../../../docs/app-store/IndependentApps.md) for
network deadlines, ownership, failure recovery and command-line use. The canonical
engine source is `tools/app-installer.py`; its Settings copy must stay identical.

Calendar, Calculator and Weather now share `NextKde/kos-apps`, VERSION and one
Release, but retain separate `org.nextks.<app>` bundles, source manifests and
selective builds. Source is published; the new-ID signed Release is not yet available.
Flatpak manifests use `<appId>.flatpak-release.json` plus `.sig`; ListenFree keeps
its independent repository and generic filenames. Retired old Flatpak identities
are reported as conflicts, not adopted or automatically removed/migrated. Old
installer-owned source desktop links remain recognized for offline management.

## KMusic compatibility catalogue

KMusic retains its existing pinned installer and installation/data identity. It
is not migrated to the four independent applications' release format implicitly.


The Settings application reads `catalog.json` from the same resource tree as its
QML entry point. The current catalogue pins KMusic commit
`49264b0d45a6f8958e8d8b6eb4e5da1ee3e655d0` and both installer hashes.
Use `release: null` when no installation revision is approved. Do not substitute
a branch, `latest`, a local checkout path or an unreviewed commit.
Pinning the installer does not mean the end-to-end store workflow has passed VM acceptance.

After the KMusic maintainer publishes the reviewed `install.sh` and
`packaging/installer.py`, prepare the catalogue locally:

```sh
python3 tools/release/prepare-kmusic-catalog.py <full-40-character-commit-sha>
```

This downloads the two files without executing them, pins their SHA-256 hashes,
and writes the local catalogue. Review that diff, preview the UI, then publish
only after user approval. The Settings backend downloads those exact files,
checks both hashes before every invocation, and preserves their directory layout.

The application uses the protocol described in
`docs/app-store/KMusicInstallation.zh-CN.md`. Install invokes `check`, `install
--version SHA`, then `status`. Uninstall invokes `uninstall`, then `status`.
Success requires one valid JSONL result and a normal zero exit code. Missing,
contradictory or duplicate results are reported as unknown. Progress uses named
stages, never invented build percentages. The page remains responsive and
operations survive page navigation. Closing Settings is blocked while an
operation is active; the user may cancel from the card. Forced termination cannot
guarantee rollback and must not be treated as success.

This is a source installer. It does not install system dependencies, use sudo,
launch KMusic automatically or remove music/account data. Missing dependencies
are displayed with their required/detected versions. Opening the application is
an explicit action through its installed desktop entry and KDE's launcher.
This KMusic compatibility catalogue is bundled with Settings. KMusic remote
catalogue updates, binary package delivery, automatic installation and system
package installation are not implemented. The four independent applications use
the separate explicit stable-release discovery described above.

`src/AppStore.cpp` is the native controller. The `appStore` QML context object is
created by the Settings executable. An older binary can preview the new card but
cannot install applications; rebuild Settings to enable the native controller.
Runtime requirements add Qt Network and KDE KIO/Service to the existing Settings
build. Python 3.9+, the source build toolchain and application dependencies remain
requirements of the KMusic installer.

Regression sources are provided for VM execution. No real installation or
uninstallation is part of local UI preview.

## Download recovery

Settings limits each installer-file request to 30 seconds, with up to 3 total
attempts for transient network/HTTP errors. Missing files, TLS validation errors
and integrity failures stop immediately. KMusic source downloads (including
submodules) have a 5-minute deadline per attempt and at most 5 total attempts.
Retries wait 2, 4, 6 and 8 seconds as applicable. The previous installer process
group is terminated before another attempt starts; only the disposable download
phase is retried, never a build or a potentially completed installation.

The UI shows the current attempt, total elapsed time, and a separate compilation
hint. Exhausted downloads stop with an actionable error and allow a manual retry.
Cancelling during either an active download or retry delay prevents further retries.
Builds have their own 30-minute deadline; checks/status use 1 minute, installation
and removal use 5 minutes. A stuck process receives TERM followed by KILL after
10 seconds. These limits are enforced by Settings even if the installer hangs.

The cloud `kos-settings.app-store` tests use synthetic installers and a loopback
HTTP server to cover stalled downloads, HTTP failures, recovery, integrity errors,
retry exhaustion and cancellation. No actual application is installed by them.
