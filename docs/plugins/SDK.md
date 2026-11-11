# Data plugin SDK v1

The SDK is the versioned JSON schema and host action vocabulary in [Protocol.md](Protocol.md),
plus two complete example packages:

- `platform/plugins/examples/counter.json`: offline counter, editable per-instance
  label, increment/decrement, reset and toggle actions; multiple instances.
- `platform/plugins/examples/system.json`: two widget types, memory and uptime,
  requiring explicit `system.summary` permission. Denial or revocation replaces
  protected values with an unavailable marker without enabling arbitrary APIs.

Copy an example into a normal user-owned JSON file, choose a distinct reverse-domain
`id`, change its metadata and edit the bounded view/settings tree. This file is the
entire package: no scripts, archives, compiler, imports or executable build step.
The host renders the same validated data in production and development.

## Install and develop

Open Settings → Plugins, choose a bundled example or use the local JSON file picker.
Inspect the prepared plan, source, version and permissions, then confirm. Local files
are unsigned development imports and require an explicit trust acknowledgement;
this does not grant `system.summary`. Installation does not add widgets automatically.
Use Add to Desktop or the desktop widget library, choose a type and supported size,
and create an instance. Its settings are isolated from every other instance.

The normal install/instance path is the development preview in this release. There
is no separate preview mode that executes arbitrary QML/JS, and no live code loader.
After changing a local file, prepare and confirm it again; compatible updates preserve
instances. Use Settings' permissions to revoke the system permission while viewing
its widget. Use Disable to keep configuration and layout without rendering the
plugin. Remove from Desktop deletes one instance. Uninstall offers retained settings
or deletion; no application databases are affected.

The bundled examples are discoverable packages, not preinstalled plugins. They go
through the same prepare/confirm and permission checks as an imported package.
A clean installation can have no remote plugin catalog entries; this is an honest
empty marketplace state, not a request to trust an arbitrary download URL.

## Publish through a trusted source

1. Publish your JSON file as an immutable GitHub Release asset on tag `vX.Y.Z`.
2. Compute its byte size and SHA-256. Create the release descriptor from Protocol.md
   with `schemaVersion:2`, matching `appId`/`version`, and the exact asset name,
   digest and size. This descriptor is separate from the plugin manifest.
3. Submit a catalog entry with `format:"declarative-widget"` to an existing source
   maintainer, or operate a separately signed directory using the existing
   [signed catalog workflow](../app-store/SignedCatalog.zh-CN.md). Set
   `release.version`, `release.tag` and base64 `release.manifest` to the approved
   release. Optional publisher metadata requires the descriptor's detached
   signature in `release.signature`.
4. The source publishes a newer signed catalog sequence with valid issue/expiry
   timestamps. Users explicitly trust its full signing fingerprint through the
   existing source-management interface; a package cannot add its own source.
5. Users refresh the catalog and prepare the specific approved plugin. The host
   downloads only the pinned Release asset, verifies size/hash and any publisher
   signature, validates the JSON and shows a plan before changing installed state.

Changing plugin origin is not an update: source identity conflicts are rejected.
New permissions need user confirmation. Updates cannot downgrade an installed
version, and incompatible settings or widget types leave the old version intact.
There is no executable migration hook. Catalog anti-rollback is independent of
package versioning. This version preserves the old record if preparation or atomic
commit fails; it does not provide a user-selectable historical-version rollback UI.

## Manual acceptance

No automated tests or local graphical launches are required by this SDK.
Use the human-operated desktop to check:

- Install the counter; add two instances, configure different labels and values,
  trigger every button, change sizes and restart the session. Confirm isolation
  and persistence. While editing the desktop, normal button actions must not fire.
- Install the system example without permission. Confirm unavailable values, grant
  permission explicitly, then revoke it and confirm the next snapshot clears them.
- Disable/re-enable; remove one instance; uninstall with retention and reinstall;
  finally uninstall with deletion. Confirm those distinct outcomes.
- Select a JSON file containing an unknown permission, expression, arbitrary URL,
  invalid action, unknown setting, excessive nesting or an unsupported API version.
  Confirm preparation fails with an explicit error and the old installation remains.
- Refresh a source, prepare an update, change the package/source state before
  confirming and confirm the old plan is rejected. Check signed-source failure,
  expiry, offline errors, source conflict and incompatible instance configuration.

These are acceptance instructions, not a claim that they have been performed.

## Scope

Only plain text, values, row/column containers and fixed-action buttons are supported.
No plugin image URLs, executable runtime, network, personal data, filesystem access,
notifications, arbitrary IPC or custom logic is available. System memory usage uses
Linux `sysinfo` (total minus free and buffers), so it is not an exact match for
applications that subtract reclaimable page cache. Widgets are refreshed by the
trusted frontend's polling; there is no plugin-owned background execution.

The existing platform socket trusts clients of the same desktop Unix user. The
JSON plugin receives no socket, process or host objects. This boundary prevents
plugin content from invoking capabilities outside the explicit vocabulary; it is
not a sandbox for hostile native programs or a guarantee against same-user malware.
Full executable isolation, expanded capabilities and the remaining #363 interaction
and recovery requirements remain separate work.
