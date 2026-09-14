{ inputs, lib, ... }:
let
  /*
    The kit as the example's input: its flake and code, not its docs,
    so a README edit does not rebuild the integration check.
  */
  kit = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../lib
      ../modules
      ../packages
      ../parts
    ];
  };
in
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks = {
        integration = pkgs.callPackage ../tests/integration/wrapped-nix.nix {
          inherit (inputs) nixpkgs;
          inherit kit;
          inherit (config.packages) nix;
          flakeParts = inputs.flake-parts;
          libDir = ../lib;
          example = ../examples/consumer;
        };
        decrypt-cache = pkgs.callPackage ../tests/unit/decrypt-cache.nix { };
        nixos-module = pkgs.callPackage ../tests/unit/nixos-module.nix { };
      };
    };
}
