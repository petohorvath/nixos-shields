{ nixpkgs }:
let
  testContext = import ../test-context.nix { inherit nixpkgs; };
in
{
  import-shield = import ./import-shield.nix testContext;
  mk-manifest = import ./mk-manifest.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
  packages.extra-builtins = {
    extra-builtins = import ./packages/extra-builtins/extra-builtins.nix testContext;
  };
}
