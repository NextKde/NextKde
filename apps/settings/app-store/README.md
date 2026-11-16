# Application store

**Installation boundary:** Native and Flatpak versions may coexist. Settings uses
only current Flatpak inventory for Install/Open/Uninstall; native executables,
desktop entries and source ownership never block discovery, planning or deployment.
Native cleanup is optional and independent, never a prerequisite for Flatpak.
To uninstall, click the app icon/name to expand details, then Uninstall and confirm.
This removes only the selected user Flatpak, keeping personal data and native apps.
System installations and ambiguous multiple Flatpak refs require their own manager.

Applications come from a signed, refreshable catalog maintained in
[NextKde/appCatalog](https://github.com/NextKde/appCatalog). Settings and `kos-apps`
share the user-Flatpak backend. Package SHA-256 is mandatory; developer signatures
are optional unless the entry pins a publisher, in which case manifest and commit
signatures are both mandatory. `gpgv` verifies the catalog using the trusted source
key. Entries cannot supply scripts or arbitrary installer URLs.

The runtime policy approves only the reviewed Flathub runtime URL/key, not Flathub
applications. Explicit Install/Update prepares that source when needed. Applications
remain GitHub Release bundles. See [catalog architecture](../../../docs/app-store/SignedCatalog.md)
for source management, update notifications, localization and future adapter boundaries,
and [Qt runtime packaging](https://github.com/NextKde/appCatalog/blob/main/docs/QtRuntime.md).

Libflatpak may create a URL-less local origin/key record even before a refused or
cancelled deployment; complete rollback is not claimed. An automatically prepared
runtime source can also remain after cancelling the plan. Read-only inventory and ordinary offline user
uninstall remain available and preserve data. Settings and CLI share the backend;
Discover is not promised to discover GitHub bundle updates.

Settings inventories, opens, installs, updates and removes these independent
applications only through their current Flatpak identities. Native executables,
source ownership manifests and retired desktop entries do not count as installed
applications. There is no source status scan or launch/lifecycle fallback.
The source installer remains available as an explicit developer CLI; it is not
part of the Settings catalogue. Old programs are removed separately with the
legacy cleanup tool, never adopted by the new app.

Calendar, Calculator and Weather now share `NextKde/kos-apps`, VERSION and one
Release, but retain separate `org.nextks.<app>` bundles, source manifests and
selective builds. Source is published; the new-ID signed Release is not yet available.
Flatpak manifests use `<appId>.flatpak-release.json` plus `.sig`; ListenFree keeps
its independent repository and generic filenames. Unpublished development IDs do not create a user migration workflow. Old
installer-owned source desktop links are excluded from Settings inventory.

## KMusic

KMusic uses the same Flatpak catalogue, plans, inventory and launch path as the
other applications, with ID `org.nextkde.KMusic`, repository `NextKde/NkMusic`, and
`flatpak-release.json` plus its signature. Its existing native `kmusic-app`
installation is not counted as an installed Flatpak or opened as a fallback.
The old source catalogue is not consumed by Settings. Publication of a signed
KMusic bundle is still required; changing this controller does not publish one.

Legacy cleanup handles historical native installations only. It never uninstalls
Flatpak applications or deletes any `~/.var/app` profile. Unproven native ownership
is retained for its original installer; cleanup is never an installation side effect.

Installation flow: Install → resolve compatible installed Flatpak components →
automatically prepare the reviewed runtime source if needed → one normal download
confirmation → deploy. There is no separate source-configuration dialog. User and
system runtimes are checked in lookup order by ID/architecture/branch and approved
origin; native Qt/KDE files never count. Reused refs show zero download and are
excluded from additional-space estimates. Confirmation and deployment recheck
scope, origin and commit. The deployment explicitly adds only planned missing
components, rather than updating unrelated compatible runtimes.

Inventory and each installation request first require an executable `flatpak`
command and a working companion backend. Missing commands and missing/unstartable
backends have separate error codes and localized instructions. Environment errors
expand card details instead of remaining on the checking placeholder; Check again
retries inventory after repair. Confirmation repeats the command check before any
bundle download. Settings does not install system packages automatically.

Download/space amounts are estimates; OSTree sharing can reduce actual transfer
and disk use. Compile success does not establish runtime acceptance.

The confirmation page shows estimated downloads, not an additional-disk-space
upper bound. Before downloading the bundle, the backend checks free space on the
actual cache and user Flatpak filesystems. Same-device requirements are combined;
separate devices are checked independently. Reused refs are excluded. The internal
conservative budget includes the bundle, new installed payloads, dependency
transfer space and 256 MiB headroom per filesystem. It is checked again before
deployment without counting the already downloaded bundle twice. Insufficient or
unreadable capacity stops the operation; disk-full errors remain handled during
writes because other processes can consume space after the check. Failure details
persist and tell the user which disk needs space and the rounded-up shortfall.

Release integrity incident (2026-11-06): the published calculator 0.2.1 bundle
passed its signed SHA-256 check and declared the same installed size (2,867,968
bytes), but its metadata was 536 bytes while the signed plan contained 535.
The producer's text helper stripped the final LF before encoding and hashing.
The kos-apps release helper must preserve original bytes and reopen the exported
bundle through libflatpak to compare its plan before signing. Its SDK and signed
artifact workflows include byte-preservation regressions. A corrected new release
is required; the consumer must continue rejecting the inconsistent published plan.
Consumer diagnostics now distinguish BUNDLE_METADATA_MISMATCH from
BUNDLE_INSTALLED_SIZE_MISMATCH and record expected/actual hashes, lengths or sizes
in the app log; UI text identifies a release problem without exposing those internals.
