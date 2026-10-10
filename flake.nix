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
        kos-desktop = pkgs.callPackage ./packaging/nix/package.nix {
          src = ./.;
        };
      in {
        inherit kos-desktop;
        inherit (kos-desktop.passthru)
          shell-data-service kos-settings kos-platform kosctl
          kwin-dock-window-animation kwin-stage-animation kwin-context-menu-input kwin-effects-glass
          kwin-kos-bridge kwin-kos-decoration;
        default = kos-desktop;
      };

      # Fully declarative NixOS module — no manual steps required
      nixosModules.kos = { config, lib, pkgs, ... }:
      let
        cfg = config.services.kos;
        kos = self.packages.${system}.kos-desktop.override { buildWeather = cfg.weather.enable; };
        qs_bin = "${pkgs.quickshell}/bin/quickshell";
        
        # NixOS control interface
        kos-ctl = pkgs.callPackage ./packaging/nix/kos-ctl.nix {};
      in {
        options.services.kos = {
          enable = lib.mkEnableOption "KOS Desktop Shell";
          weather = {
            enable = lib.mkEnableOption "KOS Weather standalone application";
          };
        };

        config = lib.mkIf cfg.enable {
          # System-wide packages: binaries + KWin plugins + kosctl + kos-ctl
          #
          # The window decoration is one of the plugins, not an option: the KOS
          # Bridge effect draws the window buttons only on windows wearing it,
          # so installing the effect without the decoration would leave the
          # session with no window buttons at all. Installing it is not the same
          # as selecting it — that stays with the user, in System Settings >
          # Window Decorations, and so does turning it back off.
          environment.systemPackages = [
            pkgs.quickshell
            kos
            kos.passthru.kosctl
            kos-ctl
            kos.passthru.kwin-dock-window-animation
            kos.passthru.kwin-stage-animation
            kos.passthru.kwin-context-menu-input
            kos.passthru.kwin-effects-glass
            kos.passthru.kwin-kos-bridge
            kos.passthru.kwin-kos-decoration
          ] ++ lib.optionals cfg.weather.enable [
            kos.passthru.weather
          ];

          # KWin plugins live under lib/kwin/ in the Nix store
          environment.pathsToLink = [ "/lib/kwin" ];

          # Systemd user services — declaratively defined with Nix store paths
          systemd.user.services = {
            # Oneshot: copy shell QML to ~/.config/quickshell/kos/
            kos-shell-init = {
              description = "KOS shell config initializer";
              wantedBy = [ "graphical-session.target" ];
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
                  
                  cp -rL --no-preserve=mode ${kos}/qml/Kos/Spatial3D ${kos}/qml/Kos/SurfaceShape "$shell_config/Kos/"

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
              wantedBy = [ "graphical-session.target" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                ExecStart = "${kos}/libexec/kos-platform daemon";
                Environment = [
                  "KOS_PLATFORM_KWIN_SCRIPT=${kos}/share/kos/platform/kwin/window-bridge.js"
                  "PATH=/run/current-system/sw/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin"
                ];
                Restart = "on-failure";
                RestartSec = 2;
              };
            };

            # Data service
            kos-data = {
              description = "KOS persistent data service";
              wantedBy = [ "graphical-session.target" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" ];
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
              wantedBy = [ "graphical-session.target" ];
              requires = [ "kos-platform.service" "kos-shell-init.service" ];
              wants = [ "kos-data.service" ];
              after = [ "graphical-session.target" "plasma-kwin_wayland.service" "plasma-plasmashell.service"
                "kos-platform.service" "kos-data.service" "kos-shell-init.service" ];
              partOf = [ "graphical-session.target" ];
              serviceConfig = {
                Type = "simple";
                KillMode = "process";
                ExecStart = "${qs_bin} --no-duplicate -c kos";
                Environment = [
                  "QS_DISABLE_FILE_WATCHER=1"
                  "MALLOC_ARENA_MAX=2"
                  "QML2_IMPORT_PATH=%h/.config/quickshell/kos:${kos.passthru.kos-spatial3d}/lib/qt6/qml:${pkgs.kdePackages.qtquick3d}/lib/qt-6/qml:${pkgs.kdePackages.qt5compat}/lib/qt-6/qml"
                  "QT_PLUGIN_PATH=${pkgs.kdePackages.qtsvg}/lib/qt-6/plugins:${pkgs.kdePackages.qtimageformats}/lib/qt-6/plugins"
                  "PATH=/run/current-system/sw/bin:${pkgs.bash}/bin:${pkgs.coreutils}/bin:${pkgs.findutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin"
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
