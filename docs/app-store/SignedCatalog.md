# Signed application catalogs

[简体中文](SignedCatalog.zh-CN.md)

Settings → **Applications and services** reads application identities from [NextKde/appCatalog](https://github.com/NextKde/appCatalog). Additions and removals are catalog changes, not Settings code changes. Both catalogs and application packages use stable **GitHub Releases**. App versions use `vX.Y.Z`; catalog releases use increasing sequence numbers.

## Contributing and packaging

Application authors publish a bundle and schema-2 manifest with SHA-256 in their own GitHub Release, then submit `apps/<appId>.json` to appCatalog. Maintainers review and publish the signed catalog. Normal new application versions only need a new application Release. Removing an entry or marking it withdrawn/revoked stops installs and updates while retaining management of existing installations.

Read the [submission guide](https://github.com/NextKde/appCatalog#submit-an-application), [release contract](https://github.com/NextKde/appCatalog/blob/main/RELEASE-CONTRACT.md), [Qt runtime guide](https://github.com/NextKde/appCatalog/blob/main/docs/QtRuntime.md) and [localization rules](https://github.com/NextKde/appCatalog/blob/main/docs/Localization.md). Qt applications normally use matching `org.kde.Platform` / `org.kde.Sdk`; current kos-apps manifests use branch 6.11. The app remains on GitHub even when its approved shared runtime comes from Flathub. Host Qt is not a Flatpak runtime.

## Client ownership

| Component | Responsibility |
| --- | --- |
| `platform/app-catalog` | Sources, signature verification, atomic cache, sequence/expiry checks and installation receipts; no installer commands |
| `IndependentAppRegistry` / `IndependentApps` | Adapt supported entries into Settings inventory and lifecycle actions |
| `FlatpakRelease` | Discover a stable GitHub Release and validate its manifest against the current catalog entry |
| `FlatpakApps` | Verify SHA-256, metadata, commit, architecture, runtime plan and installation ownership; perform the transaction |
| `kos-app-update-agent` | Check metadata in the user session, persist results and notify about updates |
| `ServicesSettingsPage` | Catalog sources, update controls, translated names/descriptions and installed-app actions |

Flatpak is the first adapter. `format` keeps source/identity logic independent of package handling; another format needs a compiled adapter, its release contract and tests. It cannot be enabled by sending a shell command in a catalog.

The bundled bootstrap is trusted through the core distribution until a verified official snapshot is received. Corrupt remote state must not reset history through fallback. Expired catalogs remain visible but cannot authorize installations or updates. The initial five applications retain their existing optional-publisher policy, with signatures required for those entries.

## Trust boundaries

Catalog signatures are mandatory and checked against a pinned full OpenPGP primary fingerprint. Packages always require SHA-256. Developer signatures are optional: if `publisher` is configured, both manifest and Flatpak commit signatures are required with no downgrade. Without it, authenticity depends on the approved GitHub repository and HTTPS. A repository attacker replacing both package and hash is outside SHA-256-only protection. These checks do not prove application safety.

Deployment binds to the catalog entry digest and actual installation snapshot, rechecked at confirmation/deployment. Receipts record repository, source, architecture, commit, origin, package hash and entry. An unsigned existing installation must match a client receipt to be eligible for managed updates; unknown installations are not adopted. Mutations use a cross-process lock. Runtime sources remain governed by a separate pinned policy; app catalogs do not authorize arbitrary runtime repositories.

## Third-party sources

In **Manage application sources**, enter a unique source ID, GitHub `owner/repository`, binary exported `.gpg` key file and full fingerprint, then explicitly trust the source. Its signed `sourceId` must match. The stable Release must contain `catalog.json` and `catalog.json.sig`. Confirm the fingerprint through an independently trusted channel.

Duplicate app IDs across sources are conflicts, not replacements. Removing a source preserves installed-app receipts and rollback history. Re-adding the same trust identity can reuse that history. Automatic root-key rotation is not implemented; a replacement third-party key needs a new source ID and explicit trust.

Configuration: `XDG_CONFIG_HOME/kos-settings/app-sources.json`. Snapshots, receipts and update state: `XDG_STATE_HOME/kos-settings/app-catalog` (defaults to `~/.local/state/kos-settings/app-catalog`).

## Update checks and languages

The single-instance agent starts with the user session and is also started by Settings. Automatic checks begin after roughly 2–4 minutes, normally recur every 6 hours with jitter and retry failures after about an hour. Only active, installed, manageable apps are checked. Users can disable automatic checks or notifications and request an immediate check. Checks fetch metadata; updates are not installed automatically.

Settings only reuses a result matching the current installation and catalog entry. Notifications are deduplicated by app ID, version and commit after delivery acknowledgement. Clicking opens Applications and services. Offline/rate-limit failures are recorded without repeated error notifications. Metered-network detection and shared GitHub ETag caching are not implemented.

Settings and catalog seed metadata support English, Simplified Chinese and Brazilian Portuguese; missing catalog translations fall back to English. Update notifications follow the system locale. Catalog translations do not translate the application's own UI; package those separately.

## Release and acceptance

The official source is `NextKde/appCatalog`. Publishing requires the matching private key in the `catalog-release` GitHub environment, a monotonically increasing sequence and renewal before the default 30-day expiry. See [maintainer instructions](https://github.com/NextKde/appCatalog/blob/main/MAINTAINING.md). A checked-in catalog or published repository is not evidence of end-to-end acceptance or of an available app Release.

Build and test only in a development VM or CI. Cover wrong/missing signatures, replay, expiry, SHA-256 mismatch, developer-signature failure, third-party add/remove/conflicts, unsigned receipts, concurrent transactions and update notification deduplication. Catalog logic tests live in `apps/settings/tests/store/catalog.cpp`; Flatpak release tests are alongside them. Real package deployment and desktop notifications also require VM acceptance before release.
