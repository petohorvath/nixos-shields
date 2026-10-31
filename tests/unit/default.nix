{ nixpkgs, pkgs }:
let
  testContext = import ../test-context.nix { inherit nixpkgs pkgs; };
in
{
  import-shield = import ./import-shield.nix testContext;
  mk-manifest = import ./mk-manifest.nix testContext;
  mk-nix = import ./mk-nix.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
  packages.extra-builtins = {
    compose = import ./packages/extra-builtins/compose.nix testContext;
    extra-builtins = import ./packages/extra-builtins/extra-builtins.nix testContext;
  };
}
