# NixOS installation

[简体中文](nixos-quickstart.zh-CN.md)

This is a declarative packaging recipe, not a claim of complete NixOS runtime acceptance.
See the exact tested environments in the [release notes](releases/v0.1.1.md).
Pin a published tag and retain `flake.lock`; only the latest official release is maintained.
The example uses the existing historical v0.1.0 tag; select the newer published tag from
[Releases](https://github.com/SuceV587/NextKde/releases/latest) when upgrading.

## Module setup

Add to system `flake.nix` inputs:

```nix
nextkde = {
  url = "git+https://github.com/SuceV587/NextKde.git?ref=v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Pass `specialArgs = { inherit inputs; };` to `nixpkgs.lib.nixosSystem`, then in the module:

```nix
{ inputs, ... }:
{
  imports = [ inputs.nextkde.nixosModules.kos ];
  services.kos.enable = true;
  services.kos.weather.enable = true; # optional standalone Weather app
}
```

After changing the tag, update the lock and rebuild; replace `your-host` with your configuration:

```sh
nix flake update nextkde
sudo nixos-rebuild switch --flake .#your-host
kosctl version
systemctl --user status kos-shell-init kos-platform kos-data kos-shell
```

Packages read root VERSION and record the available source revision. The packaged `kosctl version`
reads the installed core record under `/run/current-system/sw/share/kos/release.json`;
`KOS_RELEASE_RECORD` explicitly selects a different deployment. Do not run source `update` inside
read-only Nix store. Development inputs may explicitly use `ref=main`; they are not stable releases.

## Runtime ownership and troubleshooting

`flake.nix` owns packages, KWin integrations and user units. `kos-shell-init` copies the selected
package's QML/runtime modules before Shell starts. Native plugin changes need logout/login or reboot.
Read user-unit logs if initialization or services fail; fix the declarative input/package rather
than repeatedly chmod or overwrite the store:

```sh
journalctl --user -b -u kos-shell-init -u kos-platform -u kos-data -u kos-shell
```

The module builds against the host's package set, including its Qt/KWin versions and overlays.
The legacy `kos-ctl` helper and `kos-shell-init` share the same deployment script, bound to the
module's selected package. `kos-ctl sync` also copies the native QML modules; it never searches
for an arbitrary matching store directory. Use the selected system generation for versioned upgrades.
`tools/nix-start.sh` is an alternative development helper; do not mix manual units with declarative
units during acceptance. Settings packages must include their QML and ECM build dependency;
missing modules are a packaging failure, not a reason to bypass initialization.

Disable with `services.kos.enable = false;` and rebuild. Preserve configuration/state needed for
recovery. Use a compatible prior NixOS generation for system rollback; cross-schema downgrade still
requires validation. All contributor builds/tests and graphical acceptance run in VM/CI only.
The `nix packaging` GitHub workflow builds the module with Weather both disabled and enabled,
checks host overlays and ARM evaluation, and exercises QML deployment without launching a desktop.
