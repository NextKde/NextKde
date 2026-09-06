{
  description = "KOS Desktop Shell - iPadOS-style desktop for KDE Plasma 6";

  inputs = {
    nixpkgs = {
      url = "git+https://mirrors.nju.edu.cn/git/nixpkgs.git?ref=nixos-unstable&shallow=1";
    };
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = let
        kos-desktop = pkgs.callPackage ./nix/package.nix {
          src = ./.;
        };
      in {
        inherit kos-desktop;
        inherit (kos-desktop.passthru)
          shell-data-service kos-settings kos-platform kosctl
          kwin-dock-window-animation kwin-context-menu-input kwin-effects-glass;
        default = kos-desktop;
      };

      # Fully declarative NixOS module — no manual steps required
      nixosModules.kos = { config, lib, pkgs, ... }:
      let
        cfg = config.services.kos;
        kos = self.packages.${system}.kos-desktop;
        qs_bin = "/run/current-system/sw/bin/quickshell";
        
        # NixOS control interface
        kos-ctl = pkgs.callPackage ./nix/kos-ctl.nix {};
      in {
        options.services.kos = {
          enable = lib.mkEnableOption "KOS Desktop Shell";
        };

        config = lib.mkIf cfg.enable {
          # System-wide packages: binaries + KWin plugins + kosctl + kos-ctl
          environment.systemPackages = [
            kos
            kos.passthru.kosctl
            kos-ctl
            kos.passthru.kwin-dock-window-animation
            kos.passthru.kwin-context-menu-input
            kos.passthru.kwin-effects-glass
          ];

          # KWin plugins live under lib/kwin/ in the Nix store
          environment.pathsToLink = [ "/lib/kwin" ];

          # Systemd user services — declaratively defined with Nix store paths
          systemd.user.services = {
            # Oneshot: copy shell QML to ~/.config/quickshell/kos/
            kos-shell-init = {
              description = "KOS shell config initializer";
              wantedBy = [ "default.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "kos-shell-init" ''
                  set -e
                  shell_config="$HOME/.config/quickshell/kos"
                  
                  # Fix permissions on existing files before removal
                  # (Nix store copies may be read-only)
                  if [[ -d "$shell_config" ]]; then
                    find "$shell_config" -type d -exec chmod u+w {} + 2>/dev/null || true
                    find "$shell_config" -type f -exec chmod u+w {} + 2>/dev/null || true
                    rm -rf "$shell_config"
                  fi
                  
                  # Create fresh directories
                  mkdir -p "$shell_config/shared/qml"
                  
                  # Copy shell QML (follow symlinks, ignore source permissions)
                  cp -rL --no-preserve=mode ${kos}/share/kos-desktop/shell/. "$shell_config/"
                  
                  # Copy shared QML controls
                  if [[ -d ${kos}/share/shared/qml/controls ]]; then
                    cp -rL --no-preserve=mode ${kos}/share/shared/qml/controls "$shell_config/shared/qml/"
                  elif [[ -d ${kos}/share/kos-desktop/shared/qml/controls ]]; then
                    cp -rL --no-preserve=mode ${kos}/share/kos-desktop/shared/qml/controls "$shell_config/shared/qml/"
                  fi
                '';
              };
            };

            # Platform daemon
            kos-platform = {
              description = "KOS platform integration service";
              wantedBy = [ "default.target" ];
              after = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = "${kos}/libexec/kos-platform daemon";
                Environment = [
                  "KOS_PLATFORM_KWIN_SCRIPT=${kos}/share/kos/platform/kwin/window-bridge.js"
                ];
                Restart = "on-failure";
                RestartSec = 2;
              };
            };

            # Data service
            kos-data = {
              description = "KOS persistent data service";
              wantedBy = [ "default.target" ];
              after = [ "graphical-session.target" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = "${kos}/libexec/kos-data-service";
                Restart = "on-failure";
                RestartSec = 2;
              };
            };

            # Quickshell desktop shell
            kos-shell = {
              description = "KOS Quickshell desktop shell";
              wantedBy = [ "default.target" ];
              requires = [ "kos-platform.service" "kos-data.service" "kos-shell-init.service" ];
              after = [ "kos-platform.service" "kos-data.service" "kos-shell-init.service" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                KillMode = "mixed";
                ExecStart = "${qs_bin} --no-duplicate -c kos";
                Environment = [
                  "QS_DISABLE_FILE_WATCHER=1"
                  "PATH=${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin"
                ];
                Restart = "on-failure";
                RestartSec = 2;
              };
            };
          };
        };
      };

      # Export source path for other flakes
      lib.${system} = {
        src = ./.;
      };
    };
}
