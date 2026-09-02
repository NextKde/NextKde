{
  description = "KOS Desktop Shell - iPadOS-style desktop for KDE Plasma 6";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
          quickshell = pkgs.kdePackages.quickshell;
        };
      in {
        inherit kos-desktop;
        inherit (kos-desktop.passthru)
          shell-data-service kwin-window-bridge kos-settings kos-platform
          kwin-dock-window-animation kwin-context-menu-input kwin-effects-glass;
        default = kos-desktop;
      };

      # NixOS module: import this flake to get KOS system-wide
      nixosModules.kos = { config, lib, pkgs, ... }: {
        options.services.kos = {
          enable = lib.mkEnableOption "KOS Desktop Shell";
        };

        config = lib.mkIf config.services.kos.enable {
          environment.systemPackages = [
            self.packages.${system}.kos-desktop
          ];

          # KWin plugins go to system-level path
          environment.pathsToLink = [ "/lib/kwin" ];
        };
      };

      # Export source path for other flakes
      lib.${system} = {
        src = ./.;
      };
    };
}
