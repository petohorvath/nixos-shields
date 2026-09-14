{
  description = "Shields: evaluation-time encrypted Nix expressions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    # The hooks module uses our package set; its own flake inputs are unnecessary.
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Every per-system and flake-level output is wired explicitly here.
      imports = [ ./parts ];
    };
}
