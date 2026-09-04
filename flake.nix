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
          shell-data-service kos-settings kos-platform
          kwin-dock-window-animation kwin-context-menu-input kwin-effects-glass;
        default = kos-desktop;
      };

      # NixOS module: declaratively install KOS system-wide
      nixosModules.kos = { config, lib, pkgs, ... }:
      let
        cfg = config.services.kos;
        kos = self.packages.${system}.kos-desktop;
      in {
        options.services.kos = {
          enable = lib.mkEnableOption "KOS Desktop Shell";
        };

        config = lib.mkIf cfg.enable {
          environment.systemPackages = [
            kos
            kos.passthru.kwin-dock-window-animation
            kos.passthru.kwin-context-menu-input
            kos.passthru.kwin-effects-glass
          ];

          # KWin plugins live under lib/kwin/ in the Nix store
          environment.pathsToLink = [ "/lib/kwin" ];
        };
      };

      # Export source path for other flakes
      lib.${system} = {
        src = ./.;
      };
    };
}
