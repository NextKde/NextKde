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
      packages.${system} = pkgs.callPackage ./nix/package.nix { src = ./.; };

      # 导出源码路径，供其他 flake 使用
      lib.${system} = {
        src = ./.;
      };
    };
}
