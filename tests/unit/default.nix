# The unit suites for nix-unit. Local runs default to the root flake's
# locked inputs; the unit check passes every argument.
#
# Example: nix-unit tests/unit --attr nixos.module
let
  rootInputs = (builtins.getFlake (toString ../..)).inputs;
in
{
  nixpkgs ? rootInputs.nixpkgs,
  system ? builtins.currentSystem,
}:
let
  testContext = import ../test-context.nix { inherit nixpkgs system; };
in
{
  mk-manifest = import ./mk-manifest.nix testContext;
  nixos = {
    module = import ./nixos/module.nix testContext;
  };
}
