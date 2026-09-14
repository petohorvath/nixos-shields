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
        cli = pkgs.callPackage ../tests/integration/cli.nix {
          inherit (inputs) nixpkgs;
          inherit kit;
          inherit (config.packages) nix nixos-shields;
          flakeParts = inputs.flake-parts;
          gitHooks = inputs.git-hooks;
          example = ../examples/consumer;
        };
        integration = pkgs.callPackage ../tests/integration/wrapped-nix.nix {
          inherit (inputs) nixpkgs;
          inherit kit;
          inherit (config.packages) nix;
          flakeParts = inputs.flake-parts;
          gitHooks = inputs.git-hooks;
          libDir = ../lib;
          example = ../examples/consumer;
          composedNix = (import ../lib).mkNix {
            inherit pkgs;
            extraBuiltinsFile = pkgs.writeText "consumer-extra-builtins.nix" ''
              args:
              (import ${config.packages.nix.extraBuiltinsFile} args) // {
                consumerAnswer = 42;
              }
            '';
          };
        };
        decrypt-cache = pkgs.callPackage ../tests/unit/decrypt-cache.nix { };
        nixos-module = pkgs.callPackage ../tests/unit/nixos-module.nix { };
        flake-module = pkgs.callPackage ../tests/unit/flake-module.nix {
          flakeParts = inputs.flake-parts;
        };
      };
    };
}
