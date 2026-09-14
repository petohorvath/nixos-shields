{
  description = "Shields: evaluation-time encrypted Nix expressions";

  inputs = {
    # 26.05, not unstable: 26.11 dropped x86_64-darwin, a declared system.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Every per-system and flake-level output is wired explicitly here.
      imports = [ ./parts ];
    };
}
