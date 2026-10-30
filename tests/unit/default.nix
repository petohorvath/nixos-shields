{ nixpkgs }:
let
  testContext = import ../test-context.nix { inherit nixpkgs; };
in
{
  extra-builtins = import ./extra-builtins.nix testContext;
  import-shield = import ./import-shield.nix testContext;
  mk-manifest = import ./mk-manifest.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
}
