# Releases and maintenance

[简体中文](Releasing.zh-CN.md)

Only the **latest official release** is maintained. `main` is development;
`release/X.Y` prepares a release and its patches. Old tags remain available for provenance
and compatible reinstall rollback, without parallel long-term maintenance. Public beta/RC
releases are optional; maintainer acceptance can lead directly to a final release.

## Identity and source selection

`VERSION` identifies the desktop distribution; it does not replace IPC versions, database schemas
or individual app versions. `main` keeps a development suffix. A release branch uses exact `X.Y.Z`.
Increment Z for patches and Y for a new feature batch; disclose incompatible changes even in 0.x.
Published `vX.Y.Z` tags are immutable. Synchronize fixes between main and the release branch.

```sh
./tools/kosctl update             # GitHub Latest official Release
./tools/kosctl update v0.1.0      # explicit historical tag
./tools/kosctl update main        # explicit development
./tools/kosctl version            # deployed files and source separately
```

Git and Python 3.9+ are required for selection. `update` fetches an exact origin ref and checks
out detached HEAD, preserving branches. It stops for dirty/untracked files, incomplete Git operations,
missing releases, API limits or network errors. It does not reset the tree or silently choose main.
Forks query their own origin; non-GitHub remotes require an explicit ref. Shallow clones remain shallow
when selecting refs; existing full clones retain their history. Deleting current files does not shrink
historical Git objects automatically.

`update` selects source only; `install` deploys the checkout; `start` activates installed services.
KWin updates require logout/login or reboot. The Debian installer defaults to stable;
`--version main` opts into development and `--version vX.Y.Z` pins a release (`--branch` is an alias).
It may install dependencies first but must select the requested source before building NextKDE.

## Prepare, accept, publish

1. Choose the scope and commit. Create or reuse `release/X.Y`; accept only fixes, release docs
   and version changes there. A patch to 0.1 uses `release/0.1`.
2. Update the [English-first bilingual release notes](releases/TEMPLATE.md), dependencies,
   upgrade/rollback limits, known issues and affected PRs. Review current docs and translations.
3. Set VERSION to the target version. Push the exact candidate to run all **seven** tests jobs:
   source release selection; data/platform/logic/headless; apps; changed-file QML checks; KWin 6.6, 6.7 and 6.8 SDKs.
   Each SDK must use its complete matching dependency snapshot, build/link plugins and Glass,
   run offline regressions and inspect official headers. A different commit's green CI is insufficient.
4. Save a VM snapshot, then complete the acceptance below on that exact commit. Fix issues and
   repeat affected checks. Record commit, environment, commands, results and skipped coverage.
5. With explicit publication authorization and all gates passed, create immutable `vX.Y.Z`
   at the accepted commit. Require `release-checks` to pass Tag/VERSION identity.
6. Create the final Release, attach source/checksums and bilingual validation scope, verify artifact
   digests and set **Latest** deliberately. The workflow checks identity; it never publishes itself.
7. In the VM, use the actual no-argument `kosctl update` against the real GitHub Latest endpoint,
   install/start, reboot and verify Installed/Source and plugins. Attach this result. Restore the VM
   snapshot and leave it shut down after exporting evidence. The previous release stops maintenance.

## Required VM acceptance

Run project builds/tests/GUI/diagnostics **only in the VM or hosted CI**, never on the maintainer host.
Record distro, architecture, Qt, KWin, Quickshell and GPU/backend. SDK success does not prove
three live desktop sessions. Clearly label unverified distributions, features and schema downgrades.

- Run contract/documentation checks, source-release regressions, relevant tests and real graphical
  Shell flows. Confirm configuration loaded and inspect runtime/QML errors.
- Test fresh **default core install**, installed stable → candidate upgrade, same-version reinstall,
  candidate → previous supported tag reinstall rollback, retained settings and backup recovery.
- Test the actual **`./tools/kosctl install apps`** default command, not a manual CMake substitute.
  Confirm four standard apps, ListenFree OFF, no SDK preparation, unchanged music MIME/legacy player,
  unchanged core Settings, an old ON cache reset to OFF and a fresh apps-only prefix.
  Test explicit audio selection separately; missing audio dependencies must fail before SDK build.
- Verify service activation/autostart, reboot/logout plugin loading, launcher/Dock/bar/settings/
  notifications and affected app interactions. Test uninstall/reboot recovery to Plasma.
- Verify invalid refs, dirty sources, unavailable API/network and build/deploy failures stop correctly;
  Installed cannot falsely report a complete deployment after partial replacement.
- Preserve personal configuration; confirm removed runtime files disappear and backups can be read.
  Optional components and full model inference need separate acceptance if claimed.

## Backups and rollback

Before replacing managed Shell/Settings runtime trees, installation backs up those trees,
`~/.config/kos` and the prior release record to
`${XDG_STATE_HOME:-$HOME/.local/state}/kos/install-backups/`. Failure to back up stops replacement.
New trees are recreated to remove stale QML/plugins. User state remains. Backup retention is manual.
Backups do not include all system plugins, dependencies or application data. Deployment is not atomic;
partial replacement invalidates the old record. The record is
`${KOS_PREFIX:-$HOME/.local}/share/kos/release.json`; running processes may still be older.

After checking configuration/schema and dependency compatibility, reinstall a validated older tag:

```sh
./tools/kosctl update v0.1.0 &&
./tools/kosctl install &&
./tools/kosctl start
```

Then logout/login or reboot. Stop relevant services before restoring an old-format config backup.
Do not erase personal data as a rollback strategy. Cross-schema downgrade requires its own test;
older pre-policy tags may not remove newer runtime leftovers. Full recovery requires system backup
or a VM snapshot. NixOS uses pinned flake inputs/lock and rebuilds, not `update` inside Nix store;
see [NixOS](nixos-quickstart.md). Packaged version reporting reads the actual deployment record;
`KOS_RELEASE_RECORD` selects another real deployment explicitly.

## Serious defects after publication

Mark the affected Release and document a verified recovery path. If necessary withdraw Latest
recommendation explicitly so default installation does not keep selecting a known bad version.
Prepare a patch on the current release branch, increment Z, run the same gates, publish and
synchronize the fix to main. Do not move the bad tag or promise patches for every old series.
