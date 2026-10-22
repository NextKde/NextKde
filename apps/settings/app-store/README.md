# KMusic catalogue

The Settings application reads `catalog.json` from the same resource tree as its
QML entry point. The current catalogue pins KMusic commit
`49264b0d45a6f8958e8d8b6eb4e5da1ee3e655d0` and both installer hashes.
Use `release: null` when no installation revision is approved. Do not substitute
a branch, `latest`, a local checkout path or an unreviewed commit.
Pinning the installer does not mean the end-to-end store workflow has passed VM acceptance.

After the KMusic maintainer publishes the reviewed `install.sh` and
`packaging/installer.py`, prepare the catalogue locally:

```sh
python3 tools/prepare-kmusic-catalog.py <full-40-character-commit-sha>
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
The catalogue is bundled with Settings; remote catalogue updates, binary package
delivery, automatic updates and system package installation are not implemented.

`src/AppStore.cpp` is the native controller. The `appStore` QML context object is
created by the Settings executable. An older binary can preview the new card but
cannot install applications; rebuild Settings to enable the native controller.
Runtime requirements add Qt Network and KDE KIO/Service to the existing Settings
build. Python 3.9+, the source build toolchain and application dependencies remain
requirements of the KMusic installer.

Regression sources are provided for VM execution. No real installation or
uninstallation is part of local UI preview.
