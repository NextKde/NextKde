# Independent NextKde applications

Calendar, Calculator and Weather share the independent `NextKde/kos-apps` source
repository and release version. ListenFree remains in its own repository.
KMusic retains its existing installation controller and is not handled by this
installer. The recommended backend is user Flatpak as described below. For legacy
source compatibility, Settings and the independent repositories ship the same
Python 3 standard-library installer, `tools/app-installer.py`; that path never
fetches or executes a replacement installer.

| Key | Fixed repository | Application ID | Executables / desktop IDs |
| --- | --- | --- | --- |
| `calendar` | `NextKde/kos-apps` | `org.nextks.calendar` | `kos-calendar` |
| `calculator` | `NextKde/kos-apps` | `org.nextks.calculator` | `kos-calculator` |
| `weather` | `NextKde/kos-apps` | `org.nextks.weather` | `kos-weather` |
| `listenfree` | `NextKde/ListenFree` | `org.nextkde.ListenFree` | `listenfree` |

Tasks are integrated in Calendar; no separate Todo entry is exposed. Legacy
installer-owned `kos-todo` links remain recognized for offline removal and
upgrade cleanup. Externally installed Todo files are never removed.

The last column lists executable commands. New native and Flatpak desktop files
for the first three apps use their application ID, e.g. `org.nextks.calendar.desktop`.
Old native desktop identities remain recognized; ListenFree native naming is unchanged. No repository URL, executable name, shell command or installation root is
accepted from a store entry.

The first three apps use one VERSION/commit/Release but separate packages, source
manifests and `-DKOS_APPS=<app>` builds. Old `org.nextkde.Calendar`,
`org.nextkde.Calculator` and `org.nextkde.Weather` Flatpaks are distinct retired
refs: Settings reports RETIRED_FLATPAK_ID. No cross-identity profile copying is provided; exact user-ref
removal is a separate confirmed action that keeps data and does not install a replacement. See
[compatibility and manual transition](ProfileMigration.md) and [human acceptance](ProfileMigrationAcceptance.md).
The old per-app GitHub repositories were deleted in favor of NextKde/kos-apps;
no renamed signed release is available yet. Old installer-owned source IDs/desktop
links remain strictly recognized for offline status/uninstall.

## Signed GitHub Flatpak bundles (not yet published)

The distribution route is independent app repositories → GitHub Release `.flatpak`
assets → Settings/`kos-apps`. No hosted NextKde OSTree app repository or Flathub
listing is required. Discover is not promised to discover GitHub bundle updates.
Flatpak owns the installed files and refs; external Flatpak tools can remove the
same installation. Settings re-reads user and system installations every five
seconds, and normal user uninstall is offline, retains data and leaves runtimes.
System or ambiguous installations require explicit resolution outside Settings.

`<appId>.flatpak-release.json` (ListenFree: `flatpak-release.json`) is separate
from the source manifest. Each app has a unique attachment in the shared Release. Schema 1 names
an exact app ID, stable numeric `X.Y.Z`, immutable source revision and architecture
map. Each bundle pins `ref`, OSTree `commit`, asset filename, byte `size` and
`sha256`. A detached signature named by appending `.sig` signs the original bytes; the
bundle's OSTree commit must also be signed. Reviewed binary public keys and full
primary fingerprints ship in core's `FlatpakTrustPolicy.h`, never from the same
Release or from the bundle. The dedicated development publisher key is now embedded
for all four app IDs, fingerprint `3751DC833ED4BC7E797A9766ADF7411B531A56B4`;
no signed production bundle has been published. The key was generated locally
but is not a CI secret or published trust release. The runtime-only policy now
accepts `https://dl.flathub.org/repo/` with primary fingerprint
`6E5C05D979C76DAF93C081354184DD4D907A7CAE`, reviewed on 2026-11-05 against the
[official setup documentation](https://docs.flathub.org/docs/for-users/installation)
and its HTTPS repository file. The primary expires on 2027-06-14. This authorizes
runtimes only, not application updates from Flathub; unknown additional primary
keys, disabled verification and other URLs remain refused. Users must configure
the source separately; Settings does not add it. Signed bundle installation and
update acceptance remain pending.

Explicit update checks contact only the fixed repository's latest stable GitHub
Release, validate unique attachments, signatures, tag/version and native stable
ref. Metadata is bounded to 256 KiB, signatures to 64 KiB and bundles to 2 GiB.
Downloads permit only fixed GitHub HTTPS endpoints and attachment CDNs, at most
five redirects, no arbitrary URLs/credentials. Metadata attempts allow 30 seconds
within a 90-second discovery budget. Bundle downloads allow a 30-second idle
limit and ten minutes per attempt, at most three attempts within 30 minutes.
Transient network/5xx failures retry with finite backoff; integrity, TLS, 404 and
rate-limit failures do not. Logs avoid signed CDN URLs. Cancellation also covers
retry waits; partial downloads are removed. Full bundles are streamed, not held
in memory, and revalidated against the signed manifest before deployment.

Discovery is bound to the actual installation snapshot. Signed versions below the
installed AppStream version, invalid version baselines, and same-version/different
commit replacements are refused. Without a previous installation there is no
claim of complete old-signature replay prevention. Existing apps must have a
verified publisher-signed commit and a URL-less, verifying local bundle origin;
Settings never adopts a third-party online-origin installation for bundle updates.
New installs refuse legacy executable/desktop/ownership conflicts. Duplicate,
system, other-branch/architecture and concurrent changes are not silently resolved.

Before downloading a bundle, the backend checks signed-bundle transaction cleanup
in an isolated, bounded `kos-apps` subprocess without executing an installation.
Some libflatpak packages (including unpatched 1.16.6) incorrectly release explicit
GPG `GBytes` as a GObject and crash on transaction destruction. A failed/crashing
probe reports `FLATPAK_INCOMPATIBLE`, rather than crashing Settings or partially
deploying an app. Update Flatpak/libflatpak to a distribution package containing
[upstream fix 95b70b71](https://github.com/flatpak/flatpak/commit/95b70b71e366c78d16abadaa7e33f6d6bcdc01f4).
The probe checks behavior, not a version floor, so backported fixes are supported.
It neither runs a transaction nor changes the user's Flatpak installation. Direct
manual Flatpak CLI installs need the same upstream correction; do not omit explicit
trusted keys or signature checks to avoid the crash.

Mutation transactions run in the fixed companion `kos-apps` process, preserving
the same bundle/publisher/runtime/ownership checks. Cancellation requests graceful
termination, then kills a non-responsive helper after two seconds; Settings keeps
the operation busy until the helper exits and actual inventory is re-read. This
also bounds libflatpak paths that fail to propagate GCancellable while fetching
runtime metadata. An interrupted transaction is not promised to roll back: the
reconciled installed state is authoritative. A crashed/missing/malformed helper
returns `RESULT_UNKNOWN`, never a fabricated successful deployment.

The backend checks bundle identity/ref/commit and rejects embedded online app or
runtime-repository URLs. It passes explicit trusted key bytes to libflatpak and
checks the resolved plan before/after authentication. The target must be an exact
INSTALL_BUNDLE operation; extra applications/uninstalls are refused. Runtime
installs/updates and reused base runtimes require separately reviewed, configured
user runtime sources (exact HTTPS URL, commit/summary verification and approved
valid primary keys). No online source is added automatically. Runtime hosting is
still necessary somewhere, e.g. an independently trusted existing provider.

Libflatpak may create a **local URL-less origin record and import the supplied
public key before transaction readiness**; cancellation/refusal can leave that
record. This is not a hosted app source and is not claimed to roll back. Download
and deployment together have a 60-minute operation deadline; the companion
transaction process is supervised as described above. Results always re-query
actual installed refs/commits; a partial runtime deployment or interrupted
transaction is not claimed to be atomic. Isolated runtime-ready transaction
acceptance is recorded below; interactive desktop acceptance remains outstanding.

Permissions in the manifest are not the complete effective permission set. The
KDE 6.11 runtime used by the development builds also contributes read-only
`xdg-config/kdeglobals` access and talk access to `com.canonical.AppMenu.Registrar`,
`org.kde.kconfig.notify` and `org.kde.KGlobalSettings`. Inspect the final exported
metadata for each release; do not describe these packages as having zero host
configuration or session-bus access.

### Release source and build records

The shared three-app helper and independent ListenFree helper request flatpak-builder's Sources export
and separately sign/export `APP_ID.Sources-VERSION-ARCH.flatpak`. They also retain
an exact app revision archive, patches, build manifest, effective permission metadata
and file inventory. `build-info.json` records user-level SDK/runtime refs and commits;
a change during construction stops signing. A detached publisher signature covers
`SHA256SUMS`, which recursively records retained materials. A directly signed
`release-materials.tar.gz` preserves the complete tree, including nested patches
and checksums, without recursively including itself. The existing source preparer
also generates `app-release.json` from the same revision's exact GitHub codeload
bytes so a new latest stable Release does not break the legacy source entry point.

As of 2026-11-05, this helper has prepared signed Calendar, Calculator and Weather
app/Sources candidates from the same reviewed `ee0175f4` source revision. In the
dedicated VM, their manifest/material signatures, checksums and bundle identities
passed verification; production `kos-apps` recognized their installed signatures
and uninstalled them while retaining private-data sentinels. Those offline checks
used a process-local libflatpak with the upstream cleanup fix; the system package
was not replaced. In a separate disposable runtime-ready profile, all three apps
also completed production signed discovery/download/install, current-version and
duplicate-operation checks, offscreen sandbox startup, persistent-503 inventory
preservation and uninstall with data/runtime retention. Discovery used a local
process-only TLS fixture and genuine publisher-signed materials, not a published
Latest. Calculator and Weather passed external Flatpak removal, periodic inventory
refresh and reinstall; Calendar passed that cycle after transaction supervision
was added. A passing rerun does not explain its earlier transfer timeout. Offscreen
platform/portal warnings and optional compositor-module warnings remain; real
version upgrades, interactive graphical acceptance and a stable Release are open.

Preserve and publish the complete artifact directory with relative paths, not only
the application bundle. Sources is not an app dependency and is not installed by
Settings. It does not automatically supply external SDK/runtime sources or approve
source completeness, linked component configuration, aggregate licensing or notice obligations.

### Without Settings

The recommended non-graphical route is the shared `kos-apps` CLI below. Manual
bundle installation is also possible, but first obtain the reviewed public key
through a trusted core distribution or independently authenticated channel, verify
the detached manifest signature with `gpgv` in a private keyring, and verify the
bundle's signed size/SHA256, app/ref/arch/commit. Do not trust a key supplied beside
the download. Then use explicit key material, never a verification bypass:

```sh
flatpak --user install --gpg-file=/trusted/publisher.gpg ./application.flatpak
flatpak --user uninstall org.nextks.calculator
```

Repeat verified bundle installation to update; `flatpak update`/Discover alone
cannot discover a newer GitHub bundle with no online origin. Do not use
`--delete-data` for ordinary removal. Publisher keys, matched-source signed
candidates and runtime policy are prepared; full runtime/desktop and real-version
update acceptance still remain.

## Application packaging readiness

The table below retains historical **old-ID** preparation. New `org.nextks.*`
native builds and registered regressions run in hosted CI. At exact revision
`03c92edd0b0c9f54013ba8c63ee1e591482eb928`, all three also completed KDE 6.11
SDK app/Sources exports in
[run 41945820505](https://github.com/NextKde/kos-apps/actions/runs/41945820505).
These unsigned candidates do not establish signing, sandbox lifecycle or
production acceptance.

| App | Local preparation | Still required |
| --- | --- | --- |
| Calculator | Identity option, manifest, signed-bundle helper and artifact-only workflow; host identity and KDE 6.11 SDK builds compiled; unsigned development bundle exported | Reviewed immutable source, signing resources, signed Release and manual sandbox acceptance |
| Weather | Identity/private backend-data option, pinned Go build module, bundle helper and artifact-only workflow; host and KDE 6.11 SDK application/backend builds compiled; cleaned unsigned development bundle exported | Reviewed immutable source, signing resources, signed Release and manual sandbox acceptance |
| Calendar | Scoped PIM/activation/private storage, pre-store ownership lock, Background portal request, pinned dependency manifest, helper/workflow; host and KDE 6.11 SDK builds compiled; unsigned development bundle exported | Portal/background/relogin acceptance, limited ICS exchange and explicit host-widget limitations; reviewed immutable source, keys and signed Release |
| ListenFree | Identity/MPRIS/private credential namespace, explicit optional-feature limits, declared dependency modules/patches, mandatory license inputs, helper/workflow; host and KDE 6.11 SDK app/sourcehost builds compiled; cleaned unsigned development bundle exported | Dependency/runtime/license/source delivery review, portal/audio/credential acceptance; reviewed immutable source, keys and signed Release |

Host identity compilation does not mean a Flatpak bundle was built or accepted.
The shared backend embeds the publisher key and the reviewed runtime-only policy,
but no signed Release exists; none of these entries implies production availability.

### Pending manual bundle acceptance

None of the following scenarios is marked accepted by host compilation or the
legacy source-installer records. Use a dedicated user/environment, approved
runtime sources, reviewed public keys and signed artifacts; do not reuse personal
profiles, credentials or an existing production installation.

| Scenario | What a person must verify |
| --- | --- |
| First installation | Settings, `kos-apps` and external Flatpak agree on the exact user ref/commit; the exported desktop entry opens the app |
| New stable Release | Explicit checking offers the signed newer version without a core upgrade; identical commits are unchanged, downgrade and same-version replacement are refused |
| Download failure | Offline, 404, rate limiting, TLS failure, stalled/slow transfer and transient 5xx show distinct actionable errors; retry/deadline limits hold and no partial package is deployed |
| Cancellation / space | Cancel during retry wait, download and deployment; inspect actual installed state and partial files, preserving the previous app where deployment has not changed it; verify disk-full diagnostics |
| Invalid package | Altered manifest/bundle, unknown key, invalid signature, wrong app/arch/branch/commit and off-allowlist redirects are refused before app deployment |
| Runtime / ownership conflict | Missing or unapproved runtimes, unexpected operations/remotes, system/duplicate refs, native entry conflicts and concurrent external changes are refused without silent takeover |
| External uninstall | Remove through Settings and inspect external Flatpak, then reverse the direction; Settings refreshes state, app data and shared runtimes remain |
| Calendar | Exercise background permission denial/partial approval/timeout/approval, closing the window, relogin, reminder activation and duplicate-service rejection; native data stays untouched |
| ListenFree | Check portal-selected files after restart, playback/seeking/audio devices, MPRIS, credential-save failure/logout and the excluded web-login message with isolated non-personal inputs |

Record actual versions/commits, visible error text and diagnostic log paths for each
manual scenario. Do not treat a screenshot, compiled workflow or successful build
as lifecycle acceptance. The unpublished profile copier and Calendar finalizer have
been withdrawn; see [compatibility and manual transition](ProfileMigration.md).
Read-only app/widget summary integration is implemented locally; identity selection, failure states and pending manual acceptance are documented in [WidgetIntegration.md](WidgetIntegration.md). This is not profile migration or reminder handover.

## Unified Flatpak CLI

`kos-apps` links the same backend as Settings, is installed with core Settings, and
requires neither a graphical session nor a replacement installer download:

```sh
kos-apps status --app calculator
kos-apps check-update --app calculator
kos-apps install --app calculator --yes
kos-apps update --app calculator --yes
kos-apps uninstall --app calculator --yes
./tools/kosctl install apps status --app calculator
```

Mutations ask for terminal confirmation unless `--yes` is explicit; without a TTY
and without `--yes`, they are refused. SIGINT/SIGTERM request cancellation; the CLI
waits for the real inventory re-query instead of promising rollback. Stdout contains
one JSON result (including actual state and diagnostic log path), while progress
is printed to stderr. Missing publisher trust or bundles do not trigger online source setup or a
source-install fallback. `tools/install-apps.sh` defaults to this backend; batches
stop on the first failure, retaining earlier successes.

The source CLI below remains an explicit legacy/developer interface, not a
Discover-managed package installation. To use it through the wrapper, specify
`./tools/install-apps.sh --backend=source status --app calculator`. Source version
selection and build dependency checks are source-only. No automatic migration or
data copying is performed.

## Command interface

```sh
python3 tools/app-installer.py --app calculator check-update
python3 tools/app-installer.py --app calculator check
python3 tools/app-installer.py --app calculator install --version 0.2.0
python3 tools/app-installer.py --app calculator status
python3 tools/app-installer.py --app calculator update
python3 tools/app-installer.py --app calculator uninstall
```

`--version X.Y.Z` is an optional consistency requirement against the discovered
latest stable release, not an arbitrary tag/revision selector. Only numeric,
three-component semantic versions without prerelease/build suffixes are
accepted. Update comparisons are numeric; downgrades and changed revisions
under the same version are refused.

- `check-update` discovers and validates release metadata without building.
- `check` additionally downloads/verifies source and runs real CMake configure
  to resolve the application's actual development dependencies. It does not
  build or install the application.
- `install` / `update` configure, build and install an immutable version before
  publishing it. An identical installed revision is idempotent. `update`
  requires an existing managed installation.
- `status` / `uninstall` are strictly offline. Uninstall removes only validated
  installer-owned activation links, immutable versions and ownership metadata;
  application settings and user data are preserved. Diagnostic logs remain.

The installer never runs sudo, installs system packages, replays a failed build,
or starts an application. Install Python 3, CMake, Ninja, a C++ compiler and the
app's documented development dependencies with your distribution's package
manager. Configure failures are `DEPENDENCY_UNSATISFIED`, with a private log to
inspect; missing tools are named explicitly.

ListenFree additionally requires its checksum-pinned private audio/JavaScript SDK.
Prepare it using the independent repository's documented SDK script in a stable
location, and export `LISTENFREE_SDK` when launching Settings or the CLI. The
source installer does not bootstrap that SDK automatically. Without it, the
operation stops with `DEPENDENCY_UNSATISFIED`; the configure log contains the
preparation instructions. The same SDK environment is required for later updates.

## Result protocol

Stdout is JSON Lines. Every operation ends with exactly one `type: "result"`
record; earlier `type: "progress"` records are optional. Child output goes only
to a mode-0600 log, never into this protocol.

```json
{"schemaVersion":1,"appId":"org.nextks.calculator","action":"status","stage":"status","type":"result","success":true,"code":"INSTALLED","version":"0.1.0","revision":"0123456789012345678901234567890123456789","details":{"installed":true,"managed":true,"available":true,"version":"0.1.0","revision":"0123456789012345678901234567890123456789","currentVersion":"0.1.0","currentRevision":"0123456789012345678901234567890123456789","desktopFile":"/home/example/.local/share/applications/org.nextks.calculator.desktop","root":"/home/example/.local/share/nextkde-apps/calculator"}}
```

`available` means the local allowlisted engine supports this app; it does not
claim a release is published. Discovery errors such as `RELEASE_UNAVAILABLE`
remain errors and preserve known installed-version details. Successful
`check-update` includes `latestVersion` and `updateAvailable`. Conflicting
external installations return `EXTERNALLY_MANAGED`, `installed: true`,
`managed: false` and an existing fixed desktop path when one is available;
they are never adopted, upgraded or uninstalled. Consumers must not fabricate
an installed version from the catalog or from an error.

Exit statuses: 0 success, 2 expected failure (dependency/release/conflict/state),
3 child timeout, 130 cancellation, 1 unexpected installer error. Invalid CLI
arguments also produce one JSON result. `--help` prints usage normally.

## Release publication and trust

The fixed endpoint is
`https://api.github.com/repos/NextKde/<repository>/releases/latest`.
A published stable, non-draft release must have a `vX.Y.Z` tag and exactly one
`<appId>.app-release.json` asset for the selected kos-apps application
(or `app-release.json` for ListenFree). Example manifest:

```json
{
  "schemaVersion": 1,
  "appId": "org.nextks.calculator",
  "version": "0.1.0",
  "revision": "0123456789012345678901234567890123456789",
  "archiveSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

The example hash must be replaced with the actual SHA256. The optional
`archiveUrl` must equal
`https://codeload.github.com/NextKde/<repository>/tar.gz/<revision>`.
Metadata is limited to 256 KiB per response, compressed source to 256 MiB and
extracted source to 1 GiB / 100,000 entries. SHA256 is checked before extraction.
Traversal, symbolic links, hard links, special files and duplicate archive paths
are rejected. The source archive must have one top-level CMake project.

Initial requests stay within the exact repository's HTTPS GitHub/API/codeload
paths. Redirects may additionally target GitHub's fixed release asset hosts;
non-HTTPS URLs, credentials and other hosts are rejected. Connection reads time
out after 15 seconds. Unix main-thread signal deadlines bound each complete
metadata/archive attempt to 45/300 seconds, including DNS, redirects and headers.
The complete release discovery (both JSON requests plus retries) additionally
has a 90-second deadline. Nested deadlines never extend an earlier deadline.
Transient failures have at most three attempts with bounded backoff;
integrity/TLS errors, 404 and rate limits are not retried. 404 is
`RELEASE_UNAVAILABLE`; 429 (or exhausted GitHub 403 rate limit) is `RATE_LIMITED`,
with `retryAfter` and `rateLimitReset` details when provided by GitHub.

**Trust is the fixed NextKde GitHub publication over HTTPS, not cryptographic
release signatures.** The checksum binds source bytes to that publication but
is not an independent authenticity proof. CMake source is executable build
logic: installing explicitly trusts the allowlisted publisher. Builds are not
sandboxed. Never install untrusted source by editing the allowlist.

## Storage, activation and ownership

- `${XDG_DATA_HOME:-~/.local/share}/nextkde-apps/KEY/versions/REVISION/`
- `.../KEY/current` — atomic symlink to the published immutable version
- `.../KEY/ownership.json` — exact owned revision and activation link inventory
- `${XDG_STATE_HOME:-~/.local/state}/nextkde-apps/KEY/{lock,logs/}`
- `~/.local/bin/EXECUTABLE` — owned symlink through `current/bin`
- `$XDG_DATA_HOME/applications/ID.desktop` — owned symlink through `current`
- `$XDG_DATA_HOME/dbus-1/services/NAME.service` — only when supplied by the app

CMake's installation prefix is the final immutable version path, not a renamed
staging path. Before publication the old `current` remains untouched. Build,
configure and install failures clean the candidate and preserve the old version.
Success retains prior versions until explicit prune or uninstall. Cancellation terminates the
entire child process group (TERM then KILL); the configured child deadline is
30 minutes per configure/build/install command. Direct SIGKILL or a forced
installer crash can bypass cleanup and leave a child build process running.

Existing user desktop/bin/service files and distro/Nix activation entries are
not overwritten. The installer checks executable PATH entries and system XDG
desktop/D-Bus locations. Calendar's shared PIM service must use its immutable
owned executable directly, not a systemd unit that could activate a different
installation. Existing core PIM service activation is a conflict, not a file to
replace. Stop conflicting applications/services and resolve the package
ownership manually before choosing an independent installation.

A private `transaction.json` in the app state directory records the explicit
owned candidate and old/new inventories before mutation. Under the app lock,
the next invocation (including offline status/uninstall) recovers interruptions:
pre-commit publication rolls back; a committed ownership metadata replacement
completes publication forward and resumes stale activation cleanup. Interrupted
uninstall resumes only its journal-owned inventory. Journal/metadata writes and
publication directory changes are flushed before discarding recovery records.
Cancellation after commit can therefore leave the new version installed rather
than pretending the old version was retained.

Corrupt journals, replaced activation paths, or missing ownership metadata/current
links without a valid journal are refused. This intentionally favors retaining
files over guessing ownership. Do not remove or rewrite metadata to force an
operation. Multi-file uninstall is resumable, not instantaneously atomic; disk
failure or external file replacement can still require manual recovery. No automatic
stale-version garbage collection is performed; explicit cleanup-plan/prune keeps current
and one rollback revision (see the compatibility guide).

## Manual verification

Use an isolated HOME/XDG directory before trying a real source release. Check
release discovery and dependency diagnostics, install an app, launch it from
its desktop entry, update to a newer version, cancel a build and confirm the
old launcher still works. Verify offline status/uninstall and that application
user data remains. Check that a distro/Nix or existing PIM activation yields a
conflict rather than replacing files. No compositor restart is needed for this
installer itself.
