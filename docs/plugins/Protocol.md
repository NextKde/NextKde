# Declarative desktop plugins — protocol v1

This is a data-only plugin format. Third-party QML, JavaScript, executable files,
expressions, imports, arbitrary URLs and arbitrary platform operations are not
accepted. Trusted Shell and Settings clients call the existing platform IPC; that
socket is **not** a third-party sandbox endpoint. Plugin identity comes from the
installed record and instance, never from an action's self-reported identity.

## IPC envelope and frontend contract

Use the existing platform version-1 request/reply envelope (`operation`, `payload`).
All successful operations return a snapshot as `result`, optionally with `plan` or
`instanceId`. Errors use the existing `error.code/message` envelope. Mutations are
serialized, persist atomically before success and advance `revision`. Clients
refresh after mutations and periodically (5–30 seconds); do not assume push events.

Snapshot fields:

- `revision`: integer persistent mutation revision.
- `plugins`: installed plugin records: `id`, `name`, `description`, `author`,
  `version`, `apiVersion`, `permissions` (requested), `grantedPermissions`,
  `enabled`, `sourceId`, `sourceKind` (`example`, `local`, `catalog`), `status`
  (`enabled`, `disabled`, `unavailable`), `message`, and `widgets` (validated
  manifest widget definitions). Enabled plugins lacking permission can still
  create degraded instances.
- `instances`: records with `id` (`plugin:<uuid>`), `pluginId`, `widgetId`, `name`,
  `size`, `sizes`, `settings`, `settingsSchema`, `view`, `state`, `message`.
  State is `ready`, `disabled`, `permission-required`, or `unavailable`.
  `view` is the host-resolved tree described below; only render these resolved
  instances, not raw widget manifest views. Disabled/unavailable instances have
  an empty view. Missing permission clears restricted values on every snapshot.
- `catalog`: discoverable entries with `id`, `sourceId`, `sourceKind`, `name`,
  `description`, `author`, `version`, `installed`, `available`, `status`, `error`.
  Bundled SDK examples appear with sourceId `examples`, sourceKind `example`.
  Remote entries come exclusively from the shared verified app catalog.
- `sources`: shared catalog source information; `error`: catalog/storage message
  or an empty string. An empty remote catalog is not a claim of online success.

Operations and payloads:

| Operation | Payload | Additional result |
| --- | --- | --- |
| `plugin.snapshot` | `{}` | — |
| `plugin.refresh-catalog` | `{}` | refreshes shared signed catalog |
| `plugin.prepare-install` | `{sourceId, pluginId}` **or** `{path}` | `plan` |
| `plugin.confirm-install` | `{planId, permissions:[], trustLocal:true?}` | — |
| `plugin.set-enabled` | `{pluginId, enabled:boolean}` | — |
| `plugin.uninstall` | `{pluginId, removeData:boolean}` | — |
| `plugin.set-permissions` | `{pluginId, permissions:[]}` | — |
| `plugin.instance-add` | `{pluginId, widgetId, size?:"medium", settings?:{}}` | `instanceId` |
| `plugin.instance-remove` | `{instanceId}` | — |
| `plugin.instance-configure` | `{instanceId, settings?:{}, size?:string}` | — |
| `plugin.instance-action` | `{instanceId, actionId}` | — |

`settings` is a validated patch; unknown keys are rejected. No action can submit
an arbitrary operation, path, script or replacement action definition. The host
looks up `actionId` as a button node ID in that instance's installed widget.
Frontend dispatches actions only on actual user interaction, and disables normal
widget interaction while editing the desktop. `size` must occur in `sizes`.

An install plan contains `id`, `pluginId`, `name`, `version`, `previousVersion`,
`sourceId`, `sourceKind`, `permissions`, `previousPermissions`, `addedPermissions`,
`requiresTrust`, `digest`, `expiresAt`, `widgets`, and `warnings`.
Plans expire after five minutes, are bound to the requesting IPC connection and
current state revision, and cannot be replayed. Confirmation chooses a subset of
requested permissions (including none); a plugin can run in a degraded state.
No permissions are silently added. Local import requires an explicit file-picker
selection in Settings, a visible unsigned-file warning and `trustLocal:true` at
confirmation. This boolean records the trusted host UI's confirmation; it is not
an authentication mechanism against other programs of the same Unix user.
Examples also use the prepare/confirm path. Installation never creates new instances;
a compatible reinstall can restore retained instances after the plan discloses their
count. Plan cleanup runs on disconnect/worker completion and an idle one-second
expiry timer. A disconnected operation may already have atomically committed; the
next frontend snapshot is authoritative.

Disabling preserves instances/configuration; removing an instance deletes only
that instance. Uninstall removes active instances and the package. With
`removeData:false`, instance records are retained privately for recovery on a
compatible reinstall; they are not active or displayed while uninstalled. With
`removeData:true`, these retained settings are deleted too. Application data is
never touched. Incompatible update settings fail before replacing the old package.
This version does not execute migration scripts or offer an unrestricted downgrade.

## Manifest and view schema

A plugin is one UTF-8 JSON file, at most 128 KiB. No archive or external assets.
The root has exactly `id`, `name`, `description`, `author`, `version`, `apiVersion`,
`permissions`, `widgets`, and optional `license`. Identity uses a reverse-domain
style ID, version is numeric `major.minor.patch`, apiVersion is exactly `1`.
Only permission `system.summary` is currently supported. Unknown permissions,
fields and incompatible API versions are rejected rather than silently ignored.

Each widget has `id`, `name`, `description`, `sizes`, `multiInstance`, `settings`,
`view`. Sizes are a nonempty subset of `small`, `medium`, `large`.
Settings is an array of schemas:

- Number: `{key,label,type:"number",default,min,max}`; finite integers only.
- Boolean: `{key,label,type:"boolean",default}`.
- String: `{key,label,type:"string",default,maxLength}`; plain bounded text.

Each widget view is one node object. Every node has a unique `id` and `type`:

- `column` / `row`: `{id,type,children:[nodes...]}`.
- `text`: `{id,type,text}`.
- `value`: `{id,type,binding,label?,suffix?}`. Binding is exactly
  `settings.<declaredKey>` or one of `system.memoryTotalMiB`,
  `system.memoryUsedMiB`, `system.memoryUsedPercent`, `system.uptimeSeconds`.
  System bindings require the manifest to request `system.summary`.
- `button`: `{id,type,text,action}`. Action is `{type:"increment",key,delta}`,
  `{type:"toggle",key}`, or `{type:"set",key,value}`. Type and target setting
  must match. Increment clamps to the declared min/max.

Resolved instance value nodes additionally have `value` (string) and `available`
(boolean), and no `binding`; resolved buttons have `actionId` instead of `action`.
All text is plain text, never rich text. Host renderers use fixed components;
size, clipping, focus, spacing and input ownership remain under host control.
Maximums: 8 widget types/plugin, 16 settings/widget, 64 view nodes/widget,
8 view levels, 16 KiB serialized view/widget, 64 plugins, 1 MiB combined installed
manifests, 128 active/retained instances total, 256 displayed catalog entries.
Snapshots have a 6 MiB serialized ceiling (below the transport's 8 MiB reply cap);
aggregate view exhaustion returns explicit unavailable placeholders. JSON input has
bounded depth/node count/string length before manifest semantics are evaluated.
System data is a fixed host-produced memory/uptime summary, no filenames, process
list, environment, personal data or generic system APIs. It is recomputed only
when a granted, enabled instance requests a snapshot.

## Verified remote distribution

The shared app catalog accepts `format:"declarative-widget"` entries. Existing
entry identity remains `appId`; it must equal the plugin manifest `id`. Catalog
release selection embeds a base64 release descriptor in `release.manifest`:

```json
{"schemaVersion":2,"appId":"org.example.widget","version":"1.0.0","plugin":{"asset":"widget.json","sha256":"<64 lowercase hex>","size":1234}}
```

The signed catalog pins `release.version`, `release.tag` (`v1.0.0`), repository
and descriptor. If publisher metadata is present, the embedded descriptor's
`release.signature` must verify with that publisher. Download is restricted to
that repository's approved GitHub Release asset; size and SHA-256 must match.
The downloaded JSON is fully validated before a plan is issued. Confirmation
rechecks the current trusted catalog entry/source fingerprint and plan revision.
No arbitrary remote URL, branch tip, install command or unapproved latest release
is accepted. Test-mode catalog release overrides are not a plugin installation
escape hatch; signed marketplace plugins are paused while catalog test mode is
active, and test-catalog revocations do not modify normal installed trust state.

Shared source configuration is managed by the existing Settings source UI.
Expired/removed/withdrawn sources prevent new installs/updates but do not imply
malicious revocation or erase installed data. Explicit revocation blocks rendering
and actions, clears grants and persists the disabled state; subsequently removing
the source does not undo an observed revocation. A newly approved installation is
required to recover. A source identity change or ID conflict also blocks use. Revocation
is evaluated from locally available verified catalog data; offline clients cannot
claim knowledge of unseen revocations. Old versions cannot bypass directory
anti-rollback policy. Package updates atomically replace one data record; no
executable installation or extraction occurs.

## Limits and remaining scope

This release has no third-party executable runtime. There are no plugin processes,
network requests from plugins, filesystem APIs, arbitrary platform IPC, media or
personal-data APIs. It does not claim to sandbox arbitrary QML/JS/native code.
Bounded parsing/rendering is required even for data packages. Trusted frontend
renderers must enforce their own clipping and node budgets and show degraded/error
states. Same-user malware remains outside the existing trusted platform socket's
security boundary. Full executable isolation, a richer SDK, images, notification,
network and personal-data permissions require separate implementations.
