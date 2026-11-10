# Developer test mode

[简体中文](DeveloperTesting.zh-CN.md) · [Catalog architecture](SignedCatalog.md)

Use Settings → Applications and services → **Enter test mode** to test a developer's GitHub Release catalog before submitting an application. Test mode keeps the original application ID and the existing user Flatpak installation. It is not a separate application sandbox: a test package can replace an installed application and use its existing data. Back up valuable data and use a development VM for lifecycle testing.

## Publish and select a test release

1. Build a Flatpak bundle with the original app ID and the `stable` Flatpak branch. Upload it and its schema 2 release manifest to your own public GitHub repository. The manifest version must match the tag without `v`, such as `v1.2.0-rc.1` / `1.2.0-rc.1`. Published GitHub prereleases are supported when explicitly selected; drafts and private-repository authentication are not supported.
2. Prepare a separate catalog repository using [appCatalog](https://github.com/NextKde/appCatalog). Its entry points to the app's repository, original ID and manifest filename. Generate a catalog with your own source ID and an increasing sequence; sign it using your own catalog key. Upload `catalog.json` and `catalog.json.sig` to a published GitHub Release, for example `catalog-test-1`, which may be marked as a prerelease.
3. Enter test mode and open **Manage app sources**. Add the test source ID, GitHub repository, exported binary `.gpg` public key and full fingerprint. Test sources start empty and do not inherit official trust. Confirm trust explicitly.
4. Use **Catalog Release** on that source to select its published tag. Applying it refreshes the signed directory. A blank selection means latest stable; selecting an older catalog cannot bypass sequence/expiry checks. Use a new test source ID and matching signed document for a separate sequence history.
5. Expand the application's details and use **App Release** to select the version to test, then **Check for updates**. The picker shows up to 30 recent published releases and accepts an exact tag for older releases. Review the installation plan and its test-mode warning before confirming installation or update.
6. Publish a newer test bundle, select its Release and check again to exercise updates. For downgrade or same-version replacement tests, uninstall first; test mode does not bypass version checks. If an existing installation belongs to another source or cannot be verified with the selected publisher, uninstall it before installing the test release.

Catalog signatures and package SHA-256 remain mandatory. Developer signatures remain optional, but a pinned developer key is enforced. Downloads remain restricted to the configured GitHub repository's Release assets. Test mode accepts no local package paths, raw URLs, arbitrary servers or installer scripts.

## Exit and restore

**Exit test mode** restores normal source configuration. It does not uninstall packages, restore an older version, delete application data or migrate a test source into the normal configuration. Test installations stay visible for opening/uninstalling and are not silently adopted by the normal updater. Uninstall the test version yourself, then install the normal release. Application data is retained by the normal uninstall flow.

Scheduled update checks and desktop update notifications are paused in test mode. Manual catalog refresh, per-app checks and **Check all updates** remain available. Source errors, selected tags, installed/update versions and operation logs help diagnose failures.

## State and validation

Mode selection is per user, persists across Settings restarts and applies to the shared Settings/CLI/worker/updater backend. The CLI result includes `testMode`. Sources use `app-sources-test.json` beside the normal `app-sources.json`; catalog caches and update state use `app-catalog/test/`. Test plans use `flatpak-plans-test/`. Actual Flatpak installations, application data and installation receipts are shared. Receipts record whether the deployment was a test installation.

Switching modes or app Release selections invalidates previous plans and cached discoveries. A shared context lock blocks source/mode changes during catalog refreshes, inventory and app operations; the existing mutation lock remains shared across modes. An in-flight updater discards results if its mode context changes. No background process is permitted to confirm a package deployment.

Project contributors must build and validate only in a VM or hosted CI. Cover normal/test source and sequence separation, same-ID receipts, stale plans, signature/hash failures, selected tag mismatch, prerelease version ordering, scheduled-check suppression, manual checks, and exit without uninstall. Test actual install/update/uninstall with isolated VM fixtures as well as the Settings UI in supported languages.

Normal mode now uses approved versions embedded in the signed directory. When creating a test entry without an approved package, specify `release: null`; test mode can still select the app repository Release directly. Include repository PNG icons and exact manifests using the [submission contract](https://github.com/NextKde/appCatalog/blob/main/docs/PinnedReleases.md).
