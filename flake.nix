{
  description = "Shields: evaluation-time encrypted Nix expressions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Only x86_64-linux is exercised by the checks; the rest are declared.
      # x86_64-darwin is absent because nixpkgs dropped it in 26.11.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [ flake-parts.flakeModules.partitions ];

      partitions.dev.module = ./dev;

      partitionedAttrs = {
        checks = "dev";
        devShells = "dev";
        formatter = "dev";
      };

      perSystem =
        { pkgs, ... }:
        {
          packages = import ./packages pkgs;
        };

      flake = {
        lib = import ./lib;
        nixosModules.default = ./nixos/module.nix;
        flakeModules.default = ./flake-module.nix;
      };
    };
}
