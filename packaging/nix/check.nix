{ flake, system ? "x86_64-linux", buildWeather ? false }:

let
  lib = flake.inputs.nixpkgs.lib;
  host = lib.nixosSystem {
    inherit system;
    modules = [
      flake.nixosModules.kos
      {
        services.kos = {
          enable = true;
          weather.enable = buildWeather;
        };
        # A passthru marker does not rebuild KWin, but reveals whether the
        # module actually uses the host's package set rather than self.packages.
        nixpkgs.overlays = [
          (final: prev: {
            kdePackages = prev.kdePackages.overrideScope (kdeFinal: kdePrev: {
              kwin = kdePrev.kwin.overrideAttrs (old: {
                passthru = (old.passthru or {}) // { nextkdeHostPackage = true; };
              });
            });
          })
        ];
      }
    ];
  };
  findPackage = name: lib.findFirst (pkg: lib.getName pkg == name)
    (throw "NixOS module did not install ${name}") host.config.environment.systemPackages;
  kos = findPackage "kos-desktop";
  control = findPackage "kos-ctl";
  sync = host.config.systemd.user.services.kos-shell-init.serviceConfig.ExecStart;
  plugins = with kos.passthru; [
    kwin-dock-window-animation kwin-stage-animation kwin-context-menu-input
    kwin-effects-glass kwin-kos-bridge kwin-kos-decoration
  ];
in
assert kos.system == system;
assert builtins.any (input: input.nextkdeHostPackage or false)
  kos.passthru.kwin-dock-window-animation.buildInputs;
host.pkgs.runCommand "nextkde-nixos-packaging-check" {} ''
  test -x ${kos}/bin/kos-settings
  test -x ${kos}/libexec/kos-platform
  test -x ${kos}/libexec/kos-ai-worker
  test -x ${kos}/libexec/kos-data-service
  test -x ${control}/bin/kos-ctl
  ${lib.concatMapStringsSep "\n" (plugin: ''
    test -n "$(find ${plugin}/lib -name '*.so' -print -quit)"
  '') plugins}

  # Exercise real deployment, including a second sync over read-only files.
  deployment="$TMPDIR/deployment"
  ${sync} "$deployment"
  chmod -R u-w "$deployment"
  ${sync} "$deployment"
  test -f "$deployment/shell.qml"
  test -f "$deployment/shared/qml/i18n/qmldir"
  test -f "$deployment/shared/qml/colorize/qmldir"
  test -f "$deployment/Kos/Spatial3D/qmldir"
  test -f "$deployment/Kos/SurfaceShape/qmldir"
  test ! -d "$deployment/shared/qml/controls/controls"
  ${if buildWeather then ''
    test -x ${kos}/bin/kos-weather
    test -x ${kos.passthru.weather}/libexec/kos-data-service
  '' else ''
    test ! -e ${kos}/bin/kos-weather
  ''}
  touch "$out"
''
