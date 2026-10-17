{
  description = "Shields: evaluation-time encrypted Nix expressions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # Runs the nix-unit suites, through its flake-parts module in dev/.
    nix-unit = {
      url = "github:nix-community/nix-unit";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        treefmt-nix.follows = "";
        nix-github-actions.follows = "";
      };
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # CI checks both Linux systems; aarch64-darwin is declared only.
      # x86_64-darwin is absent because nixpkgs drops it in 26.11.
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
        tests = "dev";
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
