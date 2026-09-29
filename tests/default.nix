{
  formatter,
  inputs,
  packages,
  pkgs,
}:
let
  inherit (pkgs) lib;

  # The kit as the example's input: its flake and code, not its docs,
  # so a README edit does not rebuild the integration check.
  kit = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../flake.nix
      ../flake-module.nix
      ../lib
      ../nixos
      ../packages
    ];
  };
in
{
  cli = pkgs.callPackage ./integration/cli.nix {
    inherit (inputs) nixpkgs;
    inherit kit;
    inherit (packages) nix nixos-shields;
    flakeParts = inputs.flake-parts;
    example = ../examples/consumer;
  };
  integration = pkgs.callPackage ./integration/wrapped-nix.nix {
    inherit (inputs) nixpkgs;
    inherit kit;
    inherit (packages) nix;
    flakeParts = inputs.flake-parts;
    libDir = ../lib;
    example = ../examples/consumer;
    composedNix = (import ../lib).mkNix {
      inherit pkgs;
      extraBuiltinsFile = pkgs.writeText "consumer-extra-builtins.nix" ''
        args:
        (import ${packages.nix.extraBuiltinsFile} args) // {
          consumerAnswer = 42;
        }
      '';
    };
  };
  decrypt-cache = pkgs.callPackage ./unit/decrypt-cache.nix { };
  nixos-module = pkgs.callPackage ./unit/nixos-module.nix { };
  flake-module = pkgs.callPackage ./unit/flake-module.nix {
    flakeParts = inputs.flake-parts;
  };
}
