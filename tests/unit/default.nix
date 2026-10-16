{ nixpkgs }:
let
  testContext = import ../test-context.nix { inherit nixpkgs; };
in
{
  mk-manifest = import ./mk-manifest.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
}
