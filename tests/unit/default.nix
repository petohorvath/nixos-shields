{ nixpkgs, system }:
let
  testContext = import ../test-context.nix { inherit nixpkgs system; };
in
{
  mk-manifest = import ./mk-manifest.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
}
