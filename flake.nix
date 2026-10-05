{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
  outputs = { nixpkgs, ... }: let
    systems = ["aarch64-darwin" "x86_64-darwin"];
    forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forAll (pkgs: let
      disks = pkgs.callPackage ./nix/packages/disks.nix {};
    in {
      disks = disks;
      default = disks;
    });
  };
}
